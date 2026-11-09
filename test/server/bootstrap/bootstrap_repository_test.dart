import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zehn_intelligence/src/server/api/api_client.dart';
import 'package:zehn_intelligence/src/server/auth/file_store.dart';
import 'package:zehn_intelligence/src/server/bootstrap/bootstrap_repository.dart';

import '../../support/bootstrap_fixture.dart';
import '../../support/fake_server.dart';
import '../../support/test_info.dart';

void main() {
  late FakeServer server;
  late ZiApiClient api;
  late Directory dir;
  late ZiFileStore store;

  setUp(() async {
    server = await FakeServer.start();
    api = ZiApiClient(baseUrl: server.url, info: info);
    dir = await Directory.systemTemp.createTemp('zi_boot');
    store = ZiFileStore(() async => dir);
  });

  tearDown(() async {
    await server.close();
    await dir.delete(recursive: true);
  });

  test('refresh saves and sets specVersion', () async {
    server.on('GET', '/v1/bootstrap', (req, _) => respondJson(req, 200, bootstrapJson()));
    final repo = ZiBootstrapRepository(api: api, store: store);
    final b = await repo.refresh();
    expect(b!.specVersion, '1.0.3');
    expect(repo.current, same(b));
    expect(api.specVersion, '1.0.3');
    expect(server.requests.single.headers.containsKey('authorization'), isFalse);
    final again = ZiBootstrapRepository(api: api, store: store);
    expect((await again.loadCached())!.tools, hasLength(2));
  });

  test('network failure keeps cached data', () async {
    await store.write('bootstrap', bootstrapJson());
    server.on('GET', '/v1/bootstrap', (req, _) => respondJson(req, 500, {'code': 'internal_error'}));
    final repo = ZiBootstrapRepository(api: api, store: store);
    await repo.loadCached();
    final b = await repo.refresh();
    expect(b, isNotNull);
    expect(repo.current!.specVersion, '1.0.3');
    expect(api.specVersion, '1.0.3');
  });

  test('refresh with nothing cached and no network is null', () async {
    server.on('GET', '/v1/bootstrap', (req, _) => respondJson(req, 500, {}));
    expect(await ZiBootstrapRepository(api: api, store: store).refresh(), isNull);
  });

  test('corrupt cache is ignored', () async {
    await File('${dir.path}/bootstrap.json').writeAsString('{oops');
    server.on('GET', '/v1/bootstrap', (req, _) => respondJson(req, 200, bootstrapJson()));
    final repo = ZiBootstrapRepository(api: api, store: store);
    expect(await repo.loadCached(), isNull);
    expect((await repo.refresh())!.specVersion, '1.0.3');
  });

  test('concurrent refreshes share one request', () async {
    server.on('GET', '/v1/bootstrap', (req, _) async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await respondJson(req, 200, bootstrapJson());
    });
    final repo = ZiBootstrapRepository(api: api, store: store);
    await Future.wait([repo.refresh(), repo.refresh()]);
    expect(server.requests, hasLength(1));
  });
}
