import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zehn_intelligence/src/server/api/api_client.dart';
import 'package:zehn_intelligence/src/server/api/turn_events.dart';
import 'package:zehn_intelligence/src/server/auth/file_store.dart';
import 'package:zehn_intelligence/src/server/bootstrap/bootstrap_repository.dart';
import 'package:zehn_intelligence/src/server/proxy/proxy_executor.dart';
import 'package:zehn_intelligence/src/server/proxy/tool_runner.dart';
import 'package:zehn_intelligence/zehn_intelligence.dart' show ZiToolError;

import '../../support/bootstrap_fixture.dart';
import '../../support/fake_server.dart';
import '../../support/test_info.dart';
import 'request_builder_test.dart' show ctx;

ClientApiRequest call(String id, String tool, [Map<String, Object?> args = const {}]) =>
    ClientApiRequest(callId: id, tool: tool, args: args);

void main() {
  late FakeServer server;
  late Directory dir;
  late ZiBootstrapRepository bootstrap;

  setUp(() async {
    server = await FakeServer.start();
    dir = await Directory.systemTemp.createTemp('zi_runner');
    server.on('GET', '/v1/bootstrap', (req, _) => respondJson(req, 200, bootstrapJson(baseUrl: server.url.toString())));
    server.on('GET', '/location/venues/7', (req, _) => respondJson(req, 200, {'name': 'Seven'}));
    bootstrap = ZiBootstrapRepository(api: ZiApiClient(baseUrl: server.url, info: info), store: ZiFileStore(() async => dir));
    await bootstrap.refresh();
    server.requests.clear();
  });

  tearDown(() async {
    await server.close();
    await dir.delete(recursive: true);
  });

  ZiToolRunner runner(Map<String, ZiToolHandler> handlers, {Duration timeout = const Duration(seconds: 20), int max = 32768}) =>
      ZiToolRunner(
        handlers: handlers,
        proxy: ZiProxyExecutor(),
        bootstrap: bootstrap,
        context: () => ctx,
        timeout: timeout,
        maxResultBytes: max,
      );

  test('proxy tool result comes back ok', () async {
    final results = await runner({}).runAll([call('c1', 'locations.get', {'id': '7'})]);
    expect(results.single.toJson(), {'call_id': 'c1', 'ok': true, 'data': {'name': 'Seven'}});
  });

  test('in-app handler wins over proxy tool', () async {
    final results = await runner({'locations.get': (args) async => {'from': 'app'}}).runAll([call('c1', 'locations.get', {'id': '7'})]);
    expect(results.single.data, {'from': 'app'});
    expect(server.requests, isEmpty);
  });

  test('unknown tool refreshes start-up data once then handler_not_registered', () async {
    final results = await runner({}).runAll([call('a', 'nope.one'), call('b', 'nope.two')]);
    expect(results.map((r) => r.errorCode), ['handler_not_registered', 'handler_not_registered']);
    expect(server.requests.where((r) => r.path == '/v1/bootstrap'), hasLength(1));
  });

  test('ZiToolError code is kept', () async {
    final results = await runner({'x': (args) async => throw const ZiToolError('not_found', 'No such venue')}).runAll([call('c1', 'x')]);
    expect(results.single.toJson(), {
      'call_id': 'c1',
      'ok': false,
      'error': {'code': 'not_found', 'message': 'No such venue'},
    });
  });

  test('other exceptions are handler_failed', () async {
    final results = await runner({'x': (args) async => throw StateError('bug')}).runAll([call('c1', 'x')]);
    expect(results.single.errorCode, 'handler_failed');
  });

  test('result over 32 KB is result_too_large', () async {
    final results = await runner({'x': (args) async => {'blob': 'a' * 40000}}).runAll([call('c1', 'x')]);
    expect(results.single.errorCode, 'result_too_large');
  });

  test('slow call times out without blocking others', () async {
    final results = await runner({
      'slow': (args) async {
        await Future<void>.delayed(const Duration(seconds: 1));
        return {'late': true};
      },
      'fast': (args) async => {'ok': true},
    }, timeout: const Duration(milliseconds: 100)).runAll([call('s', 'slow'), call('f', 'fast')]).timeout(const Duration(milliseconds: 600));
    expect(results.map((r) => r.callId), ['s', 'f']);
    expect(results[0].errorCode, 'timeout');
    expect(results[1].ok, isTrue);
  });
}
