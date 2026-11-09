import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:zehn_intelligence/src/server/api/api_client.dart';

import '../../support/fake_server.dart';
import '../../support/test_info.dart';

void main() {
  late FakeServer server;
  late ZiApiClient api;

  setUp(() async {
    server = await FakeServer.start();
    api = ZiApiClient(baseUrl: server.url, info: info);
  });

  tearDown(() => server.close());

  Future<ZiApiException> failure(Future<Object?> call) async {
    try {
      await call;
    } on ZiApiException catch (e) {
      return e;
    }
    fail('expected a ZiApiException');
  }

  test('sends every X-ZI header', () async {
    server.on('GET', '/v1/suggestions', (req, _) => respondJson(req, 200, {'suggestions': []}));
    api.specVersion = '1.0.3';
    await api.getJson('/v1/suggestions', userToken: 't');
    final h = server.requests.single.headers;
    expect(h['authorization'], 'Bearer t');
    expect(h['x-zi-app-key'], 'zi_test_abc');
    expect(h['x-zi-package'], 'uz.example.app');
    expect(h['x-zi-app-version'], '1.2.0+5');
    expect(h['x-zi-spec-version'], '1.0.3');
    expect(h['x-zi-sdk-version'], '0.4.0');
    expect(h['x-zi-platform'], 'ios');
  });

  test('omits spec and auth headers when unknown', () async {
    server.on('GET', '/v1/suggestions', (req, _) => respondJson(req, 200, {}));
    await api.getJson('/v1/suggestions');
    final h = server.requests.single.headers;
    expect(h.containsKey('authorization'), isFalse);
    expect(h.containsKey('x-zi-spec-version'), isFalse);
  });

  test('getJson passes the query', () async {
    server.on('GET', '/v1/suggestions', (req, _) => respondJson(req, 200, {'suggestions': ['a']}));
    final body = await api.getJson('/v1/suggestions', query: {'language': 'uz'});
    expect(server.requests.single.query['language'], 'uz');
    expect(body, {'suggestions': ['a']});
  });

  test('maps error body to code', () async {
    server.on('POST', '/v1/installs', (req, _) => respondJson(req, 401, {
          'code': 'user_token_expired',
          'i18n_key': 'errors.user_token_expired',
          'params': <String, Object?>{},
          'message': 'm',
        }));
    final e = await failure(api.postJson('/v1/installs', {'install_id': 'x'}));
    expect(e.code, 'user_token_expired');
    expect(e.status, 401);
    expect(e.message, 'm');
    expect(e.retryable, isFalse);
  });

  test('422 is invalid_request', () async {
    server.on('POST', '/v1/installs', (req, _) => respondJson(req, 422, {'detail': []}));
    final e = await failure(api.postJson('/v1/installs', {}));
    expect(e.code, 'invalid_request');
    expect(e.retryable, isFalse);
  });

  test('unknown 5xx is retryable', () async {
    server.on('GET', '/v1/suggestions', (req, _) => respondJson(req, 503, {'message': 'busy'}));
    final e = await failure(api.getJson('/v1/suggestions'));
    expect(e.code, 'internal_error');
    expect(e.status, 503);
    expect(e.retryable, isTrue);
  });

  test('non-JSON 502 is server_unavailable', () async {
    server.on('GET', '/v1/suggestions', (req, _) => respondText(req, 502, '<html>Bad gateway</html>'));
    final e = await failure(api.getJson('/v1/suggestions'));
    expect(e.code, 'server_unavailable');
    expect(e.retryable, isTrue);
  });

  test('connection refused is network_error with null status', () async {
    final url = server.url;
    await server.close();
    final dead = ZiApiClient(baseUrl: url, info: info);
    final e = await failure(dead.getJson('/v1/suggestions'));
    expect(e.code, 'network_error');
    expect(e.status, isNull);
    expect(e.retryable, isTrue);
  });

  test('postStream returns the event stream', () async {
    server.on('POST', '/v1/turns', (req, _) => respondSse(req, [('done', {'outcome': 'answered'})]));
    final body = await api.postStream('/v1/turns', {'a': 1}, userToken: 't');
    final text = await utf8.decoder.bind(body.stream).join();
    expect(text, contains('event: done'));
    expect(server.requests.single.json, {'a': 1});
  });

  test('postStream rejects non event-stream', () async {
    server.on('POST', '/v1/turns', (req, _) => respondText(req, 200, '<html>proxy</html>'));
    final e = await failure(api.postStream('/v1/turns', {}, userToken: 't'));
    expect(e.code, 'server_unavailable');
  });

  test('postStream maps a JSON error before the stream', () async {
    server.on('POST', '/v1/turns', (req, _) => respondJson(req, 409, {'code': 'turn_in_progress', 'message': 'busy'}));
    final e = await failure(api.postStream('/v1/turns', {}, userToken: 't'));
    expect(e.code, 'turn_in_progress');
    expect(e.status, 409);
  });

  test('a console URL with a path prefix keeps it', () async {
    server.on('GET', '/api/v1/suggestions', (req, _) => respondJson(req, 200, {}));
    final prefixed = ZiApiClient(baseUrl: server.url.replace(path: '/api/'), info: info);
    await prefixed.getJson('/v1/suggestions');
    expect(server.requests.single.path, '/api/v1/suggestions');
  });
}
