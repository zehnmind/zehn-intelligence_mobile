import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:zehn_intelligence/src/server/api/api_client.dart';
import 'package:zehn_intelligence/src/server/api/turn_client.dart';
import 'package:zehn_intelligence/src/server/api/turn_events.dart';
import 'package:zehn_intelligence/src/server/auth/file_store.dart';
import 'package:zehn_intelligence/src/server/bootstrap/bootstrap.dart';
import 'package:zehn_intelligence/src/server/bootstrap/bootstrap_repository.dart';
import 'package:zehn_intelligence/src/server/chat/audio_queue.dart';
import 'package:zehn_intelligence/src/server/proxy/proxy_executor.dart';
import 'package:zehn_intelligence/src/server/proxy/request_builder.dart';
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
  FakeRunner()
    : super(
        handlers: const {},
        proxy: ZiProxyExecutor(),
        bootstrap: ZiBootstrapRepository(api: _unused, store: ZiFileStore(() async => Directory.systemTemp)),
        context: () => const ZiRequestContext(language: 'uz', appVersion: '1', platform: 'ios'),
      );

  final List<List<ClientApiRequest>> rounds = [];
  final List<DateTime?> deadlines = [];

  @override
  Future<List<ToolCallResult>> runAll(List<ClientApiRequest> calls, {DateTime? deadline}) async {
    rounds.add(calls);
    deadlines.add(deadline);
    return [for (final c in calls) ToolCallResult.ok(c.callId, {'tool': c.tool})];
  }
}

class FakeAudio implements ZiAudioQueue {
  final List<(int, String, String)> clips = [];
  int stops = 0;

  @override
  void add(int seq, String base64, String format) => clips.add((seq, base64, format));

  @override
  Future<void> stop() async => stops++;
}

TurnFailed failure(String code, {bool retryable = false}) =>
    TurnFailed(ZiApiException(code, retryable: retryable), turnId: 't1');

/// Start-up data that is simply there: no file, no network.
class FixedBootstrap extends ZiBootstrapRepository {
  FixedBootstrap(this.data) : super(api: _unused, store: ZiFileStore(() async => Directory.systemTemp));

  ZiBootstrap? data;
  int refreshes = 0;

  @override
  ZiBootstrap? get current => data;

  @override
  Future<ZiBootstrap?> refresh() async {
    refreshes++;
    return data;
  }
}
