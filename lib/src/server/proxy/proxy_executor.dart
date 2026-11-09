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

  /// The trimmed JSON answer. Throws [ZiToolError] the model can read.
  Future<Object?> call(ZiHttpCall http) async {
    // A login-only call for a signed-out user is never made: through the
    // app's own client it could set off the app's sign-out (as TCM's
    // refresh interceptor does on a 401 it cannot refresh).
    final signedIn = _isSignedIn;
    if (http.auth && signedIn != null && !await signedIn()) {
      throw const ZiToolError('not_signed_in', 'Ask the user to sign in.');
    }
    final app = _appClient;
    final Response<Object?> response;
    if (app != null) {
      response = await _send(app, http.path, http, const {}, appDefaults: true);
    } else {
      response = await _callbacks(http);
    }
    final status = response.statusCode ?? 0;
    if (status == 401) {
      throw const ZiToolError('not_signed_in', 'Ask the user to sign in.');
    }
    if (status < 200 || status >= 300) {
      throw ZiToolError('http_error', 'The app API answered $status.');
    }
    return trimResult(_json(response.data), http.result);
  }

  Future<Response<Object?>> _callbacks(ZiHttpCall http) async {
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
    if (http.auth && (token == null || token.isEmpty)) {
      throw const ZiToolError('not_signed_in', 'Ask the user to sign in.');
    }
    Map<String, String> login(String? t) =>
        t == null || t.isEmpty ? const {} : {http.authHeader: '${http.authScheme} $t'.trim()};

    var response = await _send(_own, url, http, login(token));
    if (response.statusCode == 401 && _onUnauthorized != null) {
      if (await _onUnauthorized()) {
        token = await _accessToken?.call();
        response = await _send(_own, url, http, login(token));
      }
    }
    return response;
  }

  Future<Response<Object?>> _send(
    Dio dio,
    String url,
    ZiHttpCall http,
    Map<String, String> login, {
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
              receiveTimeout: timeout,
            ),
          )
          .timeout(timeout);
    } on TimeoutException {
      throw ZiToolError('timeout', 'The app API did not answer in ${timeout.inSeconds} s.');
    } on DioException catch (e) {
      final response = e.response;
      if (response != null && response.statusCode != null) return response;
      if (e.type == DioExceptionType.receiveTimeout || e.type == DioExceptionType.connectionTimeout) {
        throw ZiToolError('timeout', 'The app API did not answer in ${timeout.inSeconds} s.');
      }
      throw const ZiToolError('network_error', 'The app API could not be reached.');
    }
  }

  static Object? _json(Object? data) {
    if (data is! String) return data;
    if (data.trim().isEmpty) return null;
    try {
      return jsonDecode(data);
    } on FormatException {
      throw const ZiToolError('handler_failed', 'The app API did not answer with JSON.');
    }
  }
}
