import 'package:flutter_test/flutter_test.dart';
import 'package:record/record.dart';
import 'package:zehn_intelligence/src/voice/voice_recorder.dart';

void main() {
  test('aac records m4a at 64 kbit/s', () {
    final config = AgentVoiceRecorder.configFor(aac: true);
    expect(config.encoder, AudioEncoder.aacLc);
    expect(config.bitRate, 64000);
    expect(AgentVoiceRecorder.extensionFor(aac: true), 'm4a');
  });

  test('default stays 16 kHz WAV', () {
    final config = AgentVoiceRecorder.configFor(aac: false);
    expect(config.encoder, AudioEncoder.wav);
    expect(config.sampleRate, 16000);
    expect(AgentVoiceRecorder.extensionFor(aac: false), 'wav');
  });
}
