import 'dart:convert';

import 'package:dio/dio.dart';

import '../log.dart';
import '../transport/zehn.dart';
import 'agent_remote_config.dart';
import 'config_caps.dart';

/// Which config a build reads: what is live for users, or the draft the
/// dashboard is still editing — for debug builds, with a key allowed to.
enum AgentConfigChannel { live, draft }

/// The outcome of one config request.
sealed class AgentConfigFetch {
  const AgentConfigFetch();
}

/// A config arrived. [body] is kept as it came, for the cache.
final class ConfigFetched extends AgentConfigFetch {
  const ConfigFetched(this.envelope, this.body, {this.etag});

  final AgentConfigEnvelope envelope;
  final String body;
  final String? etag;
}

/// Nothing changed since [etag].
final class ConfigNotModified extends AgentConfigFetch {
  const ConfigNotModified();
}

/// The backend has no such agent — or the app's project disconnected the
/// service. The app goes back to its own code.
///
/// Only on the backend's own `agent_not_found`: any other 404 — a gateway's
/// page during a deploy, a proxy that does not forward the path — keeps what
/// the app has, so a tool switched off on the dashboard stays off.
final class ConfigGone extends AgentConfigFetch {
  const ConfigGone();
}

/// No answer worth acting on: offline, refused, or unreadable. The app keeps
/// what it has.
final class ConfigUnavailable extends AgentConfigFetch {
  const ConfigUnavailable(this.reason, {this.retryAfter});

  final String reason;
  final Duration? retryAfter;
}

/// Reads a published config: `GET agents/{agentId}/config`.
///
/// Its own bare client, like the chat transport's: the app's API client
/// carries the user's token, which must never reach this server. Through a
/// proxy, pass the proxy's URL and no key.
class AgentConfigClient {
  AgentConfigClient({
    String baseUrl = Zehn.baseUrl,
    String apiKey = '',
    Dio? httpClient,
    HttpClientAdapter? httpClientAdapter,
    Duration timeout = const Duration(seconds: 15),
    this.log = silentAgentLog,
  }) : _dio =
           httpClient ?? _bareDio(baseUrl, apiKey, timeout, httpClientAdapter);

  static Dio _bareDio(
    String baseUrl,
    String apiKey,
    Duration timeout,
    HttpClientAdapter? adapter,
  ) {
    final dio = Dio(
      BaseOptions(
        // Paths below are relative: `…/v1` and `…/v1/` both mean the same.
        baseUrl: baseUrl.endsWith('/') ? baseUrl : '$baseUrl/',
        connectTimeout: timeout,
        receiveTimeout: timeout,
        responseType: ResponseType.plain,
        // Every status is read below; none is an exception.
        validateStatus: (_) => true,
        headers: {
          if (apiKey.trim().isNotEmpty) 'Authorization': 'Bearer $apiKey',
        },
      ),
    );
    if (adapter != null) dio.httpClientAdapter = adapter;
    return dio;
  }

  final Dio _dio;
  final AgentLog log;

  Future<AgentConfigFetch> fetch({
    required String agentId,
    required String appVersion,
    required String pluginVersion,
    AgentConfigChannel channel = AgentConfigChannel.live,
    String? etag,
  }) async {
    final Response<String> response;
    try {
      response = await _dio.get<String>(
        'agents/${Uri.encodeComponent(agentId)}/config',
        queryParameters: {
          'app_version': appVersion,
          'plugin_version': pluginVersion,
          'schema': AgentConfigCaps.schemaVersion,
          'channel': channel.name,
        },
        options: Options(headers: {'If-None-Match': ?etag}),
      );
    } on DioException catch (e) {
      // Never log the request: its headers carry the key.
      return ConfigUnavailable(e.type.name);
    }

    final status = response.statusCode ?? 0;
    switch (status) {
      case 304:
        return const ConfigNotModified();
      case 404 when _errorCode(response.data) == 'agent_not_found':
        return const ConfigGone();
      case 200:
        final body = response.data ?? '';
        if (utf8.encode(body).length > AgentConfigCaps.responseBytes) {
          return const ConfigUnavailable('response too large');
        }
        final Object? json;
        try {
          json = jsonDecode(body);
        } on FormatException {
          return const ConfigUnavailable('response is not JSON');
        }
        final problems = <String>[];
        final envelope = AgentConfigEnvelope.fromJson(json, problems: problems);
        if (envelope == null) {
          return ConfigUnavailable(problems.join('; '));
        }
        return ConfigFetched(
          envelope,
          body,
          etag: response.headers.value('etag'),
        );
      default:
        final retry = int.tryParse(response.headers.value('retry-after') ?? '');
        final code = _errorCode(response.data);
        return ConfigUnavailable(
          code == null ? 'status $status' : 'status $status ($code)',
          retryAfter: retry == null ? null : Duration(seconds: retry),
        );
    }
  }

  /// `error.code` of the contract's error body, if [body] is one.
  static String? _errorCode(String? body) {
    if (body == null || body.length > 4096) return null;
    try {
      final json = jsonDecode(body);
      final error = json is Map ? json['error'] : null;
      final code = error is Map ? error['code'] : null;
      return code is String ? code : null;
    } on FormatException {
      return null;
    }
  }
}
