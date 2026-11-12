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
    api.installId = '01234567-89ab-4def-8123-456789abcdef';
    await api.getJson('/v1/suggestions', userToken: 't');
    final h = server.requests.single.headers;
    expect(h['authorization'], 'Bearer t');
    expect(h['x-zi-app-key'], 'zi_test_abc');
    expect(h['x-zi-package'], 'uz.example.app');
    expect(h['x-zi-app-version'], '1.2.0+5');
    expect(h['x-zi-install-id'], '01234567-89ab-4def-8123-456789abcdef');
    expect(h['x-zi-sdk-version'], '0.6.0');
    // With it the server treats the build as one that pins a spec.
    expect(h.containsKey('x-zi-spec-version'), isFalse);
    expect(h['x-zi-platform'], 'ios');
  });

  test('omits the auth header without a user token', () async {
    server.on('GET', '/v1/suggestions', (req, _) => respondJson(req, 200, {}));
    await api.getJson('/v1/suggestions');
    final h = server.requests.single.headers;
    expect(h.containsKey('authorization'), isFalse);
  });

  test('getJson passes the query', () async {
    server.on('GET', '/v1/suggestions', (req, _) => respondJson(req, 200, {'suggestions': ['a']}));
    final body = await api.getJson('/v1/suggestions', query: {'language': 'uz'});
    expect(server.requests.single.query['language'], 'uz');
    expect(body, {'suggestions': ['a']});
  });

  test('maps error body to code', () async {
    server.on('POST', '/v1/turns', (req, _) => respondJson(req, 401, {
          'code': 'user_token_expired',
          'i18n_key': 'errors.user_token_expired',
          'params': <String, Object?>{},
          'message': 'm',
        }));
    final e = await failure(api.postJson('/v1/turns', {'install_id': 'x'}));
    expect(e.code, 'user_token_expired');
    expect(e.status, 401);
    expect(e.message, 'm');
    expect(e.retryable, isFalse);
  });

  test('422 is invalid_request', () async {
    server.on('POST', '/v1/turns', (req, _) => respondJson(req, 422, {'detail': []}));
    final e = await failure(api.postJson('/v1/turns', {}));
    expect(e.code, 'invalid_request');
    expect(e.retryable, isFalse);
  });

  test('a 422 form_invalid keeps its code and the fields that failed', () async {
    server.on('POST', '/v1/turns', (req, _) => respondJson(req, 422, {
          'code': 'form_invalid',
          'message': 'm',
          'params': {'errors': [{'field': 'phone', 'rule': 'phone'}]},
        }));
    final e = await failure(api.postJson('/v1/turns', {}));
    expect((e.code, e.retryable), ('form_invalid', false));
    expect(e.params['errors'], [{'field': 'phone', 'rule': 'phone'}]);
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

  group('Retry-After', () {
    test('a 429 carries the wait the server asked for', () async {
      server.on('POST', '/v1/turns', (req, _) async {
        req.response.headers.set('retry-after', '42');
        await respondJson(req, 429, {'code': 'user_rate_limited', 'message': 'slow down'});
      });
      final e = await failure(api.postStream('/v1/turns', {}, userToken: 't'));
      expect(e.code, 'user_rate_limited');
      expect(e.status, 429);
      expect(e.retryAfter, const Duration(seconds: 42));
      expect(e.retryable, isFalse, reason: 'the SDK never retries by itself');
    });

    test('the same on a plain call, and with none it is null', () async {
      server.on('GET', '/v1/suggestions', (req, _) async {
        req.response.headers.set('Retry-After', '3600');
        await respondJson(req, 429, {'code': 'quota_exceeded'});
      });
      expect((await failure(api.getJson('/v1/suggestions'))).retryAfter, const Duration(hours: 1));
      server.on('GET', '/v1/suggestions', (req, _) => respondJson(req, 429, {'code': 'quota_exceeded'}));
      expect((await failure(api.getJson('/v1/suggestions'))).retryAfter, isNull);
    });

    test('whole seconds or an HTTP date; nothing else is a wait', () {
      final now = DateTime.utc(2026, 11, 11, 12);
      Duration? parse(String? text) => ZiApiException.parseRetryAfter(text, now: now);
      expect(parse('30'), const Duration(seconds: 30));
      expect(parse(' 7 '), const Duration(seconds: 7));
      expect(parse('Wed, 11 Nov 2026 12:01:00 GMT'), const Duration(minutes: 1));
      expect(parse('Wed, 11 Nov 2026 11:00:00 GMT'), isNull, reason: 'already past');
      for (final bad in [null, '', '0', '-5', 'soon', '1.5']) {
        expect(parse(bad), isNull, reason: '$bad');
      }
    });
  });

  group('an answer that means the assistant cannot be used', () {
    final cases = {
      'invalid_key': 401,
      'key_revoked': 401,
      'app_mismatch': 401,
      'invalid_header': 400,
      'app_disabled': 403,
      'spec_not_found': 404,
    };

    test('every one is reported, to whichever call it came', () async {
      final told = <String>[];
      api.onUnavailable = (e) => told.add(e.code);
      for (final MapEntry(key: code, value: status) in cases.entries) {
        server
          ..on('GET', '/v1/config', (req, _) => respondJson(req, status, {'code': code}))
          ..on('POST', '/v1/turns', (req, _) => respondJson(req, status, {'code': code}));
        expect((await failure(api.getJson('/v1/config'))).code, code);
        expect((await failure(api.postStream('/v1/turns', {}, userToken: 't'))).code, code);
      }
      expect(told, [for (final code in cases.keys) ...[code, code]]);
    });

    test('other errors are not reported', () async {
      final told = <String>[];
      api.onUnavailable = (e) => told.add(e.code);
      for (final (status, code) in [(401, 'user_token_expired'), (409, 'turn_in_progress'), (429, 'quota_exceeded'), (426, 'sdk_too_old'), (500, 'internal_error')]) {
        server.on('GET', '/v1/config', (req, _) => respondJson(req, status, {'code': code}));
        expect((await failure(api.getJson('/v1/config'))).code, code);
      }
      expect(told, isEmpty);
    });
  });

  test('a console URL with a path prefix keeps it', () async {
    server.on('GET', '/api/v1/suggestions', (req, _) => respondJson(req, 200, {}));
    final prefixed = ZiApiClient(baseUrl: server.url.replace(path: '/api/'), info: info);
    await prefixed.getJson('/v1/suggestions');
    expect(server.requests.single.path, '/api/v1/suggestions');
  });
}
