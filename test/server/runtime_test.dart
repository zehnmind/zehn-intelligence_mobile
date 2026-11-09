import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zehn_intelligence/src/server/api/turn_events.dart';
import 'package:zehn_intelligence/src/server/auth/file_store.dart';
import 'package:zehn_intelligence/src/server/auth/token_source.dart';
import 'package:zehn_intelligence/src/server/chat/chat_state.dart';
import 'package:zehn_intelligence/src/server/runtime.dart';
import 'package:zehn_intelligence/zehn_intelligence.dart' show ZiConfigException;

import '../support/fake_server.dart';
import '../support/test_info.dart';

void main() {
  group('resolveInitConfig', () {
    test('argument key wins over file and defines', () {
      final c = resolveInitConfig(
        token: 'zi_prod_arg',
        fileConfig: {'zi_app_key': 'zi_prod_file'},
        defines: {'zi_app_key': 'zi_prod_define'},
      );
      expect(c.appKey, 'zi_prod_arg');
    });

    test('file config is used when no argument', () {
      final c = resolveInitConfig(fileConfig: {
        'zi_app_key': 'zi_prod_file',
        'zi_console_url': 'https://console.example',
      });
      expect(c.appKey, 'zi_prod_file');
      expect(c.consoleUrl, Uri.parse('https://console.example'));
    });

    test('defines are the last fallback', () {
      final c = resolveInitConfig(defines: {'ZEHN_API_KEY': 'zi_test_define', 'ZEHN_INTELLIGENCE_CONFIG_URL': 'http://10.0.2.2:8040'});
      expect(c.appKey, 'zi_test_define');
      expect(c.consoleUrl, Uri.parse('http://10.0.2.2:8040'));
    });

    test('an argument console URL wins', () {
      final c = resolveInitConfig(token: 'k', consoleUrl: Uri.parse('http://localhost:8787'), fileConfig: {'zi_console_url': 'https://x'});
      expect(c.consoleUrl, Uri.parse('http://localhost:8787'));
    });

    test('default console URL', () {
      expect(resolveInitConfig(token: 'k').consoleUrl, Uri.parse('https://zi-console-api.zehnmind.com'));
    });

    test('no key throws ZiConfigException', () {
      expect(() => resolveInitConfig(defines: {'zi_app_key': ''}), throwsA(isA<ZiConfigException>()));
    });
  });

  group('ZiRuntime', () {
    late FakeServer server;
    late Directory dir;
    late ZiFileStore store;

    setUp(() async {
      server = await FakeServer.start();
      dir = await Directory.systemTemp.createTemp('zi_runtime');
      store = ZiFileStore(() async => dir);
    });

    tearDown(() async {
      ZiRuntime.instance = null;
      await server.close();
      await dir.delete(recursive: true);
    });

    Future<ZiRuntime> create({Object? Function()? userToken}) => ZiRuntime.create(
      config: ZiInitConfig(appKey: 'zi_test_abc', consoleUrl: server.url),
      info: info,
      userToken: userToken == null ? null : () => userToken() as String?,
      store: store,
    );

    test('create with userToken uses CallbackTokenSource, without it no token', () async {
      expect((await create(userToken: () => 'u')).tokens, isA<CallbackTokenSource>());
      expect((await create()).tokens, isA<AnonymousTokenSource>());
    });

    test('create asks for /v1/config in the background', () async {
      server.on('GET', '/v1/config', (req, _) async {
        await Future<void>.delayed(const Duration(milliseconds: 700));
        await respondJson(req, 200, {'services': ['stt']});
      });
      final sw = Stopwatch()..start();
      final runtime = await create();
      expect(sw.elapsedMilliseconds, lessThan(500));
      expect(runtime.settings.value.speech, isFalse);
      await runtime.loadConfig();
      expect(runtime.settings.value.speech, isTrue);
      expect(server.requests.where((r) => r.path == '/v1/config'), hasLength(1));
    });

    test('every console call carries the same install id and no spec version', () async {
      server.on('GET', '/v1/config', (req, _) => respondJson(req, 200, {}));
      await (await create()).loadConfig();
      await (await create()).loadConfig();
      final ids = {for (final r in server.requests) r.headers['x-zi-install-id']};
      expect(ids.single, matches(RegExp(r'^[0-9a-f]{32}$')));
      expect(server.requests.any((r) => r.headers.containsKey('x-zi-spec-version')), isFalse);
      expect(server.requests.any((r) => r.path == '/v1/installs'), isFalse);
    });

    test('the config sets the chat settings and the language', () async {
      server.on('GET', '/v1/config', (req, _) => respondJson(req, 200, {
            'languages': ['uz', 'xx'],
            'default_language': 'uz',
            'services': ['llm', 'stt'],
            'copy': {'welcome_title': {'uz': 'Salom!'}},
          }));
      final runtime = await create();
      // Before the config: the phone's language if the SDK knows it.
      expect(runtime.language, 'en');
      await runtime.loadConfig();
      expect(runtime.available.value, isTrue);
      expect(runtime.settings.value.speech, isTrue);
      // The phone's language is not offered: the default one.
      expect(runtime.language, 'uz');
      expect(runtime.settings.value.welcomeTitle(runtime.language), 'Salom!');
      runtime.language = 'ru';
      expect(runtime.language, 'ru');
    });

    test('404 spec_not_found hides the assistant', () async {
      server.on('GET', '/v1/config', (req, _) => respondJson(req, 404, {'code': 'spec_not_found'}));
      final runtime = await create();
      await runtime.loadConfig();
      expect(runtime.available.value, isFalse);
    });

    test('a config that fails for another reason keeps the assistant and its last settings', () async {
      var fail = false;
      server.on('GET', '/v1/config', (req, _) => fail ? respondJson(req, 503, {}) : respondJson(req, 200, {'services': ['stt']}));
      final runtime = await create();
      await runtime.loadConfig();
      fail = true;
      await runtime.loadConfig();
      expect(runtime.available.value, isTrue);
      expect(runtime.settings.value.speech, isTrue);
    });

    test('the starter suggestions are only suggestions', () async {
      server.on('GET', '/v1/suggestions', (req, _) => respondJson(req, 200, {'suggestions': ['Hi']}));
      final runtime = await create(userToken: () => 'u');
      await runtime.chat.loadStarterSuggestions();
      expect(runtime.chat.state.suggestions, ['Hi']);
    });

    test('setUserToken switches to the app token; clearUser resets the chat and goes back', () async {
      final runtime = await create();
      runtime.setUserToken(() => 'user-1');
      expect(await runtime.tokens.token(), 'user-1');
      runtime.chat.showError('x');
      await runtime.clearUser();
      expect(runtime.chat.state, const ZiChatState());
      expect(runtime.tokens, isA<AnonymousTokenSource>());
    });

    test('isSignedIn false keeps login-only tools from being called', () async {
      final runtime = await ZiRuntime.create(
        config: ZiInitConfig(appKey: 'zi_test_abc', consoleUrl: server.url),
        info: info,
        accessToken: () => 't',
        isSignedIn: () => false,
        store: store,
      );
      final results = await runtime.tools.runAll([
        ClientApiRequest(callId: 'c1', tool: 'loyalty_cards.get', args: const {}, request: {
          'method': 'GET',
          'path': '/loyalty/cards/my',
          'auth': true,
          'base_url': server.url.toString(),
        }),
      ]);
      expect(results.single.errorCode, 'not_signed_in');
      expect(server.requests, isEmpty);
    });

    test('the tool runner checks writes against what the user confirmed in the chat', () async {
      final runtime = await create();
      expect(runtime.tools.takeConfirmed, isNotNull);
      expect(runtime.tools.takeConfirmed!('a1'), isFalse);
    });
  });
}
