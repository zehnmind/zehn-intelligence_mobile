import 'package:flutter_test/flutter_test.dart';
import 'package:zehn_intelligence/src/server/api/api_client.dart';
import 'package:zehn_intelligence/src/server/auth/token_source.dart';
import 'package:zehn_intelligence/src/server/chat/chat_state.dart';
import 'package:zehn_intelligence/src/server/chat/history.dart';

import '../../support/fake_server.dart';
import '../../support/test_info.dart';

/// `GET /v1/conversations/{id}` as the backend answers it (runtime/history.py).
Map<String, Object?> conversationJson({bool canContinue = true}) => {
  'conversation_id': '6f1c0000-0000-4000-8000-000000000001',
  'title': 'Where is the cinema?',
  'created_at': '2026-11-06T09:12:03Z',
  'last_turn_at': '2026-11-06T09:14:40Z',
  'spec_version': '1.2.0',
  'can_continue': canContinue,
  'messages': [
    {'role': 'user', 'type': 'text', 'text': 'Where is the cinema?', 'spoken': true, 'turn_id': 't1', 'at': '2026-11-06T09:12:03Z'},
    {'role': 'assistant', 'type': 'text', 'text': 'On the 4th floor.', 'turn_id': 't1', 'at': '2026-11-06T09:12:05Z'},
    {
      'role': 'assistant',
      'type': 'component',
      'component': 'cinema_card',
      'kind': 'inline',
      'props': {'name': 'Cinematica'},
      'surface': {'createSurface': <String, Object?>{}},
      'turn_id': 't1',
      'at': '2026-11-06T09:12:05Z',
    },
    // The live chat opened these instead of showing them; history doesn't open them again.
    {'role': 'assistant', 'type': 'component', 'component': 'loyalty_page', 'kind': 'route', 'props': <String, Object?>{}, 'route': '/loyalty'},
    {'role': 'assistant', 'type': 'component', 'component': 'map_sheet', 'kind': 'sheet', 'props': <String, Object?>{}},
    {'role': 'user', 'type': 'text', 'text': 'Reserve parking', 'spoken': false},
    {
      'role': 'assistant',
      'type': 'confirm',
      'action_id': 'a-1',
      'tool': 'parking.reserve',
      'surface': {'createSurface': <String, Object?>{}},
      'props': {'zone': 'B1'},
      'status': 'confirmed',
      'confirm_label': 'Reserve',
    },
    {'role': 'assistant', 'type': 'confirm', 'action_id': 'a-2', 'tool': 'parking.reserve', 'props': <String, Object?>{}, 'status': 'pending'},
    {'role': 'assistant', 'type': 'reaction', 'text': 'a type this SDK does not know'},
    {'role': 'user', 'type': 'text', 'text': ''},
  ],
};

void main() {
  group('reading the answers', () {
    test('a conversation summary', () {
      final s = ZiConversationSummary.fromJson(conversationJson(canContinue: false));
      expect(s.id, '6f1c0000-0000-4000-8000-000000000001');
      expect(s.title, 'Where is the cinema?');
      expect(s.createdAt, DateTime.utc(2026, 11, 6, 9, 12, 3));
      expect(s.lastTurnAt, DateTime.utc(2026, 11, 6, 9, 14, 40));
      expect(s.canContinue, isFalse);
    });

    test('a page skips entries without an id', () {
      final page = ZiConversationPage.fromJson({
        'items': [
          conversationJson(),
          {'title': 'no id'},
          'not a map',
        ],
        'total': 7,
        'page': 1,
        'size': 20,
      });
      expect(page.items.map((s) => s.id), ['6f1c0000-0000-4000-8000-000000000001']);
      expect(page.total, 7);
    });

    test('a conversation reads back as the chat showed it', () {
      final c = ZiConversation.fromJson(conversationJson());
      expect(c.summary.title, 'Where is the cinema?');
      expect(c.items, [
        const ZiUserItem('Where is the cinema?', spoken: true),
        const ZiAssistantItem('h1', 'On the 4th floor.'),
        const ZiComponentItem(
          'h2',
          'cinema_card',
          ZiComponentKind.inline,
          {'name': 'Cinematica'},
          surface: {'createSurface': <String, Object?>{}},
        ),
        const ZiUserItem('Reserve parking'),
        const ZiConfirmItem(
          actionId: 'a-1',
          tool: 'parking.reserve',
          method: '',
          surface: {'createSurface': <String, Object?>{}},
          data: {'zone': 'B1'},
          label: 'Reserve',
          status: ZiConfirmStatus.confirmed,
        ),
        const ZiConfirmItem(actionId: 'a-2', tool: 'parking.reserve', method: ''),
      ]);
    });

    test('anything broken reads as an empty conversation, not a crash', () {
      final c = ZiConversation.fromJson({'conversation_id': 'c1', 'messages': 'nope'});
      expect(c.summary.id, 'c1');
      expect(c.summary.title, '');
      expect(c.summary.canContinue, isFalse);
      expect(c.items, isEmpty);
    });
  });

  group('the calls', () {
    late FakeServer server;
    late ZiHistory history;

    setUp(() async {
      server = await FakeServer.start();
      final api = ZiApiClient(baseUrl: server.url, info: info)..installId = '01234567-89ab-4def-8123-456789abcdef';
      history = ZiHistory(api: api, tokens: () => const AnonymousTokenSource());
    });

    tearDown(() => server.close());

    test('the list asks for a page as this install', () async {
      server.on('GET', '/v1/conversations', (req, _) => respondJson(req, 200, {
            'items': [conversationJson()],
            'total': 21,
            'page': 2,
            'size': 20,
          }));
      final page = await history.list(page: 2);
      expect(page.items.single.title, 'Where is the cinema?');
      expect(page.total, 21);
      final req = server.requests.single;
      expect(req.query, {'page': '2', 'size': '20'});
      expect(req.headers['x-zi-install-id'], '01234567-89ab-4def-8123-456789abcdef');
      expect(req.headers.containsKey('authorization'), isFalse);
    });

    test('one conversation', () async {
      server.on('GET', '/v1/conversations/c1', (req, _) => respondJson(req, 200, conversationJson()));
      final c = await history.read('c1');
      expect(c.items.first, const ZiUserItem('Where is the cinema?', spoken: true));
    });

    test('delete', () async {
      server.on('DELETE', '/v1/conversations/c1', (req, _) async {
        req.response.statusCode = 204;
        await req.response.close();
      });
      await history.delete('c1');
      expect(server.requests.single.method, 'DELETE');
    });

    test('an error keeps its code', () async {
      server.on('GET', '/v1/conversations/c9', (req, _) => respondJson(req, 404, {'code': 'conversation_not_found', 'message': 'No'}));
      await expectLater(
        history.read('c9'),
        throwsA(isA<ZiApiException>().having((e) => e.code, 'code', 'conversation_not_found')),
      );
    });

    test('an app user token is sent, and refreshed once when the server says it expired', () async {
      var calls = 0;
      server.on('GET', '/v1/conversations', (req, rec) {
        calls++;
        return rec.headers['authorization'] == 'Bearer fresh'
            ? respondJson(req, 200, {'items': <Object>[], 'total': 0, 'page': 1, 'size': 20})
            : respondJson(req, 401, {'code': 'user_token_expired'});
      });
      final tokens = ['old', 'fresh'];
      final source = CallbackTokenSource(() => tokens.removeAt(0));
      final api = ZiApiClient(baseUrl: server.url, info: info);
      await ZiHistory(api: api, tokens: () => source).list();
      expect(calls, 2);
    });
  });
}
