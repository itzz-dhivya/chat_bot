import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

class WebRTCService {
  final FirebaseFirestore _firestore =
      FirebaseFirestore.instance;

  RTCPeerConnection? peerConnection;
  MediaStream? localStream;

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
  callSubscription;

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
  remoteCandidatesSubscription;

  // =========================================================
  // WEBRTC CONFIG
  // =========================================================

  final Map<String, dynamic> _configuration = {
    'iceServers': [
      {
        'urls': 'stun:stun.l.google.com:19302',
      },
    ],
  };

  // =========================================================
  // CREATE PEER CONNECTION
  // =========================================================

  Future<void> createConnection() async {
    peerConnection = await createPeerConnection(
      _configuration,
    );

    peerConnection!.onConnectionState = (state) {
      print('WebRTC connection state: $state');
    };

    peerConnection!.onIceConnectionState = (state) {
      print('ICE connection state: $state');
    };
  }

  // =========================================================
  // GET LOCAL AUDIO
  // =========================================================

  Future<MediaStream> getLocalAudio() async {
    localStream =
    await navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': false,
    });

    return localStream!;
  }

  // =========================================================
  // ADD LOCAL TRACKS
  // =========================================================

  Future<void> addLocalStream() async {
    if (peerConnection == null) {
      throw Exception('Peer connection not created');
    }

    if (localStream == null) {
      await getLocalAudio();
    }

    for (final track in localStream!.getTracks()) {
      await peerConnection!.addTrack(
        track,
        localStream!,
      );
    }
  }

  // =========================================================
  // CREATE CALL - CALLER A
  // =========================================================

  Future<String> createCall({
    required String callerId,
    required String receiverId,
  }) async {
    await createConnection();
    await addLocalStream();

    final callDoc =
    _firestore.collection('calls').doc();

    final callerCandidates =
    callDoc.collection('callerCandidates');

    final calleeCandidates =
    callDoc.collection('calleeCandidates');

    // -------------------------------------------------------
    // A ICE candidates
    // -------------------------------------------------------

    peerConnection!.onIceCandidate = (candidate) async {
      if (candidate.candidate == null) return;

      await callerCandidates.add({
        'candidate': candidate.candidate,
        'sdpMid': candidate.sdpMid,
        'sdpMLineIndex': candidate.sdpMLineIndex,
      });
    };

    // -------------------------------------------------------
    // Remote track
    // -------------------------------------------------------

    peerConnection!.onTrack = (event) {
      print(
        'Remote track received: ${event.track.kind}',
      );
    };

    // -------------------------------------------------------
    // CREATE OFFER
    // -------------------------------------------------------

    final offer =
    await peerConnection!.createOffer();

    await peerConnection!.setLocalDescription(
      offer,
    );

    // -------------------------------------------------------
    // CREATE CALL DOCUMENT
    // -------------------------------------------------------

    await callDoc.set({
      'callerId': callerId,
      'receiverId': receiverId,
      'status': 'calling',
      'type': 'voice',
      'offer': {
        'type': offer.type,
        'sdp': offer.sdp,
      },
      'createdAt':
      FieldValue.serverTimestamp(),
      'timestamp':
      FieldValue.serverTimestamp(),
    });

    print(
      'Call created: ${callDoc.id}',
    );

    // -------------------------------------------------------
    // LISTEN FOR ANSWER
    // -------------------------------------------------------

    callSubscription =
        callDoc.snapshots().listen(
              (snapshot) async {
            final data = snapshot.data();

            if (data == null) return;

            final answer = data['answer'];

            if (answer != null &&
                peerConnection != null) {
              final remoteDescription =
              await peerConnection!
                  .getRemoteDescription();

              if (remoteDescription == null) {
                final sessionDescription =
                RTCSessionDescription(
                  answer['sdp'],
                  answer['type'],
                );

                await peerConnection!
                    .setRemoteDescription(
                  sessionDescription,
                );

                print(
                  'Remote answer received',
                );
              }
            }

            if (data['status'] == 'ended') {
              print('Remote user ended call');
            }
          },
        );

    // -------------------------------------------------------
    // RECEIVE B ICE CANDIDATES
    // -------------------------------------------------------

    remoteCandidatesSubscription =
        calleeCandidates.snapshots().listen(
              (snapshot) async {
            for (final change in snapshot.docChanges) {
              if (change.type !=
                  DocumentChangeType.added) {
                continue;
              }

              final data = change.doc.data();

              if (data == null) continue;

              final candidate =
              RTCIceCandidate(
                data['candidate'],
                data['sdpMid'],
                data['sdpMLineIndex'],
              );

              try {
                await peerConnection!
                    .addCandidate(candidate);

                print(
                  'Caller added remote ICE candidate',
                );
              } catch (e) {
                print(
                  'Error adding ICE candidate: $e',
                );
              }
            }
          },
        );

    return callDoc.id;
  }

  // =========================================================
  // ANSWER CALL - B
  // =========================================================

  Future<void> answerCall({
    required String callId,
  }) async {
    await createConnection();
    await addLocalStream();

    final callDoc =
    _firestore.collection('calls').doc(callId);

    final callerCandidates =
    callDoc.collection('callerCandidates');

    final calleeCandidates =
    callDoc.collection('calleeCandidates');

    // -------------------------------------------------------
    // B ICE candidates
    // -------------------------------------------------------

    peerConnection!.onIceCandidate = (candidate) async {
      if (candidate.candidate == null) return;

      await calleeCandidates.add({
        'candidate': candidate.candidate,
        'sdpMid': candidate.sdpMid,
        'sdpMLineIndex': candidate.sdpMLineIndex,
      });
    };

    // -------------------------------------------------------
    // Remote track
    // -------------------------------------------------------

    peerConnection!.onTrack = (event) {
      print(
        'Remote track received: ${event.track.kind}',
      );
    };

    // -------------------------------------------------------
    // GET CALL DOCUMENT
    // -------------------------------------------------------

    final snapshot =
    await callDoc.get();

    final data = snapshot.data();

    if (data == null) {
      throw Exception(
        'Call not found',
      );
    }

    final offer = data['offer'];

    if (offer == null) {
      throw Exception(
        'Offer not found',
      );
    }

    // -------------------------------------------------------
    // SET REMOTE OFFER
    // -------------------------------------------------------

    final offerDescription =
    RTCSessionDescription(
      offer['sdp'],
      offer['type'],
    );

    await peerConnection!
        .setRemoteDescription(
      offerDescription,
    );

    print(
      'Caller offer received',
    );

    // -------------------------------------------------------
    // CREATE ANSWER
    // -------------------------------------------------------

    final answer =
    await peerConnection!.createAnswer();

    await peerConnection!
        .setLocalDescription(answer);

    // -------------------------------------------------------
    // UPDATE CALL
    // -------------------------------------------------------

    await callDoc.update({
      'answer': {
        'type': answer.type,
        'sdp': answer.sdp,
      },
      'status': 'accepted',
    });

    print(
      'Call accepted: $callId',
    );

    // -------------------------------------------------------
    // RECEIVE A ICE CANDIDATES
    // -------------------------------------------------------

    remoteCandidatesSubscription =
        callerCandidates.snapshots().listen(
              (snapshot) async {
            for (final change in snapshot.docChanges) {
              if (change.type !=
                  DocumentChangeType.added) {
                continue;
              }

              final data = change.doc.data();

              if (data == null) continue;

              final candidate =
              RTCIceCandidate(
                data['candidate'],
                data['sdpMid'],
                data['sdpMLineIndex'],
              );

              try {
                await peerConnection!
                    .addCandidate(candidate);

                print(
                  'Callee added remote ICE candidate',
                );
              } catch (e) {
                print(
                  'Error adding ICE candidate: $e',
                );
              }
            }
          },
        );
  }

  // =========================================================
  // END CALL
  // =========================================================

  Future<void> endCall({
    required String callId,
  }) async {
    try {
      await _firestore
          .collection('calls')
          .doc(callId)
          .update({
        'status': 'ended',
      });
    } catch (e) {
      print(
        'Error updating call status: $e',
      );
    }

    await callSubscription?.cancel();
    await remoteCandidatesSubscription?.cancel();

    callSubscription = null;
    remoteCandidatesSubscription = null;

    await localStream?.dispose();
    await peerConnection?.close();

    localStream = null;
    peerConnection = null;

    print('WebRTC call ended');
  }

  // =========================================================
  // MUTE / UNMUTE
  // =========================================================

  void setMuted(bool muted) {
    final stream = localStream;

    if (stream == null) return;

    for (final track in stream.getAudioTracks()) {
      track.enabled = !muted;
    }

    print(
      muted
          ? 'Microphone muted'
          : 'Microphone unmuted',
    );
  }

  // =========================================================
  // DISPOSE
  // =========================================================

  Future<void> dispose() async {
    await callSubscription?.cancel();
    await remoteCandidatesSubscription?.cancel();

    await localStream?.dispose();
    await peerConnection?.close();

    callSubscription = null;
    remoteCandidatesSubscription = null;

    localStream = null;
    peerConnection = null;
  }
}