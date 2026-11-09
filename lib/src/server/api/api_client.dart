import 'dart:convert';

import 'package:dio/dio.dart';

import 'client_info.dart';

/// An error from the console, or one the SDK names itself (`network_error`,
/// `server_unavailable`, `stream_interrupted`, `invalid_response`).
///
/// Switch on [code], never on [message].
class ZiApiException implements Exception {
  const ZiApiException(
    this.code, {
    this.status,
    this.params = const {},
    this.message = '',
    this.retryable = false,
  });

  /// Maps an error answer. Any 422 is `invalid_request`; a body that is not
  /// JSON (a proxy page) is `server_unavailable`; an unknown 5xx is retryable.
  factory ZiApiException.fromResponse(int status, Object? body) {
    if (body is! Map) {
      return ZiApiException(
        'server_unavailable',
        status: status,
        message: 'The server did not answer with JSON ($status).',
        retryable: true,
      );
    }
    final serverCode = body['code'];
    final code = status == 422
        ? 'invalid_request'
        : serverCode is String && serverCode.isNotEmpty
        ? serverCode
        : status >= 500
        ? 'internal_error'
        : 'invalid_request';
    final retryable = body['retryable'];
    final params = body['params'];
    final message = body['message'];
    return ZiApiException(
      code,
      status: status,
      params: params is Map ? params.cast<String, Object?>() : const {},
      message: message is String ? message : '',
      retryable: retryable is bool ? retryable : status >= 500,
    );
  }

  final String code;

  /// Null when there was no HTTP answer at all.
  final int? status;
  final Map<String, Object?> params;
  final String message;
  final bool retryable;

  @override
  String toString() => 'ZiApiException($code, $status): $message';
}

/// Talks to the console backend (`zi_console_url`). Every call carries the
/// `X-ZI-*` headers.
class ZiApiClient {
  ZiApiClient({required Uri baseUrl, required this.info, Dio? dio})
    : _base = baseUrl.toString().replaceAll(RegExp(r'/+$'), ''),
      _dio = dio ?? Dio() {
    _dio.options
      ..validateStatus = ((_) => true)
      ..connectTimeout = const Duration(seconds: 15)
      ..sendTimeout = const Duration(seconds: 30);
  }

  final String _base;
  final Dio _dio;
  final ZiClientInfo info;

  /// This install's id (`loadInstallId`); sent once known.
  String? installId;

  // No X-ZI-Spec-Version: with it the server treats the build as an old one
  // that pins a spec (no cards, no writes).
  Map<String, String> headers({String? userToken}) => {
    if (userToken != null) 'Authorization': 'Bearer $userToken',
    'X-ZI-App-Key': info.appKey,
    'X-ZI-Package': info.packageName,
    'X-ZI-App-Version': info.appVersion,
    'X-ZI-SDK-Version': info.sdkVersion,
    'X-ZI-Platform': info.platform,
    'X-ZI-Install-Id': ?installId,
  };

  Future<Object?> getJson(String path, {Map<String, String>? query, String? userToken}) =>
      _json('GET', path, query: query, userToken: userToken);

  Future<Object?> postJson(String path, Object body, {String? userToken}) =>
      _json('POST', path, body: body, userToken: userToken);

  /// Opens an event stream. Throws [ZiApiException] when the answer is an
  /// error or not `text/event-stream`.
  Future<ResponseBody> postStream(
    String path,
    Object body, {
    String? userToken,
    CancelToken? cancelToken,
  }) async {
    final Response<ResponseBody> response;
    try {
      response = await _dio.request<ResponseBody>(
        '$_base$path',
        data: jsonEncode(body),
        cancelToken: cancelToken,
        options: Options(
          method: 'POST',
          headers: {
            ...headers(userToken: userToken),
            'Content-Type': 'application/json',
            'Accept': 'text/event-stream',
          },
          responseType: ResponseType.stream,
        ),
      );
    } on DioException catch (e) {
      throw _network(e);
    }
    final status = response.statusCode ?? 0;
    final stream = response.data!;
    final type = response.headers.value('content-type') ?? '';
    if (status == 200 && type.contains('text/event-stream')) return stream;
    final text = await utf8.decoder.bind(stream.stream).join();
    if (status == 200) {
      throw const ZiApiException(
        'server_unavailable',
        status: 200,
        message: 'The answer was not an event stream.',
        retryable: true,
      );
    }
    throw ZiApiException.fromResponse(status, _decode(text));
  }

  Future<Object?> _json(
    String method,
    String path, {
    Object? body,
    Map<String, String>? query,
    String? userToken,
  }) async {
    final Response<String> response;
    try {
      response = await _dio.request<String>(
        '$_base$path',
        data: body == null ? null : jsonEncode(body),
        queryParameters: query,
        options: Options(
          method: method,
          headers: {
            ...headers(userToken: userToken),
            if (body != null) 'Content-Type': 'application/json',
          },
          responseType: ResponseType.plain,
          receiveTimeout: const Duration(seconds: 30),
        ),
      );
    } on DioException catch (e) {
      throw _network(e);
    }
    final status = response.statusCode ?? 0;
    final text = response.data ?? '';
    if (status >= 200 && status < 300) {
      if (text.trim().isEmpty) return null;
      final decoded = _decode(text);
      if (decoded == _notJson) {
        throw ZiApiException(
          'server_unavailable',
          status: status,
          message: 'The server did not answer with JSON.',
          retryable: true,
        );
      }
      return decoded;
    }
    throw ZiApiException.fromResponse(status, _decode(text));
  }

  static const Object _notJson = Object();

  static Object? _decode(String text) {
    try {
      return jsonDecode(text);
    } on FormatException {
      return _notJson;
    }
  }

  static ZiApiException _network(DioException e) {
    final response = e.response;
    if (response != null && response.statusCode != null) {
      return ZiApiException.fromResponse(response.statusCode!, response.data);
    }
    return ZiApiException(
      'network_error',
      message: e.message ?? e.type.name,
      retryable: true,
    );
  }
}
