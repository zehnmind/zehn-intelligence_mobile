import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zehn_intelligence/src/server/api/api_client.dart';
import 'package:zehn_intelligence/src/server/api/turn_client.dart';
import 'package:zehn_intelligence/src/server/api/turn_events.dart';
import 'package:zehn_intelligence/src/server/auth/token_source.dart';

import '../../support/fake_server.dart';
import '../../support/test_info.dart';

class FakeTokens implements ZiTokenSource {
  int refreshed = 0;
  String current = 'tok-0';

  @override
  Future<String> token() async => current;

  @override
  Future<String> refresh() async => current = 'tok-${++refreshed}';
}

class ThrowingTokens implements ZiTokenSource {
  @override
  Future<String> token() async => throw StateError('the app token call failed');

  @override
  Future<String> refresh() async => throw StateError('the app token call failed');
}

Map<String, Object?> ev(Map<String, Object?> data) => {'turn_id': 't1', 'seq': 1, ...data};

final pausedEvent = (
  'turn.paused',
  ev({
    'call_ids': ['c_1'],
    'deadline': '2030-01-01T00:00:00Z',
    'expires_in': 60,
    'max_result_bytes': 32768,
  }),
);

void main() {
  late FakeServer server;
  late FakeTokens tokens;
  late ZiTurnClient client;

  setUp(() async {
    server = await FakeServer.start();
    tokens = FakeTokens();
    client = ZiTurnClient(
      api: ZiApiClient(baseUrl: server.url, info: info),
      tokens: () => tokens,
      pingTimeout: const Duration(milliseconds: 300),
      retryDelay: const Duration(milliseconds: 50),
    );
  });

  tearDown(() => server.close());

  final input = TurnInput.text(text: 'kino', language: 'uz', utcOffsetMinutes: 300);

  test('turn input JSON matches the protocol', () {
    expect(input.toJson(), {
      'conversation_id': null,
      'input': {'type': 'text', 'text': 'kino'},
      'language': 'uz',
      'utc_offset_minutes': 300,
      'voice_reply': false,
    });
    final audio = TurnInput.audio(conversationId: 'c1', base64: 'AA==', format: 'm4a', language: 'ru');
    expect(audio.toJson()['input'], {'type': 'audio', 'format': 'm4a', 'data': 'AA=='});
    expect(audio.toJson()['voice_reply'], isTrue);
    expect(input.withConversation('c2').toJson()['conversation_id'], 'c2');
  });

  test('streams events of one leg and ends on turn.paused', () async {
    server.on('POST', '/v1/turns', (req, _) => respondSse(req, [
          ('turn.started', ev({'conversation_id': 'c1', 'conversation_new': true})),
          ('text.delta', ev({'text': 'Qidiryapman'})),
          ('client_api_request', ev({'call_id': 'c_1', 'tool': 'cinemas.list', 'args': <String, Object?>{}})),
          pausedEvent,
          ('text.delta', ev({'text': 'never seen'})),
        ]));
    final events = await client.start(input).toList();
    expect(events.map((e) => e.runtimeType), [TurnStarted, TextDelta, ClientApiRequest, TurnPaused]);
    expect(server.requests.single.headers['authorization'], 'Bearer tok-0');
    expect((server.requests.single.json! as Map)['language'], 'uz');
  });

  test('retries once with a refreshed token on user_token_expired', () async {
    var calls = 0;
    server.on('POST', '/v1/turns', (req, _) {
      if (calls++ == 0) return respondJson(req, 401, {'code': 'user_token_expired', 'message': 'old'});
      return respondSse(req, [('done', ev({'outcome': 'answered'}))]);
    });
    final events = await client.start(input).toList();
    expect(events.single, isA<TurnDone>());
    expect(server.requests.last.headers['authorization'], 'Bearer tok-1');
  });

  test('does not retry twice', () async {
    server.on('POST', '/v1/turns', (req, _) => respondJson(req, 401, {'code': 'user_token_expired'}));
    final events = await client.start(input).toList();
    expect((events.single as TurnFailed).error.code, 'user_token_expired');
    expect(server.requests, hasLength(2));
  });

  test('stream closed before a terminal event is stream_interrupted', () async {
    server.on('POST', '/v1/turns', (req, _) => respondSse(req, [('text.delta', ev({'text': 'a'}))]));
    final events = await client.start(input).toList();
    expect(events.first, isA<TextDelta>());
    expect((events.last as TurnFailed).error.code, 'stream_interrupted');
  });

  test('no frame for pingTimeout is stream_interrupted', () async {
    server.on('POST', '/v1/turns', (req, _) => respondSse(req, [('text.delta', ev({'text': 'a'}))], close: false));
    final events = await client.start(input).toList().timeout(const Duration(seconds: 3));
    expect((events.last as TurnFailed).error.code, 'stream_interrupted');
  });

  test('cancelling during an open stream returns promptly', () async {
    server.on('POST', '/v1/turns', (req, _) => respondSse(req, [('text.delta', ev({'text': 'a'}))], close: false));
    final first = Completer<void>();
    final sub = client.start(input).listen((_) {
      if (!first.isCompleted) first.complete();
    });
    await first.future;
    await sub.cancel().timeout(const Duration(seconds: 1));
  });

  test('pings keep the stream alive', () async {
    server.on('POST', '/v1/turns', (req, _) => respondSse(
          req,
          [('ping', null), ('ping', null), ('ping', null), ('ping', null), ('done', ev({'outcome': 'answered'}))],
          gap: const Duration(milliseconds: 150),
        ));
    final events = await client.start(input).toList();
    expect(events.single, isA<TurnDone>());
  });

  test('broken known event is invalid_response', () async {
    server.on('POST', '/v1/turns', (req, _) => respondSse(req, [('text.delta', ev({'no_text': 1}))]));
    final events = await client.start(input).toList();
    expect((events.single as TurnFailed).error.code, 'invalid_response');
  });

  test('server error event ends the turn', () async {
    server.on('POST', '/v1/turns', (req, _) => respondSse(req, [
          ('error', ev({'error': {'code': 'llm_unavailable', 'message': 'down'}, 'retryable': true})),
        ]));
    final failed = (await client.start(input).toList()).single as TurnFailed;
    expect(failed.error.code, 'llm_unavailable');
    expect(failed.error.retryable, isTrue);
  });

  test('sendResults posts all results in one body', () async {
    server.on('POST', '/v1/turns/t1/tool-results', (req, _) => respondSse(req, [('done', ev({'outcome': 'answered'}))]));
    final events = await client.sendResults('t1', [
      ToolCallResult.ok('c_1', {'tours': []}),
      ToolCallResult.error('c_2', 'not_signed_in', 'Ask the user to sign in'),
    ], deadline: DateTime.now().add(const Duration(seconds: 30))).toList();
    expect(events.single, isA<TurnDone>());
    expect(server.requests.single.json, {
      'results': [
        {'call_id': 'c_1', 'ok': true, 'data': {'tours': []}},
        {'call_id': 'c_2', 'ok': false, 'error': {'code': 'not_signed_in', 'message': 'Ask the user to sign in'}},
      ],
    });
  });

  test('sendResults retries a network failure once before the deadline', () async {
    var calls = 0;
    server.on('POST', '/v1/turns/t1/tool-results', (HttpRequest req, _) {
      if (calls++ == 0) return dropConnection(req);
      return respondSse(req, [('done', ev({'outcome': 'answered'}))]);
    });
    final events = await client.sendResults('t1', [ToolCallResult.ok('c_1', 1)],
        deadline: DateTime.now().add(const Duration(seconds: 30))).toList();
    expect(events.single, isA<TurnDone>());
    expect(server.requests, hasLength(2));
  });

  test('sendResults does not retry after an HTTP status', () async {
    server.on('POST', '/v1/turns/t1/tool-results', (req, _) => respondJson(req, 500, {'code': 'internal_error'}));
    final events = await client.sendResults('t1', [ToolCallResult.ok('c_1', 1)],
        deadline: DateTime.now().add(const Duration(seconds: 30))).toList();
    expect((events.single as TurnFailed).error.code, 'internal_error');
    expect(server.requests, hasLength(1));
  });

  test('sendResults does not retry past the deadline', () async {
    server.on('POST', '/v1/turns/t1/tool-results', (HttpRequest req, _) => dropConnection(req));
    final events = await client.sendResults('t1', [ToolCallResult.ok('c_1', 1)],
        deadline: DateTime.now().add(const Duration(milliseconds: 10))).toList();
    expect((events.single as TurnFailed).error.code, 'network_error');
    expect(server.requests, hasLength(1));
  });

  test('a token source that throws becomes one TurnFailed', () async {
    final throwing = ZiTurnClient(api: ZiApiClient(baseUrl: server.url, info: info), tokens: () => ThrowingTokens());
    final events = await throwing.start(input).toList().timeout(const Duration(seconds: 2));
    expect((events.single as TurnFailed).error.code, 'network_error');
    expect((events.single as TurnFailed).error.retryable, isTrue);
  });

  test('no answer to the request is stream_interrupted', () async {
    server.on('POST', '/v1/turns', (req, _) async {
      await Future<void>.delayed(const Duration(seconds: 3));
    });
    final events = await client.start(input).toList().timeout(const Duration(seconds: 2));
    expect((events.single as TurnFailed).error.code, 'stream_interrupted');
  });
}
