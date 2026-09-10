import 'dart:math' as math;
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// Handles incoming and outgoing call ringtone playback and message notification chimes
/// using [audioplayers] with offline PCM WAV synthesis.
class RingtoneService {
  static final RingtoneService _instance = RingtoneService._internal();
  factory RingtoneService() => _instance;
  RingtoneService._internal();

  final AudioPlayer _player = AudioPlayer();
  final AudioPlayer _notificationPlayer = AudioPlayer();
  bool _isPlaying = false;
  bool get isPlaying => _isPlaying;

  static Uint8List? _cachedIncomingWav;
  static Uint8List? _cachedOutgoingWav;
  static Uint8List? _cachedNotificationWav;

  /// Starts looping the ringtone for an incoming call.
  Future<void> startRingtone() async {
    try {
      debugPrint('RingtoneService: Starting incoming ringtone');
      await stopRingtone();
      await _configureAudioContext(isOutgoing: false);
      await _player.setReleaseMode(ReleaseMode.loop);
      await _player.setVolume(1.0);

      _cachedIncomingWav ??= _generateIncomingRingWav();
      await _player.play(BytesSource(_cachedIncomingWav!, mimeType: 'audio/wav'));
      _isPlaying = true;
      debugPrint('RingtoneService: Incoming ringtone playing');
    } catch (e) {
      debugPrint('RingtoneService: Error starting incoming ringtone: $e');
    }
  }

  /// Starts looping the dial/ring tone for an outgoing call.
  Future<void> startOutgoingRingtone() async {
    try {
      debugPrint('RingtoneService: Starting outgoing ringtone');
      await stopRingtone();
      await _configureAudioContext(isOutgoing: true);
      await _player.setReleaseMode(ReleaseMode.loop);
      await _player.setVolume(0.9);

      _cachedOutgoingWav ??= _generateOutgoingRingWav();
      await _player.play(BytesSource(_cachedOutgoingWav!, mimeType: 'audio/wav'));
      _isPlaying = true;
      debugPrint('RingtoneService: Outgoing ringtone playing');
    } catch (e) {
      debugPrint('RingtoneService: Error starting outgoing ringtone: $e');
    }
  }

  /// Plays a single short notification sound for incoming chat messages.
  Future<void> playNotificationSound() async {
    try {
      _cachedNotificationWav ??= _generateNotificationWav();
      await _notificationPlayer.setVolume(0.85);
      await _notificationPlayer.setReleaseMode(ReleaseMode.release);
      await _notificationPlayer.play(BytesSource(_cachedNotificationWav!, mimeType: 'audio/wav'));
      debugPrint('RingtoneService: Notification sound played');
    } catch (e) {
      debugPrint('RingtoneService: Error playing notification sound: $e');
    }
  }

  /// Configures platform audio session.
  Future<void> _configureAudioContext({bool isOutgoing = false}) async {
    try {
      await _player.setAudioContext(
        AudioContext(
          android: AudioContextAndroid(
            isSpeakerphoneOn: !isOutgoing,
            stayAwake: true,
            contentType: AndroidContentType.music,
            usageType: isOutgoing
                ? AndroidUsageType.voiceCommunicationSignalling
                : AndroidUsageType.notificationRingtone,
            audioFocus: AndroidAudioFocus.gainTransientMayDuck,
          ),
          iOS: AudioContextIOS(
            category: AVAudioSessionCategory.playback,
            options: const {
              AVAudioSessionOptions.mixWithOthers,
            },
          ),
        ),
      );
    } catch (e) {
      debugPrint('AudioContext configuration error: $e');
    }
  }

  /// Stops any currently playing ringtone.
  Future<void> stopRingtone() async {
    try {
      _isPlaying = false;
      await _player.stop();
      debugPrint('RingtoneService: Ringtone stopped');
    } catch (e) {
      debugPrint('RingtoneService: Error stopping ringtone: $e');
    }
  }

  Future<void> dispose() async {
    await stopRingtone();
    await _player.dispose();
    await _notificationPlayer.dispose();
    _isPlaying = false;
  }

  // ==========================================================
  // IN-MEMORY AUDIO GENERATORS (PURE DART PCM WAV)
  // ==========================================================

  /// Generates a pleasant melodic chime ringtone for incoming calls (WhatsApp / Marimba style).
  /// Multi-tone chord sequence with exponential decay and warm harmonics.
  static Uint8List _generateIncomingRingWav() {
    const int sampleRate = 22050;
    const double totalDuration = 2.5; // 2.5 seconds loop
    final int totalSamples = (sampleRate * totalDuration).toInt();
    final Uint8List wav = _createWavHeader(sampleRate, totalSamples);
    final ByteData byteData = ByteData.sublistView(wav);

    // Melodic notes sequence: (startTime, frequency, duration)
    final List<_ChimeNote> notes = [
      _ChimeNote(startTime: 0.00, freq: 659.25, duration: 0.35), // E5
      _ChimeNote(startTime: 0.18, freq: 830.61, duration: 0.35), // G#5
      _ChimeNote(startTime: 0.36, freq: 987.77, duration: 0.45), // B5
      _ChimeNote(startTime: 0.58, freq: 1318.51, duration: 0.60), // E6
      _ChimeNote(startTime: 0.95, freq: 987.77, duration: 0.30), // B5
      _ChimeNote(startTime: 1.15, freq: 1318.51, duration: 0.70), // E6
    ];

    for (int i = 0; i < totalSamples; i++) {
      final double t = i / sampleRate;
      double sample = 0.0;

      for (final note in notes) {
        if (t >= note.startTime && t < note.startTime + note.duration) {
          final double noteT = t - note.startTime;
          // Fast attack (10ms) and exponential decay
          final double attack = math.min(1.0, noteT / 0.015);
          final double decay = math.exp(-4.5 * noteT);
          final double env = attack * decay;

          // Fundamental + 2nd harmonic (warmth) + subtle 3rd harmonic
          final double f = note.freq;
          final double fund = math.sin(2 * math.pi * f * noteT);
          final double h2 = math.sin(2 * math.pi * 2 * f * noteT) * 0.35;
          final double h3 = math.sin(2 * math.pi * 3 * f * noteT) * 0.15;

          sample += (fund + h2 + h3) * env * 0.45;
        }
      }

      final int pcm = (sample * 28000).clamp(-32767, 32767).toInt();
      byteData.setInt16(44 + (i * 2), pcm, Endian.little);
    }

    return wav;
  }

  /// Generates standard telephone dial/ringback tone for outgoing calls.
  /// Dual tone 440 Hz + 480 Hz cadence: 1.2s tone burst, 1.8s silence.
  static Uint8List _generateOutgoingRingWav() {
    const int sampleRate = 22050;
    const double totalDuration = 3.0; // 3 seconds loop
    final int totalSamples = (sampleRate * totalDuration).toInt();
    final Uint8List wav = _createWavHeader(sampleRate, totalSamples);
    final ByteData byteData = ByteData.sublistView(wav);

    for (int i = 0; i < totalSamples; i++) {
      final double t = i / sampleRate;
      double sample = 0.0;

      // 1.2s tone burst, then 1.8s silence
      if (t < 1.2) {
        double envelope = 1.0;
        if (t < 0.04) {
          envelope = t / 0.04; // Smooth attack
        } else if (t > 1.16) {
          envelope = (1.2 - t) / 0.04; // Smooth decay
        }
        final double tone1 = math.sin(2 * math.pi * 440 * t);
        final double tone2 = math.sin(2 * math.pi * 480 * t);
        sample = ((tone1 * 0.5) + (tone2 * 0.5)) * envelope * 0.85;
      }

      final int pcm = (sample * 24000).clamp(-32767, 32767).toInt();
      byteData.setInt16(44 + (i * 2), pcm, Endian.little);
    }

    return wav;
  }

  /// Generates a pleasant 2-tone chime for incoming message notification (C6 -> G6).
  static Uint8List _generateNotificationWav() {
    const int sampleRate = 22050;
    const double totalDuration = 0.45; // 450ms short chime
    final int totalSamples = (sampleRate * totalDuration).toInt();
    final Uint8List wav = _createWavHeader(sampleRate, totalSamples);
    final ByteData byteData = ByteData.sublistView(wav);

    final List<_ChimeNote> notes = [
      _ChimeNote(startTime: 0.00, freq: 1046.50, duration: 0.18), // C6
      _ChimeNote(startTime: 0.10, freq: 1567.98, duration: 0.32), // G6
    ];

    for (int i = 0; i < totalSamples; i++) {
      final double t = i / sampleRate;
      double sample = 0.0;

      for (final note in notes) {
        if (t >= note.startTime && t < note.startTime + note.duration) {
          final double noteT = t - note.startTime;
          final double attack = math.min(1.0, noteT / 0.008);
          final double decay = math.exp(-8.0 * noteT);
          final double env = attack * decay;

          final double fund = math.sin(2 * math.pi * note.freq * noteT);
          final double h2 = math.sin(2 * math.pi * 2 * note.freq * noteT) * 0.25;

          sample += (fund + h2) * env * 0.5;
        }
      }

      final int pcm = (sample * 26000).clamp(-32767, 32767).toInt();
      byteData.setInt16(44 + (i * 2), pcm, Endian.little);
    }

    return wav;
  }

  /// Helper to allocate Uint8List with 44-byte RIFF/WAVE header
  static Uint8List _createWavHeader(int sampleRate, int totalSamples) {
    final int byteLength = totalSamples * 2;
    final Uint8List wav = Uint8List(44 + byteLength);
    final ByteData byteData = ByteData.sublistView(wav);

    // "RIFF"
    wav[0] = 0x52; wav[1] = 0x49; wav[2] = 0x46; wav[3] = 0x46;
    byteData.setUint32(4, 36 + byteLength, Endian.little);
    // "WAVE"
    wav[8] = 0x57; wav[9] = 0x41; wav[10] = 0x56; wav[11] = 0x45;
    // "fmt "
    wav[12] = 0x66; wav[13] = 0x6D; wav[14] = 0x74; wav[15] = 0x20;
    byteData.setUint32(16, 16, Endian.little); // Subchunk1Size (16 for PCM)
    byteData.setUint16(20, 1, Endian.little);  // AudioFormat (1 = PCM)
    byteData.setUint16(22, 1, Endian.little);  // NumChannels (1 = Mono)
    byteData.setUint32(24, sampleRate, Endian.little); // SampleRate
    byteData.setUint32(28, sampleRate * 2, Endian.little); // ByteRate
    byteData.setUint16(32, 2, Endian.little);  // BlockAlign
    byteData.setUint16(34, 16, Endian.little); // BitsPerSample
    // "data"
    wav[36] = 0x64; wav[37] = 0x61; wav[38] = 0x74; wav[39] = 0x61;
    byteData.setUint32(40, byteLength, Endian.little);

    return wav;
  }
}

class _ChimeNote {
  final double startTime;
  final double freq;
  final double duration;

  const _ChimeNote({
    required this.startTime,
    required this.freq,
    required this.duration,
  });
}