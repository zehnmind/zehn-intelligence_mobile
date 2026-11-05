import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../core/log.dart';
import '../ui/speech/agent_speech_output.dart';

import 'zehn_speech_client.dart';

/// Speaks assistant replies aloud with Zehn text-to-speech.
///
/// One at a time: starting a reply stops the previous one. [speaking] holds
/// the id of the message being read, so each bubble can show a play or stop
/// control for itself.
class ZehnSpeaker implements AgentSpeechOutput {
  ZehnSpeaker(this._client, {this.log = silentAgentLog});

  /// Null when no speech key is configured; [isAvailable] is then false and
  /// every call is a no-op.
  final ZehnSpeechClient? _client;
  final AgentLog log;

  /// Created on first use rather than up front: constructing it touches a
  /// platform channel, which nothing should do before a reply is spoken.
  AudioPlayer? _player;

  /// The message currently being synthesized or played, or null.
  @override
  final ValueNotifier<String?> speaking = ValueNotifier(null);

  @override
  bool get isAvailable => _client != null;

  @override
  Future<void> speak(String messageId, String text, String language) async {
    final client = _client;
    if (client == null || text.trim().isEmpty) return;

    await stop();
    speaking.value = messageId;

    final bytes = await client.synthesize(text, language: language);
    // Another reply may have been started, or this one stopped, while the
    // audio was being generated.
    if (speaking.value != messageId) return;
    if (bytes == null) {
      speaking.value = null;
      return;
    }

    try {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/agent_reply_$messageId.wav');
      await file.writeAsBytes(bytes, flush: true);
      if (speaking.value != messageId) return;

      final player = _player ??= AudioPlayer();
      await player.play(
        DeviceFileSource(file.path, mimeType: 'audio/wav'),
        // Loudspeaker, and audible even with the ringer switch off: the user
        // asked out loud and is expecting an answer out loud.
        ctx: AudioContextConfig(
          route: AudioContextConfigRoute.speaker,
          respectSilence: false,
        ).build(),
      );
      unawaited(
        player.onPlayerComplete.first.then((_) {
          if (speaking.value == messageId) speaking.value = null;
        }),
      );
    } catch (e) {
      log('agent speaker: playback failed: $e');
      if (speaking.value == messageId) speaking.value = null;
    }
  }

  @override
  Future<void> stop() async {
    speaking.value = null;
    try {
      await _player?.stop();
    } catch (_) {}
  }
}
