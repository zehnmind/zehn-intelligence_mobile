import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

import '../../ui/zehn_integrator.dart' show ZiToolError;
import 'http_call.dart';
import 'result_trimmer.dart';

/// Calls the customer's API for a tool, as the signed-in user.
///
/// Two ways to log in: the app's own [appClient] (its base URL, auth header
/// and refresh run as for its own calls), or [accessToken] with
/// [onUnauthorized] (this executor adds the header and retries once).
class ZiProxyExecutor {
  ZiProxyExecutor({
    Dio? appClient,
    FutureOr<String?> Function()? accessToken,
    FutureOr<bool> Function()? onUnauthorized,
    Uri? baseUrlOverride,
    FutureOr<bool> Function()? isSignedIn,
    Dio? ownClient,
    this.timeout = const Duration(seconds: 20),
  }) : _appClient = appClient,
       _accessToken = accessToken,
       _onUnauthorized = onUnauthorized,
       _baseUrlOverride = baseUrlOverride,
       _isSignedIn = isSignedIn,
       _own = ownClient ?? Dio();

  final Dio? _appClient;
  final FutureOr<String?> Function()? _accessToken;
  final FutureOr<bool> Function()? _onUnauthorized;
  final Uri? _baseUrlOverride;
  final FutureOr<bool> Function()? _isSignedIn;
  final Dio _own;
  final Duration timeout;

  bool get hasLogin => _appClient != null || _accessToken != null;

  static const _loopback = {'localhost', '127.0.0.1', '::1', '[::1]'};

  /// What the model reads when the user isn't signed in to the app.
  static const _signedOut = ZiToolError('not_signed_in', 'The user is not signed in to the app');

  /// The longest a message of the app's server is passed on as it is.
  static const _shortMessage = 120;

  /// The trimmed JSON answer. Throws [ZiToolError] the model can read
  /// (`docs/sdk.md` §5.1): `not_signed_in` for a 401 or a 403, `not_found`
  /// for a 404, `timeout` past [timeout], else `handler_failed`.
  ///
  /// [timeout] is how long this call may take, from the turn's pause
  /// (`expires_in − 5 s`); without one, the executor's own.
  Future<Object?> call(ZiHttpCall http, {Duration? timeout}) async {
    final limit = timeout ?? this.timeout;
    // A login-only call for a signed-out user is never made: through the
    // app's own client it could set off the app's sign-out (as TCM's
    // refresh interceptor does on a 401 it cannot refresh).
    final signedIn = _isSignedIn;
    if (http.auth && signedIn != null && !await signedIn()) throw _signedOut;
    final app = _appClient;
    final Response<Object?> response;
    if (app != null) {
      response = await _send(app, http.path, http, const {}, limit, appDefaults: true);
    } else {
      response = await _callbacks(http, limit);
    }
    final status = response.statusCode ?? 0;
    if (status == 401 || status == 403) throw _signedOut;
    if (status == 404) throw const ZiToolError('not_found', 'Not found');
    if (status < 200 || status >= 300) {
      // Only a 4xx says why in words meant for the user; a 5xx may say
      // more than the model should read.
      final why = status < 500 ? _messageOf(response.data) : null;
      throw ZiToolError('handler_failed', "The app's server answered $status${why == null ? '' : ': $why'}");
    }
    return trimResult(_json(response.data, status), http.result);
  }

  /// The `message` (or `detail`) of an error answer, if it is short.
  static String? _messageOf(Object? data) {
    Object? body = data;
    if (body is String) {
      try {
        body = jsonDecode(body);
      } on FormatException {
        return null;
      }
    }
    if (body is! Map) return null;
    for (final key in const ['message', 'detail']) {
      final value = body[key];
      if (value is! String) continue;
      final text = value.trim();
      if (text.isNotEmpty && text.length <= _shortMessage) return text;
    }
    return null;
  }

  Future<Response<Object?>> _callbacks(ZiHttpCall http, Duration limit) async {
    final base = _baseUrlOverride ?? http.baseUrl;
    if (base == null) {
      throw const ZiToolError('host_not_allowed', 'No base URL is set for the app API.');
    }
    // The user's token never goes over plain HTTP because of server data,
    // except to this machine. (An app's own apiBaseUrl is its own call.)
    if (_baseUrlOverride == null && base.scheme != 'https' && !_loopback.contains(base.host)) {
      throw ZiToolError('host_not_allowed', 'The app API at ${base.host} is not HTTPS.');
    }
    final url = '${base.toString().replaceAll(RegExp(r'/+$'), '')}${http.path}';
    var token = await _accessToken?.call();
    if (http.auth && (token == null || token.isEmpty)) throw _signedOut;
    Map<String, String> login(String? t) =>
        t == null || t.isEmpty ? const {} : {http.authHeader: '${http.authScheme} $t'.trim()};

    var response = await _send(_own, url, http, login(token), limit);
    if (response.statusCode == 401 && _onUnauthorized != null) {
      if (await _onUnauthorized()) {
        token = await _accessToken?.call();
        response = await _send(_own, url, http, login(token), limit);
      }
    }
    return response;
  }

  Future<Response<Object?>> _send(
    Dio dio,
    String url,
    ZiHttpCall http,
    Map<String, String> login,
    Duration limit, {
    bool appDefaults = false,
  }) async {
    try {
      return await dio
          .request<Object?>(
            url,
            data: http.body == null ? null : jsonEncode(http.body),
            queryParameters: http.query.isEmpty ? null : http.query,
            options: Options(
              method: http.method,
              listFormat: ListFormat.multi,
              headers: {
                ...http.headers,
                if (http.body != null) 'Content-Type': 'application/json',
                ...login,
              },
              // The app's own client keeps its validateStatus, so its
              // interceptors see a 401 and can refresh.
              validateStatus: appDefaults ? null : (_) => true,
              responseType: appDefaults ? null : ResponseType.plain,
              receiveTimeout: limit,
              // Marks the SDK's requests, so an app interceptor could tell
              // them from its own. Its interceptors still run, toasts and all.
              extra: const {'zi': true},
            ),
          )
          .timeout(limit);
    } on TimeoutException {
      throw ZiToolError('timeout', 'The app API did not answer in ${limit.inSeconds} s.');
    } on DioException catch (e) {
      final response = e.response;
      if (response != null && response.statusCode != null) return response;
      if (e.type == DioExceptionType.receiveTimeout || e.type == DioExceptionType.connectionTimeout) {
        throw ZiToolError('timeout', 'The app API did not answer in ${limit.inSeconds} s.');
      }
      throw const ZiToolError('handler_failed', "The app's server is unreachable");
    }
  }

  static Object? _json(Object? data, int status) {
    if (data is! String) return data;
    if (data.trim().isEmpty) return null;
    try {
      return jsonDecode(data);
    } on FormatException {
      throw ZiToolError('handler_failed', "The app's server answered $status, but not with JSON");
    }
  }
}
