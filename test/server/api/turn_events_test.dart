import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:zehn_intelligence/src/server/api/sse.dart';
import 'package:zehn_intelligence/src/server/api/turn_events.dart';

TurnEvent? event(String name, Map<String, Object?> data) =>
    TurnEvent.fromFrame(SseFrame(event: name, data: jsonEncode({'turn_id': 't1', 'seq': 4, ...data})));

void main() {
  test('text.delta parses text and seq', () {
    final e = event('text.delta', {'text': 'Salom'}) as TextDelta;
    expect(e.text, 'Salom');
    expect(e.seq, 4);
    expect(e.turnId, 't1');
  });

  test('turn.started parses the conversation', () {
    final e = event('turn.started', {'conversation_id': 'c9', 'conversation_new': true}) as TurnStarted;
    expect(e.conversationId, 'c9');
    expect(e.conversationNew, isTrue);
  });

  test('client_api_request parses args map', () {
    final e = event('client_api_request', {
      'call_id': 'c_1',
      'tool': 'stores.list',
      'args': {'page': 1, 'size': 10},
    }) as ClientApiRequest;
    expect(e.callId, 'c_1');
    expect(e.tool, 'stores.list');
    expect(e.args, {'page': 1, 'size': 10});
    expect(e.http, isNull);
  });

  test('client_api_request carries the customer request the server built', () {
    final e = event('client_api_request', {
      'call_id': 'c_1',
      'tool': 'stores.list',
      'args': {'page': 1},
      'http': {'method': 'GET', 'path': '/stores', 'query': {'page': '1'}},
    }) as ClientApiRequest;
    expect(e.http, {'method': 'GET', 'path': '/stores', 'query': {'page': '1'}});
  });

  test('mount_component parses kind and props', () {
    final e = event('mount_component', {
      'call_id': 'm1',
      'component': 'cinema_details',
      'kind': 'inline',
      'props': {'id': 1},
    }) as MountComponent;
    expect(e.component, 'cinema_details');
    expect(e.kind, 'inline');
    expect(e.props, {'id': 1});
    expect(e.surface, isNull);
    expect(e.route, isNull);
  });

  test('mount_component carries the card template, or the route, inline', () {
    final card = event('mount_component', {
      'call_id': 'm1',
      'component': 'cinema_card',
      'kind': 'inline',
      'props': {'name': 'Cinematica'},
      'surface': {'root': 'r', 'components': [{'id': 'r', 'component': 'Text', 'text': {'path': '/name'}}]},
    }) as MountComponent;
    expect(card.surface, {'root': 'r', 'components': [{'id': 'r', 'component': 'Text', 'text': {'path': '/name'}}]});
    final page = event('mount_component', {
      'component': 'loyalty_page',
      'kind': 'route',
      'route': '/loyalty',
    }) as MountComponent;
    expect(page.route, '/loyalty');
    expect(page.surface, isNull);
  });

  test('turn.paused parses deadline as DateTime', () {
    final e = event('turn.paused', {
      'call_ids': ['c_1', 'c_2'],
      'deadline': '2026-11-09T10:00:00Z',
      'expires_in': 60,
      'max_result_bytes': 32768,
    }) as TurnPaused;
    expect(e.callIds, ['c_1', 'c_2']);
    expect(e.deadline, DateTime.utc(2026, 11, 9, 10));
    expect(e.maxResultBytes, 32768);
  });

  test('audio, suggestions, transcript and done parse', () {
    final audio = event('audio', {'format': 'mp3', 'text': 'Hi', 'data': 'AAA='}) as AudioClip;
    expect(audio.data, 'AAA=');
    expect((event('suggestions', {'items': ['a', 'b']}) as SuggestionsEvent).items, ['a', 'b']);
    expect((event('transcript', {'text': 'kino', 'language': 'uz'}) as TranscriptEvent).text, 'kino');
    expect((event('done', {'outcome': 'answered'}) as TurnDone).outcome, 'answered');
  });

  test('error event becomes TurnFailed with code and retryable', () {
    final e = event('error', {
      'error': {'code': 'llm_unavailable', 'i18n_key': 'k', 'params': <String, Object?>{}, 'message': 'down'},
      'retryable': true,
    }) as TurnFailed;
    expect(e.error.code, 'llm_unavailable');
    expect(e.error.retryable, isTrue);
    expect(e.error.message, 'down');
  });

  test('ping frame is a PingEvent', () {
    expect(TurnEvent.fromFrame(const SseFrame(event: 'ping', data: '')), isA<PingEvent>());
  });

  test('unknown event type returns null', () {
    expect(event('surface.update', {'x': 1}), isNull);
  });

  test('unknown fields are ignored', () {
    final e = event('text.delta', {'text': 'a', 'future_field': [1, 2]});
    expect(e, isA<TextDelta>());
  });

  test('text.delta without text throws FormatException', () {
    expect(() => event('text.delta', {}), throwsFormatException);
  });

  test('data that is not JSON throws FormatException', () {
    expect(() => TurnEvent.fromFrame(const SseFrame(event: 'done', data: '{oops')), throwsFormatException);
  });
}
