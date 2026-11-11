import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zehn_intelligence/src/server/auth/file_store.dart';
import 'package:zehn_intelligence/src/server/auth/sign_out_watch.dart';

/// Stands in for the network: counts what would have left the phone, and
/// answers every request with 200.
class _Network implements HttpClientAdapter {
  final List<RequestOptions> sent = [];

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    sent.add(options);
    return ResponseBody.fromString('{"ok":true}', 200, headers: {
      Headers.contentTypeHeader: ['application/json'],
    });
  }

  @override
  void close({bool force = false}) {}
}

String _jwt(Map<String, Object?> claims, {String signature = 'sig'}) {
  String part(Object json) => base64Url.encode(utf8.encode(jsonEncode(json))).replaceAll('=', '');
  return '${part({'alg': 'HS256'})}.${part(claims)}.$signature';
}

void main() {
  late Directory dir;
  late ZiFileStore store;
  late _Network network;
  late Dio dio;

  /// The app's own login, as an interceptor of its own: whatever token is
  /// set goes out as `Authorization: Bearer`; none, no header.
  String? token;
  late int signOuts;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('zi_signout');
    store = ZiFileStore(() async => dir);
    network = _Network();
    token = null;
    signOuts = 0;
    dio = Dio(BaseOptions(baseUrl: 'https://api.app.example'))
      ..httpClientAdapter = network
      ..interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
        final t = token;
        if (t != null && !options.extra.containsKey('public')) options.headers['Authorization'] = 'Bearer $t';
        handler.next(options);
      }));
  });

  tearDown(() => dir.delete(recursive: true));

  /// The watch made last: what is left of its requests is waited for with [idle].
  late ZiSignOutWatch current;
  Future<void> idle() => current.idle;

  ZiSignOutWatch watch({ZiFileStore? kept, FutureOr<void> Function()? onSignOut, Duration? timeout}) =>
      current = ZiSignOutWatch(
        dio: dio,
        store: kept ?? store,
        onSignOut: onSignOut ?? () => signOuts++,
        checkTimeout: timeout ?? const Duration(seconds: 3),
      )..attach();



  /// A request of the app's, made while [token] is set.
  Future<void> appCalls({bool public = false}) => dio.get<Object?>('/orders', options: Options(extra: {if (public) 'public': true}));

  group('who a request is for', () {
    Map<String, Object?> auth(String value) => {'Authorization': value};
    String? who(String value) => ZiSignOutWatch.identityOf(auth(value));

    test('no Authorization, or an empty one, is nobody', () {
      expect(ZiSignOutWatch.identityOf(const {}), isNull);
      expect(ZiSignOutWatch.identityOf(const {'Accept': 'application/json'}), isNull);
      expect(who(''), isNull);
      expect(who('Bearer '), isNull);
      expect(who('   '), isNull);
    });

    test('the header name is read in any case', () {
      expect(ZiSignOutWatch.identityOf(const {'authorization': 'Bearer abc'}), who('Bearer abc'));
      expect(ZiSignOutWatch.identityOf(const {'AUTHORIZATION': 'Bearer abc'}), isNotNull);
    });

    test('a JWT is its user claim: a refreshed token is the same person', () {
      final first = _jwt({'sub': 'u-42', 'exp': 1000});
      final refreshed = _jwt({'sub': 'u-42', 'exp': 2000, 'jti': 'other'}, signature: 'other-sig');
      expect(who('Bearer $first'), isNotNull);
      expect(who('Bearer $first'), who('Bearer $refreshed'));
      expect(who('Bearer ${_jwt({'sub': 'u-43'})}'), isNot(who('Bearer $first')));
    });

    test('the claim is sub, then user_id, uid, id; a number counts', () {
      String? claim(Map<String, Object?> claims) => who('Bearer ${_jwt(claims)}');
      expect(claim({'sub': 'a', 'user_id': 'b'}), claim({'sub': 'a'}));
      expect(claim({'user_id': 'b', 'uid': 'c'}), claim({'user_id': 'b'}));
      expect(claim({'uid': 'c', 'id': 'd'}), claim({'uid': 'c'}));
      expect(claim({'id': 7}), claim({'id': 7, 'role': 'admin'}));
      expect(claim({'id': 7}), isNot(claim({'id': 8})));
      // The same id under another claim name is the same id.
      expect(claim({'id': 7}), isNot(claim({'sub': 'u'})));
    });

    test('any other token is the token itself, with or without its scheme', () {
      expect(who('Bearer opaque-1'), who('Bearer opaque-1'));
      expect(who('Bearer opaque-1'), who('opaque-1'));
      expect(who('Bearer opaque-1'), who('Token opaque-1'));
      expect(who('Bearer opaque-1'), isNot(who('Bearer opaque-2')));
      // A JWT that names no user is told apart by the token.
      expect(who('Bearer ${_jwt({'iat': 1})}'), isNot(who('Bearer ${_jwt({'iat': 2})}')));
      // A string with dots that isn't a JWT.
      expect(who('Bearer a.b.c'), isNotNull);
      expect(who('Bearer a.b.c'), isNot(who('Bearer a.b.d')));
    });

    test('only a fingerprint is made of it: never the token or the user', () {
      final jwt = _jwt({'sub': 'secret-user-id'});
      for (final value in ['Bearer opaque-secret-token', 'Bearer $jwt']) {
        final fingerprint = who(value)!;
        expect(fingerprint, matches(RegExp(r'^[0-9a-f]{64}$')));
        expect(fingerprint, isNot(contains('secret')));
      }
    });
  });

  group('noticing a sign-out', () {
    test('a first sign-in, and the same person again, is not a sign-out', () async {
      watch();
      await appCalls(); // nobody, from a public request
      token = _jwt({'sub': 'A'});
      await appCalls();
      token = _jwt({'sub': 'A', 'exp': 99}); // a refresh
      await appCalls();
      await Future<void>.delayed(Duration.zero);
      expect(signOuts, 0);
    });

    test('somebody else signing in is a sign-out at once, and the app\'s request is not held', () async {
      watch();
      token = 'token-A';
      await appCalls();
      token = 'token-B';
      await appCalls();
      expect(network.sent, hasLength(2), reason: 'the app\'s requests both went out');
      expect(network.sent.last.headers['Authorization'], 'Bearer token-B');
      await idle();
      expect(signOuts, 1);
      token = 'token-B';
      await appCalls();
      await idle();
      expect(signOuts, 1, reason: 'B is now who is seen');
    });

    test('a public request of the app, with no login, is not a sign-out', () async {
      watch();
      token = 'token-A';
      await appCalls();
      await appCalls(public: true);
      await appCalls(public: true);
      await idle();
      expect(signOuts, 0);
      await appCalls();
      await idle();
      expect(signOuts, 0, reason: 'A is still the one seen');
    });

    test('the check before the chat opens says nobody: a sign-out', () async {
      final w = watch();
      token = 'token-A';
      await appCalls();
      token = null;
      await w.check();
      expect(signOuts, 1);
      // Asked again with nobody signed in: nothing more.
      await w.check();
      expect(signOuts, 1);
      // Somebody signing in after nobody is a first sign-in.
      token = 'token-B';
      await appCalls();
      await idle();
      expect(signOuts, 1);
    });

    test('the check with the same person, or after nobody was ever seen, is nothing', () async {
      final w = watch();
      await w.check();
      expect(signOuts, 0);
      token = 'token-A';
      await w.check();
      await w.check();
      expect(signOuts, 0);
    });

    test('the check with somebody else is a sign-out', () async {
      final w = watch();
      token = 'token-A';
      await appCalls();
      token = 'token-B';
      await w.check();
      expect(signOuts, 1);
    });

    test('the check never leaves the phone, and the app\'s interceptors still see it', () async {
      final w = watch();
      token = 'token-A';
      await appCalls();
      network.sent.clear();
      final seenByApp = <Object?>[];
      // After the app's login interceptor, before ours (the last).
      dio.interceptors.insert(
        dio.interceptors.length - 1,
        InterceptorsWrapper(onRequest: (options, handler) {
          seenByApp.add(options.headers['Authorization']);
          handler.next(options);
        }),
      );
      await w.check();
      expect(network.sent, isEmpty);
      expect(seenByApp, ['Bearer token-A'], reason: 'the app\'s interceptors added their header to it');
    });

    test('the new install is made before the check answers', () async {
      final order = <String>[];
      final w = watch(onSignOut: () async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        order.add('new install');
      });
      token = 'token-A';
      await appCalls();
      token = null;
      await w.check();
      order.add('check answered');
      expect(order, ['new install', 'check answered']);
    });

    test('a person is kept between launches: somebody else, or nobody, after a restart', () async {
      watch();
      token = 'token-A';
      await appCalls();
      await idle();

      // A new launch: a new watch on the same files, and a Dio of its own.
      final second = Dio(BaseOptions(baseUrl: 'https://api.app.example'))
        ..httpClientAdapter = network
        ..interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
          if (token != null) o.headers['Authorization'] = 'Bearer $token';
          h.next(o);
        }));
      final restarted = ZiSignOutWatch(dio: second, store: store, onSignOut: () => signOuts++)..attach();
      token = 'token-B';
      await second.get<Object?>('/orders');
      await restarted.idle;
      expect(signOuts, 1);

      token = null;
      await restarted.check();
      expect(signOuts, 2);
    });

    test('nothing readable of the person is written to a file', () async {
      final w = watch();
      token = _jwt({'sub': 'secret-user-id'});
      await appCalls();
      await idle();
      final text = [for (final f in dir.listSync().whereType<File>()) f.readAsStringSync()].join();
      expect(text, isNotEmpty);
      expect(text, isNot(contains('secret-user-id')));
      expect(text, isNot(contains(token!)));
      token = null;
      await w.check();
      expect(dir.listSync().whereType<File>().where((f) => f.path.endsWith('user.json')), isEmpty);
    });

    test('a login interceptor the app added after ours is still run before the check is answered', () async {
      // The app's login interceptor comes last, after ours: it would never
      // have added its header to the check, which would then read "nobody".
      final late = Dio(BaseOptions(baseUrl: 'https://api.app.example'))..httpClientAdapter = network;
      final lateWatch = ZiSignOutWatch(dio: late, store: store, onSignOut: () => signOuts++)..attach();
      String login = 'token-A';
      late.interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
        o.headers['Authorization'] = 'Bearer $login';
        h.next(o);
      }));
      expect(late.interceptors.last, isA<InterceptorsWrapper>(), reason: 'sanity: the app\'s is last');

      await lateWatch.check(); // sees A: a first sign-in
      expect(late.interceptors.last, isNot(isA<InterceptorsWrapper>()), reason: 'ours went to the end');
      expect(network.sent, isEmpty);
      expect(signOuts, 0);
      login = 'token-B';
      await lateWatch.check(); // sees B, so A was seen before: a sign-out
      expect(signOuts, 1);
    });

    test('the check never throws, and waits no longer than its timeout', () async {
      final w = watch(timeout: const Duration(milliseconds: 100));
      dio.interceptors.insert(
        1,
        InterceptorsWrapper(onRequest: (options, handler) {
          if (options.extra.containsKey(ZiSignOutWatch.checkKey)) {
            handler.reject(DioException(requestOptions: options, error: 'offline'));
            return;
          }
          handler.next(options);
        }),
      );
      await w.check(); // an interceptor of the app refuses it
      dio.interceptors.removeAt(1);
      dio.interceptors.insert(
        1,
        InterceptorsWrapper(onRequest: (options, handler) {
          // Never calls next: a refresh that never ends.
        }),
      );
      final stopwatch = Stopwatch()..start();
      await w.check();
      expect(stopwatch.elapsedMilliseconds, lessThan(1500));
      expect(signOuts, 0);
    });

    test('a failing sign-out handler never breaks the app\'s request', () async {
      watch(onSignOut: () => throw StateError('bug'));
      token = 'token-A';
      await appCalls();
      token = 'token-B';
      final response = await dio.get<Object?>('/orders');
      expect(response.statusCode, 200);
      await idle();
    });

    test('the app\'s requests and answers pass through untouched', () async {
      watch();
      token = 'token-A';
      final response = await dio.get<Object?>('/orders', queryParameters: {'page': 2});
      expect(response.data, {'ok': true});
      expect(network.sent.single.uri.toString(), 'https://api.app.example/orders?page=2');
      expect(network.sent.single.headers['Authorization'], 'Bearer token-A');
    });
  });
}
