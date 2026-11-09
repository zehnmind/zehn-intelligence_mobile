import 'dart:io';
import 'dart:typed_data';

import '../../voice/voice_recorder.dart';

/// What the chat needs from a microphone.
abstract interface class ZiVoiceRecorder {
  /// Asks for the microphone if needed; false when refused or unavailable.
  Future<bool> start();

  /// Loudness 0..1 while recording.
  Stream<double> levels();

  /// The recording (AAC in `.m4a`), or null when nothing was captured.
  Future<Uint8List?> stop();

  Future<void> cancel();

  Future<void> dispose();
}

/// The SDK's own recorder: AAC `.m4a`, as the console's turn flow takes.
class DefaultVoiceRecorder implements ZiVoiceRecorder {
  final AgentVoiceRecorder _recorder = AgentVoiceRecorder(aac: true);

  @override
  Future<bool> start() => _recorder.start();

  @override
  Stream<double> levels() => _recorder.levels();

  @override
  Future<Uint8List?> stop() async {
    final path = await _recorder.stop();
    if (path == null) return null;
    try {
      return await File(path).readAsBytes();
    } on FileSystemException {
      return null;
    } finally {
      await AgentVoiceRecorder.discard(path);
    }
  }

  @override
  Future<void> cancel() => _recorder.cancel();

  @override
  Future<void> dispose() => _recorder.dispose();
}
