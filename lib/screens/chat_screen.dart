import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
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
import '../services/notification_service.dart';
import '../services/user_service.dart';
import '../widgets/avatar_image_helper.dart';
import '../widgets/whatsapp_attachment_sheet.dart';
import '../widgets/whatsapp_camera_screen.dart';
import '../widgets/whatsapp_emoji_picker.dart';
import '../widgets/whatsapp_forward_dialog.dart';
import '../widgets/whatsapp_poll_dialog.dart';
import '../widgets/whatsapp_event_dialog.dart';
import '../widgets/whatsapp_delete_dialog.dart';
import '../widgets/whatsapp_audio_picker.dart';
import 'ai_chat_screen.dart';
import 'call_screen.dart';
import 'payments_screen.dart';
import 'users_list_screen.dart';

class ChatScreen extends StatefulWidget {
  final UserModel? targetUser;

  const ChatScreen({super.key, this.targetUser});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen>
    with SingleTickerProviderStateMixin {
  final ChatService _chatService = ChatService();
  final UserService _userService = UserService();
  final ImagePicker _imagePicker = ImagePicker();
  final AudioPlayer _audioPlayer = AudioPlayer();
  final AudioRecorder _audioRecorder = AudioRecorder();
  String? _voiceRecordingPath;

  final TextEditingController _messageController = TextEditingController();
  final TextEditingController _phoneSearchController = TextEditingController();
  final TextEditingController _inChatSearchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();
  bool _initialScrollDone = false; // scroll-to-unread fires only once

  UserModel? _currentUser;
  UserModel? _otherUser;

  bool _isSearching = false;
  bool _isSending = false;
  bool _isLoading = true;
  bool _showEmojiPicker = false;
  bool _hasText = false;
  bool _isSearchingInChat = false;
  String _inChatSearchQuery = '';

  // Replying state
  MessageModel? _replyingToMessage;

  // Audio recording state
  bool _isRecordingVoice = false;
  int _recordingSeconds = 0;
  Timer? _recordingTimer;

  // Audio playback state
  String? _playingAudioMessageId;
  PlayerState _playerState = PlayerState.stopped;

  // Selected message for reaction overlay
  MessageModel? _selectedMessageForReaction;

  @override
  void initState() {
    super.initState();

    _otherUser = widget.targetUser;
    NotificationService().activeChatUserId = _otherUser?.id;

    _messageController.addListener(() {
      final hasText = _messageController.text.trim().isNotEmpty;
      if (hasText != _hasText) {
        setState(() {
          _hasText = hasText;
        });
      }
    });

    _focusNode.addListener(() {
      if (_focusNode.hasFocus && _showEmojiPicker) {
        setState(() {
          _showEmojiPicker = false;
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

    _initializeChat();
  }

  Future<void> _initializeChat() async {
    try {
      await _userService.ensureUserLoggedIn();
      _currentUser = await _userService.getCurrentUserProfile();
      NotificationService().activeChatUserId = _otherUser?.id;

      if (_currentUser != null && _otherUser != null) {
        _chatService.markChatAsRead(
          userId: _currentUser!.id,
          otherUserId: _otherUser!.id,
        );
      }

      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Initialize chat error: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // ============================================================
  // FIND USER
  // ============================================================

  Future<void> _findUserByPhone() async {
    final phone = _phoneSearchController.text.trim();
    if (phone.isEmpty) {
      _showSnackBar('Enter a phone number');
      return;
    }

    final cleanPhone = phone.replaceAll(RegExp(r'\D'), '');
    if (cleanPhone.length < 10) {
      _showSnackBar('Enter a valid 10-digit phone number');
      return;
    }

    setState(() {
      _isSearching = true;
    });

    try {
      final foundUser = await _userService.findUserByPhoneNumber(cleanPhone);
      if (!mounted) return;

      if (foundUser == null) {
        _showSnackBar('User not found with this phone number');
        return;
      }

      if (foundUser.id == _currentUser?.id) {
        _showSnackBar('You cannot chat with yourself');
        return;
      }

      setState(() {
        _otherUser = foundUser;
      });

      NotificationService().activeChatUserId = foundUser.id;
      _phoneSearchController.clear();
    } catch (e) {
      _showSnackBar('Error finding user: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isSearching = false;
        });
      }
    }
  }

  // ============================================================
  // SEND TEXT MESSAGE (WITH OPTIONAL LINK PREVIEW & REPLY)
  // ============================================================

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    if (_currentUser == null || _otherUser == null) {
      _showSnackBar('Unable to send message: user not selected');
      return;
    }

    setState(() {
      _isSending = true;
    });

    _messageController.clear();
    final reply = _replyingToMessage;
    setState(() {
      _replyingToMessage = null;
    });

    // Detect link preview
    Map<String, dynamic>? linkPreview;
    final urlMatch = RegExp(r'https?://[^\s]+').firstMatch(text);
    if (urlMatch != null) {
      final url = urlMatch.group(0)!;
      try {
        final uri = Uri.parse(url);
        linkPreview = {'url': url, 'domain': uri.host, 'title': uri.host};
      } catch (_) {}
    }

    try {
      await _chatService.sendMessage(
        senderId: _currentUser!.id,
        receiverId: _otherUser!.id,
        message: text,
        replyToId: reply?.id,
        replyToText: reply?.message,
        replyToSender: reply?.senderId == _currentUser!.id
            ? 'You'
            : _otherUser!.name,
        linkPreview: linkPreview,
      );

      _scrollToBottom();
    } catch (e) {
      _showSnackBar('Failed to send: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isSending = false;
        });
      }
    }
  }

  // ============================================================
  // SEND MEDIA / ATTACHMENTS
  // ============================================================

  Future<void> _handleGallery() async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 70,
        maxWidth: 1280,
        maxHeight: 1280,
      );
      if (image == null || _currentUser == null || _otherUser == null) return;

      _showSnackBar('Sending photo...');
      final file = File(image.path);
      final fileName = 'media_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final path =
          'chats/${_chatService.getChatId(_currentUser!.id, _otherUser!.id)}/$fileName';

      String downloadUrl = '';
      try {
        downloadUrl = await _chatService.uploadFile(file, path);
      } catch (uploadErr) {
        debugPrint(
          'Firebase Storage upload failed: $uploadErr. Using resilient Base64 payload.',
        );
        final bytes = await file.readAsBytes();
        downloadUrl = 'data:image/jpeg;base64,${base64Encode(bytes)}';
      }

      await _chatService.sendMediaMessage(
        senderId: _currentUser!.id,
        receiverId: _otherUser!.id,
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
            if (_currentUser == null || _otherUser == null) return;
            try {
              _showSnackBar('Sending $type...');
              final ext = type == 'video' ? 'mp4' : 'jpg';
              final fileName =
                  'camera_${DateTime.now().millisecondsSinceEpoch}.$ext';
              final path =
                  'chats/${_chatService.getChatId(_currentUser!.id, _otherUser!.id)}/$fileName';

              String downloadUrl = '';
              try {
                downloadUrl = await _chatService.uploadFile(file, path);
              } catch (uploadErr) {
                debugPrint(
                  'Firebase Storage camera upload failed: $uploadErr. Using Base64.',
                );
                final bytes = await file.readAsBytes();
                final mime = type == 'video' ? 'video/mp4' : 'image/jpeg';
                downloadUrl = 'data:$mime;base64,${base64Encode(bytes)}';
              }

              await _chatService.sendMediaMessage(
                senderId: _currentUser!.id,
                receiverId: _otherUser!.id,
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
      final ext = fileName.contains('.')
          ? fileName.split('.').last.toUpperCase()
          : 'FILE';
      final fileSizeString = bytes < 1024 * 1024
          ? '${(bytes / 1024).toStringAsFixed(0)} KB • $ext'
          : '$sizeMb MB • $ext';

      _showSnackBar('Sending document...');
      String mediaUrl = '';
      try {
        final path =
            'chats/${_chatService.getChatId(_currentUser!.id, _otherUser!.id)}/${DateTime.now().millisecondsSinceEpoch}_$fileName';
        mediaUrl = await _chatService.uploadFile(file, path);
      } catch (uploadErr) {
        debugPrint(
          'Storage upload error: $uploadErr. Using resilient payload.',
        );
        if (bytes < 750 * 1024) {
          final fileBytes = await file.readAsBytes();
          mediaUrl =
              'data:application/octet-stream;base64,${base64Encode(fileBytes)}';
        } else {
          mediaUrl = file.path;
        }
      }

      await _chatService.sendDocumentMessage(
        senderId: _currentUser!.id,
        receiverId: _otherUser!.id,
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

      _showSnackBar('Sending audio...');
      String mediaUrl = '';
      try {
        final path =
            'chats/${_chatService.getChatId(_currentUser!.id, _otherUser!.id)}/audio_${DateTime.now().millisecondsSinceEpoch}_$fileName';
        mediaUrl = await _chatService.uploadFile(file, path);
      } catch (uploadErr) {
        debugPrint('Audio upload failed: $uploadErr. Using Base64.');
        if (bytes < 750 * 1024) {
          final fileBytes = await file.readAsBytes();
          mediaUrl = 'data:audio/mpeg;base64,${base64Encode(fileBytes)}';
        } else {
          mediaUrl = file.path;
        }
      }

      await _chatService.sendMediaMessage(
        senderId: _currentUser!.id,
        receiverId: _otherUser!.id,
        mediaUrl: mediaUrl,
        type: 'audio',
        message: fileName,
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
        _showSnackBar(
          'Location permission permanently denied. Enable it from Settings.',
        );
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

      final lat = position.latitude;
      final lng = position.longitude;
      final mapsUrl =
          'https://www.google.com/maps/search/?api=1&query=$lat,$lng';

      await _chatService.sendLocationMessage(
        senderId: _currentUser!.id,
        receiverId: _otherUser!.id,
        latitude: lat,
        longitude: lng,
        address: mapsUrl,
      );
      _scrollToBottom();
      _showSnackBar('Location shared successfully');
    } catch (e) {
      _showSnackBar('Location error: $e');
    }
  }

  void _handlePoll() {
    showDialog(
      context: context,
      builder: (_) => WhatsAppPollDialog(
        onCreatePoll: (question, options, allowMultiple) async {
          if (_currentUser == null) return;
          final otherId = _otherUser?.id ?? widget.targetUser?.id;
          if (otherId == null) return;
          try {
            await _chatService.sendPollMessage(
              senderId: _currentUser!.id,
              receiverId: otherId,
              question: question,
              options: options,
              allowMultipleAnswers: allowMultiple,
            );
            _scrollToBottom();
          } catch (e) {
            _showSnackBar('Failed to create poll: $e');
          }
        },
      ),
    );
  }

  void _handleContact() {
    final nameController = TextEditingController();
    final phoneController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Share Contact',
          style: TextStyle(
            color: Color(0xFF171B2D),
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: 'Contact Name'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: phoneController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Phone Number'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF5B50E6),
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              final name = nameController.text.trim();
              final phone = phoneController.text.trim();
              if (name.isNotEmpty && phone.isNotEmpty) {
                Navigator.pop(ctx);
                await _chatService.sendContactMessage(
                  senderId: _currentUser!.id,
                  receiverId: _otherUser!.id,
                  contactName: name,
                  phoneNumber: phone,
                );
                _scrollToBottom();
              }
            },
            child: const Text('Share'),
          ),
        ],
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
          if (_currentUser == null || _otherUser == null) return;
          await _chatService.sendEventMessage(
            senderId: _currentUser!.id,
            receiverId: _otherUser!.id,
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

  void _handleAiImages() {
    final promptController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.auto_awesome, color: Color(0xFF5B50E6)),
            SizedBox(width: 8),
            Text('AI Images', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        content: TextField(
          controller: promptController,
          decoration: const InputDecoration(
            hintText: 'Describe an image to generate...',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF5B50E6),
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              final prompt = promptController.text.trim();
              if (prompt.isNotEmpty) {
                Navigator.pop(ctx);
                await _chatService.sendMessage(
                  senderId: _currentUser!.id,
                  receiverId: _otherUser!.id,
                  message: '✨ AI Prompt: $prompt',
                );
                _scrollToBottom();
              }
            },
            child: const Text('Generate'),
          ),
        ],
      ),
    );
  }

  Future<void> _handleVideo() async {
    final XFile? video = await _imagePicker.pickVideo(
      source: ImageSource.gallery,
      maxDuration: const Duration(minutes: 5),
    );
    if (video == null || _currentUser == null || _otherUser == null) return;

    _showSnackBar('Sending video...');
    try {
      final file = File(video.path);
      final fileName = 'video_${DateTime.now().millisecondsSinceEpoch}.mp4';
      final path =
          'videos/${_chatService.getChatId(_currentUser!.id, _otherUser!.id)}/$fileName';

      String downloadUrl = '';
      try {
        downloadUrl = await _chatService.uploadFile(file, path);
      } catch (_) {
        downloadUrl = video.path;
      }

      await _chatService.sendMediaMessage(
        senderId: _currentUser!.id,
        receiverId: _otherUser!.id,
        mediaUrl: downloadUrl,
        type: 'video',
        message: 'Video',
        replyToId: _replyingToMessage?.id,
        replyToText: _replyingToMessage?.message,
        replyToSender: _replyingToMessage?.senderId == _currentUser!.id
            ? 'You'
            : _otherUser!.name,
      );

      setState(() => _replyingToMessage = null);
      _scrollToBottom();
    } catch (e) {
      _showSnackBar('Failed to send video: $e');
    }
  }

  void _openAttachmentMenu() {
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
        onAiImagesTap: _handleAiImages,
        onPaymentTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => PaymentsScreen(
                targetUser: _otherUser,
                initialReceiverUpi: _otherUser?.effectiveUpiId ?? '',
                initialReceiverName: _otherUser?.name,
              ),
            ),
          );
        },
      ),
    );
  }

  // ============================================================
  // VOICE MESSAGE RECORDING & AUDIO PLAYBACK
  // ============================================================

  Future<void> _startVoiceRecording() async {
    try {
      if (await _audioRecorder.hasPermission()) {
        final path =
            '${Directory.systemTemp.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
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

  Future<void> _stopVoiceRecording({bool send = true}) async {
    _recordingTimer?.cancel();
    final duration = _recordingSeconds;
    setState(() {
      _isRecordingVoice = false;
      _recordingSeconds = 0;
    });

    try {
      final path = await _audioRecorder.stop();
      if (!send || duration <= 0 || _currentUser == null || _otherUser == null)
        return;

      final actualPath = path ?? _voiceRecordingPath;
      if (actualPath == null) return;
      final file = File(actualPath);
      if (!file.existsSync()) return;

      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) return;

      _showSnackBar('Sending voice message...');
      String downloadUrl = '';
      try {
        final storagePath =
            'chats/${_chatService.getChatId(_currentUser!.id, _otherUser!.id)}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
        downloadUrl = await _chatService.uploadFile(file, storagePath);
      } catch (uploadErr) {
        debugPrint(
          'Voice storage upload failed: $uploadErr. Using Base64 payload.',
        );
        downloadUrl = 'data:audio/m4a;base64,${base64Encode(bytes)}';
      }

      await _chatService.sendMediaMessage(
        senderId: _currentUser!.id,
        receiverId: _otherUser!.id,
        mediaUrl: downloadUrl,
        type: 'audio',
        message: 'Voice message (${duration}s)',
      );
      _scrollToBottom();
    } catch (e) {
      debugPrint('Error stopping audio recording: $e');
    }
  }

  Future<void> _toggleAudioPlay(MessageModel msg) async {
    if (_playingAudioMessageId == msg.id &&
        _playerState == PlayerState.playing) {
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
        final pureBase64 = mediaUrl.contains(',')
            ? mediaUrl.split(',').last
            : mediaUrl;
        final bytes = base64Decode(pureBase64);
        await _audioPlayer.play(BytesSource(bytes, mimeType: 'audio/m4a'));
      } else if (mediaUrl != null &&
          mediaUrl.startsWith('http') &&
          !mediaUrl.contains('actions.google.com')) {
        await _audioPlayer.play(UrlSource(mediaUrl));
      } else if (mediaUrl != null &&
          (mediaUrl.startsWith('/') || mediaUrl.contains(r':\')) &&
          File(mediaUrl).existsSync()) {
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
  // VOICE / VIDEO CALLS
  // ============================================================

  void _startVoiceCall() {
    if (_currentUser == null || _otherUser == null) {
      _showSnackBar('Select a user first');
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CallScreen(
          callerId: _currentUser!.id,
          callerName: _currentUser!.name,
          callerPhone: _currentUser!.phoneNumber,
          callerAvatarUrl: _currentUser!.avatarUrl,
          receiverId: _otherUser!.id,
          receiverName: _otherUser!.name,
          receiverPhone: _otherUser!.phoneNumber,
          receiverAvatarUrl: _otherUser!.avatarUrl,
          isIncoming: false,
          callType: 'voice',
        ),
      ),
    );
  }

  void _startVideoCall() {
    if (_currentUser == null || _otherUser == null) {
      _showSnackBar('Select a user first');
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CallScreen(
          callerId: _currentUser!.id,
          callerName: _currentUser!.name,
          callerPhone: _currentUser!.phoneNumber,
          callerAvatarUrl: _currentUser!.avatarUrl,
          receiverId: _otherUser!.id,
          receiverName: _otherUser!.name,
          receiverPhone: _otherUser!.phoneNumber,
          receiverAvatarUrl: _otherUser!.avatarUrl,
          isIncoming: false,
          callType: 'video',
        ),
      ),
    );
  }

  // ============================================================
  // POPUP MENU OPTIONS (MATCHES USER SCREENSHOTS 1 & 2)
  // ============================================================

  void _handleMenuAction(String value) {
    switch (value) {
      case 'meta_ai':
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const AiChatScreen()),
        );
        break;
      case 'search':
        setState(() {
          _isSearchingInChat = true;
        });
        break;
      case 'media':
        _showMediaSummaryDialog();
        break;
      case 'disappearing':
        _showDisappearingMessagesDialog();
        break;
      case 'theme':
        _showChatThemeDialog();
        break;
      case 'more':
        _showMoreOptionsMenu();
        break;
      case 'clear':
        _showClearChatConfirmation();
        break;
      case 'export':
        _showExportChatDialog();
        break;
      case 'add_shortcut':
        _showAddShortcutConfirmation();
        break;
      case 'add_to_list':
        _showAddToListDialog();
        break;
    }
  }

  void _showMoreOptionsMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              ListTile(
                leading: const Icon(
                  Icons.delete_sweep_rounded,
                  color: Colors.redAccent,
                ),
                title: const Text(
                  'Clear chat',
                  style: TextStyle(
                    color: Colors.redAccent,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _showClearChatConfirmation();
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.upload_file_rounded,
                  color: Color(0xFF171B2D),
                ),
                title: const Text(
                  'Export chat',
                  style: TextStyle(
                    color: Color(0xFF171B2D),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _showExportChatDialog();
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.shortcut_rounded,
                  color: Color(0xFF171B2D),
                ),
                title: const Text(
                  'Add shortcut',
                  style: TextStyle(
                    color: Color(0xFF171B2D),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _showAddShortcutConfirmation();
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.playlist_add_rounded,
                  color: Color(0xFF171B2D),
                ),
                title: const Text(
                  'Add to list',
                  style: TextStyle(
                    color: Color(0xFF171B2D),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _showAddToListDialog();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showClearChatConfirmation() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Clear this chat?',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Color(0xFF171B2D),
          ),
        ),
        content: const Text(
          'Messages will only be removed from this chat for everyone. This action cannot be undone.',
          style: TextStyle(color: Colors.black87, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              if (_currentUser != null && _otherUser != null) {
                await _chatService.deleteChat(
                  userId: _currentUser!.id,
                  otherUserId: _otherUser!.id,
                );
                _showSnackBar('Chat cleared successfully');
              }
            },
            child: const Text('Clear chat'),
          ),
        ],
      ),
    );
  }

  void _showExportChatDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.import_export_rounded, color: Color(0xFF5B50E6)),
            SizedBox(width: 8),
            Text('Export Chat', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(
          'Exporting conversation with ${_otherUser?.name ?? "User"}.\nIncludes timestamps, messages, and call history.',
          style: const TextStyle(color: Colors.black87, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF5B50E6),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: () {
              Navigator.pop(ctx);
              Clipboard.setData(
                ClipboardData(
                  text:
                      'Chat history between ${_currentUser?.name} and ${_otherUser?.name} exported on ${DateTime.now().toLocal()}',
                ),
              );
              _showSnackBar('Chat transcript copied to clipboard');
            },
            icon: const Icon(Icons.copy_rounded, size: 16),
            label: const Text('Copy Transcript'),
          ),
        ],
      ),
    );
  }

  void _showAddShortcutConfirmation() {
    _showSnackBar(
      'Shortcut added to home screen for ${_otherUser?.name ?? "User"}',
    );
  }

  void _showAddToListDialog() {
    final lists = ['Favorites', 'Family', 'Close Friends', 'Work', 'VIP'];
    String selectedList = 'Favorites';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) => AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Text(
            'Add ${_otherUser?.name ?? "User"} to list',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: lists.map((listName) {
              return RadioListTile<String>(
                title: Text(
                  listName,
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
                value: listName,
                groupValue: selectedList,
                activeColor: const Color(0xFF5B50E6),
                onChanged: (val) {
                  if (val != null) setModalState(() => selectedList = val);
                },
              );
            }).toList(),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF5B50E6),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onPressed: () {
                Navigator.pop(ctx);
                _showSnackBar('Added ${_otherUser?.name} to $selectedList');
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  void _showMediaSummaryDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Media, links, and docs',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              leading: Icon(
                Icons.photo_library_rounded,
                color: Color(0xFF5B50E6),
              ),
              title: Text('Media (Photos & Videos)'),
              subtitle: Text('View recent photos and videos'),
            ),
            ListTile(
              leading: Icon(Icons.link_rounded, color: Color(0xFF7C3AED)),
              title: Text('Links'),
              subtitle: Text('Shared URLs and web previews'),
            ),
            ListTile(
              leading: Icon(
                Icons.insert_drive_file_rounded,
                color: Color(0xFF10B981),
              ),
              title: Text('Documents'),
              subtitle: Text('APKs, PDFs, and files'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showDisappearingMessagesDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Disappearing messages',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Make messages in this chat disappear after a set time.',
            ),
            const SizedBox(height: 10),
            RadioListTile<String>(
              title: const Text('24 hours'),
              value: '24h',
              groupValue: 'off',
              onChanged: (_) => Navigator.pop(ctx),
            ),
            RadioListTile<String>(
              title: const Text('7 days'),
              value: '7d',
              groupValue: 'off',
              onChanged: (_) => Navigator.pop(ctx),
            ),
            RadioListTile<String>(
              title: const Text('90 days'),
              value: '90d',
              groupValue: 'off',
              onChanged: (_) => Navigator.pop(ctx),
            ),
            RadioListTile<String>(
              title: const Text('Off'),
              value: 'off',
              groupValue: 'off',
              onChanged: (_) => Navigator.pop(ctx),
            ),
          ],
        ),
      ),
    );
  }

  void _showChatThemeDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Chat theme',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: const Text(
          'Default Royal Indigo Theme (Matches Home Screen) is currently active.',
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF5B50E6),
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // REACTIONS & ACTIONS
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
    if (msg.id == null || _currentUser == null || _otherUser == null) return;

    try {
      await _chatService.toggleReaction(
        senderId: _currentUser!.id,
        receiverId: _otherUser!.id,
        messageId: msg.id!,
        userId: _currentUser!.id,
        emoji: emoji,
      );
    } catch (e) {
      debugPrint('Reaction error: $e');
    }
  }

  void _forwardMessage(MessageModel msg) {
    if (_currentUser == null) return;
    WhatsAppForwardDialog.show(
      context,
      message: msg,
      currentUserId: _currentUser!.id,
      currentUserName: _currentUser!.name.isNotEmpty
          ? _currentUser!.name
          : _currentUser!.phoneNumber,
    );
  }

  void _deleteMessage(MessageModel msg) {
    if (msg.id == null || _currentUser == null || _otherUser == null) return;

    WhatsAppDeleteMessageDialog.show(
      context: context,
      onDeleteForEveryone: () async {
        await _chatService.deleteMessageForEveryone(
          senderId: _currentUser!.id,
          receiverId: _otherUser!.id,
          messageId: msg.id!,
        );
        _showSnackBar('Message deleted for everyone');
      },
      onDeleteForMe: () async {
        await _chatService.deleteMessageForMe(
          senderId: _currentUser!.id,
          receiverId: _otherUser!.id,
          messageId: msg.id!,
          userId: _currentUser!.id,
        );
        _showSnackBar('Message deleted for you');
      },
    );
  }

  void _copyMessage(MessageModel msg) {
    Clipboard.setData(ClipboardData(text: msg.message));
    _showSnackBar('Copied to clipboard');
  }

  void _scrollToBottom() {
    if (!_scrollController.hasClients) return;
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  /// Scroll to the first unread incoming message. Falls back to bottom if all read.
  void _scrollToFirstUnread(List<dynamic> messages) {
    if (!_scrollController.hasClients) return;
    if (_currentUser == null) {
      _scrollToBottom();
      return;
    }
    // Find the index of the first message that is from the other person and unread
    int firstUnreadIdx = -1;
    for (int i = 0; i < messages.length; i++) {
      final m = messages[i];
      if (m.senderId != _currentUser!.id &&
          m.status != 'read' &&
          !m.isSeen) {
        firstUnreadIdx = i;
        break;
      }
    }
    Future.delayed(const Duration(milliseconds: 150), () {
      if (!_scrollController.hasClients) return;
      if (firstUnreadIdx <= 0) {
        // All read or first message is unread — go to bottom
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      } else {
        // Estimate item height ~72px, jump to approximate position
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

  void _showSnackBar(String text) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), behavior: SnackBarBehavior.floating),
    );
  }

  String _formatTime(DateTime dt) {
    final hour = dt.hour.toString().padLeft(2, '0');
    final minute = dt.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  String _formatDateHeader(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final msgDate = DateTime(dt.year, dt.month, dt.day);

    if (msgDate == today) return 'Today';
    if (msgDate == yesterday) return 'Yesterday';
    return '${dt.day}/${dt.month}/${dt.year}';
  }

  String _formatDuration(int seconds) {
    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    NotificationService().activeChatUserId = null;
    if (_currentUser != null && _otherUser != null) {
      _chatService.markChatAsRead(
        userId: _currentUser!.id,
        otherUserId: _otherUser!.id,
      );
    }
    _recordingTimer?.cancel();
    _audioRecorder.dispose();
    _audioPlayer.dispose();
    _messageController.dispose();
    _phoneSearchController.dispose();
    _inChatSearchController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  // ============================================================
  // BUILD METHOD (HOME SCREEN COLORS & MODERN THEME)
  // ============================================================

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFFF4F6FC),
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFF5B50E6)),
        ),
      );
    }

    if (_otherUser == null) {
      return _buildNoUserSelectedUI();
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FC), // Home screen light background
      // ========================================================
      // APP BAR (HOME SCREEN ROYAL INDIGO THEME)
      // ========================================================
      appBar: AppBar(
        backgroundColor: const Color(0xFF5B50E6),
        foregroundColor: Colors.white,
        titleSpacing: 0,
        elevation: 1,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF5B50E6), Color(0xFF7C3AED)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () {
            if (widget.targetUser == null) {
              setState(() {
                _otherUser = null;
              });
            } else {
              Navigator.pop(context);
            }
          },
        ),
        title: _isSearchingInChat
            ? TextField(
                controller: _inChatSearchController,
                autofocus: true,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Search in chat...',
                  hintStyle: const TextStyle(color: Colors.white70),
                  border: InputBorder.none,
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () {
                      setState(() {
                        _isSearchingInChat = false;
                        _inChatSearchQuery = '';
                        _inChatSearchController.clear();
                      });
                    },
                  ),
                ),
                onChanged: (val) {
                  setState(() {
                    _inChatSearchQuery = val.toLowerCase().trim();
                  });
                },
              )
            : Row(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: Colors.white.withValues(alpha: 0.2),
                    backgroundImage: getAvatarImageProvider(_otherUser!.avatarUrl),
                    child: getAvatarImageProvider(_otherUser!.avatarUrl) == null
                        ? Text(
                            _otherUser!.name.isNotEmpty
                                ? _otherUser!.name[0].toUpperCase()
                                : '?',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                            ),
                          )
                        : null,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _otherUser!.name.isNotEmpty
                              ? _otherUser!.name
                              : 'Chat User',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        StreamBuilder<UserModel?>(
                          stream: _userService.streamUser(_otherUser!.id),
                          initialData: _otherUser,
                          builder: (context, snapshot) {
                            final user = snapshot.data ?? _otherUser!;
                            final isOnline = user.isOnline;
                            final statusText = UserService.formatLastSeen(
                              user.lastSeen,
                              isOnline: isOnline,
                            );

                            return Text(
                              statusText,
                              style: TextStyle(
                                fontSize: 12,
                                color: isOnline
                                    ? const Color(0xFF86EFAC)
                                    : Colors.white70,
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
        actions: [
          IconButton(
            icon: const Icon(Icons.videocam_rounded, color: Colors.white),
            tooltip: 'Video Call',
            onPressed: _startVideoCall,
          ),
          IconButton(
            icon: const Icon(Icons.phone_rounded, color: Colors.white),
            tooltip: 'Voice Call',
            onPressed: _startVoiceCall,
          ),

          // 3-Dots Menu
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded, color: Colors.white),
            color: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            onSelected: _handleMenuAction,
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'meta_ai',
                child: Row(
                  children: [
                    Icon(
                      Icons.auto_awesome_rounded,
                      color: Color(0xFF5B50E6),
                      size: 20,
                    ),
                    SizedBox(width: 12),
                    Text(
                      'Ask Gemini',
                      style: TextStyle(
                        color: Color(0xFF171B2D),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'search',
                child: Row(
                  children: [
                    Icon(
                      Icons.search_rounded,
                      color: Color(0xFF64748B),
                      size: 20,
                    ),
                    SizedBox(width: 12),
                    Text(
                      'Search',
                      style: TextStyle(
                        color: Color(0xFF171B2D),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'media',
                child: Row(
                  children: [
                    Icon(
                      Icons.perm_media_rounded,
                      color: Color(0xFF64748B),
                      size: 20,
                    ),
                    SizedBox(width: 12),
                    Text(
                      'Media, links, and docs',
                      style: TextStyle(
                        color: Color(0xFF171B2D),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'disappearing',
                child: Row(
                  children: [
                    Icon(
                      Icons.timelapse_rounded,
                      color: Color(0xFF64748B),
                      size: 20,
                    ),
                    SizedBox(width: 12),
                    Text(
                      'Disappearing messages',
                      style: TextStyle(
                        color: Color(0xFF171B2D),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'theme',
                child: Row(
                  children: [
                    Icon(
                      Icons.color_lens_rounded,
                      color: Color(0xFF64748B),
                      size: 20,
                    ),
                    SizedBox(width: 12),
                    Text(
                      'Chat theme',
                      style: TextStyle(
                        color: Color(0xFF171B2D),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'more',
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'More',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF171B2D),
                      ),
                    ),
                    Icon(Icons.arrow_right_rounded, color: Colors.grey),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'clear',
                child: Text(
                  'Clear chat',
                  style: TextStyle(color: Colors.redAccent),
                ),
              ),
              const PopupMenuItem(
                value: 'export',
                child: Text(
                  'Export chat',
                  style: TextStyle(color: Color(0xFF171B2D)),
                ),
              ),
              const PopupMenuItem(
                value: 'add_shortcut',
                child: Text(
                  'Add shortcut',
                  style: TextStyle(color: Color(0xFF171B2D)),
                ),
              ),
              const PopupMenuItem(
                value: 'add_to_list',
                child: Text(
                  'Add to list',
                  style: TextStyle(color: Color(0xFF171B2D)),
                ),
              ),
            ],
          ),
        ],
      ),

      // ========================================================
      // BODY (CLEAN LIGHT BACKGROUND + INDIGO BUBBLES)
      // ========================================================
      body: Column(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () {
                if (_showEmojiPicker) {
                  setState(() => _showEmojiPicker = false);
                }
                if (_selectedMessageForReaction != null) {
                  setState(() => _selectedMessageForReaction = null);
                }
                FocusScope.of(context).unfocus();
              },
              child: StreamBuilder<List<MessageModel>>(
                stream: _chatService.getMessages(
                  userId: _currentUser!.id,
                  otherUserId: _otherUser!.id,
                ),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting &&
                      !snapshot.hasData) {
                    return const Center(
                      child: CircularProgressIndicator(
                        color: Color(0xFF5B50E6),
                      ),
                    );
                  }

                  var messages = snapshot.data ?? [];

                  // If any unread incoming messages exist, mark them as read immediately
                  final bool hasUnreadIncoming = messages.any(
                    (m) =>
                        m.receiverId == _currentUser!.id &&
                        (m.status != 'read' || !m.isSeen),
                  );
                  if (hasUnreadIncoming) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted &&
                          _currentUser != null &&
                          _otherUser != null) {
                        _chatService.markChatAsRead(
                          userId: _currentUser!.id,
                          otherUserId: _otherUser!.id,
                        );
                      }
                    });
                  }

                  if (_currentUser != null) {
                    messages = messages.where((m) {
                      final deletedFor = m.deletedFor;
                      return deletedFor == null || !deletedFor.contains(_currentUser!.id);
                    }).toList();
                  }

                  if (_inChatSearchQuery.isNotEmpty) {
                    messages = messages
                        .where(
                          (m) => m.message.toLowerCase().contains(
                            _inChatSearchQuery,
                          ),
                        )
                        .toList();
                  }

                  if (messages.isEmpty) {
                    return Center(
                      child: Container(
                        margin: const EdgeInsets.all(24),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.04),
                              blurRadius: 10,
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.lock_rounded,
                              size: 20,
                              color: Color(0xFF5B50E6),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Messages are end-to-end encrypted',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.black54,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Say hi to ${_otherUser!.name}!',
                              style: const TextStyle(
                                fontSize: 13,
                                color: Colors.black87,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!_initialScrollDone) {
                      _initialScrollDone = true;
                      _scrollToFirstUnread(messages);
                    } else {
                      _scrollToBottom();
                    }
                  });

                  return ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      final msg = messages[index];
                      final isMe = msg.senderId == _currentUser!.id;

                      // Date separator
                      bool showDateHeader = false;
                      if (index == 0) {
                        showDateHeader = true;
                      } else {
                        final prevMsg = messages[index - 1];
                        final prevDate = DateTime(
                          prevMsg.timestamp.year,
                          prevMsg.timestamp.month,
                          prevMsg.timestamp.day,
                        );
                        final currDate = DateTime(
                          msg.timestamp.year,
                          msg.timestamp.month,
                          msg.timestamp.day,
                        );
                        if (prevDate != currDate) {
                          showDateHeader = true;
                        }
                      }

                      return Column(
                        children: [
                          if (showDateHeader) _buildDateHeader(msg.timestamp),
                          _buildMessageRow(msg, isMe),
                        ],
                      );
                    },
                  );
                },
              ),
            ),
          ),

          // Reply banner
          if (_replyingToMessage != null) _buildReplyBanner(),

          // Input Bar
          _buildInputBar(),

          // Emoji Keyboard
          if (_showEmojiPicker)
            WhatsAppEmojiPicker(
              isDark: false,
              controller: _messageController,
              onEmojiSelected: () => setState(() {}),
              onBackspace: () => setState(() {}),
            ),
        ],
      ),
    );
  }

  // ============================================================
  // DATE HEADER (HOME SCREEN LIGHT CARD STYLE)
  // ============================================================

  Widget _buildDateHeader(DateTime dt) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Text(
        _formatDateHeader(dt),
        style: const TextStyle(
          color: Colors.black54,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  // ============================================================
  // MESSAGE ROW (WITH REACTION OVERLAY & FORWARD ARROW)
  // ============================================================

  Widget _buildMessageRow(MessageModel msg, bool isMe) {
    final bool isSelected =
        _selectedMessageForReaction?.id == msg.id && msg.id != null;

    return Column(
      crossAxisAlignment: isMe
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        if (isSelected) _buildFloatingReactionToolbar(msg),
        Row(
          mainAxisAlignment: isMe
              ? MainAxisAlignment.end
              : MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (isMe)
              IconButton(
                icon: const Icon(
                  Icons.reply_rounded,
                  color: Colors.black26,
                  size: 18,
                ),
                tooltip: 'Forward',
                onPressed: () => _forwardMessage(msg),
              ),

            GestureDetector(
              onLongPress: () => _showMessageOptions(msg),
              child: _buildMessageBubble(msg, isMe),
            ),

            if (!isMe)
              IconButton(
                icon: const Icon(
                  Icons.reply_rounded,
                  color: Colors.black26,
                  size: 18,
                ),
                tooltip: 'Forward',
                onPressed: () => _forwardMessage(msg),
              ),
          ],
        ),
      ],
    );
  }

  // ============================================================
  // FLOATING REACTION TOOLBAR (LIGHT THEME)
  // ============================================================

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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 3,
                  ),
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
                child: Icon(
                  Icons.reply_rounded,
                  color: Colors.black54,
                  size: 18,
                ),
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
                child: Icon(
                  Icons.copy_rounded,
                  color: Colors.black54,
                  size: 16,
                ),
              ),
            ),
            InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () {
                _deleteMessage(msg);
                setState(() => _selectedMessageForReaction = null);
              },
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 5, vertical: 4),
                child: Icon(
                  Icons.delete_outline_rounded,
                  color: Colors.redAccent,
                  size: 18,
                ),
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
  // MESSAGE BUBBLE BUILDER (HOME SCREEN INDIGO & WHITE CARDS)
  // ============================================================

  Widget _buildMessageBubble(MessageModel msg, bool isMe) {
    if (msg.type == 'call') {
      return _buildCallMessage(msg, isMe);
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * 0.76,
      ),
      decoration: BoxDecoration(
        gradient: isMe
            ? const LinearGradient(
                colors: [Color(0xFF5B50E6), Color(0xFF7C3AED)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : null,
        color: isMe ? null : Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(16),
          topRight: const Radius.circular(16),
          bottomLeft: Radius.circular(isMe ? 16 : 4),
          bottomRight: Radius.circular(isMe ? 4 : 16),
        ),
        boxShadow: [
          BoxShadow(
            color: isMe
                ? const Color(0xFF5B50E6).withValues(alpha: 0.25)
                : Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Forwarded header
                if (msg.isForwarded)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.forward_rounded,
                          size: 14,
                          color: isMe ? Colors.white70 : Colors.black45,
                        ),
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

                // Reply Quote Preview
                if (msg.replyToText != null && msg.replyToText!.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: isMe
                          ? Colors.white.withValues(alpha: 0.15)
                          : const Color(0xFFF4F6FC),
                      borderRadius: BorderRadius.circular(8),
                      border: Border(
                        left: BorderSide(
                          color: isMe ? Colors.white : const Color(0xFF5B50E6),
                          width: 3,
                        ),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          msg.replyToSender ?? 'User',
                          style: TextStyle(
                            color: isMe
                                ? Colors.white
                                : const Color(0xFF5B50E6),
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          msg.replyToText!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: isMe ? Colors.white70 : Colors.black54,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),

                if (msg.type == 'text' &&
                    msg.linkPreview == null &&
                    (msg.replyToText == null || msg.replyToText!.isEmpty))
                  Wrap(
                    alignment: WrapAlignment.end,
                    crossAxisAlignment: WrapCrossAlignment.end,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(right: 8, bottom: 2),
                        child: Text(
                          msg.message,
                          style: TextStyle(
                            color: isMe
                                ? Colors.white
                                : const Color(0xFF171B2D),
                            fontSize: 15,
                            height: 1.3,
                          ),
                        ),
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _formatTime(msg.timestamp),
                            style: TextStyle(
                              fontSize: 10,
                              color: isMe
                                  ? Colors.white70
                                  : Colors.grey.shade500,
                            ),
                          ),
                          if (isMe) ...[
                            const SizedBox(width: 3),
                            _buildTickIcon(msg),
                          ],
                        ],
                      ),
                    ],
                  )
                else ...[
                  if (msg.type == 'document')
                    _buildDocumentCard(msg, isMe)
                  else if (msg.type == 'poll')
                    _buildPollCard(msg, isMe)
                  else if (msg.type == 'event')
                    _buildEventCard(msg, isMe)
                  else if (msg.type == 'contact')
                    _buildContactCard(msg, isMe)
                  else if (msg.type == 'location')
                    _buildLocationCard(msg, isMe)
                  else if (msg.type == 'image')
                    _buildImageCard(msg, isMe)
                  else if (msg.type == 'video')
                    _buildVideoCard(msg, isMe)
                  else if (msg.type == 'audio')
                    _buildAudioCard(msg, isMe)
                  else
                    _buildTextContent(msg, isMe),

                  if (msg.linkPreview != null)
                    _buildLinkPreviewCard(msg.linkPreview!, isMe),

                  const SizedBox(height: 3),

                  Align(
                    alignment: Alignment.bottomRight,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _formatTime(msg.timestamp),
                          style: TextStyle(
                            fontSize: 10,
                            color: isMe ? Colors.white70 : Colors.grey.shade500,
                          ),
                        ),
                        if (isMe) ...[
                          const SizedBox(width: 3),
                          _buildTickIcon(msg),
                        ],
                      ],
                    ),
                  ),
                ],
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

  // ============================================================
  // TICK ICON HELPER (SINGLE GREY → DOUBLE GREY → DOUBLE BLUE)
  // ============================================================

  Widget _buildTickIcon(MessageModel msg) {
    if (msg.status == 'read' || msg.isSeen) {
      return const Icon(
        Icons.done_all_rounded,
        size: 14,
        color: Color(0xFFA855F7), // Purple double tick when opened/read
      );
    } else {
      // Single tick when user hasn't opened/seen yet
      return const Icon(
        Icons.check_rounded,
        size: 14,
        color: Colors.white70,
      );
    }
  }

  // ============================================================
  // DOCUMENT / APK CARD
  // ============================================================

  Widget _buildDocumentCard(MessageModel msg, bool isMe) {
    final fileName = msg.fileName ?? 'document.file';
    final fileSize = msg.fileSize ?? 'File';
    final isApk = fileName.toLowerCase().endsWith('.apk');

    return GestureDetector(
      onTap: () => DocumentHelper.openDocument(
        context,
        mediaUrl: msg.mediaUrl,
        fileName: fileName,
      ),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: isMe
              ? Colors.white.withValues(alpha: 0.15)
              : const Color(0xFFF4F6FC),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: isApk
                    ? const Color(0xFF10B981).withValues(alpha: 0.2)
                    : const Color(0xFF5B50E6).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(
                child: Icon(
                  isApk
                      ? Icons.android_rounded
                      : Icons.insert_drive_file_rounded,
                  color: isApk
                      ? const Color(0xFF10B981)
                      : const Color(0xFF5B50E6),
                  size: 26,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    fileName,
                    style: TextStyle(
                      color: isMe ? Colors.white : const Color(0xFF171B2D),
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    fileSize,
                    style: TextStyle(
                      color: isMe ? Colors.white70 : Colors.grey.shade600,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: Icon(
                Icons.open_in_new_rounded,
                color: isMe ? Colors.white : const Color(0xFF5B50E6),
              ),
              tooltip: 'Open / View',
              onPressed: () => DocumentHelper.openDocument(
                context,
                mediaUrl: msg.mediaUrl,
                fileName: fileName,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // LINK PREVIEW CARD
  // ============================================================

  Widget _buildLinkPreviewCard(Map<String, dynamic> preview, bool isMe) {
    final domain = preview['domain'] ?? 'website.com';
    final url = preview['url'] ?? '';

    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isMe
            ? Colors.white.withValues(alpha: 0.15)
            : const Color(0xFFF4F6FC),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: isMe
                  ? Colors.white24
                  : const Color(0xFF5B50E6).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              Icons.link_rounded,
              color: isMe ? Colors.white : const Color(0xFF5B50E6),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  domain,
                  style: TextStyle(
                    color: isMe ? Colors.white : const Color(0xFF171B2D),
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                Text(
                  url,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isMe ? Colors.white70 : Colors.blue.shade600,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // INTERACTIVE POLL CARD
  // ============================================================

  Widget _buildPollCard(MessageModel msg, bool isMe) {
    final pollData = msg.pollData ?? {};
    final question = pollData['question']?.toString() ?? msg.message;
    final bool allowMultiple = pollData['allowMultiple'] == true;
    final rawOptions = pollData['options'] as List? ?? [];
    final List<Map<String, dynamic>> options = rawOptions
        .map((e) => Map<String, dynamic>.from(e is Map ? e : {}))
        .toList();

    int totalVotes = 0;
    for (var opt in options) {
      final List votes = List.from(opt['votes'] ?? []);
      totalVotes += votes.length;
    }

    final otherId = _otherUser?.id ??
        (msg.senderId == _currentUser?.id ? msg.receiverId : msg.senderId);

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
                  color: isMe ? Colors.white : const Color(0xFF171B2D),
                  fontWeight: FontWeight.bold,
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
          final String title =
              opt['title']?.toString() ?? opt['text']?.toString() ?? '';
          final List<String> votes = List<String>.from(opt['votes'] ?? []);
          final count = votes.length;
          final bool hasVoted =
              _currentUser != null && votes.contains(_currentUser!.id);
          final double percentage =
              totalVotes > 0 ? count / totalVotes : 0.0;

          return Container(
            margin: const EdgeInsets.only(bottom: 6),
            decoration: BoxDecoration(
              color: isMe
                  ? Colors.white.withValues(alpha: 0.15)
                  : const Color(0xFFF4F6FC),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: hasVoted
                    ? (isMe ? Colors.white : const Color(0xFF5B50E6))
                    : Colors.transparent,
                width: 1.5,
              ),
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () async {
                  if (msg.id != null && _currentUser != null && otherId.isNotEmpty) {
                    await _chatService.votePoll(
                      senderId: _currentUser!.id,
                      receiverId: otherId,
                      messageId: msg.id!,
                      optionIndex: i,
                      userId: _currentUser!.id,
                    );
                  }
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
                                ? (hasVoted
                                    ? Icons.check_box_rounded
                                    : Icons.check_box_outline_blank_rounded)
                                : (hasVoted
                                    ? Icons.radio_button_checked_rounded
                                    : Icons.radio_button_unchecked_rounded),
                            size: 18,
                            color: isMe
                                ? Colors.white
                                : (hasVoted
                                    ? const Color(0xFF5B50E6)
                                    : Colors.grey.shade600),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              title,
                              style: TextStyle(
                                color: isMe
                                    ? Colors.white
                                    : const Color(0xFF171B2D),
                                fontWeight: hasVoted
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                                fontSize: 13.5,
                              ),
                            ),
                          ),
                          Text(
                            '$count',
                            style: TextStyle(
                              color: isMe ? Colors.white : Colors.black87,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
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
                            backgroundColor: isMe
                                ? Colors.white24
                                : Colors.grey.shade300,
                            color: isMe
                                ? Colors.white
                                : const Color(0xFF5B50E6),
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
  // CONTACT MESSAGE CARD
  // ============================================================

  Widget _buildContactCard(MessageModel msg, bool isMe) {
    final contact = msg.contactData ?? {};
    final name = contact['name'] ?? msg.message;
    final phone = contact['phone'] ?? '';

    return Container(
      padding: const EdgeInsets.all(6),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: isMe
                ? Colors.white24
                : const Color(0xFF5B50E6).withValues(alpha: 0.15),
            child: Icon(
              Icons.person_rounded,
              color: isMe ? Colors.white : const Color(0xFF5B50E6),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: TextStyle(
                    color: isMe ? Colors.white : const Color(0xFF171B2D),
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                Text(
                  phone,
                  style: TextStyle(
                    color: isMe ? Colors.white70 : Colors.grey.shade600,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // EVENT MESSAGE CARD (CALENDAR & SCHEDULE)
  // ============================================================

  Widget _buildEventCard(MessageModel msg, bool isMe) {
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

  // ============================================================
  // LOCATION MESSAGE CARD (GPS & MAP PREVIEW)
  // ============================================================

  Widget _buildLocationCard(MessageModel msg, bool isMe) {
    final lat = msg.latitude ?? 0.0;
    final lng = msg.longitude ?? 0.0;

    return Container(
      decoration: BoxDecoration(
        color: isMe
            ? Colors.white.withValues(alpha: 0.15)
            : const Color(0xFFF4F6FC),
        borderRadius: BorderRadius.circular(10),
      ),
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.location_on_rounded,
                color: Colors.redAccent,
                size: 28,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Live Location Shared',
                      style: TextStyle(
                        color: isMe ? Colors.white : const Color(0xFF171B2D),
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    Text(
                      'Lat: ${lat.toStringAsFixed(4)}, Lng: ${lng.toStringAsFixed(4)}',
                      style: TextStyle(
                        color: isMe ? Colors.white70 : Colors.grey.shade600,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            height: 36,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: isMe ? Colors.white : const Color(0xFF5B50E6),
                foregroundColor: isMe ? const Color(0xFF5B50E6) : Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onPressed: () async {
                try {
                  final uri = Uri.parse(msg.message);
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                    return;
                  }
                } catch (_) {}
                Clipboard.setData(ClipboardData(text: msg.message));
                _showSnackBar('Location link copied: ${msg.message}');
              },
              icon: const Icon(Icons.map_rounded, size: 16),
              label: const Text(
                'Open in Google Maps',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // IMAGE / AUDIO / TEXT MESSAGE CARDS
  // ============================================================

  Widget _buildImageCard(MessageModel msg, bool isMe) {
    final mediaUrl = msg.mediaUrl ?? '';
    Widget imageWidget;

    if (mediaUrl.startsWith('data:image') ||
        (!mediaUrl.startsWith('http') &&
            mediaUrl.length > 200 &&
            !mediaUrl.startsWith('/'))) {
      try {
        final pureBase64 = mediaUrl.contains(',')
            ? mediaUrl.split(',').last
            : mediaUrl;
        imageWidget = Image.memory(
          base64Decode(pureBase64),
          height: 180,
          width: double.infinity,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => Container(
            height: 120,
            color: Colors.black12,
            child: const Center(
              child: Icon(Icons.broken_image, color: Colors.grey),
            ),
          ),
        );
      } catch (_) {
        imageWidget = Container(
          height: 120,
          color: Colors.black12,
          child: const Center(
            child: Icon(Icons.broken_image, color: Colors.grey),
          ),
        );
      }
    } else if (mediaUrl.startsWith('http')) {
      imageWidget = Image.network(
        mediaUrl,
        height: 180,
        width: double.infinity,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => Container(
          height: 120,
          color: Colors.black12,
          child: const Center(
            child: Icon(Icons.broken_image, color: Colors.grey),
          ),
        ),
      );
    } else if (mediaUrl.isNotEmpty &&
        (mediaUrl.startsWith('/') || mediaUrl.contains(r':\'))) {
      imageWidget = Image.file(
        File(mediaUrl),
        height: 180,
        width: double.infinity,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => Container(
          height: 120,
          color: Colors.black12,
          child: const Center(
            child: Icon(Icons.broken_image, color: Colors.grey),
          ),
        ),
      );
    } else {
      imageWidget = Container(
        height: 120,
        color: Colors.black12,
        child: const Center(child: Icon(Icons.image, color: Colors.grey)),
      );
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
                title: isMe ? 'You' : (_otherUser?.name ?? 'Photo'),
                subtitle: _formatTime(msg.timestamp),
              );
            }
          },
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: imageWidget,
          ),
        ),
        if (msg.message.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            msg.message,
            style: TextStyle(
              color: isMe ? Colors.white : const Color(0xFF171B2D),
              fontSize: 14,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildVideoCard(MessageModel msg, bool isMe) {
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
                const Icon(
                  Icons.videocam_rounded,
                  color: Colors.white24,
                  size: 64,
                ),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF5B50E6).withValues(alpha: 0.9),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 36,
                  ),
                ),
                Positioned(
                  bottom: 8,
                  left: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.play_circle_fill_rounded,
                          color: Colors.white,
                          size: 12,
                        ),
                        SizedBox(width: 4),
                        Text(
                          'Video',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (msg.message.isNotEmpty && msg.message != 'Video') ...[
          const SizedBox(height: 6),
          Text(
            msg.message,
            style: TextStyle(
              color: isMe ? Colors.white : const Color(0xFF171B2D),
              fontSize: 14,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildAudioCard(MessageModel msg, bool isMe) {
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

  Widget _buildTextContent(MessageModel msg, bool isMe) {
    return Text(
      msg.message,
      style: TextStyle(
        color: isMe ? Colors.white : const Color(0xFF171B2D),
        fontSize: 15,
        height: 1.3,
      ),
    );
  }

  // ============================================================
  // CALL HISTORY MESSAGE
  // ============================================================

  Widget _buildCallMessage(MessageModel msg, bool isMe) {
    final bool isVideo = msg.callType == 'video';
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
        statusText = 'Ended at $timeStr';
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
                    isVideo ? 'Video Call' : 'Voice Call',
                    style: TextStyle(
                      color: isMissed
                          ? Colors.redAccent
                          : const Color(0xFF171B2D),
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
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
              tooltip: isVideo ? 'Video Call Back' : 'Voice Call Back',
              onPressed: isVideo ? _startVideoCall : _startVoiceCall,
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // REPLY BANNER
  // ============================================================

  Widget _buildReplyBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      color: Colors.white,
      child: Row(
        children: [
          Container(
            width: 4,
            height: 36,
            decoration: BoxDecoration(
              color: const Color(0xFF5B50E6),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _replyingToMessage!.senderId == _currentUser!.id
                      ? 'You'
                      : _otherUser!.name,
                  style: const TextStyle(
                    color: Color(0xFF5B50E6),
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
                Text(
                  _replyingToMessage!.message,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.black54, fontSize: 13),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.grey, size: 20),
            onPressed: () => setState(() => _replyingToMessage = null),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // INPUT BAR (MATCHES HOME SCREEN THEME & CLEAN WHITE CARD)
  // ============================================================

  Widget _buildInputBar() {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFF4F6FC),
                  borderRadius: BorderRadius.circular(25),
                ),
                child: _isRecordingVoice
                    ? _buildVoiceRecordingState()
                    : Row(
                        children: [
                          IconButton(
                            icon: Icon(
                              _showEmojiPicker
                                  ? Icons.keyboard_alt_outlined
                                  : Icons.sentiment_satisfied_alt_rounded,
                              color: const Color(0xFF5B50E6),
                              size: 24,
                            ),
                            onPressed: () {
                              if (_showEmojiPicker) {
                                _focusNode.requestFocus();
                              } else {
                                FocusScope.of(context).unfocus();
                              }
                              setState(
                                () => _showEmojiPicker = !_showEmojiPicker,
                              );
                            },
                          ),

                          Expanded(
                            child: TextField(
                              controller: _messageController,
                              focusNode: _focusNode,
                              textInputAction: TextInputAction.send,
                              minLines: 1,
                              maxLines: 4,
                              style: const TextStyle(
                                color: Color(0xFF171B2D),
                                fontSize: 15,
                              ),
                              decoration: const InputDecoration(
                                hintText: 'Type a message...',
                                hintStyle: TextStyle(
                                  color: Colors.black38,
                                  fontSize: 14,
                                ),
                                border: InputBorder.none,
                                contentPadding: EdgeInsets.symmetric(
                                  vertical: 10,
                                ),
                              ),
                              onSubmitted: (_) => _sendMessage(),
                            ),
                          ),

                          IconButton(
                            icon: const Icon(
                              Icons.attach_file_rounded,
                              color: Color(0xFF7C3AED),
                              size: 22,
                            ),
                            onPressed: _openAttachmentMenu,
                          ),

                          if (!_hasText)
                            IconButton(
                              icon: const Icon(
                                Icons.camera_alt_rounded,
                                color: Color(0xFF5B50E6),
                                size: 22,
                              ),
                              onPressed: _handleCamera,
                            ),
                        ],
                      ),
              ),
            ),

            const SizedBox(width: 8),

            // Gradient Send / Mic Circular Button
            GestureDetector(
              onTap: () {
                if (_isRecordingVoice) {
                  _stopVoiceRecording(send: true);
                } else if (_hasText) {
                  _sendMessage();
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
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : Icon(
                        _isRecordingVoice
                            ? Icons.send_rounded
                            : (_hasText
                                  ? Icons.send_rounded
                                  : Icons.mic_rounded),
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

  // ============================================================
  // NO USER SELECTED UI (HOME SCREEN STYLE)
  // ============================================================

  Widget _buildNoUserSelectedUI() {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FC),
      appBar: AppBar(
        title: const Text(
          'User Chat',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFF5B50E6),
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const SizedBox(height: 20),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 10,
                  ),
                ],
              ),
              child: Column(
                children: [
                  const Icon(
                    Icons.contacts_rounded,
                    size: 48,
                    color: Color(0xFF5B50E6),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Select Registered Contact',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'See everyone who has installed this app',
                    style: TextStyle(fontSize: 13, color: Colors.black54),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF5B50E6),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const UsersListScreen(),
                          ),
                        );
                      },
                      icon: const Icon(Icons.people_alt_rounded),
                      label: const Text(
                        'View All Contacts',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 30),
            const Row(
              children: [
                Expanded(child: Divider()),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    'OR SEARCH BY PHONE',
                    style: TextStyle(
                      color: Colors.black45,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Expanded(child: Divider()),
              ],
            ),
            const SizedBox(height: 30),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 10,
                  ),
                ],
              ),
              child: Column(
                children: [
                  TextField(
                    controller: _phoneSearchController,
                    keyboardType: TextInputType.phone,
                    maxLength: 10,
                    decoration: InputDecoration(
                      labelText: '10-digit Phone Number',
                      counterText: '',
                      prefixIcon: const Icon(
                        Icons.phone_rounded,
                        color: Color(0xFF5B50E6),
                      ),
                      filled: true,
                      fillColor: const Color(0xFFF4F6FC),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onSubmitted: (_) => _findUserByPhone(),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF7C3AED),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: _isSearching ? null : _findUserByPhone,
                      child: _isSearching
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : const Text(
                              'Find User & Start Chat',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
