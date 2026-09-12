
import 'package:cross_file/cross_file.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

/// A finished recording, already in memory and ready to upload.
class VoiceClip {
  const VoiceClip({
    required this.bytes,
    required this.fileName,
    required this.contentType,
    required this.duration,
  });

  final Uint8List bytes;
  final String fileName;
  final String contentType;
  final Duration duration;
}

/// Why voice notes cannot be recorded in a browser.
///
/// A browser's MediaRecorder produces either WebM/Opus or a *fragmented* MP4.
/// Both are valid audio, and neither is one WhatsApp will take: Meta answered
/// "Audio file uploaded with mimetype as audio/mp4, however on processing it
/// is of type application/octet-stream" for a perfectly good fragmented m4a
/// recorded in Chrome. Android and iOS record an ordinary m4a, which it
/// accepts, so the feature is left to those.
const String kBrowserVoiceNoteMessage =
    'Voice notes have to be recorded in the Android or iOS app — a browser '
    'records a format WhatsApp will not accept.';

/// Raised when the microphone could not be started or read back.
class VoiceRecorderException implements Exception {
  const VoiceRecorderException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// What the composer needs from a recorder.
///
/// The composer talks to this rather than to `package:record` directly, so a
/// widget test can drive the whole start/stop/cancel flow without a
/// microphone or a platform channel.
abstract class VoiceRecorder {
  /// Asks for microphone access, returning false if it was refused.
  Future<bool> hasPermission();

  Future<void> start();

  /// Stops and returns the clip, or null if nothing was captured.
  Future<VoiceClip?> stop();

  /// Stops and throws the recording away.
  Future<void> cancel();

  Future<void> dispose();
}

/// The real recorder, backed by `package:record`.
class DeviceVoiceRecorder implements VoiceRecorder {
  DeviceVoiceRecorder();

  final AudioRecorder _recorder = AudioRecorder();
  DateTime? _startedAt;

  /// AAC in an MP4 container. WhatsApp accepts `audio/mp4`; it does not
  /// accept the WebM that browsers otherwise default to, so Opus is only a
  /// last resort for a browser that cannot record AAC at all.
  static const _preferred = AudioEncoder.aacLc;
  static const _fallback = AudioEncoder.opus;

  AudioEncoder _encoder = _preferred;

  @override
  Future<bool> hasPermission() async {
    // Asked before the microphone is, so a browser never prompts for access
    // it cannot make use of.
    if (kIsWeb) throw const VoiceRecorderException(kBrowserVoiceNoteMessage);
    return _recorder.hasPermission();
  }

  @override
  Future<void> start() async {
    _encoder = await _recorder.isEncoderSupported(_preferred)
        ? _preferred
        : _fallback;

    try {
      await _recorder.start(
        RecordConfig(encoder: _encoder, numChannels: 1, sampleRate: 44100),
        // The web recorder keeps the clip in a blob and ignores this; on a
        // device it has to be a real, writable path.
        path: await _outputPath(),
      );
      _startedAt = DateTime.now();
    } catch (error) {
      throw VoiceRecorderException('The microphone could not start: $error');
    }
  }

  @override
  Future<VoiceClip?> stop() async {
    final startedAt = _startedAt;
    _startedAt = null;

    final String? source;
    try {
      source = await _recorder.stop();
    } catch (error) {
      throw VoiceRecorderException('The recording could not be saved: $error');
    }
    if (source == null) return null;

    // XFile reads a device path and a browser blob: URL alike, which keeps
    // this free of a dart:io import that would not compile for web.
    final Uint8List bytes;
    try {
      bytes = await XFile(source).readAsBytes();
    } catch (error) {
      throw VoiceRecorderException('The recording could not be read: $error');
    }
    if (bytes.isEmpty) return null;

    final stamp = DateTime.now().millisecondsSinceEpoch;
    return VoiceClip(
      bytes: bytes,
      fileName: 'voice-$stamp.${_extension(_encoder)}',
      contentType: _contentType(_encoder),
      duration: startedAt == null
          ? Duration.zero
          : DateTime.now().difference(startedAt),
    );
  }

  @override
  Future<void> cancel() async {
    _startedAt = null;
    try {
      await _recorder.cancel();
    } catch (_) {
      // Nothing to salvage — the clip is being thrown away either way.
    }
  }

  @override
  Future<void> dispose() => _recorder.dispose();

  Future<String> _outputPath() async {
    if (kIsWeb) return '';
    final directory = await getTemporaryDirectory();
    final stamp = DateTime.now().millisecondsSinceEpoch;
    return '${directory.path}/voice-$stamp.${_extension(_encoder)}';
  }

  static String _extension(AudioEncoder encoder) =>
      encoder == AudioEncoder.opus ? 'webm' : 'm4a';

  static String _contentType(AudioEncoder encoder) =>
      encoder == AudioEncoder.opus ? 'audio/webm' : 'audio/mp4';
}
