import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:image_picker/image_picker.dart';

class WhatsAppCameraScreen extends StatefulWidget {
  final Function(File file, String caption, String type) onMediaCaptured;

  const WhatsAppCameraScreen({
    super.key,
    required this.onMediaCaptured,
  });

  @override
  State<WhatsAppCameraScreen> createState() => _WhatsAppCameraScreenState();
}

class _WhatsAppCameraScreenState extends State<WhatsAppCameraScreen> {
  final ImagePicker _picker = ImagePicker();
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final MediaRecorder _mediaRecorder = MediaRecorder();
  MediaStream? _localStream;
  bool _isCameraReady = false;

  int _selectedModeIndex = 1; // 0: Video, 1: Photo, 2: Video note
  bool _isFrontCamera = false;
  int _flashMode = 0; // 0: Off, 1: Auto, 2: On

  File? _capturedFile;
  final TextEditingController _captionController = TextEditingController();

  final List<String> _modes = ['Video', 'Photo', 'Video note'];

  bool _isRecordingVideo = false;
  int _recordDuration = 0;
  StreamSubscription<int>? _recordTimerSubscription;
  String? _recordedVideoPath;

  bool get _isVideo =>
      _capturedFile?.path.toLowerCase().endsWith('.mp4') == true ||
      _capturedFile?.path.toLowerCase().endsWith('.mov') == true;

  @override
  void initState() {
    super.initState();
    _initLiveCamera();
  }

  Future<void> _initLiveCamera() async {
    try {
      await _localRenderer.initialize();
      await _startLiveCameraStream();
    } catch (e) {
      debugPrint('Camera init error: $e');
      if (mounted) setState(() => _isCameraReady = false);
    }
  }

  Future<void> _startLiveCameraStream() async {
    try {
      final Map<String, dynamic> mediaConstraints = {
        'audio': true,
        'video': {
          'facingMode': _isFrontCamera ? 'user' : 'environment',
          'mandatory': {
            'minWidth': '1280',
            'minHeight': '720',
            'minFrameRate': '30',
          },
          'optional': [],
        },
      };

      _localStream?.getTracks().forEach((track) => track.stop());
      _localStream?.dispose();

      try {
        _localStream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
      } catch (e) {
        debugPrint('Audio permission or stream failed, falling back to video only: $e');
        mediaConstraints['audio'] = false;
        _localStream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
      }
      _localRenderer.srcObject = _localStream;

      if (mounted) {
        setState(() {
          _isCameraReady = true;
        });
      }
    } catch (e) {
      debugPrint('Error starting camera stream: $e');
      if (mounted) {
        setState(() => _isCameraReady = false);
      }
    }
  }

  Future<void> _switchCamera() async {
    if (_localStream != null && _localStream!.getVideoTracks().isNotEmpty) {
      try {
        final track = _localStream!.getVideoTracks().first;
        await Helper.switchCamera(track);
        setState(() {
          _isFrontCamera = !_isFrontCamera;
        });
      } catch (_) {
        setState(() {
          _isFrontCamera = !_isFrontCamera;
        });
        await _startLiveCameraStream();
      }
    } else {
      setState(() {
        _isFrontCamera = !_isFrontCamera;
      });
      await _startLiveCameraStream();
    }
  }

  Future<void> _capturePhoto() async {
    // 1. Try in-app frame capture from live camera stream
    if (_localStream != null && _localStream!.getVideoTracks().isNotEmpty) {
      try {
        final track = _localStream!.getVideoTracks().first;
        final ByteBuffer buffer = await track.captureFrame();
        final Uint8List bytes = buffer.asUint8List();

        if (bytes.isNotEmpty) {
          final tempDir = Directory.systemTemp;
          final file = File('${tempDir.path}/photo_${DateTime.now().millisecondsSinceEpoch}.jpg');
          await file.writeAsBytes(bytes);

          if (mounted) {
            setState(() {
              _capturedFile = file;
            });
          }
          return;
        }
      } catch (e) {
        debugPrint('WebRTC frame capture failed: $e');
      }
    }

    // 2. Fallback
    _takePictureFallback();
  }

  Future<void> _takePictureFallback() async {
    try {
      final XFile? photo = await _picker.pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: _isFrontCamera ? CameraDevice.front : CameraDevice.rear,
      );
      if (photo != null && mounted) {
        setState(() {
          _capturedFile = File(photo.path);
        });
      }
    } catch (e) {
      debugPrint('Fallback pick error: $e');
    }
  }

  Future<void> _startVideoRecording() async {
    if (_localStream == null || _localStream!.getVideoTracks().isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Camera stream not ready')),
        );
      }
      return;
    }

    try {
      final tempDir = Directory.systemTemp;
      final videoPath = '${tempDir.path}/rec_${DateTime.now().millisecondsSinceEpoch}.mp4';
      _recordedVideoPath = videoPath;

      final videoTrack = _localStream!.getVideoTracks().first;

      await _mediaRecorder.start(
        videoPath,
        videoTrack: videoTrack,
        audioChannel: RecorderAudioChannel.INPUT,
      );

      if (mounted) {
        setState(() {
          _isRecordingVideo = true;
          _recordDuration = 0;
        });
      }

      _recordTimerSubscription?.cancel();
      _recordTimerSubscription = Stream.periodic(const Duration(seconds: 1), (i) => i).listen((_) {
        if (mounted && _isRecordingVideo) {
          setState(() {
            _recordDuration++;
          });
          if (_recordDuration >= 60) {
            _stopVideoRecording();
          }
        }
      });
    } catch (e) {
      debugPrint('In-app video record error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not record video: $e')),
        );
      }
    }
  }

  Future<void> _stopVideoRecording() async {
    if (!_isRecordingVideo) return;
    _recordTimerSubscription?.cancel();
    _recordTimerSubscription = null;

    try {
      await _mediaRecorder.stop();
      await Future.delayed(const Duration(milliseconds: 300));
      if (_recordedVideoPath != null) {
        final file = File(_recordedVideoPath!);
        if (await file.exists()) {
          if (mounted) {
            setState(() {
              _isRecordingVideo = false;
              _capturedFile = file;
            });
          }
          return;
        }
      }
    } catch (e) {
      debugPrint('Error stopping video recording: $e');
    }

    if (mounted) {
      setState(() {
        _isRecordingVideo = false;
      });
    }
  }

  void _toggleVideoRecording() {
    if (_isRecordingVideo) {
      _stopVideoRecording();
    } else {
      _startVideoRecording();
    }
  }

  Future<void> _pickFromGallery() async {
    if (_isRecordingVideo) return;
    try {
      final XFile? media = await _picker.pickImage(source: ImageSource.gallery);
      if (media != null && mounted) {
        setState(() {
          _capturedFile = File(media.path);
        });
      }
    } catch (e) {
      debugPrint('Pick error: $e');
    }
  }

  void _sendCapturedMedia() {
    if (_capturedFile != null) {
      final file = _capturedFile!;
      final caption = _captionController.text.trim();
      final type = _isVideo ? 'video' : 'image';
      Navigator.pop(context);
      widget.onMediaCaptured(file, caption, type);
    }
  }

  @override
  void dispose() {
    _captionController.dispose();
    _recordTimerSubscription?.cancel();
    if (_isRecordingVideo) {
      try {
        _mediaRecorder.stop();
      } catch (_) {}
    }
    try {
      _localStream?.getTracks().forEach((track) => track.stop());
      _localStream?.dispose();
      _localRenderer.dispose();
    } catch (_) {}
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_capturedFile != null) {
      return _buildPreviewScreen();
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            // ==========================================
            // LIVE IN-APP CAMERA VIEWFINDER (WebRTC)
            // ==========================================
            Positioned.fill(
              child: _isCameraReady && _localRenderer.srcObject != null
                  ? RTCVideoView(
                      _localRenderer,
                      mirror: _isFrontCamera,
                      objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                    )
                  : Container(
                      color: Colors.black,
                      child: const Center(
                        child: CircularProgressIndicator(color: Colors.white70),
                      ),
                    ),
            ),

            // Recording Timer Pill (Top Center)
            if (_isRecordingVideo)
              Positioned(
                top: 18,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.9),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.red.withValues(alpha: 0.4),
                          blurRadius: 10,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${(_recordDuration ~/ 60).toString().padLeft(2, '0')}:${(_recordDuration % 60).toString().padLeft(2, '0')}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            letterSpacing: 1,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

            // Top Flash & Close Bar
            Positioned(
              top: 12,
              left: 16,
              right: 16,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  CircleAvatar(
                    backgroundColor: Colors.black54,
                    child: IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () {
                        if (_isRecordingVideo) {
                          _stopVideoRecording();
                        }
                        Navigator.pop(context);
                      },
                    ),
                  ),
                  if (!_isRecordingVideo)
                    Row(
                      children: [
                        CircleAvatar(
                          backgroundColor: Colors.black54,
                          child: IconButton(
                            icon: Icon(
                              _flashMode == 0
                                  ? Icons.flash_off_rounded
                                  : (_flashMode == 1
                                      ? Icons.flash_auto_rounded
                                      : Icons.flash_on_rounded),
                              color: _flashMode == 0 ? Colors.white : Colors.amber,
                            ),
                            onPressed: () {
                              setState(() {
                                _flashMode = (_flashMode + 1) % 3;
                              });
                            },
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),

            // Bottom Controls Bar
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.only(bottom: 20, top: 12),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.transparent, Colors.black87, Colors.black],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Main shutter row
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          // Gallery button
                          GestureDetector(
                            onTap: _isRecordingVideo ? null : _pickFromGallery,
                            child: Opacity(
                              opacity: _isRecordingVideo ? 0.3 : 1.0,
                              child: Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  color: Colors.white12,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.white30, width: 1.5),
                                ),
                                child: const Icon(Icons.photo_library_outlined, color: Colors.white, size: 22),
                              ),
                            ),
                          ),

                          // In-app Shutter Button
                          GestureDetector(
                            onTap: () {
                              if (_selectedModeIndex == 0 || _selectedModeIndex == 2) {
                                _toggleVideoRecording();
                              } else {
                                _capturePhoto();
                              }
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 250),
                              width: 80,
                              height: 80,
                              padding: EdgeInsets.all(_isRecordingVideo ? 16 : 4),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: _isRecordingVideo ? Colors.redAccent : Colors.white,
                                  width: _isRecordingVideo ? 5 : 4,
                                ),
                              ),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 250),
                                decoration: BoxDecoration(
                                  color: (_selectedModeIndex == 0 || _isRecordingVideo)
                                      ? Colors.redAccent
                                      : Colors.white,
                                  shape: _isRecordingVideo ? BoxShape.rectangle : BoxShape.circle,
                                  borderRadius: _isRecordingVideo ? BorderRadius.circular(8) : null,
                                ),
                              ),
                            ),
                          ),

                          // Flip camera button
                          GestureDetector(
                            onTap: _isRecordingVideo ? null : _switchCamera,
                            child: Opacity(
                              opacity: _isRecordingVideo ? 0.3 : 1.0,
                              child: Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  color: Colors.white12,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.white30, width: 1.5),
                                ),
                                child: const Icon(Icons.flip_camera_ios_rounded, color: Colors.white, size: 22),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 10),

                    // Mode Switcher: Video, Photo, Video note
                    if (!_isRecordingVideo)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(_modes.length, (index) {
                          final isSelected = _selectedModeIndex == index;
                          return GestureDetector(
                            onTap: () {
                              setState(() {
                                _selectedModeIndex = index;
                              });
                            },
                            child: Container(
                              margin: const EdgeInsets.symmetric(horizontal: 6),
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
                              decoration: BoxDecoration(
                                color: isSelected ? Colors.white24 : Colors.transparent,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                _modes[index],
                                style: TextStyle(
                                  color: isSelected ? Colors.amber : Colors.white70,
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          );
                        }),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreviewScreen() {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: _isVideo
                  ? Container(
                      color: Colors.black,
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 90,
                              height: 90,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.white.withValues(alpha: 0.15),
                                border: Border.all(color: Colors.white30, width: 2),
                              ),
                              child: const Icon(
                                Icons.play_arrow_rounded,
                                color: Colors.white,
                                size: 54,
                              ),
                            ),
                            const SizedBox(height: 18),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              decoration: BoxDecoration(
                                color: Colors.white12,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: Colors.white24),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.videocam_rounded, color: Colors.redAccent, size: 20),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Video Recorded (${(_recordDuration ~/ 60).toString().padLeft(2, '0')}:${(_recordDuration % 60).toString().padLeft(2, '0')})',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : Image.file(
                      _capturedFile!,
                      fit: BoxFit.contain,
                    ),
            ),

            Positioned(
              top: 10,
              left: 16,
              right: 16,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  CircleAvatar(
                    backgroundColor: Colors.black54,
                    child: IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () {
                        setState(() {
                          _capturedFile = null;
                        });
                      },
                    ),
                  ),
                  Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: Colors.black54,
                        child: IconButton(
                          icon: const Icon(Icons.crop_rotate_rounded, color: Colors.white),
                          onPressed: () {},
                        ),
                      ),
                      const SizedBox(width: 8),
                      CircleAvatar(
                        backgroundColor: Colors.black54,
                        child: IconButton(
                          icon: const Icon(Icons.text_fields_rounded, color: Colors.white),
                          onPressed: () {},
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            Positioned(
              bottom: 12,
              left: 12,
              right: 12,
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1F2C34),
                        borderRadius: BorderRadius.circular(26),
                      ),
                      child: TextField(
                        controller: _captionController,
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(
                          hintText: 'Add a caption...',
                          hintStyle: TextStyle(color: Colors.white54, fontSize: 14),
                          border: InputBorder.none,
                          icon: Icon(Icons.add_photo_alternate_outlined, color: Colors.white70),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: _sendCapturedMedia,
                    child: Container(
                      width: 50,
                      height: 50,
                      decoration: const BoxDecoration(
                        color: Color(0xFF5B50E6),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.send_rounded, color: Colors.white, size: 22),
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
