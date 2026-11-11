import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'file_store.dart';
import 'sha256.dart';

/// Notices that the person using the app changed (`docs/sdk.md` §3.1), with
/// no code of the app's: a sign-out, or somebody else signing in on the same
/// phone. The next person must not read the last one's chat, and the chat is
/// kept per install id, so the SDK makes a new install id ([onSignOut]).
///
/// - **One interceptor, at the end of the app's Dio.** It never changes or
///   stops the app's requests: it sees each with the `Authorization` the
///   app's own interceptors set.
/// - **Who a request is for:** no `Authorization`, nobody; a JWT, its user
///   claim (`sub`, `user_id`, `uid` or `id`, read without checking the
///   signature); any other token, the token itself. Only a fingerprint (a
///   SHA-256) is kept, in memory and in a file, so a change between two
///   launches of the app is noticed too.
/// - **A sign-out** is somebody, then somebody else, or then nobody.
/// - **A check before the chat opens** ([check]): a request through the Dio
///   that this interceptor answers itself (`204`), so nothing leaves the
///   phone but the app's interceptors still add their header to it. That is
///   what tells "nobody".
///
/// A request with no `Authorization` that the app made for itself is not
/// taken for a sign-out: apps send public requests (a catalog, a splash
/// config) while somebody is signed in. Only the check says "nobody"; a user
/// who signed out and left the chat shut meets the check before the chat
/// opens, so nothing is lost.
class ZiSignOutWatch {
  ZiSignOutWatch({
    required Dio dio,
    required ZiFileStore store,
    required this.onSignOut,
    this.checkTimeout = const Duration(seconds: 3),
  }) : _dio = dio,
      _store = store {
    _loaded = _load();
  }

  /// `extra` key of the check request: this interceptor answers it itself.
  @visibleForTesting
  static const checkKey = 'zi_check';

  static const _file = 'user';

  /// Names a login's scheme goes by, when it comes with no token.
  static const _schemes = {'bearer', 'token', 'jwt', 'basic'};

  final Dio _dio;
  final ZiFileStore _store;

  /// Starts a new install: forget the conversation and the user's token.
  final FutureOr<void> Function() onSignOut;

  /// The most the check may delay the chat: the app's interceptors may
  /// refresh a token before they add it.
  final Duration checkTimeout;

  late final Future<void> _loaded;
  late final Interceptor _interceptor = _SignOutInterceptor(this);

  /// The fingerprint of the person last seen; null: nobody.
  String? _who;

  /// Puts the interceptor at the end of the Dio's.
  void attach() {
    _dio.interceptors
      ..remove(_interceptor)
      ..add(_interceptor);
  }

  /// Asks, through the app's Dio, who is signed in now; done before the chat
  /// opens. Never throws and waits at most [checkTimeout]: the chat opens
  /// either way.
  Future<void> check() async {
    // An interceptor the app added after ours would run after it and miss.
    if (_dio.interceptors.isEmpty || _dio.interceptors.last != _interceptor) attach();
    try {
      await _dio
          .request<Object?>(
            '/',
            options: Options(method: 'GET', extra: const {checkKey: true, 'zi': true}, validateStatus: (_) => true),
          )
          .timeout(checkTimeout);
    } on Object catch (e) {
      debugPrint('zehn_intelligence: the sign-in check could not be made: $e');
    }
  }

  /// Who a request with these [headers] is for: a fingerprint, or null for
  /// nobody.
  @visibleForTesting
  static String? identityOf(Map<String, Object?> headers) {
    Object? value;
    for (final MapEntry(:key, value: v) in headers.entries) {
      if (key.toLowerCase() == 'authorization') value = v;
    }
    final words = value == null ? const <String>[] : '$value'.trim().split(RegExp(r'\s+'));
    // "Bearer <token>", or the token alone; whatever the scheme is called. A
    // scheme with no token (`Bearer `) is no login.
    final token = words.length > 1
        ? words.sublist(1).join(' ')
        : words.length == 1 && !_schemes.contains(words.single.toLowerCase())
        ? words.single
        : '';
    if (token.isEmpty) return null;
    final user = _userClaim(token);
    return ziSha256Hex(utf8.encode(user != null ? 'user:$user' : 'token:$token'));
  }

  /// The user a JWT is for, read from its payload without checking it; null
  /// when it isn't a JWT or names no user.
  static String? _userClaim(String token) {
    final parts = token.split('.');
    if (parts.length != 3) return null;
    try {
      final payload = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))));
      if (payload is! Map) return null;
      for (final name in const ['sub', 'user_id', 'uid', 'id']) {
        final claim = payload[name];
        if ((claim is String && claim.isNotEmpty) || claim is num) return '$claim';
      }
    } on Object {
      // Not a JWT after all.
    }
    return null;
  }

  Future<void> _load() async {
    final kept = (await _store.read(_file))?['who'];
    if (kept is String && kept.isNotEmpty) _who = kept;
  }

  final Set<Future<void>> _inFlight = {};

  /// Completes when every request seen so far has been dealt with, a
  /// sign-out and the files it wrote among them. For tests, which can't tell
  /// otherwise when the file writes are done.
  Future<void> get idle async {
    while (_inFlight.isNotEmpty) {
      await Future.wait(_inFlight.toList());
    }
  }

  /// One request was for [who]; [conclusive] when its answer is "nobody" for
  /// certain (the check). Never throws.
  Future<void> _seen(String? who, {required bool conclusive}) {
    final work = _handle(who, conclusive: conclusive);
    _inFlight.add(work);
    return work.whenComplete(() => _inFlight.remove(work));
  }

  Future<void> _handle(String? who, {required bool conclusive}) async {
    try {
      await _loaded;
      final before = _who;
      if (who == before) return;
      // A request of the app's own with no login: public, says nothing.
      if (who == null && !conclusive) return;
      // Set before anything is awaited: a request that follows sees it.
      _who = who;
      try {
        if (who == null) {
          await _store.delete(_file);
        } else {
          await _store.write(_file, {'who': who});
        }
      } on Object catch (e) {
        debugPrint('zehn_intelligence: who is signed in could not be kept: $e');
      }
      // Somebody, then nobody or somebody else. Nobody, then somebody is
      // only a first sign-in.
      if (before != null) await onSignOut();
    } on Object catch (e) {
      debugPrint('zehn_intelligence: a sign-out could not be handled: $e');
    }
  }
}

class _SignOutInterceptor extends Interceptor {
  _SignOutInterceptor(this._watch);

  final ZiSignOutWatch _watch;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final check = options.extra[ZiSignOutWatch.checkKey] == true;
    final seen = _watch._seen(ZiSignOutWatch.identityOf(options.headers), conclusive: check);
    if (!check) {
      // The app's request goes on at once; it is never held for this.
      unawaited(seen);
      handler.next(options);
      return;
    }
    // The check is answered here, once the new install id is made: nothing
    // is sent.
    unawaited(seen.whenComplete(() => handler.resolve(Response<Object?>(requestOptions: options, statusCode: 204))));
  }
}
