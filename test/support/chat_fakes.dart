import 'dart:async';
import 'dart:collection';

import 'package:zehn_intelligence/src/server/api/api_client.dart';
import 'package:zehn_intelligence/src/server/api/turn_client.dart';
import 'package:zehn_intelligence/src/server/api/turn_events.dart';
import 'package:zehn_intelligence/src/server/chat/audio_queue.dart';
import 'package:zehn_intelligence/src/server/proxy/proxy_executor.dart';
import 'package:zehn_intelligence/src/server/proxy/tool_runner.dart';

import 'test_info.dart';

final _unused = ZiApiClient(baseUrl: Uri.parse('http://unused.invalid'), info: info);

/// Each start/sendResults call takes the next scripted leg.
class FakeTurns extends ZiTurnClient {
  FakeTurns() : super(api: _unused, tokens: () => throw UnimplementedError());

  final Queue<Stream<TurnEvent>> legs = Queue();
  final List<TurnInput> starts = [];
  final List<(String, List<ToolCallResult>, DateTime)> results = [];

  void script(List<TurnEvent> events) => legs.add(Stream.fromIterable(events));

  @override
  Stream<TurnEvent> start(TurnInput input) {
    starts.add(input);
    return legs.removeFirst();
  }

  @override
  Stream<TurnEvent> sendResults(String turnId, List<ToolCallResult> results, {required DateTime deadline}) {
    this.results.add((turnId, results, deadline));
    return legs.removeFirst();
  }
}

class FakeRunner extends ZiToolRunner {
  FakeRunner() : super(handlers: const {}, proxy: ZiProxyExecutor());

  final List<List<ClientApiRequest>> rounds = [];

  /// What each round was told of the pause it answers.
  final List<({Duration? expiresIn, int? maxResultBytes})> pauses = [];

  @override
  Future<List<ToolCallResult>> runAll(
    List<ClientApiRequest> calls, {
    Duration? expiresIn,
    int? maxResultBytes,
  }) async {
    rounds.add(calls);
    pauses.add((expiresIn: expiresIn, maxResultBytes: maxResultBytes));
    return [for (final c in calls) ToolCallResult.ok(c.callId, {'tool': c.tool})];
  }
}

class FakeAudio implements ZiAudioQueue {
  final List<(int, String, String)> clips = [];
  final StreamController<void> _drained = StreamController.broadcast();
  int stops = 0;

  @override
  void add(int seq, String base64, String format) => clips.add((seq, base64, format));

  @override
  Future<void> stop() async => stops++;

  @override
  Stream<void> get drained => _drained.stream;

  /// Everything queued has been played.
  void finish() => _drained.add(null);
}

TurnFailed failure(String code, {bool retryable = false}) =>
    TurnFailed(ZiApiException(code, retryable: retryable), turnId: 't1');
