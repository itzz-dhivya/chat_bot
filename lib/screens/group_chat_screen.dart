import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:record/record.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/message_model.dart';
import '../models/user_model.dart';
import '../services/chat_service.dart';
import '../widgets/media_viewer.dart';
import '../services/user_service.dart';
import '../widgets/whatsapp_attachment_sheet.dart';
import '../widgets/whatsapp_camera_screen.dart';
import '../widgets/whatsapp_emoji_picker.dart';
import '../widgets/whatsapp_forward_dialog.dart';
import '../widgets/whatsapp_poll_dialog.dart';
import '../widgets/whatsapp_event_dialog.dart';
import '../widgets/whatsapp_delete_dialog.dart';
import '../widgets/whatsapp_audio_picker.dart';
import '../services/group_call_service.dart';
import 'ai_chat_screen.dart';
import 'group_call_screen.dart';

class GroupChatScreen extends StatefulWidget {
  final String groupId;
  final String groupName;
  final List<String>? memberIds;

  const GroupChatScreen({
    super.key,
    required this.groupId,
    required this.groupName,
    this.memberIds,
  });

  @override
  State<GroupChatScreen> createState() => _GroupChatScreenState();
}

class _GroupChatScreenState extends State<GroupChatScreen> {
  final ChatService _chatService = ChatService();
  final UserService _userService = UserService();
  final ImagePicker _imagePicker = ImagePicker();
  final AudioPlayer _audioPlayer = AudioPlayer();
  final AudioRecorder _audioRecorder = AudioRecorder();
  String? _voiceRecordingPath;

  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();
  bool _initialScrollDone = false; // scroll-to-unread fires only once

  UserModel? _currentUser;
  bool _isLoading = true;
  bool _isSending = false;
  bool _showEmojiPicker = false;
  bool _hasText = false;

  // Search & Theme state
  bool _isSearching = false;
  final TextEditingController _searchFilterController = TextEditingController();
  String _searchFilterQuery = '';
  Color _chatThemeColor = const Color(0xFFF4F6FC);

  // Voice recording state
  bool _isRecordingVoice = false;
  int _recordingSeconds = 0;
  Timer? _recordingTimer;
  String? _playingAudioMessageId;
  PlayerState _playerState = PlayerState.stopped;

  // Replying state
  MessageModel? _replyingToMessage;
  MessageModel? _selectedMessageForReaction;

  // Group Details Cache
  Map<String, dynamic>? _groupData;
  List<UserModel> _memberUsers = [];

  @override
  void initState() {
    super.initState();
    _loadInitialData();

    _messageController.addListener(() {
      final hasNow = _messageController.text.trim().isNotEmpty;
      if (hasNow != _hasText) {
        setState(() {
          _hasText = hasNow;
        });
      }
    });

    _audioPlayer.onPlayerStateChanged.listen((state) {
      if (mounted) {
        setState(() {
          _playerState = state;
          if (state == PlayerState.completed || state == PlayerState.stopped) {
            _playingAudioMessageId = null;
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _messageController.dispose();
    _searchFilterController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    _recordingTimer?.cancel();
    _audioRecorder.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    final user = await _userService.getCurrentUserProfile();
    if (mounted) {
      setState(() {
        _currentUser = user;
        _isLoading = false;
      });
    }
    if (user != null) {
      _chatService.markGroupMessagesAsRead(
        groupId: widget.groupId,
        userId: user.id,
      );
    }
    _fetchGroupDetails();
  }

  Future<void> _fetchGroupDetails() async {
    try {
      final doc = await FirebaseFirestore.instance.collection('groups').doc(widget.groupId).get();
      if (doc.exists && mounted) {
        final data = doc.data();
        setState(() {
          _groupData = data;
        });
        final members = List<String>.from(data?['members'] ?? []);
        final users = <UserModel>[];
        for (final uid in members) {
          final u = await _userService.getUserById(uid);
          if (u != null) users.add(u);
        }
        if (mounted) {
          setState(() {
            _memberUsers = users;
          });
        }
      }
    } catch (e) {
      debugPrint('Error fetching group details: $e');
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent + 80,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  /// Scroll to the first unread message for this user in group. Falls back to bottom.
  void _scrollToFirstUnread(List<dynamic> docs) {
    if (!_scrollController.hasClients || _currentUser == null) {
      _scrollToBottom();
      return;
    }
    int firstUnreadIdx = -1;
    for (int i = 0; i < docs.length; i++) {
      final data = docs[i].data() as Map<String, dynamic>;
      final senderId = data['senderId'] as String? ?? '';
      final readBy = data['readBy'];
      final isSeen = data['isSeen'] == true;
      final status = data['status'] as String? ?? 'sent';
      // A message is unread if this user hasn't read it and didn't send it
      if (senderId != _currentUser!.id) {
        final alreadyRead = isSeen ||
            status == 'read' ||
            (readBy is List && readBy.contains(_currentUser!.id));
        if (!alreadyRead) {
          firstUnreadIdx = i;
          break;
        }
      }
    }
    Future.delayed(const Duration(milliseconds: 150), () {
      if (!_scrollController.hasClients) return;
      if (firstUnreadIdx <= 0) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      } else {
        final approxOffset =
            (firstUnreadIdx * 72.0).clamp(0.0, _scrollController.position.maxScrollExtent);
        _scrollController.animateTo(
          approxOffset,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // ============================================================
  // SEND MESSAGE
  // ============================================================

  Future<void> _sendTextMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || _currentUser == null || _isSending) return;

    setState(() {
      _isSending = true;
    });

    final replyId = _replyingToMessage?.id;
    final replyText = _replyingToMessage?.message;
    final replySender = _replyingToMessage?.senderName ??
        (_replyingToMessage?.senderId == _currentUser!.id ? 'You' : 'Member');

    _messageController.clear();
    setState(() {
      _replyingToMessage = null;
    });

    try {
      await _chatService.sendGroupMessage(
        groupId: widget.groupId,
        senderId: _currentUser!.id,
        senderName: _currentUser!.name.isNotEmpty ? _currentUser!.name : _currentUser!.phoneNumber,
        message: text,
        type: 'text',
        replyToId: replyId,
        replyToText: replyText,
        replyToSender: replySender,
      );
      _scrollToBottom();
    } catch (e) {
      _showSnackBar('Failed to send message: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isSending = false;
        });
      }
    }
  }

  // ============================================================
  // ATTACHMENTS & MEDIA (PHOTOS / CAMERA / DOCUMENTS / ETC.)
  // ============================================================

  void _openAttachmentSheet() {
    FocusScope.of(context).unfocus();
    setState(() {
      _showEmojiPicker = false;
    });

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => WhatsAppAttachmentSheet(
        isDark: false,
        onGalleryTap: _handleGallery,
        onVideoTap: _handleVideo,
        onCameraTap: _handleCamera,
        onLocationTap: _handleLocation,
        onContactTap: _handleContact,
        onDocumentTap: _handleDocument,
        onPollTap: _handlePoll,
        onEventTap: _handleEvent,
        onAudioTap: _handleAudio,
      ),
    );
  }

  Future<void> _handleVideo() async {
    try {
      final XFile? video = await _imagePicker.pickVideo(
        source: ImageSource.gallery,
        maxDuration: const Duration(minutes: 5),
      );
      if (video == null || _currentUser == null) return;

      _showSnackBar('Sending video...');
      final file = File(video.path);
      final fileName = 'group_video_${DateTime.now().millisecondsSinceEpoch}.mp4';
      final path = 'groups/${widget.groupId}/$fileName';

      String downloadUrl = '';
      try {
        downloadUrl = await _chatService.uploadFile(file, path);
      } catch (uploadErr) {
        debugPrint('Firebase Storage upload failed: $uploadErr. Using local path.');
        downloadUrl = video.path;
      }

      await _chatService.sendGroupMessage(
        groupId: widget.groupId,
        senderId: _currentUser!.id,
        senderName: _currentUser!.name.isNotEmpty ? _currentUser!.name : _currentUser!.phoneNumber,
        mediaUrl: downloadUrl,
        type: 'video',
        message: 'Video',
        replyToId: _replyingToMessage?.id,
        replyToText: _replyingToMessage?.message,
        replyToSender: _replyingToMessage?.senderName ?? (_replyingToMessage?.senderId == _currentUser!.id ? 'You' : 'Member'),
      );
      setState(() => _replyingToMessage = null);
      _scrollToBottom();
    } catch (e) {
      _showSnackBar('Failed to send video: $e');
    }
  }

  Future<void> _handleGallery() async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 70,
        maxWidth: 1280,
        maxHeight: 1280,
      );
      if (image == null || _currentUser == null) return;

      _showSnackBar('Sending photo...');
      final file = File(image.path);
      final fileName = 'group_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final path = 'groups/${widget.groupId}/$fileName';

      String downloadUrl = '';
      try {
        downloadUrl = await _chatService.uploadFile(file, path);
      } catch (uploadErr) {
        debugPrint('Firebase Storage upload failed: $uploadErr. Using Base64 payload.');
        final bytes = await file.readAsBytes();
        downloadUrl = 'data:image/jpeg;base64,${base64Encode(bytes)}';
      }

      await _chatService.sendGroupMessage(
        groupId: widget.groupId,
        senderId: _currentUser!.id,
        senderName: _currentUser!.name.isNotEmpty ? _currentUser!.name : _currentUser!.phoneNumber,
        mediaUrl: downloadUrl,
        type: 'image',
        message: image.name,
      );
      _scrollToBottom();
    } catch (e) {
      _showSnackBar('Failed to send image: $e');
    }
  }

  Future<void> _handleCamera() async {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => WhatsAppCameraScreen(
          onMediaCaptured: (file, caption, type) async {
            if (_currentUser == null) return;
            try {
              _showSnackBar('Sending $type...');
              final ext = type == 'video' ? 'mp4' : 'jpg';
              final fileName = 'group_camera_${DateTime.now().millisecondsSinceEpoch}.$ext';
              final path = 'groups/${widget.groupId}/$fileName';

              String downloadUrl = '';
              try {
                downloadUrl = await _chatService.uploadFile(file, path);
              } catch (uploadErr) {
                debugPrint('Firebase Storage camera upload failed: $uploadErr. Using Base64.');
                final bytes = await file.readAsBytes();
                final mime = type == 'video' ? 'video/mp4' : 'image/jpeg';
                downloadUrl = 'data:$mime;base64,${base64Encode(bytes)}';
              }

              await _chatService.sendGroupMessage(
                groupId: widget.groupId,
                senderId: _currentUser!.id,
                senderName: _currentUser!.name.isNotEmpty ? _currentUser!.name : _currentUser!.phoneNumber,
                mediaUrl: downloadUrl,
                type: type,
                message: caption,
              );
              _scrollToBottom();
            } catch (e) {
              _showSnackBar('Error sending media: $e');
            }
          },
        ),
      ),
    );
  }

  Future<void> _handleDocument() async {
    try {
      final PlatformFile? pickedFile = await FilePicker.pickFile(
        type: FileType.any,
      );
      if (pickedFile == null || pickedFile.path == null) return;

      final file = File(pickedFile.path!);
      final fileName = pickedFile.name;
      final bytes = await file.length();
      final sizeMb = (bytes / (1024 * 1024)).toStringAsFixed(1);
      final ext = fileName.contains('.') ? fileName.split('.').last.toUpperCase() : 'FILE';
      final fileSizeString = bytes < 1024 * 1024
          ? '${(bytes / 1024).toStringAsFixed(0)} KB • $ext'
          : '$sizeMb MB • $ext';

      _showSnackBar('Sending document...');
      String mediaUrl = '';
      try {
        final path = 'groups/${widget.groupId}/${DateTime.now().millisecondsSinceEpoch}_$fileName';
        mediaUrl = await _chatService.uploadFile(file, path);
      } catch (uploadErr) {
        debugPrint('Storage upload error: $uploadErr. Using resilient payload.');
        if (bytes < 750 * 1024) {
          final fileBytes = await file.readAsBytes();
          mediaUrl = 'data:application/octet-stream;base64,${base64Encode(fileBytes)}';
        } else {
          mediaUrl = file.path;
        }
      }

      await _chatService.sendGroupMessage(
        groupId: widget.groupId,
        senderId: _currentUser!.id,
        senderName: _currentUser!.name.isNotEmpty ? _currentUser!.name : _currentUser!.phoneNumber,
        message: fileName,
        type: 'document',
        mediaUrl: mediaUrl,
        fileName: fileName,
        fileSize: fileSizeString,
      );
      _scrollToBottom();
    } catch (e) {
      _showSnackBar('Failed to send document: $e');
    }
  }

  Future<void> _handleAudio() async {
    try {
      final File? pickedFile = await Navigator.push<File>(
        context,
        MaterialPageRoute(
          builder: (_) => const WhatsAppAudioPickerScreen(),
        ),
      );
      if (pickedFile == null || !pickedFile.existsSync()) return;

      final file = pickedFile;
      final fileName = file.path.split(Platform.pathSeparator).last;
      final bytes = await file.length();
      final sizeMb = (bytes / (1024 * 1024)).toStringAsFixed(1);
      final fileSizeString = bytes < 1024 * 1024
          ? '${(bytes / 1024).toStringAsFixed(0)} KB • Audio'
          : '$sizeMb MB • Audio';

      _showSnackBar('Sending audio...');
      String mediaUrl = '';
      try {
        final path = 'groups/${widget.groupId}/audio_${DateTime.now().millisecondsSinceEpoch}_$fileName';
        mediaUrl = await _chatService.uploadFile(file, path);
      } catch (uploadErr) {
        debugPrint('Group audio upload failed: $uploadErr. Using Base64.');
        if (bytes < 750 * 1024) {
          final fileBytes = await file.readAsBytes();
          mediaUrl = 'data:audio/mpeg;base64,${base64Encode(fileBytes)}';
        } else {
          mediaUrl = file.path;
        }
      }

      await _chatService.sendGroupMessage(
        groupId: widget.groupId,
        senderId: _currentUser!.id,
        senderName: _currentUser!.name.isNotEmpty ? _currentUser!.name : _currentUser!.phoneNumber,
        message: fileName,
        type: 'audio',
        mediaUrl: mediaUrl,
        fileName: fileName,
        fileSize: fileSizeString,
      );
      _scrollToBottom();
    } catch (e) {
      _showSnackBar('Failed to send audio: $e');
    }
  }

  Future<void> _handleLocation() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _showSnackBar('Please enable GPS / Location service on your device');
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          _showSnackBar('Location permission denied');
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        _showSnackBar('Location permanently denied. Enable in Settings.');
        return;
      }

      _showSnackBar('Fetching GPS location...');

      Position? position;
      try {
        position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 10),
        );
      } catch (_) {
        position = await Geolocator.getLastKnownPosition();
      }

      if (position == null) {
        _showSnackBar('Could not determine current location. Try again.');
        return;
      }

      if (_currentUser == null) return;

      await _chatService.sendGroupMessage(
        groupId: widget.groupId,
        senderId: _currentUser!.id,
        senderName: _currentUser!.name.isNotEmpty ? _currentUser!.name : _currentUser!.phoneNumber,
        message: '📍 Current Location',
        type: 'location',
        latitude: position.latitude,
        longitude: position.longitude,
      );
      _scrollToBottom();
    } catch (e) {
      _showSnackBar('Failed to share location: $e');
    }
  }

  void _handlePoll() {
    showDialog(
      context: context,
      builder: (_) => WhatsAppPollDialog(
        onCreatePoll: (question, options, allowMultiple) async {
          if (_currentUser == null) return;
          final pollData = {
            'question': question,
            'allowMultiple': allowMultiple,
            'options': options.map((opt) => {'title': opt, 'text': opt, 'votes': <String>[]}).toList(),
          };

          await _chatService.sendGroupMessage(
            groupId: widget.groupId,
            senderId: _currentUser!.id,
            senderName: _currentUser!.name.isNotEmpty ? _currentUser!.name : _currentUser!.phoneNumber,
            message: '📊 Poll: $question',
            type: 'poll',
            pollData: pollData,
          );
          _scrollToBottom();
        },
      ),
    );
  }

  void _handleEvent() {
    showDialog(
      context: context,
      builder: (_) => WhatsAppEventDialog(
        onCreateEvent: ({
          required String title,
          required DateTime date,
          required TimeOfDay time,
          String? location,
          String? description,
        }) async {
          if (_currentUser == null) return;
          final senderName = _currentUser!.name.isNotEmpty
              ? _currentUser!.name
              : _currentUser!.phoneNumber;
          await _chatService.sendGroupEventMessage(
            groupId: widget.groupId,
            senderId: _currentUser!.id,
            senderName: senderName,
            title: title,
            date: date,
            time: time,
            location: location,
            description: description,
          );
          _scrollToBottom();
        },
      ),
    );
  }

  void _handleContact() {
    _showSnackBar('Contact sharing active');
  }

  // ============================================================
  // VOICE RECORDING & PLAYBACK
  // ============================================================

  Future<void> _startVoiceRecording() async {
    try {
      if (await _audioRecorder.hasPermission()) {
        final path = '${Directory.systemTemp.path}/voice_group_${DateTime.now().millisecondsSinceEpoch}.m4a';
        _voiceRecordingPath = path;

        await _audioRecorder.start(
          const RecordConfig(encoder: AudioEncoder.aacLc),
          path: path,
        );

        setState(() {
          _isRecordingVoice = true;
          _recordingSeconds = 0;
        });

        _recordingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
          if (mounted) {
            setState(() {
              _recordingSeconds++;
            });
          }
        });
      } else {
        _showSnackBar('Microphone permission required for voice notes');
      }
    } catch (e) {
      debugPrint('Error starting audio recording: $e');
    }
  }

  String _formatDuration(int seconds) {
    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  Future<void> _stopVoiceRecording({bool send = true}) async {
    _recordingTimer?.cancel();
    final duration = _recordingSeconds;
    setState(() {
      _isRecordingVoice = false;
      _recordingSeconds = 0;
    });

    try {
      final path = await _audioRecorder.stop();
      if (!send || duration <= 0 || _currentUser == null) return;

      final actualPath = path ?? _voiceRecordingPath;
      if (actualPath == null) return;
      final file = File(actualPath);
      if (!file.existsSync()) return;

      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) return;

      _showSnackBar('Sending voice message...');
      String downloadUrl = '';
      try {
        final storagePath = 'groups/${widget.groupId}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
        downloadUrl = await _chatService.uploadFile(file, storagePath);
      } catch (uploadErr) {
        debugPrint('Voice storage upload failed: $uploadErr. Using Base64 payload.');
        downloadUrl = 'data:audio/m4a;base64,${base64Encode(bytes)}';
      }

      await _chatService.sendGroupMessage(
        groupId: widget.groupId,
        senderId: _currentUser!.id,
        senderName: _currentUser!.name.isNotEmpty ? _currentUser!.name : _currentUser!.phoneNumber,
        mediaUrl: downloadUrl,
        type: 'audio',
        message: 'Voice message (${duration}s)',
        replyToId: _replyingToMessage?.id,
        replyToText: _replyingToMessage?.message,
        replyToSender: _replyingToMessage?.senderId == _currentUser!.id
            ? 'You'
            : (_replyingToMessage?.senderName ?? 'Member'),
      );

      setState(() => _replyingToMessage = null);
      _scrollToBottom();
    } catch (e) {
      debugPrint('Error stopping audio recording: $e');
    }
  }

  Future<void> _toggleAudioPlay(MessageModel msg) async {
    if (_playingAudioMessageId == msg.id && _playerState == PlayerState.playing) {
      await _audioPlayer.pause();
      setState(() {
        _playerState = PlayerState.paused;
      });
      return;
    }

    try {
      await _audioPlayer.stop();
      await _audioPlayer.setVolume(1.0);

      final mediaUrl = msg.mediaUrl;
      if (mediaUrl != null && mediaUrl.startsWith('data:audio')) {
        final pureBase64 = mediaUrl.contains(',') ? mediaUrl.split(',').last : mediaUrl;
        final bytes = base64Decode(pureBase64);
        await _audioPlayer.play(BytesSource(bytes, mimeType: 'audio/m4a'));
      } else if (mediaUrl != null && mediaUrl.startsWith('http') && !mediaUrl.contains('actions.google.com')) {
        await _audioPlayer.play(UrlSource(mediaUrl));
      } else if (mediaUrl != null && (mediaUrl.startsWith('/') || mediaUrl.contains(r':\')) && File(mediaUrl).existsSync()) {
        await _audioPlayer.play(DeviceFileSource(mediaUrl));
      } else {
        _showSnackBar('No voice audio recorded for this message');
        return;
      }

      setState(() {
        _playingAudioMessageId = msg.id;
        _playerState = PlayerState.playing;
      });
    } catch (e) {
      debugPrint('Audio playback error: $e');
      _showSnackBar('Audio playback error: $e');
    }
  }

  // ============================================================
  // GROUP CALLING (VOICE / VIDEO)
  // ============================================================

  // ============================================================
  // GROUP CALLING (VOICE / VIDEO) - REAL WHATSAPP MULTI-PARTICIPANT
  // ============================================================

  Future<void> _startGroupCall({required bool isVideo}) async {
    if (_currentUser == null) return;

    final otherMembers = _memberUsers.where((u) => u.id != _currentUser!.id).toList();

    if (otherMembers.isEmpty) {
      _showSnackBar('No other members available to call');
      return;
    }

    // Direct call to all members - identical to 1-on-1 p2p call behavior
    await _launchGroupCall(otherMembers, isVideo: isVideo);
  }

  Future<void> _launchGroupCall(List<UserModel> membersToCall, {required bool isVideo}) async {
    if (_currentUser == null) return;

    try {
      final callId = await GroupCallService().createGroupCall(
        groupId: widget.groupId,
        groupName: widget.groupName,
        caller: _currentUser!,
        invitedMembers: membersToCall,
        isVideo: isVideo,
      );

      if (!mounted) return;

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => GroupCallScreen(
            callId: callId,
            groupId: widget.groupId,
            groupName: widget.groupName,
            currentUser: _currentUser!,
            groupMembers: _memberUsers,
            isVideo: isVideo,
            isIncoming: false,
          ),
        ),
      );
    } catch (e) {
      _showSnackBar('Error starting group call: $e');
    }
  }

  // ============================================================
  // GROUP MENU OPTIONS (MATCHING WHATSAPP SCREENSHOT)
  // ============================================================

  void _handleMenuSelection(String val) {
    switch (val) {
      case 'meta_ai':
        _askMetaAiPrivately();
        break;
      case 'add_members':
        _showAddMembersSheet();
        break;
      case 'info':
        _showGroupInfoDialog();
        break;
      case 'media':
        _showGroupMediaSheet();
        break;
      case 'search':
        setState(() {
          _isSearching = true;
        });
        break;
      case 'mute':
        _showMuteNotificationsDialog();
        break;
      case 'disappearing':
        _showDisappearingMessagesDialog();
        break;
      case 'theme':
        _showChatThemeSheet();
        break;
      case 'more':
        _showMoreOptionsSheet();
        break;
    }
  }

  void _askMetaAiPrivately() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const AiChatScreen(),
      ),
    );
  }

  void _showAddMembersSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        maxChildSize: 0.9,
        minChildSize: 0.4,
        expand: false,
        builder: (_, scrollCtrl) => StreamBuilder<List<UserModel>>(
          stream: _userService.getAllUsersStream(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator(color: Color(0xFF5B50E6)));
            }

            final existingIds = _memberUsers.map((u) => u.id).toSet();
            if (_currentUser != null) existingIds.add(_currentUser!.id);
            final availableContacts = (snapshot.data ?? []).where((u) => !existingIds.contains(u.id)).toList();

            return Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Add Members',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF171B2D)),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (availableContacts.isEmpty)
                    const Expanded(
                      child: Center(
                        child: Text('All available contacts are already in this group', style: TextStyle(color: Colors.grey)),
                      ),
                    )
                  else
                    Expanded(
                      child: ListView.separated(
                        controller: scrollCtrl,
                        itemCount: availableContacts.length,
                        separatorBuilder: (context, index) => const Divider(height: 1),
                        itemBuilder: (context, i) {
                          final c = availableContacts[i];
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: const Color(0xFF5B50E6).withValues(alpha: 0.12),
                              child: Text(c.name.isNotEmpty ? c.name[0].toUpperCase() : '👤',
                                  style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF5B50E6))),
                            ),
                            title: Text(c.name.isNotEmpty ? c.name : c.phoneNumber, style: const TextStyle(fontWeight: FontWeight.w600)),
                            subtitle: Text(c.phoneNumber, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                            trailing: ElevatedButton(
                              onPressed: () async {
                                Navigator.pop(ctx);
                                await _addMemberToGroup(c);
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF5B50E6),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                              ),
                              child: const Text('Add', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                            ),
                          );
                        },
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _addMemberToGroup(UserModel user) async {
    try {
      await FirebaseFirestore.instance.collection('groups').doc(widget.groupId).update({
        'members': FieldValue.arrayUnion([user.id]),
      });
      await _chatService.sendGroupMessage(
        groupId: widget.groupId,
        senderId: _currentUser?.id ?? '',
        senderName: _currentUser?.name ?? 'Admin',
        message: '👤 ${user.name.isNotEmpty ? user.name : user.phoneNumber} was added to the group',
        type: 'text',
      );
      _fetchGroupDetails();
      _showSnackBar('${user.name} added to group');
    } catch (e) {
      _showSnackBar('Failed to add member: $e');
    }
  }

  void _showGroupMediaSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        maxChildSize: 0.9,
        minChildSize: 0.4,
        expand: false,
        builder: (_, scrollCtrl) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _chatService.getGroupMessages(widget.groupId),
          builder: (context, snapshot) {
            final docs = snapshot.data?.docs ?? [];
            final mediaDocs = docs.where((d) {
              final type = d.data()['type']?.toString() ?? '';
              return type == 'image' || type == 'video' || type == 'document';
            }).toList();

            return Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Group Media (${mediaDocs.length})',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Color(0xFF171B2D))),
                      IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
                    ],
                  ),
                  const SizedBox(height: 14),
                  if (mediaDocs.isEmpty)
                    const Expanded(
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.perm_media_outlined, size: 50, color: Colors.grey),
                            SizedBox(height: 10),
                            Text('No photos, videos, or documents shared yet', style: TextStyle(color: Colors.grey)),
                          ],
                        ),
                      ),
                    )
                  else
                    Expanded(
                      child: GridView.builder(
                        controller: scrollCtrl,
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          crossAxisSpacing: 6,
                          mainAxisSpacing: 6,
                        ),
                        itemCount: mediaDocs.length,
                        itemBuilder: (context, idx) {
                          final data = mediaDocs[idx].data();
                          final type = data['type'] ?? 'image';
                          final url = data['mediaUrl'] ?? '';
                          final isImage = type == 'image';

                          return GestureDetector(
                            onTap: () {
                              if (url.isNotEmpty) {
                                if (isImage) {
                                  InteractivePhotoViewer.open(
                                    context,
                                    imageUrl: url,
                                    title: data['message']?.toString() ?? 'Photo',
                                  );
                                } else {
                                  launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
                                }
                              }
                            },
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.grey.shade200,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: isImage && url.isNotEmpty
                                  ? (url.startsWith('data:image')
                                      ? Image.memory(
                                          base64Decode(url.split(',').last),
                                          fit: BoxFit.cover,
                                        )
                                      : Image.network(
                                          url,
                                          fit: BoxFit.cover,
                                          errorBuilder: (context, error, stackTrace) => const Icon(Icons.broken_image, color: Colors.grey),
                                        ))
                                  : Center(
                                      child: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            type == 'video' ? Icons.videocam_rounded : Icons.insert_drive_file_rounded,
                                            color: const Color(0xFF5B50E6),
                                            size: 28,
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            type.toUpperCase(),
                                            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey),
                                          ),
                                        ],
                                      ),
                                    ),
                            ),
                          );
                        },
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  void _showMuteNotificationsDialog() {
    String selected = '8 hours';
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Mute notifications for...', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RadioListTile<String>(
                title: const Text('8 hours'),
                value: '8 hours',
                groupValue: selected,
                activeColor: const Color(0xFF5B50E6),
                onChanged: (val) => setDialogState(() => selected = val!),
              ),
              RadioListTile<String>(
                title: const Text('1 week'),
                value: '1 week',
                groupValue: selected,
                activeColor: const Color(0xFF5B50E6),
                onChanged: (val) => setDialogState(() => selected = val!),
              ),
              RadioListTile<String>(
                title: const Text('Always'),
                value: 'Always',
                groupValue: selected,
                activeColor: const Color(0xFF5B50E6),
                onChanged: (val) => setDialogState(() => selected = val!),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                _showSnackBar('Notifications muted for $selected');
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF5B50E6),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('OK'),
            ),
          ],
        ),
      ),
    );
  }

  void _showDisappearingMessagesDialog() {
    String selected = 'Off';
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(
            children: [
              Icon(Icons.timer_outlined, color: Color(0xFF5B50E6)),
              SizedBox(width: 8),
              Text('Disappearing messages', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'When turned on, new messages in this chat will disappear after the selected duration.',
                style: TextStyle(fontSize: 12.5, color: Colors.grey),
              ),
              const SizedBox(height: 12),
              ...['24 hours', '7 days', '90 days', 'Off'].map(
                (opt) => RadioListTile<String>(
                  title: Text(opt),
                  value: opt,
                  groupValue: selected,
                  activeColor: const Color(0xFF5B50E6),
                  onChanged: (val) => setDialogState(() => selected = val!),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(ctx);
                try {
                  await FirebaseFirestore.instance.collection('groups').doc(widget.groupId).update({
                    'disappearingTimer': selected,
                  });
                  await _chatService.sendGroupMessage(
                    groupId: widget.groupId,
                    senderId: _currentUser?.id ?? '',
                    senderName: _currentUser?.name ?? 'Admin',
                    message: '⏱️ Disappearing messages timer set to $selected',
                    type: 'text',
                  );
                  _showSnackBar('Disappearing messages set to $selected');
                } catch (e) {
                  _showSnackBar('Error: $e');
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF5B50E6),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Done'),
            ),
          ],
        ),
      ),
    );
  }

  void _showChatThemeSheet() {
    final themes = [
      {'name': 'Default Light', 'color': const Color(0xFFF4F6FC)},
      {'name': 'WhatsApp Green', 'color': const Color(0xFFE7F3EF)},
      {'name': 'Soft Lavender', 'color': const Color(0xFFF0EFFC)},
      {'name': 'Warm Amber', 'color': const Color(0xFFFEF9EE)},
      {'name': 'Rose Blush', 'color': const Color(0xFFFDF2F4)},
      {'name': 'Dark Mode', 'color': const Color(0xFF1B242C)},
    ];

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Chat Theme Wallpaper', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: themes.map((th) {
                final c = th['color'] as Color;
                final name = th['name'] as String;
                final isSel = _chatThemeColor == c;

                return GestureDetector(
                  onTap: () {
                    setState(() => _chatThemeColor = c);
                    Navigator.pop(ctx);
                    _showSnackBar('Theme updated to $name');
                  },
                  child: Column(
                    children: [
                      Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          color: c,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isSel ? const Color(0xFF5B50E6) : Colors.black12,
                            width: isSel ? 3 : 1,
                          ),
                        ),
                        child: isSel ? const Icon(Icons.check, color: Color(0xFF5B50E6), size: 24) : null,
                      ),
                      const SizedBox(height: 6),
                      Text(name, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500)),
                    ],
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  void _showMoreOptionsSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.report_problem_outlined, color: Colors.redAccent),
                title: const Text('Report'),
                onTap: () {
                  Navigator.pop(ctx);
                  _showReportDialog();
                },
              ),
              ListTile(
                leading: const Icon(Icons.exit_to_app_rounded, color: Colors.redAccent),
                title: const Text('Exit group'),
                onTap: () {
                  Navigator.pop(ctx);
                  _confirmExitGroup();
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_sweep_outlined, color: Color(0xFF5B50E6)),
                title: const Text('Clear chat'),
                onTap: () {
                  Navigator.pop(ctx);
                  _confirmClearChat();
                },
              ),
              ListTile(
                leading: const Icon(Icons.share_outlined, color: Color(0xFF5B50E6)),
                title: const Text('Export chat'),
                onTap: () {
                  Navigator.pop(ctx);
                  _showSnackBar('Chat exported to clipboard');
                },
              ),
              ListTile(
                leading: const Icon(Icons.add_to_home_screen_rounded, color: Color(0xFF5B50E6)),
                title: const Text('Add shortcut'),
                onTap: () {
                  Navigator.pop(ctx);
                  _showSnackBar('Shortcut added for ${widget.groupName}');
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showReportDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Report ${widget.groupName}?'),
        content: const Text('The last 5 messages from this group will be forwarded to ChatApp security. No one in the group will be notified.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _showSnackBar('Report submitted. Thank you for keeping ChatApp safe.');
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
            child: const Text('Report'),
          ),
        ],
      ),
    );
  }

  void _confirmExitGroup() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Exit "${widget.groupName}" group?'),
        content: const Text('Only group admins will be notified that you left the group.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              if (_currentUser != null) {
                try {
                  await FirebaseFirestore.instance.collection('groups').doc(widget.groupId).update({
                    'members': FieldValue.arrayRemove([_currentUser!.id]),
                  });
                  await _chatService.sendGroupMessage(
                    groupId: widget.groupId,
                    senderId: _currentUser!.id,
                    senderName: _currentUser!.name.isNotEmpty ? _currentUser!.name : _currentUser!.phoneNumber,
                    message: '👋 ${_currentUser!.name} left the group',
                    type: 'text',
                  );
                  if (mounted) Navigator.pop(context);
                } catch (e) {
                  _showSnackBar('Error leaving group: $e');
                }
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
            child: const Text('Exit'),
          ),
        ],
      ),
    );
  }

  void _confirmClearChat() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Clear chat messages?'),
        content: const Text('Messages in this group will be cleared from your view.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _showSnackBar('Chat cleared');
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }

  void _showGroupInfoDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            CircleAvatar(
              backgroundColor: const Color(0xFF5B50E6).withValues(alpha: 0.15),
              child: const Text('👥', style: TextStyle(fontSize: 20)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                widget.groupName,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Members (${_memberUsers.length})',
                style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF5B50E6)),
              ),
              const SizedBox(height: 8),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _memberUsers.length,
                  itemBuilder: (context, idx) {
                    final u = _memberUsers[idx];
                    final isAdmin = _groupData?['adminId'] == u.id;
                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(
                        radius: 16,
                        backgroundColor: const Color(0xFF5B50E6).withValues(alpha: 0.1),
                        child: Text(u.name.isNotEmpty ? u.name[0].toUpperCase() : '👤'),
                      ),
                      title: Text(u.name.isNotEmpty ? u.name : u.phoneNumber),
                      trailing: isAdmin
                          ? Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFF10B981).withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Text(
                                'Admin',
                                style: TextStyle(color: Color(0xFF10B981), fontSize: 11, fontWeight: FontWeight.bold),
                              ),
                            )
                          : null,
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _showAddMembersSheet();
            },
            child: const Text('Add Member', style: TextStyle(color: Color(0xFF5B50E6), fontWeight: FontWeight.bold)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close', style: TextStyle(color: Colors.grey)),
          ),
        ],
      ),
    );
  }

  void _showSnackBar(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), duration: const Duration(seconds: 2)),
    );
  }

  // ============================================================
  // BUILD METHOD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _chatThemeColor,
      appBar: _buildAppBar(),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF5B50E6)))
          : Column(
              children: [
                Expanded(child: _buildMessagesStream()),
                if (_replyingToMessage != null) _buildReplyPreview(),
                _buildInputBar(),
                if (_showEmojiPicker) _buildEmojiPicker(),
              ],
            ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    if (_isSearching) {
      return AppBar(
        elevation: 1,
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF171B2D),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            setState(() {
              _isSearching = false;
              _searchFilterQuery = '';
              _searchFilterController.clear();
            });
          },
        ),
        title: TextField(
          controller: _searchFilterController,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Search in group...',
            border: InputBorder.none,
          ),
          onChanged: (val) {
            setState(() {
              _searchFilterQuery = val.trim().toLowerCase();
            });
          },
        ),
        actions: [
          if (_searchFilterQuery.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.clear_rounded),
              onPressed: () {
                setState(() {
                  _searchFilterQuery = '';
                  _searchFilterController.clear();
                });
              },
            ),
        ],
      );
    }

    final memberCount = _memberUsers.isNotEmpty ? _memberUsers.length : (widget.memberIds?.length ?? 1);

    return AppBar(
      elevation: 1,
      backgroundColor: Colors.white,
      foregroundColor: const Color(0xFF171B2D),
      leadingWidth: 32,
      title: InkWell(
        onTap: _showGroupInfoDialog,
        child: Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: const Color(0xFF5B50E6).withValues(alpha: 0.12),
              child: Text(
                widget.groupName.isNotEmpty ? widget.groupName[0].toUpperCase() : '👥',
                style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF5B50E6), fontSize: 16),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.groupName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF171B2D),
                    ),
                  ),
                  Text(
                    _memberUsers.isNotEmpty
                        ? _memberUsers.take(3).map((u) => '~ ${u.name.isNotEmpty ? u.name : u.phoneNumber}').join(', ')
                        : '$memberCount members • tap for info',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        IconButton(
          tooltip: 'Group Video Call',
          icon: const Icon(Icons.videocam_rounded, color: Color(0xFF5B50E6)),
          onPressed: () => _startGroupCall(isVideo: true),
        ),
        IconButton(
          tooltip: 'Group Voice Call',
          icon: const Icon(Icons.phone_rounded, color: Color(0xFF5B50E6)),
          onPressed: () => _startGroupCall(isVideo: false),
        ),
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert_rounded, color: Color(0xFF171B2D)),
          elevation: 6,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          onSelected: _handleMenuSelection,
          itemBuilder: (ctx) => [
            const PopupMenuItem(
              value: 'meta_ai',
              child: Text('Ask Meta AI privately', style: TextStyle(fontSize: 14)),
            ),
            const PopupMenuItem(
              value: 'add_members',
              child: Text('Add members', style: TextStyle(fontSize: 14)),
            ),
            const PopupMenuItem(
              value: 'info',
              child: Text('Group info', style: TextStyle(fontSize: 14)),
            ),
            const PopupMenuItem(
              value: 'media',
              child: Text('Group media', style: TextStyle(fontSize: 14)),
            ),
            const PopupMenuItem(
              value: 'search',
              child: Text('Search', style: TextStyle(fontSize: 14)),
            ),
            const PopupMenuItem(
              value: 'mute',
              child: Text('Mute notifications', style: TextStyle(fontSize: 14)),
            ),
            const PopupMenuItem(
              value: 'disappearing',
              child: Text('Disappearing messages', style: TextStyle(fontSize: 14)),
            ),
            const PopupMenuItem(
              value: 'theme',
              child: Text('Chat theme', style: TextStyle(fontSize: 14)),
            ),
            const PopupMenuItem(
              value: 'more',
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('More', style: TextStyle(fontSize: 14)),
                  Icon(Icons.chevron_right_rounded, size: 18, color: Colors.grey),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ============================================================
  // REACTIONS & ACTIONS (REPLY / COPY / FORWARD / DELETE)
  // ============================================================

  void _showMessageOptions(MessageModel msg) {
    setState(() {
      _selectedMessageForReaction = msg;
    });
  }

  Future<void> _reactToMessage(MessageModel msg, String emoji) async {
    setState(() {
      _selectedMessageForReaction = null;
    });
    if (msg.id == null || _currentUser == null) return;

    try {
      await _chatService.toggleGroupReaction(
        groupId: widget.groupId,
        messageId: msg.id!,
        userId: _currentUser!.id,
        emoji: emoji,
      );
    } catch (e) {
      debugPrint('Group reaction error: $e');
    }
  }

  void _forwardMessage(MessageModel msg) {
    if (_currentUser == null) return;
    WhatsAppForwardDialog.show(
      context,
      message: msg,
      currentUserId: _currentUser!.id,
      currentUserName: _currentUser!.name.isNotEmpty ? _currentUser!.name : _currentUser!.phoneNumber,
    );
  }

  void _copyMessage(MessageModel msg) {
    Clipboard.setData(ClipboardData(text: msg.message));
    _showSnackBar('Copied to clipboard');
  }

  void _deleteMessage(MessageModel msg) {
    if (msg.id == null || _currentUser == null) return;

    WhatsAppDeleteMessageDialog.show(
      context: context,
      onDeleteForEveryone: () async {
        await _chatService.deleteGroupMessageForEveryone(
          groupId: widget.groupId,
          messageId: msg.id!,
        );
        _showSnackBar('Message deleted for everyone');
      },
      onDeleteForMe: () async {
        await _chatService.deleteGroupMessageForMe(
          groupId: widget.groupId,
          messageId: msg.id!,
          userId: _currentUser!.id,
        );
        _showSnackBar('Message deleted for you');
      },
    );
  }

  Widget _buildFloatingReactionToolbar(MessageModel msg) {
    final List<String> quickReactions = ['👍', '❤️', '😂', '😮', '😢', '🙏'];

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * 0.92,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.14),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ...quickReactions.map((emoji) {
              return InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => _reactToMessage(msg, emoji),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
                  child: Text(emoji, style: const TextStyle(fontSize: 20)),
                ),
              );
            }),
            InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => setState(() => _showEmojiPicker = true),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 5, vertical: 4),
                child: Icon(Icons.add, color: Color(0xFF5B50E6), size: 20),
              ),
            ),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 4),
              height: 18,
              width: 1,
              color: Colors.grey.shade300,
            ),
            InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () {
                setState(() {
                  _replyingToMessage = msg;
                  _selectedMessageForReaction = null;
                });
              },
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 5, vertical: 4),
                child: Icon(Icons.reply_rounded, color: Colors.black54, size: 18),
              ),
            ),
            InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () {
                setState(() => _selectedMessageForReaction = null);
                _forwardMessage(msg);
              },
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 5, vertical: 4),
                child: Icon(Icons.forward_rounded, color: Color(0xFF5B50E6), size: 18),
              ),
            ),
            InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () {
                _copyMessage(msg);
                setState(() => _selectedMessageForReaction = null);
              },
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 5, vertical: 4),
                child: Icon(Icons.copy_rounded, color: Colors.black54, size: 16),
              ),
            ),
            InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () {
                setState(() => _selectedMessageForReaction = null);
                _deleteMessage(msg);
              },
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 5, vertical: 4),
                child: Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 18),
              ),
            ),
            InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => setState(() => _selectedMessageForReaction = null),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                child: Icon(Icons.close_rounded, color: Colors.grey, size: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // MESSAGES STREAM & BUBBLE RENDERING
  // ============================================================

  Widget _buildMessagesStream() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _chatService.getGroupMessages(widget.groupId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
          return const Center(child: CircularProgressIndicator(color: Color(0xFF5B50E6)));
        }

        var docs = snapshot.data?.docs ?? [];

        if (_currentUser != null) {
          docs = docs.where((d) {
            final data = d.data();
            final deletedFor = List<String>.from(data['deletedFor'] ?? []);
            return !deletedFor.contains(_currentUser!.id);
          }).toList();
        }

        if (_searchFilterQuery.isNotEmpty) {
          docs = docs.where((d) {
            final data = d.data();
            final text = data['message']?.toString().toLowerCase() ?? '';
            final sender = data['senderName']?.toString().toLowerCase() ?? '';
            return text.contains(_searchFilterQuery) || sender.contains(_searchFilterQuery);
          }).toList();
        }

        if (docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(_searchFilterQuery.isNotEmpty ? Icons.search_off_rounded : Icons.group_outlined, size: 56, color: Colors.grey),
                const SizedBox(height: 12),
                Text(
                  _searchFilterQuery.isNotEmpty ? 'No messages found' : 'Welcome to ${widget.groupName}!',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF171B2D)),
                ),
                const SizedBox(height: 4),
                Text(
                  _searchFilterQuery.isNotEmpty
                      ? 'No results matching "$_searchFilterQuery"'
                      : 'Send a message to begin chatting with group members.',
                  style: const TextStyle(color: Colors.grey, fontSize: 13),
                ),
              ],
            ),
          );
        }

        if (snapshot.hasData && _currentUser != null && docs.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _chatService.markGroupMessagesAsRead(
              groupId: widget.groupId,
              userId: _currentUser!.id,
            );
          });
        }

        // Scroll to first unread on first open; then auto-scroll to bottom for new messages
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!_initialScrollDone) {
            _initialScrollDone = true;
            _scrollToFirstUnread(docs);
          } else {
            _scrollToBottom();
          }
        });

        return ListView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final doc = docs[index];
            final msg = MessageModel.fromMap(doc.data(), doc.id);
            final bool isMe = _currentUser != null && msg.senderId == _currentUser!.id;

            if (msg.type == 'system') {
              return Center(
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 4),
                    ],
                  ),
                  child: Text(
                    msg.message,
                    style: const TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.w500),
                  ),
                ),
              );
            }

            return _buildGroupMessageRow(msg, isMe);
          },
        );
      },
    );
  }

  Widget _buildGroupMessageTick(MessageModel msg) {
    // Get total members excluding sender
    final List<String> allMembers = List<String>.from(
      _groupData?['members'] ?? widget.memberIds ?? [],
    );
    final otherMembers = allMembers.where((m) => m != msg.senderId).toList();
    final readBy = msg.readBy ?? [msg.senderId];

    // Double Purple Tick if any other member has opened the chat / read the message
    final otherReaders = readBy.where((r) => r != msg.senderId).toList();
    final bool isRead = otherMembers.isNotEmpty
        ? otherMembers.any((m) => readBy.contains(m)) || msg.status == 'read' || msg.isSeen
        : otherReaders.isNotEmpty;

    if (isRead) {
      return const Icon(
        Icons.done_all_rounded,
        size: 15,
        color: Color(0xFFA855F7), // Purple tick when opened/seen
      );
    }

    // Default: Single tick if not seen/opened yet
    return const Icon(
      Icons.check_rounded,
      size: 15,
      color: Colors.white70,
    );
  }

  Widget _buildGroupMessageRow(MessageModel msg, bool isMe) {
    final bool isSelected = _selectedMessageForReaction?.id == msg.id && msg.id != null;

    return Column(
      crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        if (isSelected) _buildFloatingReactionToolbar(msg),
        Row(
          mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (isMe)
              IconButton(
                icon: const Icon(Icons.reply_rounded, color: Colors.black26, size: 18),
                tooltip: 'Forward',
                onPressed: () => _forwardMessage(msg),
              ),

            GestureDetector(
              onLongPress: () => _showMessageOptions(msg),
              child: _buildGroupMessageBubble(msg, isMe),
            ),

            if (!isMe)
              IconButton(
                icon: const Icon(Icons.reply_rounded, color: Colors.black26, size: 18),
                tooltip: 'Forward',
                onPressed: () => _forwardMessage(msg),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildGroupMessageBubble(MessageModel msg, bool isMe) {
    if (msg.type == 'call' || msg.message.startsWith('📞 Calling') || msg.type == 'group_call') {
      return _buildCallMessage(msg, isMe);
    }

    final senderName = msg.senderName ?? 'Member';

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
      decoration: BoxDecoration(
        color: isMe ? const Color(0xFF5B50E6) : Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(16),
          topRight: const Radius.circular(16),
          bottomLeft: Radius.circular(isMe ? 16 : 4),
          bottomRight: Radius.circular(isMe ? 4 : 16),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 5,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Column(
              crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                // Forwarded header
                if (msg.isForwarded)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.forward_rounded, size: 13, color: isMe ? Colors.white70 : Colors.black45),
                        const SizedBox(width: 4),
                        Text(
                          'Forwarded',
                          style: TextStyle(
                            color: isMe ? Colors.white70 : Colors.black45,
                            fontStyle: FontStyle.italic,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),

                // Sender name on incoming message
                if (!isMe)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      senderName,
                      style: const TextStyle(
                        color: Color(0xFF5B50E6),
                        fontWeight: FontWeight.bold,
                        fontSize: 12.5,
                      ),
                    ),
                  ),

                // Replying preview
                if (msg.replyToText != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: isMe ? Colors.white.withValues(alpha: 0.15) : const Color(0xFFF4F6FC),
                      borderRadius: BorderRadius.circular(8),
                      border: Border(
                        left: BorderSide(
                          color: isMe ? Colors.white70 : const Color(0xFF5B50E6),
                          width: 3,
                        ),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          msg.replyToSender ?? 'Replying',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                            color: isMe ? Colors.white : const Color(0xFF5B50E6),
                          ),
                        ),
                        Text(
                          msg.replyToText!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: isMe ? Colors.white70 : Colors.black87,
                          ),
                        ),
                      ],
                    ),
                  ),

                // Content according to type
                if (msg.type == 'image')
                  _buildImageContent(msg, isMe)
                else if (msg.type == 'video')
                  _buildVideoContent(msg, isMe)
                else if (msg.type == 'document')
                  _buildDocumentContent(msg, isMe)
                else if (msg.type == 'audio')
                  _buildAudioContent(msg, isMe)
                else if (msg.type == 'location')
                  _buildLocationContent(msg, isMe)
                else if (msg.type == 'poll')
                  _buildPollContent(msg, isMe)
                else if (msg.type == 'event')
                  _buildEventContent(msg, isMe)
                else
                  Text(
                    msg.message,
                    style: TextStyle(
                      color: isMe ? Colors.white : const Color(0xFF171B2D),
                      fontSize: 14.5,
                    ),
                  ),

                const SizedBox(height: 3),
                // Timestamp and tick
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _formatTime(msg.timestamp),
                      style: TextStyle(
                        fontSize: 10,
                        color: isMe ? Colors.white70 : Colors.grey,
                      ),
                    ),
                    if (isMe) ...[
                      const SizedBox(width: 4),
                      _buildGroupMessageTick(msg),
                    ],
                  ],
                ),
              ],
            ),
          ),

          // Floating Reaction Badge
          if (msg.reactions != null && msg.reactions!.isNotEmpty)
            Positioned(
              bottom: -10,
              right: isMe ? 8 : null,
              left: isMe ? null : 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 4,
                    ),
                  ],
                ),
                child: Text(
                  msg.reactions!.values.toSet().join(' '),
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildImageContent(MessageModel msg, bool isMe) {
    final mediaUrl = msg.mediaUrl ?? '';
    Widget img;

    if (mediaUrl.startsWith('data:image') || (!mediaUrl.startsWith('http') && mediaUrl.length > 200 && !mediaUrl.startsWith('/'))) {
      try {
        final pureBase64 = mediaUrl.contains(',') ? mediaUrl.split(',').last : mediaUrl;
        img = Image.memory(
          base64Decode(pureBase64),
          fit: BoxFit.cover,
          height: 200,
          width: double.infinity,
          errorBuilder: (context, error, stackTrace) => _buildPlaceholder(),
        );
      } catch (_) {
        img = _buildPlaceholder();
      }
    } else if (mediaUrl.startsWith('http')) {
      img = Image.network(
        mediaUrl,
        fit: BoxFit.cover,
        height: 200,
        width: double.infinity,
        errorBuilder: (context, error, stackTrace) => _buildPlaceholder(),
      );
    } else if (mediaUrl.isNotEmpty && (mediaUrl.startsWith('/') || mediaUrl.contains(r':\'))) {
      img = Image.file(
        File(mediaUrl),
        fit: BoxFit.cover,
        height: 200,
        width: double.infinity,
        errorBuilder: (context, error, stackTrace) => _buildPlaceholder(),
      );
    } else {
      img = _buildPlaceholder();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () {
            if (mediaUrl.isNotEmpty) {
              InteractivePhotoViewer.open(
                context,
                imageUrl: mediaUrl,
                title: widget.groupName,
                subtitle: _formatTime(msg.timestamp),
              );
            }
          },
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: img,
          ),
        ),
        if (msg.message.isNotEmpty && msg.message != msg.fileName) ...[
          const SizedBox(height: 4),
          Text(msg.message, style: TextStyle(color: isMe ? Colors.white : const Color(0xFF171B2D))),
        ],
      ],
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      height: 120,
      color: Colors.black12,
      child: const Center(child: Icon(Icons.broken_image, color: Colors.grey)),
    );
  }

  Widget _buildVideoContent(MessageModel msg, bool isMe) {
    final mediaUrl = msg.mediaUrl ?? '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () => InAppVideoPlayerScreen.open(
            context,
            mediaUrl: mediaUrl,
            title: msg.fileName ?? 'Video',
          ),
          child: Container(
            height: 180,
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.black87,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                const Icon(Icons.videocam_rounded, color: Colors.white24, size: 64),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF5B50E6).withValues(alpha: 0.9),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 36),
                ),
                Positioned(
                  bottom: 8,
                  left: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.play_circle_fill_rounded, color: Colors.white, size: 12),
                        SizedBox(width: 4),
                        Text('Video', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (msg.message.isNotEmpty && msg.message != 'Video' && msg.message != msg.fileName) ...[
          const SizedBox(height: 4),
          Text(msg.message, style: TextStyle(color: isMe ? Colors.white : const Color(0xFF171B2D))),
        ],
      ],
    );
  }

  Widget _buildDocumentContent(MessageModel msg, bool isMe) {
    final fileName = msg.fileName ?? 'Document';
    final fileSize = msg.fileSize ?? 'File';
    final isApk = fileName.toLowerCase().endsWith('.apk');

    return GestureDetector(
      onTap: () => DocumentHelper.openDocument(context, mediaUrl: msg.mediaUrl, fileName: fileName),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: isMe ? Colors.white.withValues(alpha: 0.15) : const Color(0xFFF4F6FC),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(
              isApk ? Icons.android_rounded : Icons.insert_drive_file_rounded,
              color: isMe ? Colors.white : const Color(0xFF5B50E6),
              size: 32,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    fileName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontWeight: FontWeight.bold, color: isMe ? Colors.white : const Color(0xFF171B2D)),
                  ),
                  Text(fileSize, style: TextStyle(fontSize: 11, color: isMe ? Colors.white70 : Colors.grey)),
                ],
              ),
            ),
            IconButton(
              icon: Icon(Icons.open_in_new_rounded, color: isMe ? Colors.white : const Color(0xFF5B50E6)),
              tooltip: 'Open / View',
              onPressed: () => DocumentHelper.openDocument(context, mediaUrl: msg.mediaUrl, fileName: fileName),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAudioContent(MessageModel msg, bool isMe) {
    final bool isPlayingThis =
        _playingAudioMessageId == msg.id && _playerState == PlayerState.playing;

    return Row(
      children: [
        GestureDetector(
          onTap: () => _toggleAudioPlay(msg),
          child: CircleAvatar(
            backgroundColor: isMe ? Colors.white : const Color(0xFF5B50E6),
            radius: 18,
            child: Icon(
              isPlayingThis ? Icons.pause_rounded : Icons.play_arrow_rounded,
              color: isMe ? const Color(0xFF5B50E6) : Colors.white,
              size: 22,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: List.generate(22, (index) {
                  final height = (index % 4 == 0
                      ? 16.0
                      : (index % 2 == 0 ? 10.0 : 6.0));
                  return Expanded(
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 1),
                      height: height,
                      decoration: BoxDecoration(
                        color: isPlayingThis
                            ? (isMe ? Colors.white : const Color(0xFF5B50E6))
                            : (isMe ? Colors.white60 : Colors.grey.shade400),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  );
                }),
              ),
              const SizedBox(height: 4),
              Text(
                msg.message.isNotEmpty ? msg.message : 'Voice Note',
                style: TextStyle(
                  color: isMe ? Colors.white70 : Colors.grey.shade600,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLocationContent(MessageModel msg, bool isMe) {
    final lat = msg.latitude ?? 0;
    final lng = msg.longitude ?? 0;
    final mapsUrl = 'https://www.google.com/maps/search/?api=1&query=$lat,$lng';

    return GestureDetector(
      onTap: () async {
        try {
          final uri = Uri.parse(mapsUrl);
          if (await canLaunchUrl(uri)) {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
            return;
          }
        } catch (_) {}
        Clipboard.setData(ClipboardData(text: mapsUrl));
        _showSnackBar('Location copied: $mapsUrl');
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 120,
            decoration: BoxDecoration(
              color: Colors.blueGrey.shade100,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.location_on, color: Colors.red, size: 36),
                  const SizedBox(height: 4),
                  Text(
                    '${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)}',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                  const SizedBox(height: 4),
                  const Text('Tap to open Google Maps', style: TextStyle(fontSize: 11, color: Colors.black54)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text('📍 Live GPS Location', style: TextStyle(color: isMe ? Colors.white : const Color(0xFF171B2D))),
        ],
      ),
    );
  }

  Widget _buildPollContent(MessageModel msg, bool isMe) {
    final poll = msg.pollData ?? {};
    final question = poll['question']?.toString() ?? msg.message;
    final bool allowMultiple = poll['allowMultiple'] == true;
    final options = List<Map<String, dynamic>>.from(
      (poll['options'] as List? ?? []).map((e) => Map<String, dynamic>.from(e is Map ? e : {})),
    );

    int totalVotes = 0;
    for (var opt in options) {
      final List votes = List.from(opt['votes'] ?? []);
      totalVotes += votes.length;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.bar_chart_rounded,
              color: isMe ? Colors.white : const Color(0xFF5B50E6),
              size: 20,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                question,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: isMe ? Colors.white : const Color(0xFF171B2D),
                  fontSize: 15,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          allowMultiple ? 'Select one or more' : 'Select one',
          style: TextStyle(
            fontSize: 11,
            color: isMe ? Colors.white70 : Colors.grey.shade600,
          ),
        ),
        const SizedBox(height: 8),
        ...List.generate(options.length, (i) {
          final opt = options[i];
          final optText = opt['title']?.toString() ?? opt['text']?.toString() ?? '';
          final List<String> votes = List<String>.from(opt['votes'] ?? []);
          final count = votes.length;
          final hasVoted = _currentUser != null && votes.contains(_currentUser!.id);
          final double percentage = totalVotes > 0 ? count / totalVotes : 0.0;

          return Container(
            margin: const EdgeInsets.only(bottom: 6),
            decoration: BoxDecoration(
              color: isMe ? Colors.white.withValues(alpha: 0.15) : const Color(0xFFF4F6FC),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: hasVoted ? (isMe ? Colors.white : const Color(0xFF10B981)) : Colors.transparent,
                width: 1.5,
              ),
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () async {
                  if (_currentUser == null || msg.id == null) return;
                  await _chatService.voteGroupPoll(
                    groupId: widget.groupId,
                    messageId: msg.id!,
                    optionIndex: i,
                    userId: _currentUser!.id,
                  );
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            allowMultiple
                                ? (hasVoted ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded)
                                : (hasVoted ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded),
                            size: 18,
                            color: isMe ? Colors.white : (hasVoted ? const Color(0xFF10B981) : const Color(0xFF5B50E6)),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              optText,
                              style: TextStyle(
                                color: isMe ? Colors.white : const Color(0xFF171B2D),
                                fontWeight: hasVoted ? FontWeight.bold : FontWeight.normal,
                                fontSize: 13.5,
                              ),
                            ),
                          ),
                          Text(
                            '$count',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: isMe ? Colors.white70 : Colors.grey.shade700,
                            ),
                          ),
                        ],
                      ),
                      if (totalVotes > 0) ...[
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: LinearProgressIndicator(
                            value: percentage,
                            backgroundColor: isMe ? Colors.white24 : Colors.grey.shade300,
                            color: isMe ? Colors.white : const Color(0xFF10B981),
                            minHeight: 4,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          );
        }),
        const SizedBox(height: 2),
        Text(
          '$totalVotes vote${totalVotes == 1 ? '' : 's'}',
          style: TextStyle(
            fontSize: 11,
            color: isMe ? Colors.white70 : Colors.grey.shade600,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  // ============================================================
  // EVENT MESSAGE CONTENT (CALENDAR & SCHEDULE)
  // ============================================================

  Widget _buildEventContent(MessageModel msg, bool isMe) {
    final eventData = msg.eventData ?? {};
    final title = eventData['title']?.toString() ??
        (msg.message.isNotEmpty ? msg.message : 'Event');
    final dateStr = eventData['date']?.toString();
    final timeStr = eventData['time']?.toString();
    final location = eventData['location']?.toString();
    final description = eventData['description']?.toString();

    DateTime? parsedDate;
    if (dateStr != null) {
      parsedDate = DateTime.tryParse(dateStr);
    }

    final effectiveDate = parsedDate ?? msg.timestamp;

    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final String monthAbbr = months[effectiveDate.month - 1].toUpperCase();
    final String dayNumber = effectiveDate.day.toString();
    final String dayName = days[effectiveDate.weekday - 1];
    final String displayDate = '$dayName, ${effectiveDate.day} ${months[effectiveDate.month - 1]} ${effectiveDate.year}';

    String displayTime = timeStr ?? '';
    if (displayTime.contains(':')) {
      final parts = displayTime.split(':');
      final h = int.tryParse(parts[0]);
      final m = int.tryParse(parts[1]);
      if (h != null && m != null) {
        final period = h >= 12 ? 'PM' : 'AM';
        final displayH = h == 0 ? 12 : (h > 12 ? h - 12 : h);
        displayTime = '$displayH:${m.toString().padLeft(2, '0')} $period';
      }
    }

    return Container(
      width: 270,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isMe
            ? Colors.white.withValues(alpha: 0.12)
            : const Color(0xFFF7F8FE),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isMe
              ? Colors.white.withValues(alpha: 0.25)
              : const Color(0xFFE5E7EB),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 46,
                height: 50,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isMe ? Colors.white24 : const Color(0xFFE2E8F0),
                    width: 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      decoration: const BoxDecoration(
                        color: Color(0xFF5B50E6),
                        borderRadius: BorderRadius.vertical(top: Radius.circular(9)),
                      ),
                      child: Text(
                        monthAbbr,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Center(
                        child: Text(
                          dayNumber,
                          style: const TextStyle(
                            color: Color(0xFF171B2D),
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: isMe ? Colors.white : const Color(0xFF171B2D),
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          Icons.event_available_rounded,
                          size: 14,
                          color: isMe ? Colors.white70 : const Color(0xFF5B50E6),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            displayDate,
                            style: TextStyle(
                              color: isMe ? Colors.white70 : const Color(0xFF5B50E6),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (displayTime.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  Icons.access_time_rounded,
                  size: 14,
                  color: isMe ? Colors.white70 : Colors.grey.shade600,
                ),
                const SizedBox(width: 6),
                Text(
                  displayTime,
                  style: TextStyle(
                    fontSize: 12,
                    color: isMe ? Colors.white70 : Colors.grey.shade700,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],
          if (location != null && location.isNotEmpty) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(
                  Icons.location_on_outlined,
                  size: 14,
                  color: isMe ? Colors.white70 : Colors.grey.shade600,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    location,
                    style: TextStyle(
                      fontSize: 12,
                      color: isMe ? Colors.white70 : Colors.grey.shade700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
          if (description != null && description.isNotEmpty) ...[
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isMe
                    ? Colors.white.withValues(alpha: 0.08)
                    : Colors.white,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                description,
                style: TextStyle(
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                  color: isMe ? Colors.white70 : Colors.grey.shade700,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildReplyPreview() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Colors.white,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Replying to ${_replyingToMessage?.senderName ?? 'Member'}',
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF5B50E6), fontSize: 12),
                ),
                Text(
                  _replyingToMessage?.message ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, color: Colors.grey),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            onPressed: () => setState(() => _replyingToMessage = null),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // INPUT BAR & EMOJI PICKER
  // ============================================================

  Widget _buildInputBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      color: Colors.white,
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFF4F6FC),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: _isRecordingVoice
                    ? _buildVoiceRecordingState()
                    : Row(
                        children: [
                          IconButton(
                            icon: Icon(
                              _showEmojiPicker ? Icons.keyboard_rounded : Icons.emoji_emotions_outlined,
                              color: const Color(0xFF5B50E6),
                            ),
                            onPressed: () {
                              setState(() {
                                _showEmojiPicker = !_showEmojiPicker;
                              });
                              if (_showEmojiPicker) {
                                FocusScope.of(context).unfocus();
                              } else {
                                _focusNode.requestFocus();
                              }
                            },
                          ),
                          Expanded(
                            child: TextField(
                              controller: _messageController,
                              focusNode: _focusNode,
                              textCapitalization: TextCapitalization.sentences,
                              style: const TextStyle(
                                color: Color(0xFF171B2D),
                                fontSize: 15,
                              ),
                              decoration: const InputDecoration(
                                hintText: 'Type a message...',
                                hintStyle: TextStyle(color: Colors.black38, fontSize: 14),
                                border: InputBorder.none,
                                contentPadding: EdgeInsets.symmetric(vertical: 10),
                              ),
                              onSubmitted: (_) => _sendTextMessage(),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.attach_file_rounded, color: Color(0xFF7C3AED), size: 22),
                            onPressed: _openAttachmentSheet,
                          ),
                          if (!_hasText)
                            IconButton(
                              icon: const Icon(Icons.camera_alt_rounded, color: Color(0xFF5B50E6), size: 22),
                              onPressed: _handleCamera,
                            ),
                        ],
                      ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () {
                if (_isRecordingVoice) {
                  _stopVoiceRecording(send: true);
                } else if (_hasText) {
                  _sendTextMessage();
                } else {
                  _startVoiceRecording();
                }
              },
              child: Container(
                width: 46,
                height: 46,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [Color(0xFF5B50E6), Color(0xFF7C3AED)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: _isSending
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                      )
                    : Icon(
                        _isRecordingVoice
                            ? Icons.send_rounded
                            : (_hasText ? Icons.send_rounded : Icons.mic_rounded),
                        color: Colors.white,
                        size: 20,
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVoiceRecordingState() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          const Icon(
            Icons.fiber_manual_record,
            color: Colors.redAccent,
            size: 16,
          ),
          const SizedBox(width: 8),
          Text(
            _formatDuration(_recordingSeconds),
            style: const TextStyle(
              color: Color(0xFF171B2D),
              fontWeight: FontWeight.bold,
            ),
          ),
          const Spacer(),
          GestureDetector(
            onTap: () => _stopVoiceRecording(send: false),
            child: const Row(
              children: [
                Icon(Icons.delete_outline, color: Colors.redAccent, size: 18),
                SizedBox(width: 4),
                Text(
                  'Cancel',
                  style: TextStyle(color: Colors.redAccent, fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmojiPicker() {
    return WhatsAppEmojiPicker(
      isDark: false,
      controller: _messageController,
      onEmojiSelected: () => setState(() {}),
      onBackspace: () => setState(() {}),
    );
  }

  Widget _buildCallMessage(MessageModel msg, bool isMe) {
    final bool isVideo = msg.callType == 'video' || msg.message.toLowerCase().contains('video');
    final int duration = msg.callDuration ?? 0;
    final String timeStr = _formatTime(msg.timestamp);

    String statusText;
    bool isMissed = false;
    switch (msg.callStatus) {
      case 'ended':
        statusText = duration > 0
            ? 'Ended at $timeStr · ${_formatDuration(duration)}'
            : 'Ended at $timeStr';
        break;
      case 'rejected':
        statusText = 'Call declined at $timeStr';
        isMissed = true;
        break;
      case 'busy':
        statusText = 'User busy at $timeStr';
        isMissed = true;
        break;
      case 'missed':
        statusText = isVideo
            ? 'Missed video call at $timeStr'
            : 'Missed voice call at $timeStr';
        isMissed = true;
        break;
      default:
        if (msg.message.startsWith('📞 Calling')) {
          statusText = '${msg.message.replaceFirst('📞 ', '')} at $timeStr';
        } else {
          statusText = 'Ended at $timeStr';
        }
    }

    final Color statusColor = isMissed
        ? Colors.redAccent
        : (isVideo ? const Color(0xFF5B50E6) : const Color(0xFF10B981));

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        width: 270,
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
          border: Border.all(
            color: isMissed
                ? Colors.redAccent.withValues(alpha: 0.25)
                : Colors.black12,
            width: 1,
          ),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: statusColor.withValues(alpha: 0.14),
              child: Icon(
                isMissed
                    ? Icons.call_missed_rounded
                    : (isVideo ? Icons.videocam_rounded : Icons.call_rounded),
                color: statusColor,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${isMe ? "You" : (msg.senderName ?? "Member")} • ${isVideo ? "Video Call" : "Voice Call"}',
                    style: TextStyle(
                      color: isMissed
                          ? Colors.redAccent
                          : const Color(0xFF171B2D),
                      fontWeight: FontWeight.bold,
                      fontSize: 13.5,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    statusText,
                    style: TextStyle(
                      color: isMissed
                          ? Colors.redAccent.shade400
                          : Colors.grey.shade600,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: Icon(
                isVideo ? Icons.videocam_rounded : Icons.phone_rounded,
                color: const Color(0xFF5B50E6),
                size: 22,
              ),
              tooltip: isVideo ? 'Group Video Call' : 'Group Voice Call',
              onPressed: () => _startGroupCall(isVideo: isVideo),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final hour = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
    final minute = dt.minute.toString().padLeft(2, '0');
    final period = dt.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $period';
  }
}

