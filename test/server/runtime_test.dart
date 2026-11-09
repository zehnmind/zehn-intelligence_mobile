import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zehn_intelligence/src/server/auth/file_store.dart';
import 'package:zehn_intelligence/src/server/auth/token_source.dart';
import 'package:zehn_intelligence/src/server/chat/chat_state.dart';
import 'package:zehn_intelligence/src/server/runtime.dart';
import 'package:zehn_intelligence/zehn_intelligence.dart' show ZiConfigException;

import '../support/bootstrap_fixture.dart';
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
      server.on('GET', '/v1/bootstrap', (req, _) => respondJson(req, 200, bootstrapJson()));
      expect((await create(userToken: () => 'u')).tokens, isA<CallbackTokenSource>());
      expect((await create()).tokens, isA<InstallTokenSource>());
    });

    test('create does not wait for the network', () async {
      server.on('GET', '/v1/bootstrap', (req, _) async {
        await Future<void>.delayed(const Duration(seconds: 2));
        await respondJson(req, 200, bootstrapJson());
      });
      final sw = Stopwatch()..start();
      final runtime = await create();
      expect(sw.elapsedMilliseconds, lessThan(500));
      expect(runtime.api.specVersion, '1.0.0');
    });

    test('cached start-up data sets the language when the device one is not offered', () async {
      server.on('GET', '/v1/bootstrap', (req, _) => respondJson(req, 500, {}));
      await store.write('bootstrap', {...bootstrapJson(), 'languages': ['uz', 'xx'], 'default_language': 'uz'});
      final runtime = await create();
      expect(runtime.language, 'uz');
      runtime.language = 'ru';
      expect(runtime.language, 'ru');
    });

    test('setUserToken switches to the app token; clearUser resets the chat and goes back', () async {
      server.on('GET', '/v1/bootstrap', (req, _) => respondJson(req, 200, bootstrapJson()));
      final runtime = await create();
      runtime.setUserToken(() => 'user-1');
      expect(await runtime.tokens.token(), 'user-1');
      runtime.chat.showError('x');
      await runtime.clearUser();
      expect(runtime.chat.state, const ZiChatState());
      expect(runtime.tokens, isA<InstallTokenSource>());
    });
  });
}
