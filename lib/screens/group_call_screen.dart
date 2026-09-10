import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/user_model.dart';
import '../services/group_call_service.dart';
import '../services/notification_service.dart';
import '../services/ringtone_service.dart';
import '../widgets/avatar_image_helper.dart';

class GroupCallScreen extends StatefulWidget {
  final String callId;
  final String groupId;
  final String groupName;
  final UserModel currentUser;
  final List<UserModel> groupMembers;
  final bool isVideo;
  final bool isIncoming;

  const GroupCallScreen({
    super.key,
    required this.callId,
    required this.groupId,
    required this.groupName,
    required this.currentUser,
    required this.groupMembers,
    required this.isVideo,
    this.isIncoming = false,
  });

  @override
  State<GroupCallScreen> createState() => _GroupCallScreenState();
}

class _GroupCallScreenState extends State<GroupCallScreen>
    with TickerProviderStateMixin {
  final GroupCallService _groupCallService = GroupCallService();
  final RingtoneService _ringtoneService = RingtoneService();

  late bool _isVideo;
  bool _isMuted = false;
  bool _isSpeakerOn = true;
  bool _isFrontCamera = true;
  bool _isEndingCall = false;
  bool _isIncomingState = false;

  // WebRTC local camera preview
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  MediaStream? _localStream;
  bool _localRendererInitialized = false;

  // WebRTC Mesh Peer Connections & Remote Renderers
  final Map<String, RTCPeerConnection> _peerConnections = {};
  final Map<String, RTCVideoRenderer> _remoteRenderers = {};
  final Map<String, MediaStream> _remoteStreams = {};
  StreamSubscription? _signalsSubscription;
  final Set<String> _processedSignalIds = {};

  final Map<String, dynamic> _iceConfiguration = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
      {'urls': 'stun:stun2.l.google.com:19302'},
    ],
    'sdpSemantics': 'unified-plan',
  };

  // Call duration timer
  Timer? _callTimer;
  int _callDurationSeconds = 0;
  bool _hasConnected = false;

  // Pulse animation for speaking/ringing avatar
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  StreamSubscription<GroupCallModel?>? _callStreamSub;
  GroupCallModel? _currentCallModel;

  @override
  void initState() {
    super.initState();
    _isVideo = widget.isVideo;
    NotificationService().activeCallId = widget.callId;

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _listenToCallDoc();

    if (widget.isIncoming) {
      _isIncomingState = true;
      _ringtoneService.startRingtone();
    } else {
      _isIncomingState = false;
      _ringtoneService.startOutgoingRingtone();
      _initLocalMediaAndWebRTC();
    }
  }

  Future<void> _acceptIncomingCall() async {
    setState(() {
      _isIncomingState = false;
    });

    _ringtoneService.stopRingtone();

    await _initLocalMediaAndWebRTC();

    await _groupCallService.joinGroupCall(
      callId: widget.callId,
      user: widget.currentUser,
      isVideo: _isVideo,
    );
  }

  Future<void> _initLocalMediaAndWebRTC() async {
    try {
      await _localRenderer.initialize();
      if (!mounted) return;
      setState(() => _localRendererInitialized = true);

      await [Permission.camera, Permission.microphone].request();

      final Map<String, dynamic> mediaConstraints = {
        'audio': true,
        'video': {
          'facingMode': _isFrontCamera ? 'user' : 'environment',
          'width': {'ideal': 640},
          'height': {'ideal': 480},
        },
      };

      final stream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
      _localStream = stream;

      // If initially in voice mode, mute video track
      if (!_isVideo) {
        _localStream?.getVideoTracks().forEach((t) => t.enabled = false);
      }

      if (mounted) {
        setState(() {
          _localRenderer.srcObject = stream;
        });
      }

      // Audio setup: ensure speakerphone is on and audio tracks enabled
      Helper.setSpeakerphoneOn(_isSpeakerOn);
      _localStream?.getAudioTracks().forEach((t) {
        t.enableSpeakerphone(_isSpeakerOn);
      });

      // Start listening to incoming WebRTC signals from other participants
      _listenToSignals();

      // Connect with any already active participants in the call
      if (_currentCallModel != null) {
        _syncPeerConnections(_currentCallModel!.participants);
      }
    } catch (e) {
      debugPrint('GroupCallScreen: Error initializing local media: $e');
    }
  }

  void _syncPeerConnections(List<GroupCallParticipant> participants) {
    if (_localStream == null) return;

    for (final p in participants) {
      if (p.userId == widget.currentUser.id) continue;
      if (!p.isConnected) continue;

      if (!_peerConnections.containsKey(p.userId)) {
        _createPeerConnectionFor(p.userId);
      }
    }
  }

  Future<RTCPeerConnection> _createPeerConnectionFor(String peerUserId, {bool isOfferer = false}) async {
    if (_peerConnections.containsKey(peerUserId)) {
      return _peerConnections[peerUserId]!;
    }

    final renderer = RTCVideoRenderer();
    await renderer.initialize();
    _remoteRenderers[peerUserId] = renderer;

    final pc = await createPeerConnection(_iceConfiguration);
    _peerConnections[peerUserId] = pc;

    // Add local audio and video tracks
    if (_localStream != null) {
      for (final track in _localStream!.getTracks()) {
        await pc.addTrack(track, _localStream!);
      }
    }

    pc.onTrack = (event) {
      debugPrint('GroupCall: Remote track received from $peerUserId: ${event.track.kind}');
      if (event.streams.isNotEmpty) {
        final stream = event.streams.first;
        _remoteStreams[peerUserId] = stream;
        _remoteRenderers[peerUserId]?.srcObject = stream;

        // Ensure incoming audio plays through speakerphone
        stream.getAudioTracks().forEach((t) {
          t.enableSpeakerphone(_isSpeakerOn);
        });
      }
      Helper.setSpeakerphoneOn(_isSpeakerOn);
      if (mounted) setState(() {});
    };

    pc.onIceCandidate = (candidate) {
      if (candidate.candidate == null) return;
      _groupCallService.sendSignal(
        callId: widget.callId,
        fromUserId: widget.currentUser.id,
        toUserId: peerUserId,
        type: 'candidate',
        data: {
          'candidate': candidate.candidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex,
        },
      );
    };

    // Polite offer rule: smaller userId sends the offer to prevent glare
    final bool shouldOffer = isOfferer || widget.currentUser.id.compareTo(peerUserId) < 0;
    if (shouldOffer) {
      try {
        final offer = await pc.createOffer();
        await pc.setLocalDescription(offer);
        await _groupCallService.sendSignal(
          callId: widget.callId,
          fromUserId: widget.currentUser.id,
          toUserId: peerUserId,
          type: 'offer',
          data: {'type': offer.type, 'sdp': offer.sdp},
        );
      } catch (e) {
        debugPrint('GroupCall: Error creating offer for $peerUserId: $e');
      }
    }

    if (mounted) setState(() {});
    return pc;
  }

  void _listenToSignals() {
    _signalsSubscription?.cancel();
    _signalsSubscription = _groupCallService
        .streamIncomingSignals(callId: widget.callId, myUserId: widget.currentUser.id)
        .listen((snapshot) async {
      for (final doc in snapshot.docs) {
        if (_processedSignalIds.contains(doc.id)) continue;
        _processedSignalIds.add(doc.id);

        final data = doc.data();
        final fromUserId = data['fromUserId']?.toString() ?? '';
        final type = data['type']?.toString() ?? '';
        final signalData = data['data'];
        if (fromUserId.isEmpty || signalData == null) continue;

        try {
          if (type == 'offer') {
            var pc = _peerConnections[fromUserId];
            pc ??= await _createPeerConnectionFor(fromUserId, isOfferer: false);
            await pc.setRemoteDescription(RTCSessionDescription(
              signalData['sdp']?.toString(),
              signalData['type']?.toString(),
            ));
            final answer = await pc.createAnswer();
            await pc.setLocalDescription(answer);
            await _groupCallService.sendSignal(
              callId: widget.callId,
              fromUserId: widget.currentUser.id,
              toUserId: fromUserId,
              type: 'answer',
              data: {'type': answer.type, 'sdp': answer.sdp},
            );
          } else if (type == 'answer') {
            final pc = _peerConnections[fromUserId];
            if (pc != null) {
              await pc.setRemoteDescription(RTCSessionDescription(
                signalData['sdp']?.toString(),
                signalData['type']?.toString(),
              ));
            }
          } else if (type == 'candidate') {
            final pc = _peerConnections[fromUserId];
            if (pc != null) {
              final candidate = RTCIceCandidate(
                signalData['candidate']?.toString() ?? '',
                signalData['sdpMid']?.toString() ?? '',
                signalData['sdpMLineIndex'] is int ? signalData['sdpMLineIndex'] : 0,
              );
              await pc.addCandidate(candidate);
            }
          }

          _groupCallService.deleteSignal(callId: widget.callId, signalId: doc.id);
        } catch (e) {
          debugPrint('GroupCall: Error processing signal $type: $e');
        }
      }
    });
  }

  void _listenToCallDoc() {
    _callStreamSub = _groupCallService.streamGroupCall(widget.callId).listen((callModel) {
      if (!mounted || callModel == null) return;

      setState(() {
        _currentCallModel = callModel;
      });

      // If call is ended by others
      if (callModel.status == 'ended' && !_isEndingCall) {
        _hangupAndExit(announce: false);
        return;
      }

      // Sync WebRTC peer connections with connected participants
      _syncPeerConnections(callModel.participants);

      // Check if at least 2 participants are connected
      final connectedCount = callModel.participants.where((p) => p.isConnected).length;
      if (connectedCount >= 2 && !_hasConnected) {
        _hasConnected = true;
        _ringtoneService.stopRingtone();
        _startTimer();
      }
    });
  }

  void _startTimer() {
    _callTimer?.cancel();
    _callTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _callDurationSeconds++;
      });
    });
  }

  String _formatCallDuration(int totalSeconds) {
    final int minutes = totalSeconds ~/ 60;
    final int seconds = totalSeconds % 60;
    final String minutesStr = minutes.toString().padLeft(2, '0');
    final String secondsStr = seconds.toString().padLeft(2, '0');
    return '$minutesStr:$secondsStr';
  }

  // -----------------------------------------------------------
  // CONTROLS
  // -----------------------------------------------------------

  void _toggleMute() {
    setState(() => _isMuted = !_isMuted);
    _localStream?.getAudioTracks().forEach((track) {
      track.enabled = !_isMuted;
    });
    _groupCallService.updateParticipantState(
      callId: widget.callId,
      userId: widget.currentUser.id,
      isMuted: _isMuted,
    );
  }

  Future<void> _toggleVideo() async {
    setState(() => _isVideo = !_isVideo);

    if (_isVideo) {
      _localStream?.getVideoTracks().forEach((t) => t.enabled = true);
    } else {
      _localStream?.getVideoTracks().forEach((t) => t.enabled = false);
    }

    await _groupCallService.updateParticipantState(
      callId: widget.callId,
      userId: widget.currentUser.id,
      isVideoOff: !_isVideo,
    );
  }

  void _toggleSpeaker() {
    setState(() => _isSpeakerOn = !_isSpeakerOn);
    Helper.setSpeakerphoneOn(_isSpeakerOn);
    _localStream?.getAudioTracks().forEach((t) {
      t.enableSpeakerphone(_isSpeakerOn);
    });
    for (final stream in _remoteStreams.values) {
      stream.getAudioTracks().forEach((t) {
        t.enableSpeakerphone(_isSpeakerOn);
      });
    }
  }

  Future<void> _switchCamera() async {
    if (!_isVideo || _localStream == null) return;
    setState(() => _isFrontCamera = !_isFrontCamera);
    final videoTrack = _localStream?.getVideoTracks().firstOrNull;
    if (videoTrack != null) {
      await Helper.switchCamera(videoTrack);
    }
  }

  Future<void> _hangupAndExit({bool announce = true}) async {
    if (_isEndingCall) return;
    _isEndingCall = true;

    _ringtoneService.stopRingtone();
    _callTimer?.cancel();

    NotificationService().activeCallId = null;
    NotificationService().clearCallNotification();

    if (mounted) {
      Navigator.of(context).pop();
    }

    if (announce) {
      _groupCallService.leaveGroupCall(
        callId: widget.callId,
        userId: widget.currentUser.id,
        groupId: widget.groupId,
      ).catchError((e) {
        debugPrint('GroupCallScreen: Error leaving group call: $e');
      });
    }
  }

  void _openAddParticipantsSheet() {
    final invitedIds = _currentCallModel?.invitedUserIds ?? [];
    final uninvitedMembers = widget.groupMembers.where((m) {
      return m.id != widget.currentUser.id && !invitedIds.contains(m.id);
    }).toList();

    final Set<String> selectedToAdd = {};

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1F2C34),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Add participants to call',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.white70),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (uninvitedMembers.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Text(
                      'All group members have been invited.',
                      style: TextStyle(color: Colors.white60, fontSize: 14),
                    ),
                  ),
                )
              else ...[
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: uninvitedMembers.length,
                    itemBuilder: (context, idx) {
                      final m = uninvitedMembers[idx];
                      final isSelected = selectedToAdd.contains(m.id);

                      return ListTile(
                        onTap: () {
                          setModalState(() {
                            if (isSelected) {
                              selectedToAdd.remove(m.id);
                            } else {
                              selectedToAdd.add(m.id);
                            }
                          });
                        },
                        leading: CircleAvatar(
                          backgroundColor: const Color(0xFF00A884),
                          backgroundImage: getAvatarImageProvider(m.avatarUrl),
                          child: (m.avatarUrl == null || m.avatarUrl!.isEmpty)
                              ? Text(
                                  m.name.isNotEmpty ? m.name[0].toUpperCase() : '👤',
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                )
                              : null,
                        ),
                        title: Text(
                          m.name.isNotEmpty ? m.name : m.phoneNumber,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(
                          m.phoneNumber,
                          style: const TextStyle(color: Colors.white54, fontSize: 12),
                        ),
                        trailing: Checkbox(
                          value: isSelected,
                          activeColor: const Color(0xFF00A884),
                          checkColor: Colors.white,
                          onChanged: (val) {
                            setModalState(() {
                              if (val == true) {
                                selectedToAdd.add(m.id);
                              } else {
                                selectedToAdd.remove(m.id);
                              }
                            });
                          },
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00A884),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: selectedToAdd.isEmpty
                      ? null
                      : () async {
                          final toInvite = uninvitedMembers
                              .where((m) => selectedToAdd.contains(m.id))
                              .toList();
                          Navigator.pop(ctx);
                          await _groupCallService.inviteMoreMembers(
                            callId: widget.callId,
                            newMembers: toInvite,
                          );
                        },
                  child: Text('Add to call (${selectedToAdd.length})'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _ringtoneService.stopRingtone();
    _callTimer?.cancel();
    _pulseController.dispose();
    _callStreamSub?.cancel();
    _signalsSubscription?.cancel();
    for (final pc in _peerConnections.values) {
      pc.close();
    }
    _peerConnections.clear();
    for (final r in _remoteRenderers.values) {
      r.dispose();
    }
    _remoteRenderers.clear();
    for (final s in _remoteStreams.values) {
      s.dispose();
    }
    _remoteStreams.clear();
    _localStream?.dispose();
    if (_localRendererInitialized) {
      _localRenderer.dispose();
    }
    NotificationService().activeCallId = null;
    super.dispose();
  }

  // -----------------------------------------------------------
  // BUILD UI
  // -----------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    if (_isIncomingState) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _hangupAndExit(announce: false);
        },
        child: _buildIncomingCallView(),
      );
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _hangupAndExit();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0B141A),
        body: SafeArea(
          child: Stack(
            children: [
              // Dynamic Participant Grid
              Positioned.fill(
                child: Padding(
                  padding: const EdgeInsets.only(top: 80, bottom: 120),
                  child: _buildParticipantGrid(),
                ),
              ),

              // WhatsApp Top Header Bar
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: _buildTopHeader(),
              ),

              // WhatsApp Floating Control Pill
              Positioned(
                bottom: 20,
                left: 20,
                right: 20,
                child: _buildBottomControlDock(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildIncomingCallView() {
    final callerName = _currentCallModel?.callerName.isNotEmpty == true
        ? _currentCallModel!.callerName
        : 'Group Member';
    final groupName = widget.groupName;

    return Scaffold(
      backgroundColor: const Color(0xFF0B141A),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 36),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  _isVideo ? Icons.videocam_rounded : Icons.phone_rounded,
                  color: const Color(0xFF00A884),
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  _isVideo ? 'Incoming Group Video Call' : 'Incoming Group Voice Call',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                groupName,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '$callerName is inviting you...',
              style: const TextStyle(
                color: Color(0xFF00A884),
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),

            const Spacer(),

            // Pulsing Group Avatar
            Center(
              child: AnimatedBuilder(
                animation: _pulseAnimation,
                builder: (context, child) {
                  return Transform.scale(
                    scale: _pulseAnimation.value,
                    child: Container(
                      width: 140,
                      height: 140,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFF1F2C34),
                        border: Border.all(color: const Color(0xFF00A884), width: 3),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF00A884).withValues(alpha: 0.35),
                            blurRadius: 24,
                            spreadRadius: 8,
                          ),
                        ],
                      ),
                      child: Center(
                        child: Text(
                          groupName.isNotEmpty ? groupName[0].toUpperCase() : '👥',
                          style: const TextStyle(color: Colors.white, fontSize: 52, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),

            const Spacer(),

            // Action Buttons: Decline (Red) and Accept (Green)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 40),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Decline Button
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      GestureDetector(
                        onTap: () => _hangupAndExit(announce: false),
                        child: Container(
                          width: 68,
                          height: 68,
                          decoration: const BoxDecoration(
                            color: Color(0xFFEA0038),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(color: Color(0x66EA0038), blurRadius: 16, offset: Offset(0, 4)),
                            ],
                          ),
                          child: const Icon(Icons.call_end_rounded, color: Colors.white, size: 32),
                        ),
                      ),
                      const SizedBox(height: 10),
                      const Text('Decline', style: TextStyle(color: Colors.white70, fontSize: 14)),
                    ],
                  ),

                  // Accept Button
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      GestureDetector(
                        onTap: _acceptIncomingCall,
                        child: Container(
                          width: 68,
                          height: 68,
                          decoration: const BoxDecoration(
                            color: Color(0xFF00A884),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(color: Color(0x6600A884), blurRadius: 16, offset: Offset(0, 4)),
                            ],
                          ),
                          child: Icon(
                            _isVideo ? Icons.videocam_rounded : Icons.call_rounded,
                            color: Colors.white,
                            size: 32,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      const Text('Join', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopHeader() {
    final participants = _currentCallModel?.participants ?? [];
    final connectedCount = participants.where((p) => p.isConnected).length;

    String subtitle = 'Ringing members...';
    if (_hasConnected && _callDurationSeconds > 0) {
      subtitle = '${_formatCallDuration(_callDurationSeconds)} • $connectedCount participants';
    } else if (connectedCount > 1) {
      subtitle = 'Connected • $connectedCount participants';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            const Color(0xFF0B141A).withValues(alpha: 0.95),
            Colors.transparent,
          ],
        ),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white, size: 30),
            onPressed: () => _hangupAndExit(),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Icon(
                      _isVideo ? Icons.videocam_rounded : Icons.phone_rounded,
                      color: const Color(0xFF00A884),
                      size: 16,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        widget.groupName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    const Icon(Icons.lock_rounded, size: 10, color: Colors.white54),
                    const SizedBox(width: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Quick Mode Toggle (Video <-> Voice)
          GestureDetector(
            onTap: _toggleVideo,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              margin: const EdgeInsets.only(right: 6),
              decoration: BoxDecoration(
                color: _isVideo ? const Color(0xFF00A884).withValues(alpha: 0.25) : Colors.white.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: _isVideo ? const Color(0xFF00A884) : Colors.white24,
                  width: 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _isVideo ? Icons.videocam_rounded : Icons.mic_rounded,
                    color: _isVideo ? const Color(0xFF00A884) : Colors.white70,
                    size: 16,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _isVideo ? 'Video' : 'Voice',
                    style: TextStyle(
                      color: _isVideo ? const Color(0xFF00A884) : Colors.white70,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
          IconButton(
            icon: Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.person_add_rounded, color: Colors.white, size: 20),
            ),
            tooltip: 'Add Participants',
            onPressed: _openAddParticipantsSheet,
          ),
        ],
      ),
    );
  }

  Widget _buildParticipantGrid() {
    final participants = _currentCallModel?.participants ?? [];

    // ONLY participants who are actively connected in the call!
    final activeOthers = participants.where((p) {
      return p.userId != widget.currentUser.id && p.isConnected;
    }).toList();

    final List<Widget> cards = [];

    // 1. Current user tile
    cards.add(_buildSelfTile());

    // 2. Add each actively connected other participant
    for (final participant in activeOthers) {
      final member = widget.groupMembers.firstWhere(
        (m) => m.id == participant.userId,
        orElse: () => UserModel(
          id: participant.userId,
          name: participant.userName,
          phoneNumber: participant.userPhone,
          avatarUrl: participant.avatarUrl,
          createdAt: DateTime.now(),
        ),
      );
      cards.add(_buildRemoteParticipantTile(participant, member));
    }

    if (activeOthers.isEmpty) {
      return Column(
        children: [
          Expanded(child: Padding(padding: const EdgeInsets.all(6), child: cards.first)),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF00A884)),
                ),
                const SizedBox(width: 12),
                Text(
                  _currentCallModel?.status == 'calling'
                      ? 'Calling group members...'
                      : 'Waiting for members to join...',
                  style: const TextStyle(color: Colors.white70, fontSize: 14),
                ),
              ],
            ),
          ),
        ],
      );
    }

    if (cards.length == 2) {
      return Column(
        children: [
          Expanded(child: Padding(padding: const EdgeInsets.all(6), child: cards[0])),
          Expanded(child: Padding(padding: const EdgeInsets.all(6), child: cards[1])),
        ],
      );
    } else if (cards.length <= 4) {
      return GridView.count(
        crossAxisCount: 2,
        padding: const EdgeInsets.all(8),
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 0.85,
        physics: const NeverScrollableScrollPhysics(),
        children: cards,
      );
    } else {
      return GridView.count(
        crossAxisCount: 2,
        padding: const EdgeInsets.all(8),
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 0.85,
        children: cards,
      );
    }
  }

  Widget _buildSelfTile() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1F2C34),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: _isMuted ? Colors.transparent : const Color(0xFF00A884).withValues(alpha: 0.4),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Live Video Renderer or Avatar
          if (_isVideo && _localRendererInitialized && _localStream != null)
            RTCVideoView(
              _localRenderer,
              mirror: _isFrontCamera,
              objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
            )
          else
            _buildAvatarPlaceholder(
              name: widget.currentUser.name,
              avatarUrl: widget.currentUser.avatarUrl,
              isSpeaking: !_isMuted,
            ),

          // Label Bottom Bar
          Positioned(
            bottom: 8,
            left: 8,
            right: 8,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text(
                    'You',
                    style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ),
                if (_isMuted)
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: Colors.redAccent,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.mic_off_rounded, color: Colors.white, size: 12),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRemoteParticipantTile(GroupCallParticipant p, UserModel user) {
    final bool isConnected = p.isConnected;
    final String displayName = p.userName.isNotEmpty ? p.userName : user.name;
    final renderer = _remoteRenderers[p.userId];
    final bool hasLiveVideo = isConnected && !p.isVideoOff && renderer != null && renderer.srcObject != null;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1F2C34),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isConnected ? const Color(0xFF00A884).withValues(alpha: 0.4) : Colors.white10,
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (hasLiveVideo)
            RTCVideoView(
              renderer,
              objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
            )
          else
            _buildAvatarPlaceholder(
              name: displayName,
              avatarUrl: p.avatarUrl ?? user.avatarUrl,
              isSpeaking: isConnected && !p.isMuted,
            ),

          // Status & Name Banner
          Positioned(
            bottom: 8,
            left: 8,
            right: 8,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                if (!isConnected)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'Ringing...',
                      style: TextStyle(color: Colors.white70, fontSize: 10),
                    ),
                  )
                else if (p.isMuted)
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: Colors.redAccent,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.mic_off_rounded, color: Colors.white, size: 12),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAvatarPlaceholder({
    required String name,
    required String? avatarUrl,
    required bool isSpeaking,
  }) {
    return Center(
      child: AnimatedBuilder(
        animation: _pulseAnimation,
        builder: (context, child) {
          return Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: isSpeaking
                    ? const Color(0xFF00A884).withValues(alpha: 0.6)
                    : Colors.transparent,
                width: isSpeaking ? 3 * (_pulseAnimation.value - 0.9) : 0,
              ),
            ),
            child: CircleAvatar(
              radius: 36,
              backgroundColor: const Color(0xFF00A884).withValues(alpha: 0.2),
              backgroundImage: getAvatarImageProvider(avatarUrl),
              child: (avatarUrl == null || avatarUrl.isEmpty)
                  ? Text(
                      name.isNotEmpty ? name[0].toUpperCase() : '👤',
                      style: const TextStyle(
                        color: Color(0xFF00A884),
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    )
                  : null,
            ),
          );
        },
      ),
    );
  }

  Widget _buildBottomControlDock() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1F2C34).withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(32),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // Speaker toggle
          _buildDockButton(
            icon: _isSpeakerOn ? Icons.volume_up_rounded : Icons.volume_off_rounded,
            isActive: _isSpeakerOn,
            onTap: _toggleSpeaker,
            tooltip: 'Speaker',
          ),

          // Video camera toggle
          _buildDockButton(
            icon: _isVideo ? Icons.videocam_rounded : Icons.videocam_off_rounded,
            isActive: _isVideo,
            onTap: _toggleVideo,
            tooltip: 'Camera',
          ),

          // Mic mute toggle
          _buildDockButton(
            icon: _isMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
            isActive: !_isMuted,
            isAlert: _isMuted,
            onTap: _toggleMute,
            tooltip: 'Microphone',
          ),

          // Switch camera if video is on
          if (_isVideo)
            _buildDockButton(
              icon: Icons.cameraswitch_rounded,
              isActive: true,
              onTap: _switchCamera,
              tooltip: 'Switch Camera',
            ),

          // Hang up (Red Button)
          GestureDetector(
            onTap: () => _hangupAndExit(),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: const BoxDecoration(
                color: Color(0xFFEA0038),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Color(0x66EA0038),
                    blurRadius: 10,
                    offset: Offset(0, 3),
                  ),
                ],
              ),
              child: const Icon(
                Icons.call_end_rounded,
                color: Colors.white,
                size: 26,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDockButton({
    required IconData icon,
    required bool isActive,
    bool isAlert = false,
    required VoidCallback onTap,
    required String tooltip,
  }) {
    Color bg = Colors.white.withValues(alpha: 0.12);
    Color iconColor = Colors.white;

    if (isAlert) {
      bg = Colors.redAccent.withValues(alpha: 0.25);
      iconColor = Colors.redAccent;
    } else if (isActive) {
      bg = Colors.white.withValues(alpha: 0.2);
      iconColor = Colors.white;
    }

    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: bg,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: iconColor, size: 22),
        ),
      ),
    );
  }
}
