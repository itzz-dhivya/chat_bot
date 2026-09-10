import 'dart:async';
import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../services/call_service.dart';
import '../services/chat_service.dart';
import '../services/notification_service.dart';
import '../services/ringtone_service.dart';
import '../services/user_service.dart';

class CallScreen extends StatefulWidget {
  final String? callId;

  final String callerId;
  final String callerName;
  final String callerPhone;
  final String? callerAvatarUrl;

  final String receiverId;
  final String receiverName;
  final String receiverPhone;
  final String? receiverAvatarUrl;

  final bool isIncoming;

  // voice / video
  final String callType;

  const CallScreen({
    super.key,
    this.callId,

    required this.callerId,
    required this.callerName,
    required this.callerPhone,
    this.callerAvatarUrl,

    required this.receiverId,
    required this.receiverName,
    required this.receiverPhone,
    this.receiverAvatarUrl,

    this.isIncoming = false,

    this.callType = 'voice',
  });

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen>
    with SingleTickerProviderStateMixin {
  final CallService _callService = CallService();

  final ChatService _chatService = ChatService();

  final RingtoneService _ringtoneService = RingtoneService();

  final FirebaseAuth _auth = FirebaseAuth.instance;

  String? _activeCallId;
  String? _otherAvatarUrl;

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
  _callDocSubscription;

  late bool _isIncoming;
  late bool _isVideoCall;

  bool _isConnected = false;
  bool _isMuted = false;
  bool _isSpeakerOn = false;
  bool _isCameraOn = true;

  // Prevent duplicate call history messages
  bool _callMessageSaved = false;

  // Prevent multiple end-call operations
  bool _isEndingCall = false;

  String _callStatusText = 'Connecting...';

  Timer? _callTimer;
  int _callDurationSeconds = 0;

  // ---------------------------------------------------------
  // VIDEO RENDERERS
  // ---------------------------------------------------------

  final RTCVideoRenderer _localRenderer =
  RTCVideoRenderer();

  final RTCVideoRenderer _remoteRenderer =
  RTCVideoRenderer();

  bool _localRendererInitialized = false;
  bool _remoteRendererInitialized = false;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  // ---------------------------------------------------------
  // INIT
  // ---------------------------------------------------------

  @override
  void initState() {
    super.initState();

    _activeCallId = widget.callId;

    _isIncoming = widget.isIncoming;

    _isVideoCall = widget.callType == 'video';

    _otherAvatarUrl = _isIncoming
        ? widget.callerAvatarUrl
        : widget.receiverAvatarUrl;

    _fetchOtherUserProfile();

    // This call's screen is now open — tell NotificationService so it
    // doesn't fire a duplicate OS notification for the same call.
    if (_activeCallId != null) {
      NotificationService().activeCallId = _activeCallId;
      _listenToCallStatus(_activeCallId!);
    }

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(
        milliseconds: 1500,
      ),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(
      begin: 1.0,
      end: 1.15,
    ).animate(
      CurvedAnimation(
        parent: _pulseController,
        curve: Curves.easeInOut,
      ),
    );

    _initializeRenderers();

    _setupCallbacks();

    if (_isIncoming) {
      _callStatusText = _isVideoCall
          ? 'Incoming Video Call'
          : 'Incoming Voice Call';

      // Ring the moment the incoming call screen appears.
      _ringtoneService.startRingtone();
    } else {
      _callStatusText = _isVideoCall
          ? 'Calling with video...'
          : 'Calling...';

      _ringtoneService.startOutgoingRingtone();
      _startOutgoingCall();
    }
  }

  Future<void> _fetchOtherUserProfile() async {
    final otherId = _isIncoming ? widget.callerId : widget.receiverId;
    if (otherId.isNotEmpty) {
      try {
        final profile = await UserService().getUserById(otherId);
        if (profile != null &&
            profile.avatarUrl != null &&
            profile.avatarUrl!.isNotEmpty &&
            mounted) {
          setState(() {
            _otherAvatarUrl = profile.avatarUrl;
          });
        }
      } catch (_) {}
    }
  }

  // ---------------------------------------------------------
  // INITIALIZE VIDEO RENDERERS
  // ---------------------------------------------------------

  Future<void> _initializeRenderers() async {
    try {
      await _localRenderer.initialize();
      await _remoteRenderer.initialize();

      if (!mounted) {
        return;
      }

      setState(() {
        _localRendererInitialized = true;
        _remoteRendererInitialized = true;
      });

      // Attach local stream if already available
      if (_callService.localStream != null) {
        _localRenderer.srcObject =
            _callService.localStream;
      }

      // Attach remote stream if already available
      if (_callService.remoteStream != null) {
        _remoteRenderer.srcObject =
            _callService.remoteStream;
      }
    } catch (e) {
      debugPrint(
        'Renderer initialization error: $e',
      );
    }
  }

  // ---------------------------------------------------------
  // CALLBACKS
  // ---------------------------------------------------------

  void _setupCallbacks() {
    // =======================================================
    // REMOTE STREAM READY
    // =======================================================

    _callService.onRemoteStreamReady =
        (MediaStream stream) {
      debugPrint(
        'Remote stream ready',
      );

      if (!_remoteRendererInitialized) {
        return;
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _remoteRenderer.srcObject = stream;
      });
    };

    // =======================================================
    // CALL CONNECTED
    // =======================================================

    _callService.onCallConnected = () {
      debugPrint(
        'CALL SCREEN: Call connected',
      );

      // Stop ringing the moment the call actually connects.
      _ringtoneService.stopRingtone();

      if (!mounted) {
        return;
      }

      setState(() {
        _isConnected = true;
        _isIncoming = false;
        _callStatusText = 'Connected';
      });

      // Timer starts ONLY after actual connection
      _startTimer();

      // Attach local video
      if (_isVideoCall &&
          _localRendererInitialized &&
          _callService.localStream != null) {
        _localRenderer.srcObject =
            _callService.localStream;
      }

      // Attach remote video
      if (_isVideoCall &&
          _remoteRendererInitialized &&
          _callService.remoteStream != null) {
        _remoteRenderer.srcObject =
            _callService.remoteStream;
      }
    };

    // =======================================================
    // CALL ENDED
    // =======================================================

    _callService.onCallEnded =
        (String reason) {
      debugPrint(
        'CALL SCREEN: Call ended - $reason',
      );

      _ringtoneService.stopRingtone();

      // If local user is already ending the call,
      // _endCall() itself will navigate back.
      if (_isEndingCall) {
        return;
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _callStatusText = reason;
      });

      _callTimer?.cancel();

      Future.delayed(
        const Duration(
          milliseconds: 1000,
        ),
            () {
          if (mounted && !_isEndingCall) {
            Navigator.of(context).pop();
          }
        },
      );
    };

    // =======================================================
    // CALL MODE CHANGED (video <-> voice switch, either side)
    // =======================================================

    _callService.onCallModeChanged = (bool isVideo) {
      debugPrint(
        'CALL SCREEN: Call mode changed - isVideo=$isVideo',
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _isVideoCall = isVideo;

        // Reset camera-on flag whenever we (re)enter video mode.
        if (isVideo) {
          _isCameraOn = true;
        }
      });

      // Make sure renderers are attached now that we might be
      // switching into video mode.
      if (isVideo) {
        if (_localRendererInitialized &&
            _callService.localStream != null) {
          _localRenderer.srcObject = _callService.localStream;
        }

        if (_remoteRendererInitialized &&
            _callService.remoteStream != null) {
          _remoteRenderer.srcObject = _callService.remoteStream;
        }
      }
    };

    // =======================================================
    // UPGRADED TO VIDEO (voice -> video, first-time renegotiation)
    // =======================================================

    _callService.onUpgradedToVideo = () {
      debugPrint(
        'CALL SCREEN: Upgraded to video',
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _isVideoCall = true;
        _isCameraOn = true;
      });

      if (_localRendererInitialized &&
          _callService.localStream != null) {
        _localRenderer.srcObject = _callService.localStream;
      }

      if (_remoteRendererInitialized &&
          _callService.remoteStream != null) {
        _remoteRenderer.srcObject = _callService.remoteStream;
      }
    };
  }

  // ---------------------------------------------------------
  // FIRESTORE LIVE CALL STATUS LISTENER
  // ---------------------------------------------------------

  void _listenToCallStatus(String callId) {
    _callDocSubscription?.cancel();
    _callDocSubscription = FirebaseFirestore.instance
        .collection('calls')
        .doc(callId)
        .snapshots()
        .listen((snapshot) {
      if (!snapshot.exists || snapshot.data() == null) return;
      final data = snapshot.data()!;
      final status = data['status']?.toString();

      if (status == 'ended' || status == 'rejected' || status == 'missed') {
        if (_isEndingCall) return;
        debugPrint('CALL SCREEN: Call ended from Firestore status ($status)');

        _ringtoneService.stopRingtone();
        _callTimer?.cancel();

        if (mounted) {
          setState(() {
            _callStatusText = status == 'rejected'
                ? 'Call declined'
                : (status == 'missed' ? 'Missed call' : 'Call ended');
          });

          Future.delayed(const Duration(milliseconds: 800), () {
            if (mounted && !_isEndingCall) {
              Navigator.of(context).pop();
            }
          });
        }
      }
    });
  }

  // ---------------------------------------------------------
  // OUTGOING CALL
  // ---------------------------------------------------------

  Future<void> _startOutgoingCall() async {
    try {
      final String callId =
      await _callService.createCall(
        callerId: widget.callerId,
        receiverId: widget.receiverId,

        callerName: widget.callerName,
        callerPhone: widget.callerPhone,
        callerAvatarUrl: widget.callerAvatarUrl,

        receiverName: widget.receiverName,
        receiverPhone: widget.receiverPhone,
        receiverAvatarUrl: widget.receiverAvatarUrl,

        callType: _isVideoCall
            ? 'video'
            : 'voice',
      );

      if (!mounted || _isEndingCall) {
        // User hung up or closed the screen while call was being created
        _callService.endCall(callId: callId);
        return;
      }

      setState(() {
        _activeCallId = callId;

        _callStatusText = 'Ringing...';
      });

      NotificationService().activeCallId = callId;
      _listenToCallStatus(callId);

      // Local camera stream may now exist
      if (_isVideoCall &&
          _localRendererInitialized &&
          _callService.localStream != null) {
        _localRenderer.srcObject =
            _callService.localStream;
      }
    } catch (e) {
      debugPrint(
        'Outgoing call error: $e',
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _callStatusText =
        'Failed to connect';
      });

      Future.delayed(
        const Duration(seconds: 2),
            () {
          if (mounted) {
            Navigator.of(context).pop();
          }
        },
      );
    }
  }

  // ---------------------------------------------------------
  // ACCEPT CALL
  // ---------------------------------------------------------

  Future<void> _acceptCall() async {
    if (_activeCallId == null) {
      return;
    }

    _ringtoneService.stopRingtone();

    setState(() {
      _callStatusText = 'Connecting...';
    });

    try {
      await _callService.answerCall(
        callId: _activeCallId!,
      );

      if (!mounted) {
        return;
      }

      // IMPORTANT:
      //
      // Don't set _isConnected = true here.
      //
      // answerCall() only creates/sends the WebRTC answer.
      // Actual connection is confirmed through
      // onCallConnected callback.
      //
      // So timer also starts from onCallConnected.

      setState(() {
        _isIncoming = false;
        _callStatusText = 'Connecting...';
      });

      // Attach local video if available
      if (_isVideoCall &&
          _localRendererInitialized &&
          _callService.localStream != null) {
        _localRenderer.srcObject =
            _callService.localStream;
      }

      // Attach remote video if available
      if (_isVideoCall &&
          _remoteRendererInitialized &&
          _callService.remoteStream != null) {
        _remoteRenderer.srcObject =
            _callService.remoteStream;
      }
    } catch (e) {
      debugPrint(
        'Accept call error: $e',
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _callStatusText =
        'Failed to answer';
      });

      Future.delayed(
        const Duration(seconds: 1),
            () {
          if (mounted) {
            Navigator.of(context).pop();
          }
        },
      );
    }
  }

  // ---------------------------------------------------------
  // REJECT CALL
  // ---------------------------------------------------------

  Future<void> _rejectCall() async {
    if (_isEndingCall) {
      return;
    }

    _isEndingCall = true;

    _ringtoneService.stopRingtone();

    try {
      if (_activeCallId != null) {
        await _callService.rejectCall(
          callId: _activeCallId!,
        );
      }
    } catch (e) {
      debugPrint(
        'Reject call error: $e',
      );
    }

    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  // ---------------------------------------------------------
  // SAVE CALL HISTORY MESSAGE
  // ---------------------------------------------------------

  Future<void> _saveCallMessage() async {
    // -------------------------------------------------------
    // Don't save if call was never connected.
    //
    // Example:
    // Caller calls -> receiver doesn't answer -> caller cuts.
    //
    // This method is only for:
    // Connected -> Call ended
    // Prevent duplicate messages
    if (_callMessageSaved) {
      debugPrint('CALL HISTORY: Already saved.');
      return;
    }

    final User? currentUser = _auth.currentUser;
    if (currentUser == null) {
      debugPrint('CALL HISTORY: Current user is null.');
      return;
    }

    final String currentUserId = currentUser.uid;
    String otherUserId;
    if (currentUserId == widget.callerId) {
      otherUserId = widget.receiverId;
    } else if (currentUserId == widget.receiverId) {
      otherUserId = widget.callerId;
    } else {
      debugPrint('CALL HISTORY: Current user does not match caller or receiver.');
      return;
    }

    final bool connected = _isConnected;
    final int duration = _callDurationSeconds;
    final String status = connected ? 'ended' : 'missed';

    try {
      await _chatService.sendCallMessage(
        senderId: currentUserId,
        receiverId: otherUserId,
        callType: _isVideoCall ? 'video' : 'voice',
        callStatus: status,
        duration: duration,
      );

      _callMessageSaved = true;
      debugPrint('CALL HISTORY: Message saved: type=${_isVideoCall ? 'video' : 'voice'}, status=$status, duration=$duration');
    } catch (e) {
      debugPrint('CALL HISTORY ERROR: $e');
    }
  }

  // ---------------------------------------------------------
  // END CALL
  // ---------------------------------------------------------

  Future<void> _endCall() async {
    // Prevent double execution
    if (_isEndingCall) {
      return;
    }

    _isEndingCall = true;

    debugPrint(
      'CALL SCREEN: Ending call...',
    );

    _ringtoneService.stopRingtone();

    // Stop timer first
    _callTimer?.cancel();

    // -------------------------------------------------------
    // SAVE CALL HISTORY
    // -------------------------------------------------------

    await _saveCallMessage();

    // -------------------------------------------------------
    // UPDATE CALL STATUS
    // -------------------------------------------------------

    try {
      if (_activeCallId != null) {
        await _callService.endCall(
          callId: _activeCallId!,
        );
      }
    } catch (e) {
      debugPrint(
        'End call service error: $e',
      );
    }

    // -------------------------------------------------------
    // GO BACK TO CHAT
    // -------------------------------------------------------

    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  // ---------------------------------------------------------
  // MUTE
  // ---------------------------------------------------------

  void _toggleMute() {
    setState(() {
      _isMuted = !_isMuted;
    });

    _callService.setMuted(
      _isMuted,
    );
  }

  // ---------------------------------------------------------
  // SPEAKER
  // ---------------------------------------------------------

  void _toggleSpeaker() {
    setState(() {
      _isSpeakerOn = !_isSpeakerOn;
    });

    _callService.setSpeakerphone(
      _isSpeakerOn,
    );
  }

  // ---------------------------------------------------------
  // CAMERA ON / OFF
  // ---------------------------------------------------------

  void _toggleCamera() {
    if (!_isVideoCall) {
      return;
    }

    setState(() {
      _isCameraOn = !_isCameraOn;
    });

    _callService.setCameraEnabled(
      _isCameraOn,
    );
  }

  // ---------------------------------------------------------
  // SWITCH CAMERA (front/back)
  // ---------------------------------------------------------

  Future<void> _switchCamera() async {
    if (!_isVideoCall) {
      return;
    }

    await _callService.switchCamera();
  }

  // ---------------------------------------------------------
  // SWITCH VIDEO -> AUDIO ONLY
  // ---------------------------------------------------------

  Future<void> _switchToAudioOnly() async {
    if (_activeCallId == null) {
      return;
    }

    await _callService.switchCallMode(
      callId: _activeCallId!,
      toVideo: false,
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _isVideoCall = false;
    });
  }

  // ---------------------------------------------------------
  // SWITCH AUDIO -> VIDEO
  // ---------------------------------------------------------

  Future<void> _switchToVideo() async {
    if (_activeCallId == null) {
      return;
    }

    await _callService.switchCallMode(
      callId: _activeCallId!,
      toVideo: true,
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _isVideoCall = true;
      _isCameraOn = true;
    });

    if (_localRendererInitialized &&
        _callService.localStream != null) {
      _localRenderer.srcObject = _callService.localStream;
    }

    if (_remoteRendererInitialized &&
        _callService.remoteStream != null) {
      _remoteRenderer.srcObject = _callService.remoteStream;
    }
  }

  // ---------------------------------------------------------
  // TIMER
  // ---------------------------------------------------------

  void _startTimer() {
    _callTimer?.cancel();

    _callDurationSeconds = 0;

    _callTimer = Timer.periodic(
      const Duration(seconds: 1),
          (_) {
        if (!mounted) {
          return;
        }

        setState(() {
          _callDurationSeconds++;
        });
      },
    );
  }

  // ---------------------------------------------------------
  // FORMATTED DURATION
  // ---------------------------------------------------------

  String get _formattedDuration {
    final int minutes =
        _callDurationSeconds ~/ 60;

    final int seconds =
        _callDurationSeconds % 60;

    return '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }

  // ---------------------------------------------------------
  // DISPOSE
  // ---------------------------------------------------------

  @override
  void dispose() {
    _callDocSubscription?.cancel();
    _callDocSubscription = null;

    _ringtoneService.stopRingtone();

    // Clear the notification-suppression guard + tray notification
    // for this call once the screen closes.
    if (NotificationService().activeCallId == _activeCallId) {
      NotificationService().activeCallId = null;
    }
    NotificationService().clearCallNotification();

    _callTimer?.cancel();

    _pulseController.dispose();

    if (_localRendererInitialized) {
      _localRenderer.dispose();
    }

    if (_remoteRendererInitialized) {
      _remoteRenderer.dispose();
    }

    _callService.dispose();

    super.dispose();
  }

  // =========================================================
  // BUILD
  // =========================================================

  @override
  Widget build(BuildContext context) {
    if (_isVideoCall) {
      return _buildVideoCallScreen();
    }

    return _buildVoiceCallScreen();
  }

  // =========================================================
  // VIDEO CALL SCREEN
  // =========================================================

  Widget _buildVideoCallScreen() {
    final String displayName = _isIncoming
        ? (widget.callerName.isNotEmpty
        ? widget.callerName
        : 'Caller')
        : (widget.receiverName.isNotEmpty
        ? widget.receiverName
        : 'Contact');

    return PopScope(
      canPop: false,
      onPopInvokedWithResult:
          (didPop, _) {
        if (!didPop) {
          _endCall();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Stack(
            children: [
              // ------------------------------------------------
              // REMOTE VIDEO
              // ------------------------------------------------

              Positioned.fill(
                child: _buildRemoteVideo(),
              ),

              // ------------------------------------------------
              // TOP INFO
              // ------------------------------------------------

              Positioned(
                top: 20,
                left: 16,
                right: 16,
                child: Row(
                  children: [
                    Container(
                      padding:
                      const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration:
                      BoxDecoration(
                        color:
                        Colors.black.withValues(
                          alpha: 0.45,
                        ),
                        borderRadius:
                        BorderRadius.circular(
                          20,
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.videocam,
                            color:
                            Colors.white,
                            size: 18,
                          ),
                          const SizedBox(
                            width: 6,
                          ),
                          Text(
                            displayName,
                            style:
                            const TextStyle(
                              color:
                              Colors.white,
                              fontSize: 15,
                              fontWeight:
                              FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const Spacer(),

                    if (_isConnected)
                      Container(
                        padding:
                        const EdgeInsets
                            .symmetric(
                          horizontal: 10,
                          vertical: 7,
                        ),
                        decoration:
                        BoxDecoration(
                          color:
                          Colors.black.withValues(
                            alpha: 0.45,
                          ),
                          borderRadius:
                          BorderRadius.circular(
                            20,
                          ),
                        ),
                        child: Text(
                          _formattedDuration,
                          style:
                          const TextStyle(
                            color:
                            Colors.white,
                            fontWeight:
                            FontWeight.bold,
                          ),
                        ),
                      ),
                  ],
                ),
              ),

              // ------------------------------------------------
              // LOCAL VIDEO PREVIEW
              // ------------------------------------------------

              if (_localRendererInitialized &&
                  _localRenderer.srcObject != null)
                Positioned(
                  top: 80,
                  right: 16,
                  child: _buildLocalVideo(),
                ),

              // ------------------------------------------------
              // BOTTOM CONTROLS
              // ------------------------------------------------

              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _isIncoming
                    ? _buildVideoIncomingControls()
                    : _buildVideoControls(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // =========================================================
  // REMOTE VIDEO
  // =========================================================

  Widget _buildRemoteVideo() {
    final String displayName = _isIncoming
        ? (widget.callerName.isNotEmpty
        ? widget.callerName
        : 'Caller')
        : (widget.receiverName.isNotEmpty
        ? widget.receiverName
        : 'Contact');

    if (!_remoteRendererInitialized ||
        _remoteRenderer.srcObject == null ||
        !_isConnected) {
      return Stack(
        fit: StackFit.expand,
        children: [
          // Blurred background image if avatar exists, else dark gradient
          if (_otherAvatarUrl != null && _otherAvatarUrl!.isNotEmpty)
            Image.network(
              _otherAvatarUrl!,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF0F172A), Color(0xFF1E1B4B)],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
              ),
            )
          else
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Color(0xFF0F172A),
                    Color(0xFF1E1B4B),
                    Color(0xFF020617),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),

          // Blur & dark overlay
          BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
            child: Container(
              color: Colors.black.withValues(alpha: 0.65),
            ),
          ),

          // Centered Profile Photo Avatar + Name + Pulse Animation
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ScaleTransition(
                  scale: _isConnected
                      ? const AlwaysStoppedAnimation(1.0)
                      : _pulseAnimation,
                  child: Container(
                    width: 140,
                    height: 140,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.8),
                        width: 3,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF5B50E6).withValues(alpha: 0.5),
                          blurRadius: 32,
                          spreadRadius: 8,
                        ),
                      ],
                    ),
                    child: ClipOval(
                      child: _otherAvatarUrl != null &&
                              _otherAvatarUrl!.isNotEmpty
                          ? Image.network(
                              _otherAvatarUrl!,
                              fit: BoxFit.cover,
                              width: 140,
                              height: 140,
                              errorBuilder: (_, __, ___) =>
                                  _buildInitialAvatar(displayName),
                            )
                          : _buildInitialAvatar(displayName),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  displayName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.4,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    _callStatusText,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    return RTCVideoView(
      _remoteRenderer,
      objectFit:
      RTCVideoViewObjectFit
          .RTCVideoViewObjectFitCover,
    );
  }

  Widget _buildInitialAvatar(String displayName) {
    return Container(
      width: 140,
      height: 140,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF5B50E6), Color(0xFF7C3AED)],
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        displayName.isNotEmpty ? displayName[0].toUpperCase() : '?',
        style: const TextStyle(
          fontSize: 56,
          color: Colors.white,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  // =========================================================
  // LOCAL VIDEO
  // =========================================================

  Widget _buildLocalVideo() {
    return Container(
      width: 110,
      height: 155,
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius:
        BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white54,
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color:
            Colors.black.withValues(
              alpha: 0.4,
            ),
            blurRadius: 10,
          ),
        ],
      ),
      clipBehavior:
      Clip.antiAlias,
      child: !_isCameraOn ||
          !_localRendererInitialized ||
          _localRenderer.srcObject ==
              null
          ? const Center(
        child: Icon(
          Icons.videocam_off,
          color: Colors.white70,
          size: 30,
        ),
      )
          : RTCVideoView(
        _localRenderer,
        mirror: true,
        objectFit:
        RTCVideoViewObjectFit
            .RTCVideoViewObjectFitCover,
      ),
    );
  }

  // =========================================================
  // VIDEO INCOMING CONTROLS
  // =========================================================

  Widget _buildVideoIncomingControls() {
    return Container(
      padding:
      const EdgeInsets.symmetric(
        horizontal: 30,
        vertical: 30,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.transparent,
            Colors.black.withValues(
              alpha: 0.85,
            ),
          ],
        ),
      ),
      child: Row(
        mainAxisAlignment:
        MainAxisAlignment.spaceEvenly,
        children: [
          _roundButton(
            icon: Icons.call_end,
            color: const Color(
              0xFFEF4444,
            ),
            label: 'Decline',
            onTap: _rejectCall,
          ),
          _roundButton(
            icon: Icons.videocam,
            color: const Color(
              0xFF10B981,
            ),
            label: 'Accept',
            onTap: _acceptCall,
          ),
        ],
      ),
    );
  }

  // =========================================================
  // VIDEO ACTIVE CONTROLS
  // =========================================================

  Widget _buildVideoControls() {
    return Container(
      padding:
      const EdgeInsets.fromLTRB(
        20,
        30,
        20,
        25,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.transparent,
            Colors.black.withValues(
              alpha: 0.9,
            ),
          ],
        ),
      ),
      child: Column(
        mainAxisSize:
        MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment:
            MainAxisAlignment.spaceEvenly,
            children: [
              _controlButton(
                icon: _isMuted
                    ? Icons.mic_off
                    : Icons.mic,
                label: _isMuted
                    ? 'Unmute'
                    : 'Mute',
                active: _isMuted,
                onTap: _toggleMute,
              ),

              _controlButton(
                icon: _isCameraOn
                    ? Icons.videocam
                    : Icons.videocam_off,
                label: _isCameraOn
                    ? 'Camera'
                    : 'Camera Off',
                active: !_isCameraOn,
                onTap: _toggleCamera,
              ),

              _controlButton(
                icon:
                Icons.cameraswitch,
                label: 'Flip',
                onTap:
                _switchCamera,
              ),

              _controlButton(
                icon: _isSpeakerOn
                    ? Icons.volume_up
                    : Icons.volume_down,
                label: _isSpeakerOn
                    ? 'Speaker'
                    : 'Earpiece',
                active:
                _isSpeakerOn,
                onTap:
                _toggleSpeaker,
              ),

              // Switch this video call to audio-only.
              _controlButton(
                icon: Icons.call_merge_rounded,
                label: 'Audio Only',
                onTap: _switchToAudioOnly,
              ),
            ],
          ),

          const SizedBox(
            height: 22,
          ),

          // End call
          GestureDetector(
            onTap: _isEndingCall
                ? null
                : _endCall,
            child: Container(
              width: 68,
              height: 68,
              decoration:
              const BoxDecoration(
                color: Color(
                  0xFFEF4444,
                ),
                shape:
                BoxShape.circle,
              ),
              child: const Icon(
                Icons.call_end,
                color: Colors.white,
                size: 32,
              ),
            ),
          ),

          const SizedBox(
            height: 8,
          ),

          const Text(
            'End Call',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  // =========================================================
  // VOICE CALL SCREEN
  // =========================================================

  Widget _buildVoiceCallScreen() {
    final String displayName = _isIncoming
        ? (widget.callerName.isNotEmpty
        ? widget.callerName
        : 'Caller')
        : (widget.receiverName.isNotEmpty
        ? widget.receiverName
        : 'Contact');

    final String displayPhone =
    _isIncoming
        ? widget.callerPhone
        : widget.receiverPhone;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult:
          (didPop, _) {
        if (!didPop) {
          _endCall();
        }
      },
      child: Scaffold(
        backgroundColor:
        const Color(0xFF0F172A),
        body: SafeArea(
          child: Column(
            children: [
              const SizedBox(
                height: 40,
              ),

              Row(
                mainAxisAlignment:
                MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.lock_rounded,
                    size: 14,
                    color: Colors.white60,
                  ),
                  const SizedBox(
                    width: 6,
                  ),
                  Text(
                    'End-to-end encrypted '
                        '${_isVideoCall ? 'video' : 'voice'} call',
                    style:
                    const TextStyle(
                      color:
                      Colors.white60,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),

              const SizedBox(
                height: 30,
              ),

              Text(
                displayName,
                style:
                const TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight:
                  FontWeight.bold,
                ),
              ),

              if (displayPhone.isNotEmpty)
                Padding(
                  padding:
                  const EdgeInsets.only(
                    top: 6,
                  ),
                  child: Text(
                    displayPhone,
                    style:
                    const TextStyle(
                      color:
                      Colors.white70,
                      fontSize: 16,
                    ),
                  ),
                ),

              const SizedBox(
                height: 12,
              ),

              Text(
                _isConnected
                    ? _formattedDuration
                    : _callStatusText,
                style: TextStyle(
                  color: _isConnected
                      ? const Color(
                    0xFF818CF8,
                  )
                      : Colors.white70,
                  fontSize: 18,
                  fontWeight:
                  FontWeight.w600,
                ),
              ),

              const Spacer(),

              ScaleTransition(
                scale: _isConnected
                    ? const AlwaysStoppedAnimation(
                  1.0,
                )
                    : _pulseAnimation,
                child: Container(
                  width: 140,
                  height: 140,
                  decoration:
                  BoxDecoration(
                    shape:
                    BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.8),
                      width: 3,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color:
                        const Color(
                          0xFF6366F1,
                        ).withValues(
                          alpha: 0.35,
                        ),
                        blurRadius: 35,
                        spreadRadius: 10,
                      ),
                    ],
                  ),
                  child: ClipOval(
                    child: _otherAvatarUrl != null &&
                            _otherAvatarUrl!.isNotEmpty
                        ? Image.network(
                            _otherAvatarUrl!,
                            fit: BoxFit.cover,
                            width: 140,
                            height: 140,
                            errorBuilder: (_, __, ___) =>
                                _buildInitialAvatar(displayName),
                          )
                        : _buildInitialAvatar(displayName),
                  ),
                ),
              ),

              const Spacer(),

              Container(
                padding:
                const EdgeInsets
                    .symmetric(
                  horizontal: 24,
                  vertical: 30,
                ),
                decoration:
                const BoxDecoration(
                  color:
                  Color(0xFF1E293B),
                  borderRadius:
                  BorderRadius.only(
                    topLeft:
                    Radius.circular(
                      30,
                    ),
                    topRight:
                    Radius.circular(
                      30,
                    ),
                  ),
                ),
                child: _isIncoming
                    ? _buildIncomingControls()
                    : _buildActiveControls(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // =========================================================
  // VOICE INCOMING CONTROLS
  // =========================================================

  Widget _buildIncomingControls() {
    return Row(
      mainAxisAlignment:
      MainAxisAlignment.spaceEvenly,
      children: [
        _roundButton(
          icon: Icons.call_end,
          color: const Color(
            0xFFEF4444,
          ),
          label: 'Decline',
          onTap: _rejectCall,
        ),
        _roundButton(
          icon: Icons.call,
          color: const Color(
            0xFF10B981,
          ),
          label: 'Accept',
          onTap: _acceptCall,
        ),
      ],
    );
  }

  // =========================================================
  // VOICE ACTIVE CONTROLS
  // =========================================================

  Widget _buildActiveControls() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment:
          MainAxisAlignment.spaceEvenly,
          children: [
            _controlButton(
              icon: _isMuted
                  ? Icons.mic_off
                  : Icons.mic,
              label: _isMuted
                  ? 'Unmute'
                  : 'Mute',
              active: _isMuted,
              onTap: _toggleMute,
            ),

            _controlButton(
              icon: Icons.call_end,
              label: 'End Call',
              color: const Color(
                0xFFEF4444,
              ),
              onTap: _endCall,
            ),

            _controlButton(
              icon: _isSpeakerOn
                  ? Icons.volume_up
                  : Icons.volume_down,
              label: _isSpeakerOn
                  ? 'Speaker ON'
                  : 'Speaker',
              active: _isSpeakerOn,
              onTap: _toggleSpeaker,
            ),
          ],
        ),

        const SizedBox(height: 18),

        // Switch this audio call to video.
        TextButton.icon(
          onPressed: _switchToVideo,
          style: TextButton.styleFrom(
            foregroundColor: Colors.white,
            backgroundColor: Colors.white.withValues(alpha: 0.08),
            padding: const EdgeInsets.symmetric(
              horizontal: 18,
              vertical: 10,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
          ),
          icon: const Icon(Icons.videocam_rounded, size: 18),
          label: const Text('Switch to Video'),
        ),
      ],
    );
  }

  // =========================================================
  // COMMON ROUND BUTTON
  // =========================================================

  Widget _roundButton({
    required IconData icon,
    required Color color,
    required String label,
    required VoidCallback onTap,
  }) {
    return Column(
      mainAxisSize:
      MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: onTap,
          child: Container(
            width: 65,
            height: 65,
            decoration:
            BoxDecoration(
              color: color,
              shape:
              BoxShape.circle,
            ),
            child: Icon(
              icon,
              color: Colors.white,
              size: 32,
            ),
          ),
        ),
        const SizedBox(
          height: 8,
        ),
        Text(
          label,
          style:
          const TextStyle(
            color:
            Colors.white70,
            fontSize: 13,
          ),
        ),
      ],
    );
  }

  // =========================================================
  // COMMON CONTROL BUTTON
  // =========================================================

  Widget _controlButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool active = false,
    Color? color,
  }) {
    return Column(
      mainAxisSize:
      MainAxisSize.min,
      children: [
        IconButton.filled(
          style:
          IconButton.styleFrom(
            backgroundColor:
            color ??
                (active
                    ? Colors.white
                    : Colors.white24),
            padding:
            const EdgeInsets.all(
              16,
            ),
          ),
          onPressed: onTap,
          icon: Icon(
            icon,
            color: color != null
                ? Colors.white
                : (active
                ? Colors.black
                : Colors.white),
            size: 28,
          ),
        ),
        const SizedBox(
          height: 8,
        ),
        Text(
          label,
          style:
          const TextStyle(
            color:
            Colors.white70,
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}