import 'dart:async';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import '../core/log.dart';

/// Records one spoken question as 16 kHz mono WAV — what speech recognisers
/// want, and small: about 32 KB a second.
///
/// Owned by the chat and disposed with it; nothing records while the chat is
/// closed.
class AgentVoiceRecorder {
  /// [aac] records AAC in `.m4a` at 64 kbit/s instead: what the console's
  /// turn flow takes (about a minute fits its 1 MiB limit).
  AgentVoiceRecorder({this.log = silentAgentLog, this.aac = false}) : _recorder = AudioRecorder();

  final AudioRecorder _recorder;
  final AgentLog log;
  final bool aac;

  // The default iOS options include defaultToSpeaker, which is what keeps
  // the spoken reply on the loudspeaker afterwards instead of the earpiece.
  static RecordConfig configFor({required bool aac}) => aac
      ? const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 64000,
          sampleRate: 44100,
          numChannels: 1,
          noiseSuppress: true,
        )
      : const RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: 16000,
          numChannels: 1,
          noiseSuppress: true,
        );

  static String extensionFor({required bool aac}) => aac ? 'm4a' : 'wav';

  /// The level meter's range, from Evonote's recorder: quieter than [_floorDb]
  /// reads as silence, louder than [_ceilingDb] as full scale. Normal speech
  /// sits in the middle of it, so the waveform visibly moves.
  static const double _floorDb = -60;
  static const double _ceilingDb = -10;

  /// Asks for the microphone if needed, then starts recording. False when
  /// permission is refused or the recorder cannot start.
  Future<bool> start() async {
    try {
      if (!await _recorder.hasPermission()) return false;

      final dir = await getTemporaryDirectory();
      final path =
          '${dir.path}/agent_voice_${DateTime.now().millisecondsSinceEpoch}.${extensionFor(aac: aac)}';

      await _recorder.start(configFor(aac: aac), path: path);
      return true;
    } catch (e) {
      log('agent voice: could not start recording: $e');
      return false;
    }
  }

  /// Loudness 0..1, for the recording animation.
  Stream<double> levels() => _recorder
      .onAmplitudeChanged(const Duration(milliseconds: 80))
      .map((amplitude) {
        final db = amplitude.current;
        if (db.isNaN || db <= _floorDb) return 0.0;
        return ((db - _floorDb) / (_ceilingDb - _floorDb)).clamp(0.0, 1.0);
      });

  /// Stops and returns the recording's path, or null if nothing was captured.
  Future<String?> stop() async {
    try {
      return await _recorder.stop();
    } catch (e) {
      log('agent voice: could not stop recording: $e');
      return null;
    }
  }

  Future<void> cancel() async {
    try {
      await _recorder.cancel();
    } catch (_) {}
  }

  Future<void> dispose() async {
    try {
      await _recorder.dispose();
    } catch (_) {}
  }

  /// Recordings are transient; delete once transcribed.
  static Future<void> discard(String? path) async {
    if (path == null) return;
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }
}
