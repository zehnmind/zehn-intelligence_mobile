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
        'zi_spec_version': '1.0.3',
      });
      expect(c.appKey, 'zi_prod_file');
      expect(c.consoleUrl, Uri.parse('https://console.example'));
      expect(c.specVersion, '1.0.3');
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
      config: ZiInitConfig(appKey: 'zi_test_abc', consoleUrl: server.url, specVersion: '1.0.0'),
      info: info,
      userToken: userToken == null ? null : () => userToken() as String?,
      store: store,
    );

    test('create with userToken uses CallbackTokenSource, without it InstallTokenSource', () async {
      expect((await create(userToken: () => 'u')).tokens, isA<CallbackTokenSource>());
      expect((await create()).tokens, isA<InstallTokenSource>());
    });

    test('create makes no network call', () async {
      final runtime = await create();
      expect(server.requests, isEmpty);
      expect(runtime.api.specVersion, '1.0.0');
      expect(runtime.settings.value.services, isEmpty);
    });

    test('the starter suggestions bring the chat settings', () async {
      server.on('GET', '/v1/suggestions', (req, _) => respondJson(req, 200, {
            'suggestions': ['Salom'],
            'chat': {
              'languages': ['uz', 'xx'],
              'default_language': 'uz',
              'services': ['llm', 'stt'],
              'welcome_title': 'Salom!',
              'spec_version': 'v7',
            },
          }));
      final runtime = await create(userToken: () => 'u');
      // Before the settings: the phone's language if the SDK knows it.
      expect(runtime.language, 'en');
      await runtime.chat.loadStarterSuggestions();
      expect(runtime.chat.state.suggestions, ['Salom']);
      expect(runtime.settings.value.welcomeTitle, 'Salom!');
      expect(runtime.settings.value.speech, isTrue);
      expect(runtime.api.specVersion, 'v7');
      // The phone's language is not offered: the default one.
      expect(runtime.language, 'uz');
      runtime.language = 'ru';
      expect(runtime.language, 'ru');
    });

    test('suggestions without chat settings keep the ones it has', () async {
      server.on('GET', '/v1/suggestions', (req, _) => respondJson(req, 200, {'suggestions': ['Hi']}));
      final runtime = await create(userToken: () => 'u');
      await runtime.chat.loadStarterSuggestions();
      expect(runtime.chat.state.suggestions, ['Hi']);
      expect(runtime.api.specVersion, '1.0.0');
    });

    test('setUserToken switches to the app token; clearUser resets the chat and goes back', () async {
      final runtime = await create();
      runtime.setUserToken(() => 'user-1');
      expect(await runtime.tokens.token(), 'user-1');
      runtime.chat.showError('x');
      await runtime.clearUser();
      expect(runtime.chat.state, const ZiChatState());
      expect(runtime.tokens, isA<InstallTokenSource>());
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
        ClientApiRequest(callId: 'c1', tool: 'loyalty_cards.get', args: const {}, http: {
          'method': 'GET',
          'path': '/loyalty/cards/my',
          'auth': true,
          'base_url': server.url.toString(),
        }),
      ]);
      expect(results.single.errorCode, 'not_signed_in');
      expect(server.requests, isEmpty);
    });

    test('the chat answers the tool runner\'s questions', () async {
      final runtime = await create();
      expect(runtime.tools.confirmer, isNotNull);
    });
  });
}
