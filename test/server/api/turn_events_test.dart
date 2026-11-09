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
    expect(e.request, isNull);
  });

  test('client_api_request carries the customer request the server built', () {
    final e = event('client_api_request', {
      'call_id': 'c_1',
      'tool': 'stores.list',
      'args': {'page': 1},
      'request': {'method': 'GET', 'path': '/stores', 'query': {'page': '1'}},
    }) as ClientApiRequest;
    expect(e.request, {'method': 'GET', 'path': '/stores', 'query': {'page': '1'}});
    expect(e.actionId, isNull);
  });

  test('a write carries the action the user confirmed, on the event or in its request', () {
    final top = event('client_api_request', {
      'call_id': 'c_2',
      'tool': 'parking.reserve',
      'action_id': 'a1',
      'request': {'method': 'POST', 'path': '/r'},
    }) as ClientApiRequest;
    expect(top.actionId, 'a1');
    final inner = event('client_api_request', {
      'call_id': 'c_2',
      'tool': 'parking.reserve',
      'request': {'method': 'POST', 'path': '/r', 'action_id': 'a2'},
    }) as ClientApiRequest;
    expect(inner.actionId, 'a2');
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

  test('confirm parses the card, its action and its expiry', () {
    final e = event('confirm', {
      'call_id': 'c2',
      'action_id': '6f1d',
      'tool': 'parking.reserve',
      'method': 'post',
      'surface': {'createSurface': <String, Object?>{}},
      'props': {'zone_id': 12},
      'confirm_label': 'Reserve',
      'expires_in': 600,
    }) as ConfirmEvent;
    expect(e.actionId, '6f1d');
    expect(e.tool, 'parking.reserve');
    expect(e.method, 'POST');
    expect(e.surface, {'createSurface': <String, Object?>{}});
    expect(e.props, {'zone_id': 12});
    expect(e.confirmLabel, 'Reserve');
    expect(e.expiresIn, const Duration(seconds: 600));
    final bare = event('confirm', {'action_id': 'a2'}) as ConfirmEvent;
    expect(bare.method, 'POST');
    expect(bare.props, isEmpty);
    expect(bare.confirmLabel, isNull);
    expect(bare.expiresIn, const Duration(seconds: 600));
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
