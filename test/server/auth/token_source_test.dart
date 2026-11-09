import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zehn_intelligence/src/server/api/api_client.dart';
import 'package:zehn_intelligence/src/server/auth/file_store.dart';
import 'package:zehn_intelligence/src/server/auth/token_source.dart';

void main() {
  late Directory dir;
  late ZiFileStore store;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('zi_tokens');
    store = ZiFileStore(() async => dir);
  });

  tearDown(() => dir.delete(recursive: true));

  test('the install id is made once and kept', () async {
    final id = await loadInstallId(store);
    expect(id, matches(RegExp(r'^[0-9a-f]{32}$')));
    expect(await loadInstallId(store), id);
    expect(await loadInstallId(ZiFileStore(() async => dir)), id);
  });

  test('an install id saved by an older SDK is kept', () async {
    await store.write('install', {'install_id': 'ffffffffffffffffffffffffffffffff', 'token': 'old'});
    expect(await loadInstallId(store), 'ffffffffffffffffffffffffffffffff');
  });

  test('a broken saved id is replaced', () async {
    await File('${dir.path}/install.json').writeAsString('{oops');
    final id = await loadInstallId(store);
    expect(id, matches(RegExp(r'^[0-9a-f]{32}$')));
    expect(await loadInstallId(store), id);
  });

  test('an anonymous user has no token', () async {
    const source = AnonymousTokenSource();
    expect(await source.token(), isNull);
    expect(await source.refresh(), isNull);
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
