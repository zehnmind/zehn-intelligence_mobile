import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zehn_intelligence/src/server/bootstrap/bootstrap.dart';
import 'package:zehn_intelligence/src/server/proxy/proxy_executor.dart';
import 'package:zehn_intelligence/zehn_intelligence.dart' show ZiToolError;

import '../../support/bootstrap_fixture.dart';
import '../../support/fake_server.dart';
import 'request_builder_test.dart' show ctx, toolError;

const cinema = ZiHttpTool(method: 'GET', path: '/cinematica/');
const card = ZiHttpTool(method: 'GET', path: '/loyalty/cards/my', auth: true);

void main() {
  late FakeServer server;
  late ZiBootstrap boot;

  setUp(() async {
    server = await FakeServer.start();
    boot = ZiBootstrap.fromJson(bootstrapJson(baseUrl: server.url.toString()));
    server.on('GET', '/cinematica/', (req, _) => respondJson(req, 200, {'id': 1, 'name': 'Cinematica'}));
  });

  tearDown(() => server.close());

  test('callbacks mode adds Bearer and Accept-Language', () async {
    final proxy = ZiProxyExecutor(accessToken: () => 'demo');
    expect(await proxy.call(cinema, {}, boot, ctx), {'id': 1, 'name': 'Cinematica'});
    final h = server.requests.single.headers;
    expect(h['authorization'], 'Bearer demo');
    expect(h['accept-language'], 'ru');
  });

  test('result rule trims the answer', () async {
    server.on('GET', '/location/venues', (req, _) => respondJson(req, 200, {
          'results': [
            {'public_id': 'a', 'name': 'A', 'floor': '1', 'phone': 'x'},
          ],
        }));
    final proxy = ZiProxyExecutor();
    final out = await proxy.call(boot.tools['stores.list']!, {'page': 1}, boot, ctx);
    expect(out, [
      {'public_id': 'a', 'name': 'A', 'floor': '1'},
    ]);
    expect(server.requests.single.query, {'page': '1'});
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
    expect(await proxy.call(card, {}, boot, ctx), {'points': 10});
    expect(refreshes, 1);
    expect(server.requests, hasLength(2));
  });

  test('401 twice is not_signed_in', () async {
    server.on('GET', '/loyalty/cards/my', (req, _) => respondJson(req, 401, {}));
    final proxy = ZiProxyExecutor(accessToken: () => 't', onUnauthorized: () => true);
    await expectLater(proxy.call(card, {}, boot, ctx), toolError('not_signed_in'));
    expect(server.requests, hasLength(2));
  });

  test('auth tool without login is not_signed_in with no request', () async {
    await expectLater(ZiProxyExecutor().call(card, {}, boot, ctx), toolError('not_signed_in'));
    await expectLater(ZiProxyExecutor(accessToken: () => null).call(card, {}, boot, ctx), toolError('not_signed_in'));
    expect(server.requests, isEmpty);
  });

  test('no base URL in callbacks mode is host_not_allowed', () async {
    final json = bootstrapJson();
    (json['api']! as Map).remove('base_url');
    await expectLater(
      ZiProxyExecutor().call(cinema, {}, ZiBootstrap.fromJson(json), ctx),
      toolError('host_not_allowed'),
    );
  });

  test('baseUrlOverride wins over the console base URL', () async {
    final json = bootstrapJson(baseUrl: 'https://not-used.example');
    final proxy = ZiProxyExecutor(baseUrlOverride: server.url);
    expect(await proxy.call(cinema, {}, ZiBootstrap.fromJson(json), ctx), isNotNull);
  });

  test('client mode uses the app Dio base URL and adds no auth header', () async {
    final app = Dio(BaseOptions(baseUrl: server.url.toString()))
      ..interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
        o.headers['X-From-App'] = 'yes';
        h.next(o);
      }));
    final proxy = ZiProxyExecutor(appClient: app, accessToken: () => 'ignored');
    expect(await proxy.call(cinema, {}, boot, ctx), {'id': 1, 'name': 'Cinematica'});
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
    final proxy = ZiProxyExecutor(appClient: app);
    await expectLater(proxy.call(card, {}, boot, ctx), toolError('not_signed_in'));
    expect(seen, 1);
    expect(server.requests, hasLength(1));
  });

  test('non-JSON body becomes handler_failed', () async {
    server.on('GET', '/cinematica/', (req, _) => respondText(req, 200, '<html>maintenance</html>'));
    await expectLater(ZiProxyExecutor().call(cinema, {}, boot, ctx), toolError('handler_failed'));
  });

  test('empty body is null', () async {
    server.on('GET', '/cinematica/', (req, _) => respondText(req, 200, '', type: 'application/json'));
    expect(await ZiProxyExecutor().call(cinema, {}, boot, ctx), isNull);
  });

  test('500 is http_error with status in message', () async {
    server.on('GET', '/cinematica/', (req, _) => respondText(req, 500, 'boom'));
    await expectLater(
      ZiProxyExecutor().call(cinema, {}, boot, ctx),
      throwsA(isA<ZiToolError>().having((e) => e.code, 'code', 'http_error').having((e) => e.message, 'message', contains('500'))),
    );
  });

  test('slow answer is timeout', () async {
    server.on('GET', '/cinematica/', (req, _) async {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      await respondJson(req, 200, {});
    });
    final proxy = ZiProxyExecutor(timeout: const Duration(milliseconds: 100));
    await expectLater(proxy.call(cinema, {}, boot, ctx), toolError('timeout'));
  });

  test('closed server is network_error', () async {
    final url = server.url.toString();
    await server.close();
    final dead = ZiBootstrap.fromJson(bootstrapJson(baseUrl: url));
    await expectLater(ZiProxyExecutor().call(cinema, {}, dead, ctx), toolError('network_error'));
  });
}
