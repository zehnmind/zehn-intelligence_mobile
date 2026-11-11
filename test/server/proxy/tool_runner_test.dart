import 'package:flutter_test/flutter_test.dart';
import 'package:zehn_intelligence/src/server/api/turn_events.dart';
import 'package:zehn_intelligence/src/server/proxy/proxy_executor.dart';
import 'package:zehn_intelligence/src/server/proxy/tool_runner.dart';
import 'package:zehn_intelligence/zehn_intelligence.dart' show ZiArg, ZiToolError;

import '../../support/fake_server.dart';

ClientApiRequest call(String id, String tool, {Map<String, Object?> args = const {}, Map<String, Object?>? http, String? actionId}) =>
    ClientApiRequest(callId: id, tool: tool, args: args, request: http, actionId: actionId);

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

  test('declared arguments are checked before the handler runs', () async {
    var ran = 0;
    final checked = ZiToolRunner(
      handlers: {
        'map.route': (args) async {
          ran++;
          return {'to': args['to']};
        },
      },
      proxy: ZiProxyExecutor(),
      args: const {
        'map.route': {
          'to': ZiArg.string('Where to go', required: true),
          'floor': ZiArg.integer('The floor', oneOf: [1, 2]),
          'accessible': ZiArg.boolean('Lifts only'),
        },
      },
    );
    final results = await checked.runAll([
      call('a', 'map.route'),
      call('b', 'map.route', args: {'to': 7}),
      call('c', 'map.route', args: {'to': 'Zara', 'floor': 9}),
      call('d', 'map.route', args: {'to': 'Zara', 'accessible': 'yes'}),
      call('e', 'map.route', args: {'to': 'Zara', 'floor': 2, 'accessible': null, 'other': 1}),
    ]);
    expect(results.map((r) => r.errorCode), ['invalid_args', 'invalid_args', 'invalid_args', 'invalid_args', null]);
    expect(results.first.errorMessage, contains('"to"'));
    expect(results.last.data, {'to': 'Zara'});
    expect(ran, 1);
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

  test("the pause's max_result_bytes is the limit, not the runner's own", () async {
    final handlers = {'x': (Map<String, Object?> args) async => <String, Object?>{'blob': 'a' * 200}};
    final within = await runner(handlers).runAll([call('c1', 'x')], maxResultBytes: 1000);
    expect(within.single.ok, isTrue);
    final over = await runner(handlers).runAll([call('c1', 'x')], maxResultBytes: 100);
    expect(over.single.errorCode, 'result_too_large');
    expect(over.single.errorMessage, contains('100'));
  });

  test("a call may take the pause's expires_in less 5 s; at least a second", () async {
    final handlers = {
      'slow': (Map<String, Object?> args) async {
        await Future<void>.delayed(const Duration(milliseconds: 1500));
        return <String, Object?>{'late': true};
      },
    };
    // 6 s − 5 s: one second, so a call of 1.5 s is too slow ...
    final tight = await runner(handlers).runAll([call('s', 'slow')], expiresIn: const Duration(seconds: 6));
    expect(tight.single.errorCode, 'timeout');
    // ... and one second is the least it gets, whatever the pause says.
    final none = await runner(handlers).runAll([call('s', 'slow')], expiresIn: Duration.zero);
    expect(none.single.errorCode, 'timeout');
    // 7 s − 5 s: two seconds, enough, though the runner's own limit is 100 ms.
    final roomy = await runner(handlers, timeout: const Duration(milliseconds: 100))
        .runAll([call('s', 'slow')], expiresIn: const Duration(seconds: 7));
    expect(roomy.single.ok, isTrue);
  });

  test("the pause's time reaches the request too, not only the runner", () async {
    server.on('GET', '/slow', (req, _) async {
      await Future<void>.delayed(const Duration(milliseconds: 400));
      await respondJson(req, 200, {'ok': true});
    });
    final slow = {'method': 'GET', 'path': '/slow', 'base_url': server.url.toString()};
    // The executor's own limit is 100 ms, the pause's 2 s: the request is let finish.
    final limited = ZiToolRunner(handlers: const {}, proxy: ZiProxyExecutor(timeout: const Duration(milliseconds: 100)));
    final results = await limited.runAll([call('c1', 'slow.get', http: slow)], expiresIn: const Duration(seconds: 7));
    expect(results.single.ok, isTrue);
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

    Map<String, Object?> reserve() => {
      'method': 'POST',
      'path': '/parking/reservations',
      'body': {'zone_id': 7},
      'base_url': server.url.toString(),
    };

    ZiToolRunner confirmed(Set<String> actions) =>
        ZiToolRunner(handlers: const {}, proxy: ZiProxyExecutor())..takeConfirmed = actions.remove;

    test('a write runs after the user confirmed its action', () async {
      final results = await confirmed({'a1'}).runAll([call('c1', 'parking.reserve', http: reserve(), actionId: 'a1')]);
      expect(results.single.data, {'id': 'r1'});
      expect(server.requests.single.method, 'POST');
    });

    test('a write the user did not confirm is not_confirmed and makes no request', () async {
      final results = await confirmed({'a1'}).runAll([
        call('c1', 'parking.reserve', http: reserve()),
        call('c2', 'parking.reserve', http: reserve(), actionId: 'other'),
      ]);
      expect(results.map((r) => r.errorCode), ['not_confirmed', 'not_confirmed']);
      expect(server.requests, isEmpty);
    });

    test('one confirmation allows one request', () async {
      final runner = confirmed({'a1'});
      await runner.runAll([call('c1', 'parking.reserve', http: reserve(), actionId: 'a1')]);
      final again = await runner.runAll([call('c2', 'parking.reserve', http: reserve(), actionId: 'a1')]);
      expect(again.single.errorCode, 'not_confirmed');
      expect(server.requests, hasLength(1));
    });

    test('without a way to check, a write is not_confirmed', () async {
      final results = await ZiToolRunner(handlers: const {}, proxy: ZiProxyExecutor())
          .runAll([call('c1', 'parking.reserve', http: reserve(), actionId: 'a1')]);
      expect(results.single.errorCode, 'not_confirmed');
    });

    test('reads and in-app handlers need no confirmation', () async {
      final runner = ZiToolRunner(handlers: {'app.write': (args) async => {'done': true}}, proxy: ZiProxyExecutor());
      final results = await runner.runAll([call('c1', 'locations.get', http: venue()), call('c2', 'app.write')]);
      expect(results.map((r) => r.ok), [true, true]);
    });
  });
}
