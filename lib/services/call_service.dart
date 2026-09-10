import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';

class CallService {
  final FirebaseFirestore _firestore =
      FirebaseFirestore.instance;

  RTCPeerConnection? peerConnection;

  MediaStream? localStream;
  MediaStream? remoteStream;

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
  callSubscription;

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
  candidateSubscription;

  // ---------------------------------------------------------
  // CALLBACKS
  // ---------------------------------------------------------

  Function(MediaStream)? onRemoteStreamReady;
  Function()? onCallConnected;
  Function(String reason)? onCallEnded;

  /// Called on BOTH sides when a voice call is upgraded to video.
  Function()? onUpgradedToVideo;

  /// Called on BOTH sides whenever the display mode (video <-> voice)
  /// changes, either because we switched it locally or because the
  /// remote side switched it. `isVideo == true` means the call should
  /// now be shown/treated as a video call.
  Function(bool isVideo)? onCallModeChanged;

  // ---------------------------------------------------------
  // CONNECTION FLAGS
  // ---------------------------------------------------------

  bool _connectionNotified = false;
  bool _callEndedNotified = false;

  // ---------------------------------------------------------
  // ICE CONFIGURATION
  // ---------------------------------------------------------

  final Map<String, dynamic> _iceConfiguration = {
    'iceServers': [
      {
        'urls': 'stun:stun.l.google.com:19302',
      },
      {
        'urls': 'stun:stun1.l.google.com:19302',
      },
      {
        'urls': 'stun:stun2.l.google.com:19302',
      },
    ],
    'sdpSemantics': 'unified-plan',
  };

  // ---------------------------------------------------------
  // CALL TYPE
  // ---------------------------------------------------------

  String currentCallType = 'voice';

  bool get isVideoCall =>
      currentCallType == 'video';

  // =========================================================
  // CONNECTED CALLBACK
  // =========================================================

  void _notifyCallConnected() {
    if (_connectionNotified) {
      return;
    }

    _connectionNotified = true;

    debugPrint(
      '==========================================',
    );
    debugPrint(
      'WEBRTC CALL CONNECTED',
    );
    debugPrint(
      'CALL TYPE: $currentCallType',
    );
    debugPrint(
      '==========================================',
    );

    onCallConnected?.call();
  }

  // =========================================================
  // ENDED CALLBACK
  // =========================================================

  void _notifyCallEnded(String reason) {
    if (_callEndedNotified) {
      return;
    }

    _callEndedNotified = true;

    debugPrint(
      '==========================================',
    );
    debugPrint(
      'WEBRTC CALL ENDED',
    );
    debugPrint(
      'REASON: $reason',
    );
    debugPrint(
      '==========================================',
    );

    onCallEnded?.call(reason);
  }

  // =========================================================
  // CREATE PEER CONNECTION
  // =========================================================

  Future<void> _createPeerConnection() async {
    await disposeConnection();

    _connectionNotified = false;
    _callEndedNotified = false;

    debugPrint(
      '==========================================',
    );
    debugPrint(
      'CREATING PEER CONNECTION',
    );
    debugPrint(
      'CALL TYPE: $currentCallType',
    );
    debugPrint(
      '==========================================',
    );

    peerConnection = await createPeerConnection(
      _iceConfiguration,
    );

    // -------------------------------------------------------
    // CONNECTION STATE
    // -------------------------------------------------------

    peerConnection!.onConnectionState =
        (RTCPeerConnectionState state) {
      debugPrint(
        'WebRTC Connection State: $state',
      );

      if (state ==
          RTCPeerConnectionState
              .RTCPeerConnectionStateConnected) {
        _notifyCallConnected();
      }

      if (state ==
          RTCPeerConnectionState
              .RTCPeerConnectionStateDisconnected ||
          state ==
              RTCPeerConnectionState
                  .RTCPeerConnectionStateFailed) {
        _notifyCallEnded(
          'Connection closed',
        );
      }
    };

    // -------------------------------------------------------
    // ICE CONNECTION STATE
    // -------------------------------------------------------

    peerConnection!.onIceConnectionState =
        (RTCIceConnectionState state) {
      debugPrint(
        'ICE Connection State: $state',
      );

      if (state ==
          RTCIceConnectionState
              .RTCIceConnectionStateConnected ||
          state ==
              RTCIceConnectionState
                  .RTCIceConnectionStateCompleted) {
        _notifyCallConnected();
      }

      if (state ==
          RTCIceConnectionState
              .RTCIceConnectionStateFailed) {
        debugPrint(
          'ICE CONNECTION FAILED',
        );

        _notifyCallEnded(
          'ICE connection failed',
        );
      }
    };

    // -------------------------------------------------------
    // ICE GATHERING
    // -------------------------------------------------------

    peerConnection!.onIceGatheringState =
        (RTCIceGatheringState state) {
      debugPrint(
        'ICE Gathering State: $state',
      );
    };

    // -------------------------------------------------------
    // SIGNALING STATE
    // -------------------------------------------------------

    peerConnection!.onSignalingState =
        (RTCSignalingState state) {
      debugPrint(
        'Signaling State: $state',
      );
    };

    // -------------------------------------------------------
    // REMOTE TRACK
    // -------------------------------------------------------

    peerConnection!.onTrack =
        (RTCTrackEvent event) {
      debugPrint(
        '==========================================',
      );

      debugPrint(
        'REMOTE TRACK RECEIVED',
      );

      debugPrint(
        'KIND: ${event.track.kind}',
      );

      debugPrint(
        'TRACK ID: ${event.track.id}',
      );

      debugPrint(
        'TRACK ENABLED: ${event.track.enabled}',
      );

      debugPrint(
        'TRACK MUTED: ${event.track.muted}',
      );

      debugPrint(
        'STREAM COUNT: ${event.streams.length}',
      );

      debugPrint(
        '==========================================',
      );

      // -----------------------------------------------------
      // REMOTE STREAM
      // -----------------------------------------------------

      if (event.streams.isNotEmpty) {
        remoteStream = event.streams.first;

        debugPrint(
          'REMOTE STREAM RECEIVED',
        );

        final audioTracks =
        remoteStream!.getAudioTracks();

        final videoTracks =
        remoteStream!.getVideoTracks();

        debugPrint(
          'REMOTE AUDIO TRACKS: '
              '${audioTracks.length}',
        );

        debugPrint(
          'REMOTE VIDEO TRACKS: '
              '${videoTracks.length}',
        );

        // ---------------------------------------------------
        // REMOTE AUDIO
        // ---------------------------------------------------

        for (final track in audioTracks) {
          debugPrint(
            'REMOTE AUDIO: '
                'id=${track.id}, '
                'enabled=${track.enabled}, '
                'muted=${track.muted}',
          );

          // Make sure remote audio is enabled.
          track.enabled = true;
        }

        // ---------------------------------------------------
        // REMOTE VIDEO
        // ---------------------------------------------------

        for (final track in videoTracks) {
          debugPrint(
            'REMOTE VIDEO: '
                'id=${track.id}, '
                'enabled=${track.enabled}, '
                'muted=${track.muted}',
          );
        }

        onRemoteStreamReady?.call(
          remoteStream!,
        );
      } else {
        debugPrint(
          'WARNING: Remote track has NO stream',
        );
      }
    };

    // -------------------------------------------------------
    // OLD STYLE STREAM CALLBACK
    // -------------------------------------------------------

    peerConnection!.onAddStream =
        (MediaStream stream) {
      debugPrint(
        'REMOTE STREAM ADDED',
      );

      remoteStream = stream;

      debugPrint(
        'REMOTE AUDIO TRACKS: '
            '${stream.getAudioTracks().length}',
      );

      debugPrint(
        'REMOTE VIDEO TRACKS: '
            '${stream.getVideoTracks().length}',
      );

      onRemoteStreamReady?.call(
        stream,
      );
    };

    debugPrint(
      'Peer connection created successfully',
    );
  }

  // =========================================================
  // GET LOCAL MEDIA
  // =========================================================

  Future<void> _getLocalMedia() async {
    final Map<String, dynamic> constraints = {
      'audio': {
        'echoCancellation': true,
        'noiseSuppression': true,
        'autoGainControl': true,
      },
      'video': isVideoCall
          ? {
        'facingMode': 'user',
        'width': {
          'ideal': 1280,
        },
        'height': {
          'ideal': 720,
        },
        'frameRate': {
          'ideal': 30,
        },
      }
          : false,
    };

    debugPrint(
      '==========================================',
    );

    debugPrint(
      'GETTING LOCAL MEDIA',
    );

    debugPrint(
      'VIDEO: $isVideoCall',
    );

    debugPrint(
      '==========================================',
    );

    // Request permissions before getting local media
    final micStatus = await Permission.microphone.request();
    if (micStatus.isDenied || micStatus.isPermanentlyDenied) {
      debugPrint('Microphone permission denied');
      // Continue anyway, getUserMedia will probably throw an error, which we catch
    }

    if (isVideoCall) {
      final camStatus = await Permission.camera.request();
      if (camStatus.isDenied || camStatus.isPermanentlyDenied) {
        debugPrint('Camera permission denied');
      }
    }

    localStream =
    await navigator.mediaDevices.getUserMedia(
      constraints,
    );

    // -------------------------------------------------------
    // AUDIO
    // -------------------------------------------------------

    final audioTracks =
    localStream!.getAudioTracks();

    debugPrint(
      'LOCAL AUDIO TRACKS: '
          '${audioTracks.length}',
    );

    for (final track in audioTracks) {
      debugPrint(
        'LOCAL AUDIO: '
            'id=${track.id}, '
            'enabled=${track.enabled}, '
            'muted=${track.muted}',
      );

      // Voice -> earpiece
      // Video -> speaker

      track.enableSpeakerphone(isVideoCall);


      debugPrint(
        'Speakerphone: $isVideoCall',
      );
    }

    // -------------------------------------------------------
    // VIDEO
    // -------------------------------------------------------

    if (isVideoCall) {
      final videoTracks =
      localStream!.getVideoTracks();

      debugPrint(
        'LOCAL VIDEO TRACKS: '
            '${videoTracks.length}',
      );

      for (final track in videoTracks) {
        debugPrint(
          'LOCAL VIDEO: '
              'id=${track.id}, '
              'enabled=${track.enabled}, '
              'muted=${track.muted}',
        );
      }
    }

    debugPrint(
      'Local media created successfully',
    );
  }

  // =========================================================
  // ADD LOCAL TRACKS
  // =========================================================

  Future<void> _addLocalTracks() async {
    if (peerConnection == null) {
      throw Exception(
        'Peer connection not created',
      );
    }

    if (localStream == null) {
      await _getLocalMedia();
    }

    debugPrint(
      '==========================================',
    );

    debugPrint(
      'ADDING LOCAL TRACKS',
    );

    debugPrint(
      '==========================================',
    );

    final tracks =
    localStream!.getTracks();

    for (final track in tracks) {
      debugPrint(
        'LOCAL TRACK BEFORE ADD: '
            'kind=${track.kind}, '
            'id=${track.id}, '
            'enabled=${track.enabled}, '
            'muted=${track.muted}',
      );

      await peerConnection!.addTrack(
        track,
        localStream!,
      );

      debugPrint(
        'LOCAL TRACK ADDED: '
            '${track.kind}',
      );
    }

    debugPrint(
      'All local tracks added',
    );
  }

  // =========================================================
  // CREATE OUTGOING CALL
  // =========================================================

  Future<String> createCall({
    required String callerId,
    required String receiverId,
    String callerName = '',
    String callerPhone = '',
    String? callerAvatarUrl,
    String receiverName = '',
    String receiverPhone = '',
    String? receiverAvatarUrl,
    String callType = 'voice',
  }) async {
    currentCallType = callType;

    debugPrint(
      '==========================================',
    );

    debugPrint(
      'CREATING OUTGOING CALL',
    );

    debugPrint(
      'TYPE: $currentCallType',
    );

    debugPrint(
      'CALLER: $callerId',
    );

    debugPrint(
      'RECEIVER: $receiverId',
    );

    debugPrint(
      '==========================================',
    );

    // -------------------------------------------------------
    // PEER
    // -------------------------------------------------------

    await _createPeerConnection();

    // -------------------------------------------------------
    // LOCAL MEDIA
    // -------------------------------------------------------

    await _addLocalTracks();

    // -------------------------------------------------------
    // FIRESTORE
    // -------------------------------------------------------

    final callDoc =
    _firestore.collection('calls').doc();

    final callerCandidates =
    callDoc.collection(
      'callerCandidates',
    );

    final calleeCandidates =
    callDoc.collection(
      'calleeCandidates',
    );

    // -------------------------------------------------------
    // CALLER ICE
    // -------------------------------------------------------

    peerConnection!.onIceCandidate =
        (RTCIceCandidate candidate) async {
      if (candidate.candidate == null) {
        return;
      }

      try {
        await callerCandidates.add({
          'candidate': candidate.candidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex':
          candidate.sdpMLineIndex,
        });

        debugPrint(
          'Caller ICE candidate added',
        );
      } catch (e) {
        debugPrint(
          'Caller ICE error: $e',
        );
      }
    };

    // -------------------------------------------------------
    // OFFER
    // -------------------------------------------------------

    final RTCSessionDescription offer =
    await peerConnection!.createOffer({
      'offerToReceiveAudio': 1,
      'offerToReceiveVideo':
      isVideoCall ? 1 : 0,
    });

    await peerConnection!
        .setLocalDescription(
      offer,
    );

    debugPrint(
      'Local offer created',
    );

    debugPrint(
      'Offer SDP length: '
          '${offer.sdp?.length ?? 0}',
    );

    // -------------------------------------------------------
    // FIRESTORE CALL DOCUMENT
    // -------------------------------------------------------

    await callDoc.set({
      'callerId': callerId,
      'receiverId': receiverId,

      'callerName': callerName,
      'callerPhone': callerPhone,
      'callerAvatarUrl': callerAvatarUrl ?? '',

      'receiverName': receiverName,
      'receiverPhone': receiverPhone,
      'receiverAvatarUrl': receiverAvatarUrl ?? '',

      'type': currentCallType,
      'status': 'calling',

      // Tracks what mode the call should currently be displayed in.
      // Kept in sync separately from 'type' so a voice<->video switch
      // mid-call doesn't get confused with the original upgrade flow.
      'displayMode': currentCallType,

      'offer': {
        'type': offer.type,
        'sdp': offer.sdp,
      },

      'createdAt':
      FieldValue.serverTimestamp(),
      'timestamp':
      FieldValue.serverTimestamp(),
    });

    debugPrint(
      '==========================================',
    );

    debugPrint(
      'OUTGOING CALL CREATED',
    );

    debugPrint(
      'CALL ID: ${callDoc.id}',
    );

    debugPrint(
      'TYPE: $currentCallType',
    );

    debugPrint(
      '==========================================',
    );

    // -------------------------------------------------------
    // ANSWER + STATUS LISTENER
    // -------------------------------------------------------

    callSubscription =
        callDoc.snapshots().listen(
              (snapshot) async {
            final data =
            snapshot.data();

            if (data == null) {
              return;
            }

            final answer =
            data['answer'];

            final status =
            data['status'];

            // ---------------------------------------------------
            // ANSWER
            // ---------------------------------------------------

            if (answer != null &&
                peerConnection != null) {
              try {
                final remoteDescription =
                await peerConnection!
                    .getRemoteDescription();

                if (remoteDescription == null) {
                  final RTCSessionDescription
                  answerDescription =
                  RTCSessionDescription(
                    answer['sdp'],
                    answer['type'],
                  );

                  await peerConnection!
                      .setRemoteDescription(
                    answerDescription,
                  );

                  debugPrint(
                    'Remote answer set successfully',
                  );
                }
              } catch (e) {
                debugPrint(
                  'Remote answer error: $e',
                );
              }
            }

            // ---------------------------------------------------
            // CALLER: Handle upgrade answer from callee
            // ---------------------------------------------------

            final upgradeAnswer = data['upgradeAnswer'];

            if (upgradeAnswer != null &&
                peerConnection != null &&
                currentCallType == 'video') {
              try {
                final currentRemote =
                await peerConnection!.getRemoteDescription();

                // Only set if upgrade answer hasn't been applied yet
                // (check by SDP content difference)
                final currentSdp = currentRemote?.sdp ?? '';
                final newSdp =
                    upgradeAnswer['sdp']?.toString() ?? '';

                if (!currentSdp.contains('m=video') &&
                    newSdp.contains('m=video')) {
                  final RTCSessionDescription upgradeAnswerDesc =
                  RTCSessionDescription(
                    upgradeAnswer['sdp'],
                    upgradeAnswer['type'],
                  );

                  await peerConnection!.setRemoteDescription(
                    upgradeAnswerDesc,
                  );

                  debugPrint(
                    'UPGRADE: Caller set remote upgrade answer',
                  );
                }
              } catch (e) {
                debugPrint(
                  'UPGRADE: Caller error setting upgrade answer: $e',
                );
              }
            }

            // ---------------------------------------------------
            // DISPLAY MODE SWITCH (video <-> voice, either side)
            // ---------------------------------------------------

            final displayMode = data['displayMode'];

            if (displayMode != null) {
              final bool remoteWantsVideo =
                  displayMode == 'video';

              if (remoteWantsVideo != isVideoCall) {
                currentCallType =
                remoteWantsVideo ? 'video' : 'voice';

                onCallModeChanged?.call(remoteWantsVideo);
              }
            }

            // ---------------------------------------------------
            // REJECTED
            // ---------------------------------------------------

            if (status == 'rejected') {
              _notifyCallEnded(
                'Call rejected',
              );
            }

            // ---------------------------------------------------
            // ENDED
            // ---------------------------------------------------

            if (status == 'ended') {
              _notifyCallEnded(
                'Call ended',
              );
            }
          },
        );

    // -------------------------------------------------------
    // CALLEE ICE
    // -------------------------------------------------------

    candidateSubscription =
        calleeCandidates.snapshots().listen(
              (snapshot) async {
            for (final change
            in snapshot.docChanges) {
              if (change.type !=
                  DocumentChangeType.added) {
                continue;
              }

              final data =
              change.doc.data();

              if (data == null) {
                continue;
              }

              final candidate =
              RTCIceCandidate(
                data['candidate'],
                data['sdpMid'],
                data['sdpMLineIndex'],
              );

              try {
                await peerConnection
                    ?.addCandidate(
                  candidate,
                );

                debugPrint(
                  'Caller added remote ICE',
                );
              } catch (e) {
                debugPrint(
                  'Error adding callee ICE: $e',
                );
              }
            }
          },
        );

    return callDoc.id;
  }

  // =========================================================
  // ANSWER INCOMING CALL
  // =========================================================

  Future<void> answerCall({
    required String callId,
  }) async {
    final callDoc =
    _firestore
        .collection('calls')
        .doc(callId);

    debugPrint(
      '==========================================',
    );

    debugPrint(
      'ANSWERING INCOMING CALL',
    );

    debugPrint(
      'CALL ID: $callId',
    );

    debugPrint(
      '==========================================',
    );

    // -------------------------------------------------------
    // GET CALL
    // -------------------------------------------------------

    final snapshot =
    await callDoc.get();

    final data =
    snapshot.data();

    if (data == null) {
      throw Exception(
        'Call document not found',
      );
    }

    // -------------------------------------------------------
    // CALL TYPE
    // -------------------------------------------------------

    currentCallType =
        data['type']?.toString() ??
            'voice';

    debugPrint(
      'INCOMING CALL TYPE: '
          '$currentCallType',
    );

    // -------------------------------------------------------
    // PEER
    // -------------------------------------------------------

    await _createPeerConnection();

    // -------------------------------------------------------
    // LOCAL MEDIA
    // -------------------------------------------------------

    await _addLocalTracks();

    final callerCandidates =
    callDoc.collection(
      'callerCandidates',
    );

    final calleeCandidates =
    callDoc.collection(
      'calleeCandidates',
    );

    // -------------------------------------------------------
    // CALLEE ICE
    // -------------------------------------------------------

    peerConnection!.onIceCandidate =
        (RTCIceCandidate candidate) async {
      if (candidate.candidate == null) {
        return;
      }

      try {
        await calleeCandidates.add({
          'candidate': candidate.candidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex':
          candidate.sdpMLineIndex,
        });

        debugPrint(
          'Callee ICE candidate added',
        );
      } catch (e) {
        debugPrint(
          'Callee ICE error: $e',
        );
      }
    };

    // -------------------------------------------------------
    // OFFER
    // -------------------------------------------------------

    final offer =
    data['offer'];

    if (offer == null) {
      throw Exception(
        'Call offer not found',
      );
    }

    final RTCSessionDescription
    offerDescription =
    RTCSessionDescription(
      offer['sdp'],
      offer['type'],
    );

    // -------------------------------------------------------
    // SET REMOTE OFFER
    // -------------------------------------------------------

    await peerConnection!
        .setRemoteDescription(
      offerDescription,
    );

    debugPrint(
      'Caller offer set successfully',
    );

    // -------------------------------------------------------
    // ANSWER
    // -------------------------------------------------------

    final RTCSessionDescription
    answer =
    await peerConnection!
        .createAnswer({
      'offerToReceiveAudio': 1,
      'offerToReceiveVideo':
      isVideoCall ? 1 : 0,
    });

    await peerConnection!
        .setLocalDescription(
      answer,
    );

    debugPrint(
      'Local answer created',
    );

    debugPrint(
      'Answer SDP length: '
          '${answer.sdp?.length ?? 0}',
    );

    // -------------------------------------------------------
    // FIRESTORE UPDATE
    // -------------------------------------------------------

    await callDoc.update({
      'answer': {
        'type': answer.type,
        'sdp': answer.sdp,
      },
      'status': 'accepted',
      'acceptedAt':
      FieldValue.serverTimestamp(),
    });

    debugPrint(
      '==========================================',
    );

    debugPrint(
      '$currentCallType CALL ACCEPTED',
    );

    debugPrint(
      'CALL ID: $callId',
    );

    debugPrint(
      '==========================================',
    );

    // -------------------------------------------------------
    // CALLER ICE
    // -------------------------------------------------------

    candidateSubscription =
        callerCandidates.snapshots().listen(
              (snapshot) async {
            for (final change
            in snapshot.docChanges) {
              if (change.type !=
                  DocumentChangeType.added) {
                continue;
              }

              final data =
              change.doc.data();

              if (data == null) {
                continue;
              }

              final candidate =
              RTCIceCandidate(
                data['candidate'],
                data['sdpMid'],
                data['sdpMLineIndex'],
              );

              try {
                await peerConnection
                    ?.addCandidate(
                  candidate,
                );

                debugPrint(
                  'Callee added caller ICE',
                );
              } catch (e) {
                debugPrint(
                  'Error adding caller ICE: $e',
                );
              }
            }
          },
        );

    // -------------------------------------------------------
    // CALL STATUS
    // -------------------------------------------------------

    callSubscription =
        callDoc.snapshots().listen(
              (snapshot) async {
            final data =
            snapshot.data();

            if (data == null) {
              return;
            }

            final status =
            data['status'];

            if (status == 'ended') {
              _notifyCallEnded(
                'Call ended',
              );
            }

            if (status == 'rejected') {
              _notifyCallEnded(
                'Call rejected',
              );
            }

            // ---------------------------------------------------
            // CALLEE: Handle voice → video upgrade offer
            // ---------------------------------------------------

            final upgradeOffer = data['upgradeOffer'];

            if (upgradeOffer != null &&
                peerConnection != null &&
                currentCallType == 'voice') {
              try {
                debugPrint(
                  'UPGRADE: Callee received upgrade offer',
                );

                // Update call type
                currentCallType = 'video';

                // Add local video track
                final MediaStream videoStream =
                await navigator.mediaDevices.getUserMedia({
                  'audio': false,
                  'video': {
                    'facingMode': 'user',
                    'width': {'ideal': 1280},
                    'height': {'ideal': 720},
                    'frameRate': {'ideal': 30},
                  },
                });

                final videoTracks = videoStream.getVideoTracks();

                if (localStream != null && videoTracks.isNotEmpty) {
                  for (final track in videoTracks) {
                    await localStream!.addTrack(track);
                    await peerConnection!.addTrack(
                      track,
                      localStream!,
                    );
                  }
                }

                // Switch audio to speaker
                final audioTracks =
                    localStream?.getAudioTracks() ?? [];
                for (final track in audioTracks) {
                  track.enableSpeakerphone(true);
                }

                // Set remote upgrade offer
                final RTCSessionDescription upgradeDesc =
                RTCSessionDescription(
                  upgradeOffer['sdp'],
                  upgradeOffer['type'],
                );

                await peerConnection!.setRemoteDescription(
                  upgradeDesc,
                );

                // Create & set upgrade answer
                final RTCSessionDescription upgradeAnswer =
                await peerConnection!.createAnswer({
                  'offerToReceiveAudio': 1,
                  'offerToReceiveVideo': 1,
                });

                await peerConnection!.setLocalDescription(
                  upgradeAnswer,
                );

                // Write upgrade answer to Firestore
                await callDoc.update({
                  'upgradeAnswer': {
                    'type': upgradeAnswer.type,
                    'sdp': upgradeAnswer.sdp,
                  },
                });

                debugPrint(
                  'UPGRADE: Callee answer written to Firestore',
                );

                // Notify callee UI
                onUpgradedToVideo?.call();
              } catch (e) {
                debugPrint(
                  'UPGRADE: Callee error handling upgrade: $e',
                );
              }
            }

            // ---------------------------------------------------
            // DISPLAY MODE SWITCH (video <-> voice, either side)
            // ---------------------------------------------------

            final displayMode = data['displayMode'];

            if (displayMode != null) {
              final bool remoteWantsVideo =
                  displayMode == 'video';

              if (remoteWantsVideo != isVideoCall) {
                currentCallType =
                remoteWantsVideo ? 'video' : 'voice';

                onCallModeChanged?.call(remoteWantsVideo);
              }
            }
          },
        );
  }

  // =========================================================
  // MUTE / UNMUTE
  // =========================================================

  void setMuted(bool muted) {
    if (localStream == null) {
      debugPrint(
        'MUTE ERROR: localStream is null',
      );
      return;
    }

    final audioTracks =
    localStream!.getAudioTracks();

    if (audioTracks.isEmpty) {
      debugPrint(
        'MUTE ERROR: No audio tracks',
      );
      return;
    }

    debugPrint(
      '==========================================',
    );

    debugPrint(
      muted
          ? 'MICROPHONE MUTING'
          : 'MICROPHONE UNMUTING',
    );

    for (final track in audioTracks) {
      track.enabled = !muted;

      debugPrint(
        'MUTE RESULT: '
            'muted=$muted | '
            'enabled=${track.enabled} | '
            'id=${track.id}',
      );
    }

    debugPrint(
      muted
          ? 'MICROPHONE MUTED'
          : 'MICROPHONE UNMUTED',
    );

    debugPrint(
      '==========================================',
    );
  }

  // =========================================================
  // CAMERA
  // =========================================================

  void setCameraEnabled(
      bool enabled,
      ) {
    if (localStream == null) {
      debugPrint(
        'CAMERA ERROR: localStream is null',
      );
      return;
    }

    final videoTracks =
    localStream!.getVideoTracks();

    if (videoTracks.isEmpty) {
      debugPrint(
        'CAMERA ERROR: No video tracks',
      );
      return;
    }

    for (final track in videoTracks) {
      track.enabled = enabled;

      debugPrint(
        'CAMERA: '
            'enabled=$enabled | '
            'id=${track.id}',
      );
    }
  }

  // =========================================================
  // SWITCH CAMERA
  // =========================================================

  Future<void> switchCamera() async {
    if (localStream == null) {
      debugPrint(
        'SWITCH CAMERA: localStream null',
      );
      return;
    }

    final videoTracks =
    localStream!.getVideoTracks();

    if (videoTracks.isEmpty) {
      debugPrint(
        'SWITCH CAMERA: No video tracks',
      );
      return;
    }

    try {
      await Helper.switchCamera(
        videoTracks.first,
      );

      debugPrint(
        'Camera switched',
      );
    } catch (e) {
      debugPrint(
        'Camera switch error: $e',
      );
    }
  }

  // =========================================================
  // SPEAKERPHONE
  // =========================================================

  Future<void> setSpeakerphone(
      bool enable,
      ) async {
    if (localStream == null) {
      debugPrint(
        'SPEAKER: localStream null',
      );
      return;
    }

    final audioTracks =
    localStream!.getAudioTracks();

    for (final track in audioTracks) {
      track.enableSpeakerphone(enable
      );
    }

    debugPrint(
      'Speakerphone: $enable',
    );
  }

  // =========================================================
  // UPGRADE VOICE → VIDEO
  // (full SDP renegotiation — adds a video m-line the very first
  // time video is needed on a call that started as voice-only)
  // =========================================================

  /// Upgrades an active voice call to video by adding a video track
  /// and performing a WebRTC SDP renegotiation.
  ///
  /// This is called by the CALLER side (the one who initiates the upgrade).
  /// The callee side detects the `upgradeOffer` in Firestore and auto-accepts.
  Future<void> upgradeToVideo({
    required String callId,
  }) async {
    if (peerConnection == null) {
      debugPrint('UPGRADE: peerConnection is null');
      return;
    }

    debugPrint('==========================================');
    debugPrint('UPGRADING VOICE → VIDEO');
    debugPrint('==========================================');

    // -------------------------------------------------------
    // GET VIDEO STREAM
    // -------------------------------------------------------

    final MediaStream videoStream =
    await navigator.mediaDevices.getUserMedia({
      'audio': false,
      'video': {
        'facingMode': 'user',
        'width': {'ideal': 1280},
        'height': {'ideal': 720},
        'frameRate': {'ideal': 30},
      },
    });

    final videoTracks = videoStream.getVideoTracks();

    if (videoTracks.isEmpty) {
      debugPrint('UPGRADE: No video tracks obtained');
      await videoStream.dispose();
      return;
    }

    // -------------------------------------------------------
    // ADD VIDEO TRACK TO PEER CONNECTION
    // -------------------------------------------------------

    // Add the video track to the existing local stream
    if (localStream != null) {
      for (final track in videoTracks) {
        await localStream!.addTrack(track);
        await peerConnection!.addTrack(track, localStream!);
        debugPrint('UPGRADE: Added video track: ${track.id}');
      }
    }

    // Update call type
    currentCallType = 'video';

    // Switch audio to speaker for video call
    final audioTracks = localStream?.getAudioTracks() ?? [];
    for (final track in audioTracks) {
      track.enableSpeakerphone(true);
    }

    // -------------------------------------------------------
    // SDP RENEGOTIATION — CREATE NEW OFFER
    // -------------------------------------------------------

    final RTCSessionDescription upgradeOffer =
    await peerConnection!.createOffer({
      'offerToReceiveAudio': 1,
      'offerToReceiveVideo': 1,
    });

    await peerConnection!.setLocalDescription(upgradeOffer);

    debugPrint('UPGRADE: New offer created for video');
    debugPrint('UPGRADE: SDP length: ${upgradeOffer.sdp?.length ?? 0}');

    // -------------------------------------------------------
    // WRITE UPGRADE OFFER TO FIRESTORE
    // -------------------------------------------------------

    await _firestore.collection('calls').doc(callId).update({
      'upgradeOffer': {
        'type': upgradeOffer.type,
        'sdp': upgradeOffer.sdp,
      },
      'type': 'video',
      'displayMode': 'video',
      'upgradedAt': FieldValue.serverTimestamp(),
    });

    debugPrint('UPGRADE: Upgrade offer written to Firestore');

    // Notify local UI
    onUpgradedToVideo?.call();
  }

  // =========================================================
  // SWITCH DISPLAY MODE (video <-> voice) ON AN ALREADY-VIDEO CALL
  //
  // Lightweight switch used once the call already has a video m-line
  // negotiated (i.e. it either started as a video call, or has already
  // gone through upgradeToVideo() once). It just enables/disables the
  // local video track and syncs a 'displayMode' flag over Firestore —
  // no renegotiation needed, works instantly in both directions.
  //
  // If the call has NEVER had a video track negotiated yet (a pure
  // voice call, receiver side never called upgradeToVideo), call
  // upgradeToVideo() instead of this method when switching to video
  // for the first time.
  // =========================================================

  Future<void> switchCallMode({
    required String callId,
    required bool toVideo,
  }) async {
    debugPrint('==========================================');
    debugPrint('SWITCHING CALL MODE: toVideo=$toVideo');
    debugPrint('==========================================');

    currentCallType = toVideo ? 'video' : 'voice';

    final videoTracks = localStream?.getVideoTracks() ?? [];

    if (videoTracks.isEmpty && toVideo) {
      // No video track negotiated yet on this call — fall back to a
      // full upgrade instead of silently doing nothing.
      debugPrint(
        'SWITCH: No existing video track, falling back to upgradeToVideo()',
      );
      await upgradeToVideo(callId: callId);
      return;
    }

    for (final track in videoTracks) {
      track.enabled = toVideo;

      debugPrint(
        'SWITCH: video track ${track.id} enabled=$toVideo',
      );
    }

    // Voice-only -> keep earpiece; video -> speaker
    final audioTracks = localStream?.getAudioTracks() ?? [];
    for (final track in audioTracks) {
      track.enableSpeakerphone(toVideo);
    }

    try {
      await _firestore.collection('calls').doc(callId).update({
        'displayMode': toVideo ? 'video' : 'voice',
      });
    } catch (e) {
      debugPrint('SWITCH: Firestore update error: $e');
    }

    onCallModeChanged?.call(toVideo);
  }

  // =========================================================
  // INCOMING CALLS
  // =========================================================

  Stream<QuerySnapshot<Map<String, dynamic>>>
  listenForIncomingCalls(
      String userId,
      ) {
    return _firestore
        .collection('calls')
        .where(
      'receiverId',
      isEqualTo: userId,
    )
        .where(
      'status',
      isEqualTo: 'calling',
    )
        .snapshots();
  }

  // =========================================================
  // REJECT CALL
  // =========================================================

  Future<void> rejectCall({
    required String callId,
  }) async {
    debugPrint(
      'Rejecting call: $callId',
    );

    try {
      await _firestore
          .collection('calls')
          .doc(callId)
          .update({
        'status': 'rejected',
        'endedAt':
        FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint(
        'Reject call error: $e',
      );
    }

    await disposeConnection();
  }

  // =========================================================
  // END CALL
  // =========================================================

  Future<void> endCall({
    required String callId,
  }) async {
    debugPrint(
      'Ending call: $callId',
    );

    try {
      await _firestore
          .collection('calls')
          .doc(callId)
          .update({
        'status': 'ended',
        'endedAt':
        FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint(
        'End call error: $e',
      );
    }

    await disposeConnection();
  }

  // =========================================================
  // DISPOSE CONNECTION
  // =========================================================

  Future<void> disposeConnection() async {
    debugPrint(
      '==========================================',
    );

    debugPrint(
      'DISPOSING CALL CONNECTION',
    );

    debugPrint(
      '==========================================',
    );

    // -------------------------------------------------------
    // FIRESTORE LISTENERS
    // -------------------------------------------------------

    try {
      await callSubscription?.cancel();
    } catch (e) {
      debugPrint(
        'Call subscription cancel error: $e',
      );
    }

    try {
      await candidateSubscription?.cancel();
    } catch (e) {
      debugPrint(
        'Candidate subscription cancel error: $e',
      );
    }

    callSubscription = null;
    candidateSubscription = null;

    // -------------------------------------------------------
    // LOCAL STREAM
    // -------------------------------------------------------

    try {
      final tracks =
          localStream?.getTracks() ?? [];

      debugPrint(
        'Stopping local tracks: '
            '${tracks.length}',
      );

      for (final track in tracks) {
        debugPrint(
          'Stopping local track: '
              '${track.kind} ${track.id}',
        );

        track.stop();
      }

      await localStream?.dispose();
    } catch (e) {
      debugPrint(
        'Local stream dispose error: $e',
      );
    }

    // -------------------------------------------------------
    // REMOTE STREAM
    // -------------------------------------------------------

    try {
      final tracks =
          remoteStream?.getTracks() ?? [];

      debugPrint(
        'Stopping remote tracks: '
            '${tracks.length}',
      );

      for (final track in tracks) {
        debugPrint(
          'Stopping remote track: '
              '${track.kind} ${track.id}',
        );

        track.stop();
      }

      await remoteStream?.dispose();
    } catch (e) {
      debugPrint(
        'Remote stream dispose error: $e',
      );
    }

    // -------------------------------------------------------
    // PEER CONNECTION
    // -------------------------------------------------------

    try {
      await peerConnection?.close();
      await peerConnection?.dispose();
    } catch (e) {
      debugPrint(
        'Peer connection dispose error: $e',
      );
    }

    // -------------------------------------------------------
    // RESET
    // -------------------------------------------------------

    localStream = null;
    remoteStream = null;
    peerConnection = null;

    _connectionNotified = false;
    _callEndedNotified = false;

    debugPrint(
      'Call connection disposed',
    );
  }

  // =========================================================
  // FINAL DISPOSE
  // =========================================================

  Future<void> dispose() async {
    await disposeConnection();
  }
}