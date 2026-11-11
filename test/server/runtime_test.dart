import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zehn_intelligence/src/server/api/api_client.dart';
import 'package:zehn_intelligence/src/server/api/turn_events.dart';
import 'package:zehn_intelligence/src/server/auth/file_store.dart';
import 'package:zehn_intelligence/src/server/auth/token_source.dart';
import 'package:zehn_intelligence/src/server/chat/chat_state.dart';
import 'package:zehn_intelligence/src/server/proxy/tool_runner.dart';
import 'package:zehn_intelligence/src/server/runtime.dart';
import 'package:zehn_intelligence/src/server/ui/chat_sheet.dart' show ZiComponentBuilder;
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
        await respondJson(req, 200, {'assistant_name': 'Mall guide'});
      });
      final sw = Stopwatch()..start();
      final runtime = await create();
      expect(sw.elapsedMilliseconds, lessThan(500));
      expect(runtime.settings.value.assistantName, isNull);
      await runtime.loadConfig();
      expect(runtime.settings.value.assistantName, 'Mall guide');
      expect(server.requests.where((r) => r.path == '/v1/config'), hasLength(1));
    });

    test('every console call carries the same install id and no spec version', () async {
      server.on('GET', '/v1/config', (req, _) => respondJson(req, 200, {}));
      await (await create()).loadConfig();
      await (await create()).loadConfig();
      final ids = {for (final r in server.requests) r.headers['x-zi-install-id']};
      expect(ids.single, matches(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')));
      expect(server.requests.any((r) => r.headers.containsKey('x-zi-spec-version')), isFalse);
      expect(server.requests.any((r) => r.path == '/v1/installs'), isFalse);
    });

    test('the config sets the chat settings and the language', () async {
      server.on('GET', '/v1/config', (req, _) => respondJson(req, 200, {
            'languages': ['uz', 'xx'],
            'default_language': 'uz',
            'assistant_name': 'Mall guide',
            'copy': {'welcome_title': {'uz': 'Salom!'}},
          }));
      final runtime = await create();
      // Before the config: the phone's language if the SDK knows it.
      expect(runtime.language, 'en');
      await runtime.loadConfig();
      expect(runtime.available.value, isTrue);
      expect(runtime.settings.value.assistantName, 'Mall guide');
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
      server.on('GET', '/v1/config', (req, _) => fail ? respondJson(req, 503, {}) : respondJson(req, 200, {'assistant_name': 'Mall guide'}));
      final runtime = await create();
      await runtime.loadConfig();
      fail = true;
      await runtime.loadConfig();
      expect(runtime.available.value, isTrue);
      expect(runtime.settings.value.assistantName, 'Mall guide');
    });

    group('a sign-out in the app, seen through its Dio', () {
      late Dio app;
      String? login;

      setUp(() {
        login = null;
        server.on('GET', '/orders', (req, _) => respondJson(req, 200, []));
        server.on('GET', '/v1/suggestions', (req, _) => respondJson(req, 200, {'suggestions': []}));
        server.on('GET', '/v1/config', (req, _) => respondJson(req, 200, {}));
        app = Dio(BaseOptions(baseUrl: server.url.toString()))
          ..interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
            if (login != null) options.headers['Authorization'] = 'Bearer $login';
            handler.next(options);
          }));
      });

      Future<ZiRuntime> startWithDio() => ZiRuntime.create(
        config: ZiInitConfig(appKey: 'zi_test_abc', consoleUrl: server.url),
        info: info,
        client: app,
        store: store,
      );

      String? installIdOf(RecordedRequest request) => request.headers['x-zi-install-id'];

      Future<String?> idSentNow(ZiRuntime runtime) async {
        server.requests.clear();
        await runtime.api.getJson('/v1/suggestions');
        return installIdOf(server.requests.singleWhere((r) => r.path == '/v1/suggestions'));
      }

      test('somebody else signing in is a new install: a new install id, an empty chat', () async {
        final runtime = await startWithDio();
        final first = await idSentNow(runtime);
        runtime.chat.showError('something_from_the_last_person');
        expect(runtime.chat.state.items, isNotEmpty);

        login = 'token-A';
        await app.get<Object?>('/orders');
        await runtime.signOutIdle;
        expect(await idSentNow(runtime), first, reason: 'a first sign-in is not a sign-out');
        expect(runtime.chat.state.items, isNotEmpty);

        login = 'token-B';
        await app.get<Object?>('/orders');
        await runtime.signOutIdle;
        final second = await idSentNow(runtime);
        expect(second, isNot(first));
        expect(second, await loadInstallId(store), reason: 'and kept, for the next launch');
        expect(runtime.chat.state.items, isEmpty);
      });

      test('the check before the chat opens notices a sign-out with no other request', () async {
        final runtime = await startWithDio();
        login = 'token-A';
        await app.get<Object?>('/orders');
        await runtime.signOutIdle;
        final before = await idSentNow(runtime);
        runtime.chat.showError('something_from_the_last_person');

        login = null; // signed out; the app made no request since
        await runtime.checkUser();
        expect(await idSentNow(runtime), isNot(before));
        expect(runtime.chat.state.items, isEmpty);

        // Asked again, with still nobody: nothing changes.
        final after = await idSentNow(runtime);
        await runtime.checkUser();
        expect(await idSentNow(runtime), after);
      });

      test('the check never sends anything to the app\'s server', () async {
        final runtime = await startWithDio();
        login = 'token-A';
        server.requests.clear();
        await runtime.checkUser();
        expect(server.requests.where((r) => r.path != '/v1/config'), isEmpty);
      });

      test('with no Dio of the app\'s there is nothing to watch, and nothing breaks', () async {
        final runtime = await create();
        await runtime.checkUser();
        expect(runtime.available.value, isTrue);
      });
    });

    group('the config between starts', () {
      const config = {
        'assistant_name': 'Mall guide',
        'button': {
          'show_on': 'except',
          'paths': ['/', '/auth'],
        },
      };

      // The address of a server that is gone: its port can't be read once it is closed.
      Future<ZiRuntime> createAt(Uri url) =>
          ZiRuntime.create(config: ZiInitConfig(appKey: 'zi_test_abc', consoleUrl: url), info: info, store: store);

      test('a first start has no config in hand, so no button, until the server answers', () async {
        server.on('GET', '/v1/config', (req, _) async {
          await Future<void>.delayed(const Duration(milliseconds: 200));
          await respondJson(req, 200, config);
        });
        final runtime = await create();
        expect(runtime.hasConfig.value, isFalse);
        expect(runtime.showsButtonOn('/home'), isFalse);
        await runtime.loadConfig();
        expect(runtime.hasConfig.value, isTrue);
        expect(runtime.showsButtonOn('/home'), isTrue);
        expect(runtime.showsButtonOn('/auth'), isFalse);
        expect(runtime.showsButtonOn('/'), isFalse);
        // A screen that isn't known.
        expect(runtime.showsButtonOn(null), isTrue);
      });

      test('a first start with no network: no config, no button', () async {
        final url = server.url;
        await server.close();
        final runtime = await createAt(url);
        await runtime.loadConfig();
        expect(runtime.hasConfig.value, isFalse);
        expect(runtime.showsButtonOn('/home'), isFalse);
        // The app's own button can still try to open the chat.
        expect(runtime.available.value, isTrue);
      });

      test('the last good config is kept in a file and used at the next start, before the server answers', () async {
        server.on('GET', '/v1/config', (req, _) => respondJson(req, 200, config));
        final url = server.url;
        await (await create()).loadConfig();

        server.on('GET', '/v1/config', (req, _) async {
          await Future<void>.delayed(const Duration(milliseconds: 200));
          await respondJson(req, 200, {
            'assistant_name': 'City guide',
            'button': {
              'show_on': 'only',
              'paths': ['/home'],
            },
          });
        });
        final next = await create();
        expect(next.hasConfig.value, isTrue);
        expect(next.settings.value.assistantName, 'Mall guide');
        expect(next.showsButtonOn('/auth'), isFalse);
        expect(next.showsButtonOn('/profile'), isTrue);

        // Refreshed in the background: what the console published since.
        await next.loadConfig();
        expect(next.settings.value.assistantName, 'City guide');
        expect(next.showsButtonOn('/profile'), isFalse);
        await server.close();
        expect((await createAt(url)).settings.value.assistantName, 'City guide');
      });

      test('a start with no network, or a server that fails, keeps the saved config', () async {
        server.on('GET', '/v1/config', (req, _) => respondJson(req, 200, config));
        final url = server.url;
        await (await create()).loadConfig();

        server.on('GET', '/v1/config', (req, _) => respondJson(req, 503, {}));
        final failing = await create();
        await failing.loadConfig();
        expect(failing.hasConfig.value, isTrue);
        expect(failing.showsButtonOn('/auth'), isFalse);
        expect(failing.showsButtonOn('/home'), isTrue);

        await server.close();
        final offline = await createAt(url);
        await offline.loadConfig();
        expect(offline.settings.value.assistantName, 'Mall guide');
        expect(offline.showsButtonOn('/auth'), isFalse);
        expect(offline.showsButtonOn('/home'), isTrue);
      });

      test('404 spec_not_found hides the button and deletes the saved config', () async {
        server.on('GET', '/v1/config', (req, _) => respondJson(req, 200, config));
        await (await create()).loadConfig();
        expect(await store.read('config'), isNotNull);

        server.on('GET', '/v1/config', (req, _) => respondJson(req, 404, {'code': 'spec_not_found'}));
        final unpublished = await create();
        expect(unpublished.showsButtonOn('/home'), isTrue);
        await unpublished.loadConfig();
        expect(unpublished.available.value, isFalse);
        expect(unpublished.showsButtonOn('/home'), isFalse);
        expect(await store.read('config'), isNull);

        final next = await create();
        expect(next.hasConfig.value, isFalse);
      });

      test('a refused key or app hides the button, deletes the saved config and is not asked again until the next start', () async {
        const refused = {
          'invalid_key': 401,
          'key_revoked': 401,
          'app_mismatch': 401,
          'invalid_header': 400,
          'app_disabled': 403,
        };
        for (final MapEntry(key: code, value: status) in refused.entries) {
          server.on('GET', '/v1/config', (req, _) => respondJson(req, 200, config));
          await (await create()).loadConfig();
          expect(await store.read('config'), isNotNull, reason: code);

          server.requests.clear();
          server.on('GET', '/v1/config', (req, _) => respondJson(req, status, {'code': code}));
          final refusedRuntime = await create();
          await refusedRuntime.loadConfig();
          expect(refusedRuntime.available.value, isFalse, reason: code);
          expect(refusedRuntime.showsButtonOn('/home'), isFalse, reason: code);
          expect(await store.read('config'), isNull, reason: code);

          // Not asked for again by a return to the foreground, only by the next start.
          server.requests.clear();
          await refusedRuntime.retryConfig();
          expect(server.requests, isEmpty, reason: code);
          expect((await create()).hasConfig.value, isFalse, reason: code);
        }
      });

      test('the same answer to a call of the chat hides it too, whichever call that is', () async {
        server.on('GET', '/v1/config', (req, _) => respondJson(req, 200, config));
        final runtime = await create();
        await runtime.loadConfig();
        expect(runtime.showsButtonOn('/home'), isTrue);

        server.on('GET', '/v1/suggestions', (req, _) => respondJson(req, 403, {'code': 'app_disabled'}));
        await expectLater(runtime.api.getJson('/v1/suggestions'), throwsA(isA<ZiApiException>()));
        expect(runtime.available.value, isFalse);
        expect(runtime.showsButtonOn('/home'), isFalse);
        // The kept config goes too, a moment later (a file is deleted).
        for (var i = 0; i < 100 && await store.read('config') != null; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        expect(await store.read('config'), isNull);
      });

      test('an answer that is not about the build leaves the button as it is', () async {
        server.on('GET', '/v1/config', (req, _) => respondJson(req, 200, config));
        final runtime = await create();
        await runtime.loadConfig();
        server.on('GET', '/v1/suggestions', (req, _) => respondJson(req, 429, {'code': 'user_rate_limited'}));
        await expectLater(runtime.api.getJson('/v1/suggestions'), throwsA(isA<ZiApiException>()));
        expect(runtime.available.value, isTrue);
        expect(runtime.showsButtonOn('/home'), isTrue);
      });

      test('a config saved for another key or another server is not this build\'s', () async {
        server.on('GET', '/v1/config', (req, _) => respondJson(req, 200, config));
        await (await create()).loadConfig();
        server.on('GET', '/v1/config', (req, _) => respondJson(req, 503, {}));

        final otherKey = await ZiRuntime.create(
          config: ZiInitConfig(appKey: 'zi_prod_abc', consoleUrl: server.url),
          info: info,
          store: store,
        );
        expect(otherKey.hasConfig.value, isFalse);
        final otherServer = await ZiRuntime.create(
          config: ZiInitConfig(appKey: 'zi_test_abc', consoleUrl: Uri.parse('http://127.0.0.1:9')),
          info: info,
          store: store,
        );
        expect(otherServer.hasConfig.value, isFalse);
        expect((await create()).hasConfig.value, isTrue);
      });

      test('a saved file that is broken is no config', () async {
        await File('${dir.path}/config.json').writeAsString('{"for": 7, "config": "nope"');
        expect((await create()).hasConfig.value, isFalse);
        await store.write('config', {'config': config});
        expect((await create()).hasConfig.value, isFalse);
      });

      test('the file is written again only when the config changed', () async {
        final counting = _CountingStore(dir);
        var name = 'Mall guide';
        server.on('GET', '/v1/config', (req, _) => respondJson(req, 200, {'assistant_name': name}));
        final runtime = await ZiRuntime.create(
          config: ZiInitConfig(appKey: 'zi_test_abc', consoleUrl: server.url),
          info: info,
          store: counting,
        );
        await runtime.loadConfig();
        await runtime.loadConfig();
        expect(counting.writes['config'], 1);
        name = 'City guide';
        await runtime.loadConfig();
        expect(counting.writes['config'], 2);
      });

      test('back in the foreground, the config is asked for again only if the last try failed', () async {
        var fail = true;
        server.on('GET', '/v1/config', (req, _) => fail ? respondJson(req, 503, {}) : respondJson(req, 200, config));
        int asked() => server.requests.where((r) => r.path == '/v1/config').length;

        final runtime = await create();
        await runtime.loadConfig();
        expect(asked(), 1);
        expect(runtime.hasConfig.value, isFalse);

        await runtime.retryConfig();
        expect(asked(), 2);
        expect(runtime.hasConfig.value, isFalse);

        fail = false;
        await runtime.retryConfig();
        expect(asked(), 3);
        expect(runtime.hasConfig.value, isTrue);
        expect(runtime.showsButtonOn('/home'), isTrue);

        // It loaded: the next foreground asks for nothing.
        await runtime.retryConfig();
        expect(asked(), 3);
      });

      test('nothing published is not a failure to try again from the foreground', () async {
        server.on('GET', '/v1/config', (req, _) => respondJson(req, 404, {'code': 'spec_not_found'}));
        final runtime = await create();
        await runtime.loadConfig();
        await runtime.retryConfig();
        expect(server.requests.where((r) => r.path == '/v1/config'), hasLength(1));
      });
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

    test('the history is this install\'s; clearUser makes a new install id, so the next person sees none of it', () async {
      server.on('GET', '/v1/conversations', (req, _) => respondJson(req, 200, {'items': <Object>[], 'total': 0, 'page': 1, 'size': 20}));
      final runtime = await create();
      final before = runtime.api.installId;
      await runtime.history.list();
      await runtime.clearUser();
      await runtime.history.list();
      final sent = [for (final r in server.requests.where((r) => r.path == '/v1/conversations')) r.headers['x-zi-install-id']];
      expect(sent.first, before);
      expect(sent.last, isNot(before));
      expect(sent.last, runtime.api.installId);
      expect(sent.last, matches(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')));
      // Kept for the next launch.
      expect((await create()).api.installId, sent.last);
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

    test('a turn names what the app registered, and a call with no request runs the app\'s handler', () async {
      Map<String, Object?> ev(int seq, Map<String, Object?> data) => {'turn_id': 't1', 'seq': seq, ...data};
      server.on('POST', '/v1/turns', (req, _) => respondSse(req, [
            ('turn.started', ev(1, {'conversation_id': 'c1', 'conversation_new': true})),
            ('client_api_request', ev(2, {'call_id': 'c_1', 'tool': 'map.locate', 'args': {'target': 'Zara'}})),
            (
              'turn.paused',
              ev(3, {
                'call_ids': ['c_1'],
                'deadline': '2030-01-01T00:00:00Z',
                'expires_in': 60,
                'max_result_bytes': 32768,
              }),
            ),
          ]));
      server.on('POST', '/v1/turns/t1/tool-results', (req, _) => respondSse(req, [('done', ev(4, {'outcome': 'answered'}))]));

      final handlers = <String, ZiToolHandler>{
        'map.locate': (args) async => {'name': args['target'], 'floor': 1},
      };
      final builders = <String, ZiComponentBuilder>{};
      final runtime = await ZiRuntime.create(
        config: ZiInitConfig(appKey: 'zi_test_abc', consoleUrl: server.url),
        info: info,
        handlers: handlers,
        builders: builders,
        store: store,
      );
      // Registered after the start: named from the next turn on.
      builders['map_spot'] = (context, props, controller) => const SizedBox.shrink();

      await runtime.chat.sendText('Zara qayerda?');

      final turn = server.requests.firstWhere((r) => r.path == '/v1/turns').json! as Map;
      expect(turn['tools'], ['map.locate']);
      expect(turn['components'], ['map_spot']);
      final results = server.requests.firstWhere((r) => r.path == '/v1/turns/t1/tool-results').json! as Map;
      expect(results['results'], [
        {'call_id': 'c_1', 'ok': true, 'data': {'name': 'Zara', 'floor': 1}},
      ]);
    });

    test('the tool runner checks writes against what the user confirmed in the chat', () async {
      final runtime = await create();
      expect(runtime.tools.takeConfirmed, isNotNull);
      expect(runtime.tools.takeConfirmed!('a1'), isFalse);
    });
  });
}

/// Counts the writes of each file.
class _CountingStore extends ZiFileStore {
  _CountingStore(Directory dir) : super(() async => dir);

  final Map<String, int> writes = {};

  @override
  Future<void> write(String name, Map<String, Object?> json) {
    writes[name] = (writes[name] ?? 0) + 1;
    return super.write(name, json);
  }
}
