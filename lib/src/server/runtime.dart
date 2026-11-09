import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../ui/zehn_integrator.dart' show ZiConfigException;
import 'api/api_client.dart';
import 'api/client_info.dart';
import 'api/turn_client.dart';
import 'auth/file_store.dart';
import 'auth/token_source.dart';
import 'bootstrap/bootstrap_repository.dart';
import 'chat/audio_queue.dart';
import 'chat/chat_cubit.dart';
import 'proxy/proxy_executor.dart';
import 'proxy/request_builder.dart';
import 'proxy/tool_runner.dart';
import 'ui/chat_sheet.dart';

const ziDefaultConsoleUrl = 'https://zi-console-api.zehnmind.com';

/// Where the SDK connects and with which app key.
class ZiInitConfig {
  const ZiInitConfig({required this.appKey, required this.consoleUrl, this.specVersion});

  final String appKey;
  final Uri consoleUrl;

  /// From the config file, until start-up data says otherwise.
  final String? specVersion;
}

/// The first that applies: the argument, the config file, `--dart-define`,
/// then the default console URL. No app key anywhere throws
/// [ZiConfigException].
ZiInitConfig resolveInitConfig({
  String? token,
  Uri? consoleUrl,
  Map<String, Object?>? fileConfig,
  Map<String, String> defines = const {},
}) {
  String? pick(List<String> fileKeys, List<String> defineKeys) {
    for (final k in fileKeys) {
      final v = fileConfig?[k];
      if (v is String && v.trim().isNotEmpty) return v.trim();
    }
    for (final k in defineKeys) {
      final v = defines[k];
      if (v != null && v.trim().isNotEmpty) return v.trim();
    }
    return null;
  }

  final key = (token != null && token.trim().isNotEmpty)
      ? token.trim()
      : pick(['zi_app_key', 'ZEHN_API_KEY'], ['zi_app_key', 'ZEHN_API_KEY']);
  if (key == null) {
    throw const ZiConfigException('No app key: pass init(token: …) or build with the console config file.');
  }
  final url = consoleUrl ??
      Uri.tryParse(pick(['zi_console_url', 'ZEHN_INTELLIGENCE_CONFIG_URL'], ['zi_console_url', 'ZEHN_INTELLIGENCE_CONFIG_URL']) ?? '') ??
      Uri.parse(ziDefaultConsoleUrl);
  return ZiInitConfig(
    appKey: key,
    consoleUrl: url.host.isEmpty ? Uri.parse(ziDefaultConsoleUrl) : url,
    specVersion: pick(['zi_spec_version'], ['zi_spec_version']),
  );
}

/// Everything `ZehnIntelligence.init` builds for the server flow.
class ZiRuntime {
  ZiRuntime._({
    required this.api,
    required this.info,
    required this.bootstrap,
    required ZiFileStore store,
    required this.openRoute,
    required ZiTokenSource tokens,
    required this.builders,
  }) : _store = store,
       _tokens = tokens;

  static ZiRuntime? instance;

  final ZiApiClient api;
  final ZiClientInfo info;
  final ZiBootstrapRepository bootstrap;
  final ZiFileStore _store;

  /// Set once in [create]: the cubit reads the runtime's language and tokens.
  late final ZiChatCubit chat;
  final FutureOr<void> Function(String route)? openRoute;
  final Map<String, ZiComponentBuilder> builders;
  ZiTokenSource _tokens;
  String? _language;
  late final ZiToolRunner _tools;

  @visibleForTesting
  ZiTokenSource get tokens => _tokens;

  @visibleForTesting
  ZiToolRunner get tools => _tools;

  static Future<ZiRuntime> create({
    required ZiInitConfig config,
    required ZiClientInfo info,
    Dio? client,
    FutureOr<String?> Function()? accessToken,
    FutureOr<bool> Function()? onUnauthorized,
    Uri? apiBaseUrl,
    FutureOr<bool> Function()? isSignedIn,
    FutureOr<String?> Function()? userToken,
    FutureOr<void> Function(String route)? openRoute,
    Map<String, ZiToolHandler> handlers = const {},
    Map<String, ZiComponentBuilder> builders = const {},
    ZiFileStore? store,
  }) async {
    final files = store ?? ZiFileStore();
    final api = ZiApiClient(baseUrl: config.consoleUrl, info: info)..specVersion = config.specVersion;
    final bootstrap = ZiBootstrapRepository(api: api, store: files);
    await bootstrap.loadCached();
    unawaited(bootstrap.refresh());

    if (client != null && (accessToken != null || onUnauthorized != null)) {
      debugPrint('zehn_intelligence: both client and accessToken/onUnauthorized were given; the client is used');
    }
    final proxy = client != null
        ? ZiProxyExecutor(appClient: client, isSignedIn: isSignedIn)
        : ZiProxyExecutor(
            accessToken: accessToken,
            onUnauthorized: onUnauthorized,
            baseUrlOverride: apiBaseUrl,
            isSignedIn: isSignedIn,
          );

    final runtime = ZiRuntime._(
      api: api,
      info: info,
      bootstrap: bootstrap,
      store: files,
      openRoute: openRoute,
      tokens: userToken != null ? CallbackTokenSource(userToken) : InstallTokenSource(api: api, store: files),
      builders: builders,
    );
    final turns = ZiTurnClient(api: api, tokens: () => runtime._tokens);
    final tools = runtime._tools = ZiToolRunner(
      handlers: handlers,
      proxy: proxy,
      bootstrap: bootstrap,
      context: () => ZiRequestContext(language: runtime.language, appVersion: info.appVersion, platform: info.platform),
    );
    runtime.chat = ZiChatCubit(
      turns: turns,
      tools: tools,
      audio: AudioPlayerQueue(),
      language: () => runtime.language,
      starterSuggestions: runtime._starterSuggestions,
    );
    // Data-changing tools ask the user in the chat first.
    tools.confirmer = runtime.chat.confirm;
    return runtime;
  }

  /// The app's choice ([ZehnIntelligence.setLanguage]), else the phone's if
  /// the assistant offers it, else the start-up default, else `en`.
  String get language {
    final chosen = _language;
    final offered = bootstrap.current?.languages ?? const ['uz', 'ru', 'en'];
    if (chosen != null) return chosen;
    final device = PlatformDispatcher.instance.locale.languageCode;
    if (offered.contains(device)) return device;
    return bootstrap.current?.defaultLanguage ?? (offered.isNotEmpty ? offered.first : 'en');
  }

  set language(String value) => _language = value;

  /// A Zehn user token from the app's backend; null goes back to the install token.
  void setUserToken(FutureOr<String?> Function()? fetch) {
    _tokens = fetch != null ? CallbackTokenSource(fetch) : InstallTokenSource(api: api, store: _store);
  }

  /// Sign-out: forget the conversation and the user's token.
  Future<void> clearUser() async {
    chat.reset();
    setUserToken(null);
  }

  Future<void> openChat(BuildContext context, {String? title}) => ZiChatSheet.show(
    context,
    cubit: chat,
    bootstrap: bootstrap,
    language: () => language,
    builders: builders,
    openRoute: openRoute,
    title: title,
  );

  Future<List<String>> _starterSuggestions() async {
    Future<Object?> get(String token) =>
        api.getJson('/v1/suggestions', query: {'language': language}, userToken: token);
    Object? body;
    try {
      body = await get(await _tokens.token());
    } on ZiApiException catch (e) {
      if (e.code != 'user_token_expired' && e.code != 'user_token_required') rethrow;
      body = await get(await _tokens.refresh());
    }
    final list = body is Map ? body['suggestions'] : null;
    return list is List ? [for (final s in list) if (s is String) s] : const [];
  }
}
