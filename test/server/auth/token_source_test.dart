import 'dart:io';
import 'dart:math';

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

  // What the server accepts in X-ZI-Install-Id: a lower-case UUID v4 with hyphens.
  final uuidV4 = RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$');

  test('the install id is a lower-case UUID v4, made once and kept', () async {
    final id = await loadInstallId(store);
    expect(id, matches(uuidV4));
    expect(await loadInstallId(store), id);
    expect(await loadInstallId(ZiFileStore(() async => dir)), id);
  });

  test('renewing the install id replaces the kept one', () async {
    final old = await loadInstallId(store);
    final fresh = await renewInstallId(store);
    expect(fresh, matches(uuidV4));
    expect(fresh, isNot(old));
    expect(await loadInstallId(store), fresh);
  });

  test('a new id is a UUID v4 every time', () {
    final random = Random(7);
    for (var i = 0; i < 100; i++) {
      expect(newInstallId(random), matches(uuidV4));
    }
  });

  test('an id an older build kept without hyphens keeps its value, with hyphens', () async {
    await store.write('install', {'install_id': '0123456789abcdef0123456789abcdef', 'token': 'old'});
    expect(await loadInstallId(store), '01234567-89ab-cdef-0123-456789abcdef');
    expect(await store.read('install'), {'install_id': '01234567-89ab-cdef-0123-456789abcdef'});
  });

  test('a kept UUID is used as it is', () async {
    await store.write('install', {'install_id': 'ffffffff-ffff-4fff-bfff-ffffffffffff'});
    expect(await loadInstallId(store), 'ffffffff-ffff-4fff-bfff-ffffffffffff');
  });

  test('a broken saved id is replaced', () async {
    await File('${dir.path}/install.json').writeAsString('{oops');
    final id = await loadInstallId(store);
    expect(id, matches(uuidV4));
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
