import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

import '../../ui/zehn_integrator.dart' show ZiToolError;
import '../bootstrap/bootstrap.dart';
import 'request_builder.dart';
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
    Dio? ownClient,
    this.timeout = const Duration(seconds: 20),
  }) : _appClient = appClient,
       _accessToken = accessToken,
       _onUnauthorized = onUnauthorized,
       _baseUrlOverride = baseUrlOverride,
       _own = ownClient ?? Dio();

  final Dio? _appClient;
  final FutureOr<String?> Function()? _accessToken;
  final FutureOr<bool> Function()? _onUnauthorized;
  final Uri? _baseUrlOverride;
  final Dio _own;
  final Duration timeout;

  bool get hasLogin => _appClient != null || _accessToken != null;

  /// The trimmed JSON answer. Throws [ZiToolError] the model can read.
  Future<Object?> call(ZiHttpTool tool, Map<String, Object?> args, ZiBootstrap boot, ZiRequestContext ctx) async {
    final request = buildRequest(tool, args, boot.api, ctx);
    final app = _appClient;
    final Response<Object?> response;
    if (app != null) {
      response = await _send(app, request.path, request, const {}, appDefaults: true);
    } else {
      response = await _callbacks(tool, request, boot.api);
    }
    final status = response.statusCode ?? 0;
    if (status == 401) {
      throw const ZiToolError('not_signed_in', 'Ask the user to sign in.');
    }
    if (status < 200 || status >= 300) {
      throw ZiToolError('http_error', 'The app API answered $status.');
    }
    return trimResult(_json(response.data), tool.result);
  }

  Future<Response<Object?>> _callbacks(ZiHttpTool tool, ZiHttpRequest request, ZiApiSettings api) async {
    final base = _baseUrlOverride ?? api.baseUrl;
    if (base == null) {
      throw const ZiToolError('host_not_allowed', 'No base URL is set for the app API.');
    }
    final url = '${base.toString().replaceAll(RegExp(r'/+$'), '')}${request.path}';
    final host = Uri.parse(url).host;
    if (host != base.host && !api.allowedHosts.contains(host)) {
      throw ZiToolError('host_not_allowed', 'The host $host is not allowed.');
    }
    var token = await _accessToken?.call();
    if (tool.auth && (token == null || token.isEmpty)) {
      throw const ZiToolError('not_signed_in', 'Ask the user to sign in.');
    }
    Map<String, String> login(String? t) =>
        t == null || t.isEmpty ? const {} : {api.authHeader: '${api.authScheme} $t'.trim()};

    var response = await _send(_own, url, request, login(token));
    if (response.statusCode == 401 && _onUnauthorized != null) {
      if (await _onUnauthorized()) {
        token = await _accessToken?.call();
        response = await _send(_own, url, request, login(token));
      }
    }
    return response;
  }

  Future<Response<Object?>> _send(
    Dio dio,
    String url,
    ZiHttpRequest request,
    Map<String, String> login, {
    bool appDefaults = false,
  }) async {
    try {
      return await dio
          .request<Object?>(
            url,
            queryParameters: request.query.isEmpty ? null : request.query,
            options: Options(
              method: request.method,
              headers: {...request.headers, ...login},
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
