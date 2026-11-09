import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zehn_intelligence/src/server/api/api_client.dart';
import 'package:zehn_intelligence/src/server/auth/file_store.dart';
import 'package:zehn_intelligence/src/server/auth/token_source.dart';

import '../../support/fake_server.dart';
import '../../support/test_info.dart';

void main() {
  late FakeServer server;
  late ZiApiClient api;
  late Directory dir;
  late ZiFileStore store;
  var issued = 0;

  setUp(() async {
    issued = 0;
    server = await FakeServer.start();
    api = ZiApiClient(baseUrl: server.url, info: info);
    dir = await Directory.systemTemp.createTemp('zi_tokens');
    store = ZiFileStore(() async => dir);
    server.on('POST', '/v1/installs', (req, _) {
      issued++;
      return respondJson(req, 200, {'token': 'install-$issued', 'token_type': 'Bearer', 'expires_in': 3600});
    });
  });

  tearDown(() async {
    await server.close();
    await dir.delete(recursive: true);
  });

  test('install token is fetched once and cached', () async {
    final source = InstallTokenSource(api: api, store: store);
    expect(await source.token(), 'install-1');
    expect(await source.token(), 'install-1');
    expect(server.requests, hasLength(1));
    final id = (server.requests.single.json! as Map)['install_id'] as String;
    expect(id, matches(RegExp(r'^[0-9a-f]{32}$')));
  });

  test('a new source on the same store reuses the saved token', () async {
    await InstallTokenSource(api: api, store: store).token();
    expect(await InstallTokenSource(api: api, store: store).token(), 'install-1');
    expect(server.requests, hasLength(1));
  });

  test('install_id survives refresh and a new source', () async {
    final first = InstallTokenSource(api: api, store: store);
    await first.token();
    expect(await InstallTokenSource(api: api, store: store).refresh(), 'install-2');
    final ids = server.requests.map((r) => (r.json! as Map)['install_id']).toSet();
    expect(ids, hasLength(1));
  });

  test('expired token is fetched again', () async {
    var now = DateTime.utc(2026, 11, 9, 10);
    final source = InstallTokenSource(api: api, store: store, now: () => now);
    await source.token();
    now = now.add(const Duration(hours: 2));
    expect(await source.token(), 'install-2');
  });

  test('callback source caches and refreshes', () async {
    var calls = 0;
    final source = CallbackTokenSource(() => 'user-${++calls}');
    expect(await source.token(), 'user-1');
    expect(await source.token(), 'user-1');
    expect(await source.refresh(), 'user-2');
    expect(await source.token(), 'user-2');
  });

  test('callback null throws user_token_required', () async {
    final source = CallbackTokenSource(() => null);
    await expectLater(
      source.token(),
      throwsA(isA<ZiApiException>().having((e) => e.code, 'code', 'user_token_required')),
    );
  });

  test('corrupt file reads as null', () async {
    await File('${dir.path}/install.json').writeAsString('{oops');
    expect(await store.read('install'), isNull);
  });

  test('store round-trips and deletes', () async {
    await store.write('x', {'a': 1});
    expect(await store.read('x'), {'a': 1});
    await store.delete('x');
    expect(await store.read('x'), isNull);
  });
}
