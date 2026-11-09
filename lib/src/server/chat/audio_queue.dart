import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Spoken-answer clips (`audio` events), played in `seq` order.
abstract interface class ZiAudioQueue {
  void add(int seq, String base64, String format);

  /// Stops playback and drops what is queued.
  Future<void> stop();
}

/// Plays clips one at a time through `audioplayers`, from temp files.
class AudioPlayerQueue implements ZiAudioQueue {
  AudioPlayerQueue();

  final SplayTreeMap<int, (String, String)> _queue = SplayTreeMap();
  AudioPlayer? _player;
  bool _playing = false;
  int _epoch = 0;

  @override
  void add(int seq, String base64, String format) {
    _queue[seq] = (base64, format);
    if (!_playing) unawaited(_next(_epoch));
  }

  Future<void> _next(int epoch) async {
    if (epoch != _epoch || _queue.isEmpty) {
      _playing = false;
      return;
    }
    _playing = true;
    final seq = _queue.firstKey()!;
    final (data, format) = _queue.remove(seq)!;
    File? file;
    try {
      final dir = await getTemporaryDirectory();
      file = File('${dir.path}/zi_reply_${epoch}_$seq.$format');
      await file.writeAsBytes(base64Decode(data), flush: true);
      if (epoch != _epoch) return;
      final player = _player ??= AudioPlayer();
      final finished = player.onPlayerComplete.first;
      await player.play(DeviceFileSource(file.path));
      await finished;
    } on Object catch (e) {
      debugPrint('zehn_intelligence: a spoken clip failed: $e');
    } finally {
      unawaited(file?.delete().then((_) {}, onError: (Object _) {}));
    }
    await _next(epoch);
  }

  @override
  Future<void> stop() async {
    _epoch++;
    _queue.clear();
    _playing = false;
    await _player?.stop();
  }
}
