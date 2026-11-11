import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zehn_intelligence/src/server/proxy/http_call.dart';
import 'package:zehn_intelligence/src/server/proxy/proxy_executor.dart';
import 'package:zehn_intelligence/zehn_intelligence.dart' show ZiToolError;

import '../../support/fake_server.dart';
import 'http_call_test.dart' show toolError;

void main() {
  late FakeServer server;

  setUp(() async {
    server = await FakeServer.start();
    server.on('GET', '/cinematica/', (req, _) => respondJson(req, 200, {'id': 1, 'name': 'Cinematica'}));
  });

  tearDown(() => server.close());

  ZiHttpCall get(String path, {bool auth = false, ZiResultRule? result, Map<String, String> query = const {}}) => ZiHttpCall(
    method: 'GET',
    path: path,
    query: query,
    headers: const {'Accept-Language': 'ru'},
    auth: auth,
    result: result,
    baseUrl: server.url,
  );

  test('callbacks mode adds Bearer and the request headers', () async {
    final proxy = ZiProxyExecutor(accessToken: () => 'demo');
    expect(await proxy.call(get('/cinematica/')), {'id': 1, 'name': 'Cinematica'});
    final h = server.requests.single.headers;
    expect(h['authorization'], 'Bearer demo');
    expect(h['accept-language'], 'ru');
  });

  test('the query and the result rule are applied', () async {
    server.on('GET', '/location/venues', (req, _) => respondJson(req, 200, {
          'results': [
            {'public_id': 'a', 'name': 'A', 'phone': 'x'},
          ],
        }));
    final out = await ZiProxyExecutor().call(get(
      '/location/venues',
      query: {'page': '1'},
      result: const ZiResultRule(root: '/results', fields: ['public_id', 'name']),
    ));
    expect(out, [
      {'public_id': 'a', 'name': 'A'},
    ]);
    expect(server.requests.single.query, {'page': '1'});
  });

  test('a list in the query repeats the key', () async {
    server.on('GET', '/stores', (req, _) => respondJson(req, 200, []));
    await ZiProxyExecutor().call(ZiHttpCall(
      method: 'GET',
      path: '/stores',
      query: const {'tag': ['food', 'kids'], 'page': '1'},
      baseUrl: server.url,
    ));
    expect(server.requests.single.queryAll, {'tag': ['food', 'kids'], 'page': ['1']});
  });

  test('the app client repeats the key too', () async {
    server.on('GET', '/stores', (req, _) => respondJson(req, 200, []));
    await ZiProxyExecutor(appClient: Dio(BaseOptions(baseUrl: server.url.toString())))
        .call(const ZiHttpCall(method: 'GET', path: '/stores', query: {'tag': ['food', 'kids']}));
    expect(server.requests.single.queryAll['tag'], ['food', 'kids']);
  });

  test('a renamed login header is used', () async {
    final call = ZiHttpCall(method: 'GET', path: '/cinematica/', authHeader: 'X-Token', authScheme: '', baseUrl: server.url);
    await ZiProxyExecutor(accessToken: () => 'abc').call(call);
    expect(server.requests.single.headers['x-token'], 'abc');
  });

  test('401 calls onUnauthorized once then retries', () async {
    var token = 'old';
    var refreshes = 0;
    server.on('GET', '/loyalty/cards/my', (req, rec) {
      if (rec.headers['authorization'] != 'Bearer new') return respondJson(req, 401, {'detail': 'expired'});
      return respondJson(req, 200, {'points': 10});
    });
    final proxy = ZiProxyExecutor(
      accessToken: () => token,
      onUnauthorized: () {
        refreshes++;
        token = 'new';
        return true;
      },
    );
    expect(await proxy.call(get('/loyalty/cards/my', auth: true)), {'points': 10});
    expect(refreshes, 1);
    expect(server.requests, hasLength(2));
  });

  test('401 twice is not_signed_in', () async {
    server.on('GET', '/loyalty/cards/my', (req, _) => respondJson(req, 401, {}));
    final proxy = ZiProxyExecutor(accessToken: () => 't', onUnauthorized: () => true);
    await expectLater(proxy.call(get('/loyalty/cards/my', auth: true)), toolError('not_signed_in'));
    expect(server.requests, hasLength(2));
  });

  test('auth call without login is not_signed_in with no request', () async {
    await expectLater(ZiProxyExecutor().call(get('/loyalty/cards/my', auth: true)), toolError('not_signed_in'));
    await expectLater(ZiProxyExecutor(accessToken: () => null).call(get('/loyalty/cards/my', auth: true)), toolError('not_signed_in'));
    expect(server.requests, isEmpty);
  });

  test('isSignedIn false keeps an auth call from being made, even through the app client', () async {
    final app = Dio(BaseOptions(baseUrl: server.url.toString()));
    final proxy = ZiProxyExecutor(appClient: app, isSignedIn: () => false);
    await expectLater(proxy.call(get('/loyalty/cards/my', auth: true)), toolError('not_signed_in'));
    expect(server.requests, isEmpty);
  });

  test('isSignedIn does not block public calls', () async {
    expect(await ZiProxyExecutor(isSignedIn: () => false).call(get('/cinematica/')), isNotNull);
  });

  test('no base URL in callbacks mode is host_not_allowed', () async {
    await expectLater(
      ZiProxyExecutor().call(const ZiHttpCall(method: 'GET', path: '/cinematica/')),
      toolError('host_not_allowed'),
    );
  });

  test('the app apiBaseUrl wins over the server base URL', () async {
    final call = ZiHttpCall(method: 'GET', path: '/cinematica/', baseUrl: Uri.parse('https://not-used.example'));
    expect(await ZiProxyExecutor(baseUrlOverride: server.url).call(call), isNotNull);
  });

  test('a plain http base URL from the server is refused unless it is this machine', () async {
    final remote = ZiHttpCall(method: 'GET', path: '/x', baseUrl: Uri.parse('http://api.example.invalid'));
    await expectLater(ZiProxyExecutor().call(remote), toolError('host_not_allowed'));
    // server.url is http://127.0.0.1, which is allowed.
    expect(await ZiProxyExecutor().call(get('/cinematica/')), isNotNull);
  });

  test('client mode uses the app Dio base URL and adds no auth header', () async {
    final app = Dio(BaseOptions(baseUrl: server.url.toString()))
      ..interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
        o.headers['X-From-App'] = 'yes';
        h.next(o);
      }));
    const call = ZiHttpCall(method: 'GET', path: '/cinematica/', headers: {'Accept-Language': 'ru'});
    expect(await ZiProxyExecutor(appClient: app, accessToken: () => 'ignored').call(call), {'id': 1, 'name': 'Cinematica'});
    final h = server.requests.single.headers;
    expect(h['x-from-app'], 'yes');
    expect(h.containsKey('authorization'), isFalse);
    expect(h['accept-language'], 'ru');
  });

  test('client mode lets the app interceptor see a 401', () async {
    var seen = 0;
    server.on('GET', '/loyalty/cards/my', (req, _) => respondJson(req, 401, {}));
    final app = Dio(BaseOptions(baseUrl: server.url.toString()))
      ..interceptors.add(InterceptorsWrapper(onError: (e, h) {
        if (e.response?.statusCode == 401) seen++;
        h.next(e);
      }));
    await expectLater(
      ZiProxyExecutor(appClient: app).call(const ZiHttpCall(method: 'GET', path: '/loyalty/cards/my', auth: true)),
      toolError('not_signed_in'),
    );
    expect(seen, 1);
  });

  test('POST sends the JSON body with its content type', () async {
    server.on('POST', '/parking/reservations', (req, _) => respondJson(req, 201, {'id': 'r1'}));
    final call = ZiHttpCall(method: 'POST', path: '/parking/reservations', body: const {'zone_id': 7, 'hours': 2}, baseUrl: server.url);
    expect(await ZiProxyExecutor().call(call), {'id': 'r1'});
    final rec = server.requests.single;
    expect(rec.method, 'POST');
    expect(rec.json, {'zone_id': 7, 'hours': 2});
    expect(rec.headers['content-type'], contains('application/json'));
  });

  test('the app client sends the body too', () async {
    server.on('POST', '/parking/reservations', (req, _) => respondJson(req, 200, {'ok': true}));
    final proxy = ZiProxyExecutor(appClient: Dio(BaseOptions(baseUrl: server.url.toString())));
    await proxy.call(const ZiHttpCall(method: 'POST', path: '/parking/reservations', body: {'zone_id': 3}));
    expect(server.requests.single.json, {'zone_id': 3});
  });

  test('a 204 with no body is null', () async {
    server.on('DELETE', '/r/x9', (req, _) async {
      req.response.statusCode = 204;
      await req.response.close();
    });
    expect(await ZiProxyExecutor().call(ZiHttpCall(method: 'DELETE', path: '/r/x9', baseUrl: server.url)), isNull);
  });

  test('non-JSON body becomes handler_failed', () async {
    server.on('GET', '/cinematica/', (req, _) => respondText(req, 200, '<html>maintenance</html>'));
    await expectLater(ZiProxyExecutor().call(get('/cinematica/')), toolError('handler_failed'));
  });

  group('what the model reads when the app\'s server does not answer well', () {
    Matcher fails(String code, {Object? message}) => throwsA(
      isA<ZiToolError>().having((e) => e.code, 'code', code).having((e) => e.message, 'message', message ?? isNotEmpty),
    );

    test('a 401 and a 403 are not_signed_in', () async {
      server
        ..on('GET', '/a', (req, _) => respondJson(req, 401, {}))
        ..on('GET', '/b', (req, _) => respondJson(req, 403, {'message': 'Forbidden'}));
      for (final path in ['/a', '/b']) {
        await expectLater(
          ZiProxyExecutor().call(get(path)),
          fails('not_signed_in', message: 'The user is not signed in to the app'),
          reason: path,
        );
      }
    });

    test('a 404 is not_found', () async {
      server.on('GET', '/gone', (req, _) => respondJson(req, 404, {'message': 'No such venue'}));
      await expectLater(ZiProxyExecutor().call(get('/gone')), fails('not_found', message: 'Not found'));
    });

    test('another 4xx is handler_failed with the answer\'s short message', () async {
      server
        ..on('GET', '/bad', (req, _) => respondJson(req, 422, {'message': 'zone_id is required'}))
        ..on('GET', '/detail', (req, _) => respondJson(req, 400, {'detail': 'Hours must be 1 to 8'}))
        ..on('GET', '/mute', (req, _) => respondText(req, 409, 'conflict', type: 'text/plain'));
      await expectLater(
        ZiProxyExecutor().call(get('/bad')),
        fails('handler_failed', message: "The app's server answered 422: zone_id is required"),
      );
      await expectLater(
        ZiProxyExecutor().call(get('/detail')),
        fails('handler_failed', message: "The app's server answered 400: Hours must be 1 to 8"),
      );
      await expectLater(ZiProxyExecutor().call(get('/mute')), fails('handler_failed', message: "The app's server answered 409"));
    });

    test('a long message is left out', () async {
      server.on('GET', '/long', (req, _) => respondJson(req, 400, {'message': 'x' * 300}));
      await expectLater(ZiProxyExecutor().call(get('/long')), fails('handler_failed', message: "The app's server answered 400"));
    });

    test('a 5xx is handler_failed with the status only', () async {
      server.on('GET', '/boom', (req, _) => respondJson(req, 503, {'message': 'database password is hunter2'}));
      await expectLater(ZiProxyExecutor().call(get('/boom')), fails('handler_failed', message: "The app's server answered 503"));
      server.on('GET', '/boom', (req, _) => respondText(req, 500, 'boom'));
      await expectLater(ZiProxyExecutor().call(get('/boom')), fails('handler_failed', message: contains('500')));
    });

    test('the same through the app\'s own client', () async {
      server
        ..on('GET', '/gone', (req, _) => respondJson(req, 404, {}))
        ..on('GET', '/denied', (req, _) => respondJson(req, 403, {}))
        ..on('GET', '/bad', (req, _) => respondJson(req, 400, {'message': 'Bad zone'}))
        ..on('GET', '/boom', (req, _) => respondJson(req, 502, {}));
      final proxy = ZiProxyExecutor(appClient: Dio(BaseOptions(baseUrl: server.url.toString())));
      Future<Object?> app(String path) => proxy.call(ZiHttpCall(method: 'GET', path: path));
      await expectLater(app('/gone'), fails('not_found'));
      await expectLater(app('/denied'), fails('not_signed_in'));
      await expectLater(app('/bad'), fails('handler_failed', message: "The app's server answered 400: Bad zone"));
      await expectLater(app('/boom'), fails('handler_failed', message: "The app's server answered 502"));
    });
  });

  test("the SDK's requests are marked for the app's interceptors", () async {
    final seen = <Object?>[];
    final app = Dio(BaseOptions(baseUrl: server.url.toString()))
      ..interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
        seen.add(o.extra['zi']);
        h.next(o);
      }));
    await ZiProxyExecutor(appClient: app).call(const ZiHttpCall(method: 'GET', path: '/cinematica/'));
    expect(seen, [true]);
  });

  test('the time a call may take is the one it is given, not the executor\'s own', () async {
    server.on('GET', '/cinematica/', (req, _) async {
      await Future<void>.delayed(const Duration(milliseconds: 400));
      await respondJson(req, 200, {'late': true});
    });
    final proxy = ZiProxyExecutor(timeout: const Duration(milliseconds: 100));
    await expectLater(proxy.call(get('/cinematica/')), toolError('timeout'));
    expect(await proxy.call(get('/cinematica/'), timeout: const Duration(seconds: 5)), {'late': true});
  });

  test('slow answer is timeout', () async {
    server.on('GET', '/cinematica/', (req, _) async {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      await respondJson(req, 200, {});
    });
    await expectLater(
      ZiProxyExecutor(timeout: const Duration(milliseconds: 100)).call(get('/cinematica/')),
      toolError('timeout'),
    );
  });

  test('a server that cannot be reached is handler_failed', () async {
    final call = get('/cinematica/');
    await server.close();
    await expectLater(
      ZiProxyExecutor().call(call),
      throwsA(
        isA<ZiToolError>()
            .having((e) => e.code, 'code', 'handler_failed')
            .having((e) => e.message, 'message', "The app's server is unreachable"),
      ),
    );
  });
}
