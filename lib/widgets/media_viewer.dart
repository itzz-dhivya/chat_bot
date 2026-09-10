import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

/// Full-screen interactive image viewer supporting pinch-to-zoom, pan, double-tap zoom,
/// and saving/copying.
class InteractivePhotoViewer extends StatefulWidget {
  final String imageUrl;
  final String title;
  final String? subtitle;

  const InteractivePhotoViewer({
    super.key,
    required this.imageUrl,
    this.title = 'Photo',
    this.subtitle,
  });

  static void open(BuildContext context, {
    required String imageUrl,
    String title = 'Photo',
    String? subtitle,
  }) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => InteractivePhotoViewer(
          imageUrl: imageUrl,
          title: title,
          subtitle: subtitle,
        ),
      ),
    );
  }

  @override
  State<InteractivePhotoViewer> createState() => _InteractivePhotoViewerState();
}

class _InteractivePhotoViewerState extends State<InteractivePhotoViewer> {
  final TransformationController _transformationController = TransformationController();
  TapDownDetails? _doubleTapDetails;

  @override
  void dispose() {
    _transformationController.dispose();
    super.dispose();
  }

  void _handleDoubleTap() {
    if (_transformationController.value != Matrix4.identity()) {
      _transformationController.value = Matrix4.identity();
    } else {
      final position = _doubleTapDetails?.localPosition ?? Offset.zero;
      _transformationController.value = Matrix4.diagonal3Values(2.5, 2.5, 1.0)
        ..setTranslationRaw(-position.dx * 1.5, -position.dy * 1.5, 0.0);
    }
  }

  Widget _buildImage() {
    final url = widget.imageUrl;

    if (url.startsWith('data:image') || (!url.startsWith('http') && url.length > 200 && !url.startsWith('/'))) {
      try {
        final pureBase64 = url.contains(',') ? url.split(',').last : url;
        final bytes = base64Decode(pureBase64);
        return Image.memory(
          bytes,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) => _errorWidget(),
        );
      } catch (_) {
        return _errorWidget();
      }
    } else if (url.startsWith('http')) {
      return Image.network(
        url,
        fit: BoxFit.contain,
        loadingBuilder: (_, child, progress) {
          if (progress == null) return child;
          return const Center(
            child: CircularProgressIndicator(color: Colors.white),
          );
        },
        errorBuilder: (context, error, stackTrace) => _errorWidget(),
      );
    } else if (url.isNotEmpty && (url.startsWith('/') || url.contains(r':\'))) {
      final file = File(url);
      if (file.existsSync()) {
        return Image.file(
          file,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) => _errorWidget(),
        );
      }
    }

    return _errorWidget();
  }

  Widget _errorWidget() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.broken_image_rounded, color: Colors.white54, size: 64),
          SizedBox(height: 12),
          Text(
            'Unable to display image',
            style: TextStyle(color: Colors.white70, fontSize: 14),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black.withValues(alpha: 0.8),
        foregroundColor: Colors.white,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            if (widget.subtitle != null)
              Text(
                widget.subtitle!,
                style: const TextStyle(fontSize: 12, color: Colors.white70),
              ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy_rounded, color: Colors.white),
            tooltip: 'Copy Image Link',
            onPressed: () {
              Clipboard.setData(ClipboardData(text: widget.imageUrl));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Image link copied to clipboard'),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
          ),
        ],
      ),
      body: Center(
        child: GestureDetector(
          onDoubleTapDown: (details) => _doubleTapDetails = details,
          onDoubleTap: _handleDoubleTap,
          child: InteractiveViewer(
            transformationController: _transformationController,
            minScale: 0.5,
            maxScale: 5.0,
            boundaryMargin: const EdgeInsets.all(double.infinity),
            child: _buildImage(),
          ),
        ),
      ),
    );
  }
}

/// Helper for opening documents and URLs
class DocumentHelper {
  static Future<void> openDocument(BuildContext context, {
    required String? mediaUrl,
    required String fileName,
  }) async {
    if (mediaUrl == null || mediaUrl.isEmpty) {
      _showSnack(context, 'Document link unavailable');
      return;
    }

    try {
      // If it's a local file path
      if ((mediaUrl.startsWith('/') || mediaUrl.contains(r':\')) && File(mediaUrl).existsSync()) {
        final result = await OpenFilex.open(mediaUrl);
        if (result.type != ResultType.done) {
          _showSnack(context, 'Opened with status: ${result.message}');
        }
        return;
      }

      // If it's a base64 encoded file, save to temp and open
      if (mediaUrl.startsWith('data:')) {
        final pureBase64 = mediaUrl.contains(',') ? mediaUrl.split(',').last : mediaUrl;
        final bytes = base64Decode(pureBase64);
        final tempFile = File('${Directory.systemTemp.path}/$fileName');
        await tempFile.writeAsBytes(bytes);
        final result = await OpenFilex.open(tempFile.path);
        if (result.type != ResultType.done) {
          _showSnack(context, 'Status: ${result.message}');
        }
        return;
      }

      // If it's an HTTP URL
      if (mediaUrl.startsWith('http')) {
        final uri = Uri.parse(mediaUrl);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
          return;
        }
      }

      _showSnack(context, 'Unable to open $fileName');
    } catch (e) {
      _showSnack(context, 'Error opening document: $e');
    }
  }

  static void _showSnack(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
  }
}

/// Full-screen in-app video player using video_player package.
/// Supports HTTP URLs, local file paths, and base64 data URIs.
class InAppVideoPlayerScreen extends StatefulWidget {
  final String mediaUrl;
  final String title;

  const InAppVideoPlayerScreen({
    super.key,
    required this.mediaUrl,
    this.title = 'Video',
  });

  /// Push this screen onto the navigator.
  static void open(BuildContext context, {
    required String mediaUrl,
    String title = 'Video',
  }) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => InAppVideoPlayerScreen(mediaUrl: mediaUrl, title: title),
      ),
    );
  }

  @override
  State<InAppVideoPlayerScreen> createState() => _InAppVideoPlayerScreenState();
}

class _InAppVideoPlayerScreenState extends State<InAppVideoPlayerScreen> {
  VideoPlayerController? _controller;
  bool _initialized = false;
  bool _hasError = false;
  String _errorMsg = '';
  bool _showControls = true;
  Timer? _hideTimer;
  bool _isMuted = false;
  bool _isDownloading = false;
  double _downloadProgress = 0.0;

  @override
  void initState() {
    super.initState();
    _initPlayer();
  }

  /// Download an HTTP URL to the app cache directory and return the local File.
  /// Re-uses a cached file if already downloaded (keyed by URL hashCode).
  Future<File> _downloadToCache(String url) async {
    final cacheDir = await getTemporaryDirectory();
    final cacheFile = File('${cacheDir.path}/vid_${url.hashCode.abs()}.mp4');
    if (await cacheFile.exists()) return cacheFile;

    setState(() => _isDownloading = true);
    final request = http.Request('GET', Uri.parse(url));
    final response = await request.send();
    final totalBytes = response.contentLength ?? 0;
    int received = 0;
    final sink = cacheFile.openWrite();
    await response.stream.map((chunk) {
      received += chunk.length;
      if (totalBytes > 0 && mounted) {
        setState(() => _downloadProgress = received / totalBytes);
      }
      return chunk;
    }).pipe(sink);
    await sink.close();
    if (mounted) setState(() => _isDownloading = false);
    return cacheFile;
  }

  Future<void> _initPlayer() async {
    try {
      VideoPlayerController ctrl;
      final url = widget.mediaUrl;

      if (url.startsWith('http')) {
        // Download Firebase Storage / HTTP videos to local cache first.
        // ExoPlayer handles local files reliably — avoids format-sniff errors.
        final localFile = await _downloadToCache(url);
        ctrl = VideoPlayerController.file(
          localFile,
          videoPlayerOptions: VideoPlayerOptions(allowBackgroundPlayback: false),
        );
      } else if (url.startsWith('data:')) {
        // Decode base64 to the app's cache directory.
        final pureBase64 = url.contains(',') ? url.split(',').last : url;
        final bytes = base64Decode(pureBase64);
        final tempDir = await getTemporaryDirectory();
        final tempFile = File(
          '${tempDir.path}/tmp_video_${DateTime.now().millisecondsSinceEpoch}.mp4',
        );
        await tempFile.writeAsBytes(bytes);
        ctrl = VideoPlayerController.file(
          tempFile,
          videoPlayerOptions: VideoPlayerOptions(allowBackgroundPlayback: false),
        );
      } else if (File(url).existsSync()) {
        // Local file path (Android: /data/... or /storage/...)
        ctrl = VideoPlayerController.file(
          File(url),
          videoPlayerOptions: VideoPlayerOptions(allowBackgroundPlayback: false),
        );
      } else {
        setState(() {
          _hasError = true;
          _errorMsg = 'Cannot play this video.';
        });
        return;
      }

      await ctrl.initialize();
      ctrl.addListener(_onVideoUpdate);
      ctrl.play();
      setState(() {
        _controller = ctrl;
        _initialized = true;
      });
      _resetHideTimer();
    } catch (e) {
      setState(() {
        _hasError = true;
        _errorMsg = 'Error: $e';
      });
    }
  }

  void _onVideoUpdate() {
    if (mounted) setState(() {});
    // Loop
    if (_controller != null &&
        _controller!.value.position >= _controller!.value.duration &&
        _controller!.value.duration > Duration.zero) {
      _controller!.seekTo(Duration.zero);
      _controller!.pause();
    }
  }

  void _resetHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _showControls = false);
    });
  }

  void _onTapOverlay() {
    setState(() => _showControls = !_showControls);
    if (_showControls) _resetHideTimer();
  }

  void _togglePlay() {
    if (_controller == null) return;
    if (_controller!.value.isPlaying) {
      _controller!.pause();
    } else {
      _controller!.play();
      _resetHideTimer();
    }
    setState(() {});
  }

  void _toggleMute() {
    if (_controller == null) return;
    setState(() => _isMuted = !_isMuted);
    _controller!.setVolume(_isMuted ? 0 : 1);
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _controller?.removeListener(_onVideoUpdate);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Video or loading/error
          GestureDetector(
            onTap: _onTapOverlay,
            child: Center(
              child: _hasError
                  ? _buildError()
                  : !_initialized
                      ? _isDownloading
                          ? _buildDownloadProgress()
                          : const Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                CircularProgressIndicator(color: Color(0xFF5B50E6)),
                                SizedBox(height: 14),
                                Text(
                                  'Preparing video...',
                                  style: TextStyle(color: Colors.white60, fontSize: 13),
                                ),
                              ],
                            )
                      : AspectRatio(
                          aspectRatio: _controller!.value.aspectRatio,
                          child: VideoPlayer(_controller!),
                        ),
            ),
          ),

          // Controls overlay
          if (_initialized && _showControls && !_hasError) ...[
            // Top bar
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.black87, Colors.transparent],
                  ),
                ),
                child: SafeArea(
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
                        onPressed: () => Navigator.pop(context),
                      ),
                      Expanded(
                        child: Text(
                          widget.title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        icon: Icon(_isMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded, color: Colors.white),
                        onPressed: _toggleMute,
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Bottom controls
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [Colors.black87, Colors.transparent],
                  ),
                ),
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                child: SafeArea(
                  top: false,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Seek bar
                      VideoProgressIndicator(
                        _controller!,
                        allowScrubbing: true,
                        colors: const VideoProgressColors(
                          playedColor: Color(0xFF5B50E6),
                          bufferedColor: Colors.white38,
                          backgroundColor: Colors.white12,
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                      ),
                      // Duration row
                      Row(
                        children: [
                          Text(
                            _formatDuration(_controller!.value.position),
                            style: const TextStyle(color: Colors.white70, fontSize: 12),
                          ),
                          const Spacer(),
                          Text(
                            _formatDuration(_controller!.value.duration),
                            style: const TextStyle(color: Colors.white70, fontSize: 12),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Center play/pause button
            Center(
              child: GestureDetector(
                onTap: _togglePlay,
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white30),
                  ),
                  child: Icon(
                    _controller!.value.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 48,
                  ),
                ),
              ),
            ),
          ],

          // Minimal close when controls hidden (initialized & no error)
          if (_initialized && !_showControls && !_hasError)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                child: Align(
                  alignment: Alignment.topLeft,
                  child: IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white54),
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
              ),
            ),

          // Error back button
          if (_hasError)
            Positioned(
              top: 0,
              left: 0,
              child: SafeArea(
                child: IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.broken_image_rounded, color: Colors.white54, size: 64),
        const SizedBox(height: 12),
        const Text(
          'Unable to play video',
          style: TextStyle(color: Colors.white70, fontSize: 16),
        ),
        if (_errorMsg.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              _errorMsg,
              style: const TextStyle(color: Colors.white38, fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ),
      ],
    );
  }

  Widget _buildDownloadProgress() {
    final pct = (_downloadProgress * 100).toStringAsFixed(0);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 72,
          height: 72,
          child: Stack(
            alignment: Alignment.center,
            children: [
              CircularProgressIndicator(
                value: _downloadProgress > 0 ? _downloadProgress : null,
                color: const Color(0xFF5B50E6),
                strokeWidth: 5,
              ),
              if (_downloadProgress > 0)
                Text(
                  '$pct%',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        const Text(
          'Downloading video...',
          style: TextStyle(color: Colors.white60, fontSize: 13),
        ),
      ],
    );
  }
}
