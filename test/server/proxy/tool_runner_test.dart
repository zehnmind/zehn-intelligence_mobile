import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:zehn_intelligence/src/server/api/turn_events.dart';
import 'package:zehn_intelligence/src/server/proxy/proxy_executor.dart';
import 'package:zehn_intelligence/src/server/proxy/tool_runner.dart';
import 'package:zehn_intelligence/zehn_intelligence.dart' show ZiToolError;

import '../../support/fake_server.dart';

ClientApiRequest call(String id, String tool, {Map<String, Object?> args = const {}, Map<String, Object?>? http}) =>
    ClientApiRequest(callId: id, tool: tool, args: args, http: http);

void main() {
  late FakeServer server;

  setUp(() async {
    server = await FakeServer.start();
    server.on('GET', '/location/venues/7', (req, _) => respondJson(req, 200, {'name': 'Seven'}));
  });

  tearDown(() => server.close());

  Map<String, Object?> venue() => {'method': 'GET', 'path': '/location/venues/7', 'base_url': server.url.toString()};

  ZiToolRunner runner(Map<String, ZiToolHandler> handlers, {Duration timeout = const Duration(seconds: 20), int max = 32768}) =>
      ZiToolRunner(handlers: handlers, proxy: ZiProxyExecutor(), timeout: timeout, maxResultBytes: max);

  test('the request the server built is made and its answer comes back ok', () async {
    final results = await runner({}).runAll([call('c1', 'locations.get', http: venue())]);
    expect(results.single.toJson(), {'call_id': 'c1', 'ok': true, 'data': {'name': 'Seven'}});
  });

  test('in-app handler wins over the request', () async {
    final results = await runner({'locations.get': (args) async => {'from': 'app'}})
        .runAll([call('c1', 'locations.get', http: venue())]);
    expect(results.single.data, {'from': 'app'});
    expect(server.requests, isEmpty);
  });

  test('no request and no handler is handler_not_registered', () async {
    final results = await runner({}).runAll([call('a', 'nope.one'), call('b', 'nope.two')]);
    expect(results.map((r) => r.errorCode), ['handler_not_registered', 'handler_not_registered']);
    expect(server.requests, isEmpty);
  });

  test('a request the phone will not make keeps its error code', () async {
    final results = await runner({}).runAll([
      call('a', 'x', http: {'method': 'TRACE', 'path': '/x'}),
      call('b', 'y', http: {'method': 'GET', 'path': 'https://evil.example/x'}),
    ]);
    expect(results.map((r) => r.errorCode), ['method_not_allowed', 'host_not_allowed']);
    expect(server.requests, isEmpty);
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

  group('writes', () {
    setUp(() {
      server.on('POST', '/parking/reservations', (req, _) => respondJson(req, 201, {'id': 'r1'}));
    });

    Map<String, Object?> reserve({Object? confirm}) => {
      'method': 'POST',
      'path': '/parking/reservations',
      'body': {'zone_id': 7},
      'base_url': server.url.toString(),
      'confirm': ?confirm,
    };

    ZiToolRunner asking(ZiConfirmer? confirmer, {Duration timeout = const Duration(seconds: 20)}) =>
        ZiToolRunner(handlers: const {}, proxy: ZiProxyExecutor(), timeout: timeout, confirmMargin: Duration.zero)
          ..confirmer = confirmer;

    test('a write asks first and runs when allowed', () async {
      final asked = <ZiConfirmRequest>[];
      final results = await asking((r) async {
        asked.add(r);
        return true;
      }).runAll([call('c1', 'parking.reserve', args: {'zone_id': 7}, http: reserve())]);
      expect(asked.single.callId, 'c1');
      expect(asked.single.tool, 'parking.reserve');
      expect(asked.single.args, {'zone_id': 7});
      expect(asked.single.title, isNull);
      expect(results.single.data, {'id': 'r1'});
      expect(server.requests.single.method, 'POST');
    });

    test('the question is the one the server wrote', () async {
      final asked = <ZiConfirmRequest>[];
      await asking((r) async {
        asked.add(r);
        return false;
      }).runAll([call('c1', 'parking.reserve', http: reserve(confirm: {'title': 'Забронировать место в зоне 7?'}))]);
      expect(asked.single.title, 'Забронировать место в зоне 7?');
    });

    test('a write the server marked confirm: false runs without asking', () async {
      var asked = 0;
      final results = await asking((r) async {
        asked++;
        return false;
      }).runAll([call('c1', 'parking.reserve', http: reserve(confirm: false))]);
      expect(asked, 0);
      expect(results.single.ok, isTrue);
    });

    test('a declined write is user_declined and makes no request', () async {
      final results = await asking((r) async => false).runAll([call('c1', 'parking.reserve', http: reserve())]);
      expect(results.single.errorCode, 'user_declined');
      expect(server.requests, isEmpty);
    });

    test('a write with no way to ask is user_declined', () async {
      final results = await asking(null).runAll([call('c1', 'parking.reserve', http: reserve())]);
      expect(results.single.errorCode, 'user_declined');
      expect(server.requests, isEmpty);
    });

    test('waiting for the user does not count toward the tool timeout', () async {
      final results = await asking((r) async {
        await Future<void>.delayed(const Duration(milliseconds: 300));
        return true;
      }, timeout: const Duration(milliseconds: 150)).runAll([call('c1', 'parking.reserve', http: reserve())]);
      expect(results.single.ok, isTrue);
    });

    test('no answer before the deadline is user_declined', () async {
      final never = Completer<bool>();
      final results = await asking((r) => never.future)
          .runAll([call('c1', 'parking.reserve', http: reserve())], deadline: DateTime.now().add(const Duration(milliseconds: 200)))
          .timeout(const Duration(seconds: 2));
      expect(results.single.errorCode, 'user_declined');
      expect(server.requests, isEmpty);
    });

    test('reads never ask', () async {
      var asked = 0;
      await asking((r) async {
        asked++;
        return true;
      }).runAll([call('c1', 'locations.get', http: venue())]);
      expect(asked, 0);
    });
  });
}
