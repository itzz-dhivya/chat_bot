import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

class AudioFileItem {
  final File file;
  final String title;
  final String path;
  final int sizeBytes;
  final String sizeFormatted;
  final DateTime modified;

  AudioFileItem({
    required this.file,
    required this.title,
    required this.path,
    required this.sizeBytes,
    required this.sizeFormatted,
    required this.modified,
  });
}

class WhatsAppAudioPickerScreen extends StatefulWidget {
  const WhatsAppAudioPickerScreen({super.key});

  @override
  State<WhatsAppAudioPickerScreen> createState() =>
      _WhatsAppAudioPickerScreenState();
}

class _WhatsAppAudioPickerScreenState extends State<WhatsAppAudioPickerScreen> {
  final List<AudioFileItem> _audioList = [];
  List<AudioFileItem> _filteredList = [];
  bool _isLoading = true;
  String? _selectedPath;
  AudioFileItem? _selectedItem;

  // Search
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();

  // Audio preview playback
  final AudioPlayer _audioPlayer = AudioPlayer();
  String? _playingPath;
  PlayerState _playerState = PlayerState.stopped;

  static const List<String> _audioExtensions = [
    '.mp3',
    '.m4a',
    '.wav',
    '.aac',
    '.ogg',
    '.opus',
    '.flac',
    '.amr',
    '.wma',
  ];

  static String sanitizeText(String? input) {
    if (input == null || input.isEmpty) return '';
    final buffer = StringBuffer();
    for (int i = 0; i < input.length; i++) {
      final cu = input.codeUnitAt(i);
      if (cu >= 0xD800 && cu <= 0xDFFF) {
        if (cu <= 0xDBFF && i + 1 < input.length) {
          final next = input.codeUnitAt(i + 1);
          if (next >= 0xDC00 && next <= 0xDFFF) {
            buffer.writeCharCode(cu);
            buffer.writeCharCode(next);
            i++;
            continue;
          }
        }
        buffer.write(' ');
      } else if (cu == 0) {
        continue;
      } else {
        buffer.writeCharCode(cu);
      }
    }
    return buffer.toString();
  }

  @override
  void initState() {
    super.initState();
    _initAudioPlayer();
    _loadAudioFiles();
    _searchController.addListener(_onSearchChanged);
  }

  void _initAudioPlayer() {
    _audioPlayer.onPlayerStateChanged.listen((state) {
      if (mounted) {
        setState(() {
          _playerState = state;
        });
      }
    });

    _audioPlayer.onPlayerComplete.listen((_) {
      if (mounted) {
        setState(() {
          _playingPath = null;
          _playerState = PlayerState.stopped;
        });
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _audioPlayer.stop();
    _audioPlayer.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    final query = sanitizeText(_searchController.text.trim().toLowerCase());
    setState(() {
      if (query.isEmpty) {
        _filteredList = List.from(_audioList);
      } else {
        _filteredList = _audioList
            .where((item) =>
                item.title.toLowerCase().contains(query) ||
                item.path.toLowerCase().contains(query))
            .toList();
      }
    });
  }

  Future<void> _loadAudioFiles() async {
    setState(() {
      _isLoading = true;
    });

    try {
      if (Platform.isAndroid) {
        try {
          await Permission.storage.request();
        } catch (_) {}
        try {
          await Permission.audio.request();
        } catch (_) {}
      }
    } catch (e) {
      debugPrint('Permission error: $e');
    }

    final Set<String> discoveredPaths = {};
    final List<AudioFileItem> results = [];

    final List<String> directoriesToScan = [];

    if (Platform.isAndroid) {
      final List<String> knownAudioDirs = [
        '/storage/emulated/0/Music',
        '/storage/emulated/0/Download',
        '/storage/emulated/0/Downloads',
        '/storage/emulated/0/Recordings',
        '/storage/emulated/0/Audio',
        '/storage/emulated/0/Sounds',
        '/storage/emulated/0/Ringtones',
        '/storage/emulated/0/Notifications',
        '/storage/emulated/0/Podcasts',
        '/storage/emulated/0/Audiobooks',
        '/storage/emulated/0/Android/media/com.whatsapp/WhatsApp/Media/WhatsApp Audio',
        '/storage/emulated/0/Android/media/com.whatsapp/WhatsApp/Media/WhatsApp Voice Notes',
        '/storage/emulated/0/WhatsApp/Media/WhatsApp Audio',
        '/storage/emulated/0/WhatsApp/Media/WhatsApp Voice Notes',
      ];

      for (final path in knownAudioDirs) {
        try {
          if (Directory(path).existsSync()) {
            directoriesToScan.add(path);
          }
        } catch (_) {}
      }
    }

    try {
      final appDocDir = await getApplicationDocumentsDirectory();
      directoriesToScan.add(appDocDir.path);
    } catch (_) {}

    try {
      final downloadsDir = await getDownloadsDirectory();
      if (downloadsDir != null) {
        directoriesToScan.add(downloadsDir.path);
      }
    } catch (_) {}

    // Async scan without blocking UI thread
    for (final dirPath in directoriesToScan) {
      try {
        final dir = Directory(dirPath);
        if (!await dir.exists()) continue;

        await _scanDirAsync(dir, results, discoveredPaths, depth: 0, maxDepth: 2);
      } catch (e) {
        debugPrint('Scan error on $dirPath: $e');
      }
    }

    // Sort newest first
    results.sort((a, b) => b.modified.compareTo(a.modified));

    if (mounted) {
      setState(() {
        _audioList.clear();
        _audioList.addAll(results);
        _filteredList = List.from(_audioList);
        _isLoading = false;
      });
    }
  }

  Future<void> _scanDirAsync(
    Directory dir,
    List<AudioFileItem> results,
    Set<String> discoveredPaths, {
    required int depth,
    required int maxDepth,
  }) async {
    if (depth > maxDepth) return;

    try {
      final stream = dir.list(followLinks: false);
      await for (final entity in stream) {
        final rawName = entity.path.split(Platform.pathSeparator).last;
        if (rawName.startsWith('.')) continue;

        final name = sanitizeText(rawName);

        if (entity is Directory) {
          if (name == 'Android' || name == 'data' || name == 'obb') continue;
          await _scanDirAsync(
            entity,
            results,
            discoveredPaths,
            depth: depth + 1,
            maxDepth: maxDepth,
          );
        } else if (entity is File) {
          final lowerPath = entity.path.toLowerCase();
          final isAudio =
              _audioExtensions.any((ext) => lowerPath.endsWith(ext));

          if (isAudio && !discoveredPaths.contains(entity.path)) {
            discoveredPaths.add(entity.path);
            try {
              final stat = await entity.stat();
              final bytes = stat.size;
              final sizeMb = (bytes / (1024 * 1024)).toStringAsFixed(1);
              final sizeStr = bytes < 1024 * 1024
                  ? '${(bytes / 1024).toStringAsFixed(0)} KB'
                  : '$sizeMb MB';

              String cleanTitle = name;
              for (final ext in _audioExtensions) {
                if (cleanTitle.toLowerCase().endsWith(ext)) {
                  cleanTitle = cleanTitle.substring(
                      0, cleanTitle.length - ext.length);
                  break;
                }
              }

              final finalTitle = sanitizeText(cleanTitle.trim().isNotEmpty
                  ? cleanTitle.trim()
                  : name);

              results.add(AudioFileItem(
                file: entity,
                title: finalTitle.isNotEmpty ? finalTitle : 'Audio File',
                path: entity.path,
                sizeBytes: bytes,
                sizeFormatted: sanitizeText(sizeStr),
                modified: stat.modified,
              ));
            } catch (statErr) {
              debugPrint('Stat error on ${entity.path}: $statErr');
            }
          }
        }
      }
    } catch (_) {
      // Ignore directory access permission errors
    }
  }

  Future<void> _togglePlayPreview(AudioFileItem item) async {
    if (_playingPath == item.path && _playerState == PlayerState.playing) {
      await _audioPlayer.pause();
    } else {
      await _audioPlayer.stop();
      _playingPath = item.path;
      await _audioPlayer.play(DeviceFileSource(item.path));
    }
    setState(() {});
  }

  Future<void> _pickFromDeviceStorage() async {
    try {
      final PlatformFile? pickedFile = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['mp3', 'm4a', 'wav', 'aac', 'ogg', 'opus', 'flac', 'amr', 'wma'],
      );

      if (pickedFile != null && pickedFile.path != null) {
        final file = File(pickedFile.path!);
        await _audioPlayer.stop();
        if (mounted) {
          Navigator.pop(context, file);
        }
      }
    } catch (e) {
      debugPrint('File picker error: $e');
    }
  }

  void _sendSelectedAudio() {
    if (_selectedItem != null) {
      _audioPlayer.stop();
      Navigator.pop(context, _selectedItem!.file);
    }
  }

  String _formatDate(DateTime dt) {
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    const primaryColor = Color(0xFF075E54);
    const accentColor = Color(0xFF25D366);

    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: AppBar(
        backgroundColor: primaryColor,
        elevation: 1,
        titleSpacing: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          onPressed: () {
            _audioPlayer.stop();
            Navigator.pop(context);
          },
        ),
        title: _isSearching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                style: const TextStyle(color: Colors.white, fontSize: 17),
                cursorColor: Colors.white,
                decoration: const InputDecoration(
                  hintText: 'Search audio...',
                  hintStyle: TextStyle(color: Colors.white70),
                  border: InputBorder.none,
                ),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Send audio',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    _isLoading
                        ? 'Scanning device...'
                        : '${_audioList.length} audio files found',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
        actions: [
          IconButton(
            icon: Icon(
              _isSearching ? Icons.close_rounded : Icons.search_rounded,
              color: Colors.white,
            ),
            onPressed: () {
              setState(() {
                if (_isSearching) {
                  _isSearching = false;
                  _searchController.clear();
                  _filteredList = List.from(_audioList);
                } else {
                  _isSearching = true;
                }
              });
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.white),
            tooltip: 'Refresh list',
            onPressed: _loadAudioFiles,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
                  ),
                  SizedBox(height: 16),
                  Text(
                    'Loading audio files...',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),
            )
          : Column(
              children: [
                // Top Action: Browse file manager if needed
                Container(
                  color: Colors.white,
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF9800).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(22),
                      ),
                      child: const Icon(
                        Icons.folder_open_rounded,
                        color: Color(0xFFFF9800),
                        size: 24,
                      ),
                    ),
                    title: const Text(
                      'Browse other audio files',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1E293B),
                      ),
                    ),
                    subtitle: const Text(
                      'Select from device storage (.mp3, .m4a, .wav...)',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    trailing: const Icon(
                      Icons.chevron_right_rounded,
                      color: Colors.grey,
                    ),
                    onTap: _pickFromDeviceStorage,
                  ),
                ),

                // Audio list
                Expanded(
                  child: _filteredList.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.music_off_rounded,
                                size: 64,
                                color: Colors.grey.shade400,
                              ),
                              const SizedBox(height: 12),
                              const Text(
                                'No audio files found on device',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF475569),
                                ),
                              ),
                              const SizedBox(height: 6),
                              const Text(
                                'Tap "Browse other audio files" above to select manually',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.separated(
                          itemCount: _filteredList.length,
                          separatorBuilder: (_, __) => const Divider(
                            height: 1,
                            indent: 68,
                            endIndent: 16,
                            color: Color(0xFFF1F5F9),
                          ),
                          itemBuilder: (context, index) {
                            final item = _filteredList[index];
                            final isSelected = _selectedPath == item.path;
                            final isPlaying = _playingPath == item.path &&
                                _playerState == PlayerState.playing;

                            final displayTitle = sanitizeText(item.title);

                            return Container(
                              color: isSelected
                                  ? accentColor.withValues(alpha: 0.1)
                                  : Colors.white,
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 4,
                                ),
                                leading: Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    Container(
                                      width: 44,
                                      height: 44,
                                      decoration: BoxDecoration(
                                        color: isPlaying
                                            ? accentColor
                                            : const Color(0xFFFF9800)
                                                .withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(22),
                                      ),
                                      child: Icon(
                                        Icons.audiotrack_rounded,
                                        color: isPlaying
                                            ? Colors.white
                                            : const Color(0xFFFF9800),
                                        size: 24,
                                      ),
                                    ),
                                    // Play/Pause Overlay button
                                    Material(
                                      color: Colors.transparent,
                                      child: InkWell(
                                        borderRadius: BorderRadius.circular(22),
                                        onTap: () => _togglePlayPreview(item),
                                        child: Container(
                                          width: 44,
                                          height: 44,
                                          alignment: Alignment.center,
                                          decoration: BoxDecoration(
                                            color: isPlaying
                                                ? Colors.black.withValues(alpha: 0.25)
                                                : Colors.transparent,
                                            borderRadius:
                                                BorderRadius.circular(22),
                                          ),
                                          child: Icon(
                                            isPlaying
                                                ? Icons.pause_rounded
                                                : Icons.play_arrow_rounded,
                                            color: isPlaying
                                                ? Colors.white
                                                : const Color(0xFFFF9800),
                                            size: 22,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                title: Text(
                                  displayTitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: isSelected
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                    color: const Color(0xFF1E293B),
                                  ),
                                ),
                                subtitle: Text(
                                  sanitizeText(
                                      '${item.sizeFormatted} • ${_formatDate(item.modified)}${isPlaying ? ' • Playing...' : ''}'),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: isPlaying ? accentColor : Colors.grey,
                                    fontWeight: isPlaying
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                  ),
                                ),
                                trailing: Radio<String>(
                                  value: item.path,
                                  groupValue: _selectedPath,
                                  activeColor: accentColor,
                                  onChanged: (val) {
                                    setState(() {
                                      _selectedPath = val;
                                      _selectedItem = item;
                                    });
                                  },
                                ),
                                onTap: () {
                                  setState(() {
                                    _selectedPath = item.path;
                                    _selectedItem = item;
                                  });
                                },
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
      floatingActionButton: _selectedItem != null
          ? FloatingActionButton.extended(
              backgroundColor: accentColor,
              onPressed: _sendSelectedAudio,
              icon: const Icon(Icons.send_rounded, color: Colors.white),
              label: const Text(
                'Send (1)',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            )
          : null,
    );
  }
}
