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
import 'chat/audio_queue.dart';
import 'chat/chat_cubit.dart';
import 'chat/chat_settings.dart';
import 'proxy/proxy_executor.dart';
import 'proxy/tool_runner.dart';
import 'ui/chat_sheet.dart';

const ziDefaultConsoleUrl = 'https://zi-console-api.zehnmind.com';

/// Where the SDK connects and with which app key.
class ZiInitConfig {
  const ZiInitConfig({required this.appKey, required this.consoleUrl});

  final String appKey;
  final Uri consoleUrl;
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
  );
}

/// Everything `ZehnIntelligence.init` builds for the server flow.
class ZiRuntime {
  ZiRuntime._({
    required this.api,
    required this.info,
    required this.openRoute,
    required ZiTokenSource tokens,
    required this.builders,
  }) : _tokens = tokens;

  static ZiRuntime? instance;

  final ZiApiClient api;
  final ZiClientInfo info;

  /// From the last good `GET /v1/config`; the SDK's defaults until then.
  final ValueNotifier<ZiChatSettings> settings = ValueNotifier(const ZiChatSettings());

  /// False once the console says nothing is published (`spec_not_found`):
  /// the assistant stays hidden.
  final ValueNotifier<bool> available = ValueNotifier(true);
  Future<void>? _configLoad;

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
    final api = ZiApiClient(baseUrl: config.consoleUrl, info: info)..installId = await loadInstallId(files);

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
      openRoute: openRoute,
      tokens: userToken != null ? CallbackTokenSource(userToken) : const AnonymousTokenSource(),
      builders: builders,
    );
    final turns = ZiTurnClient(api: api, tokens: () => runtime._tokens);
    final tools = runtime._tools = ZiToolRunner(handlers: handlers, proxy: proxy);
    runtime.chat = ZiChatCubit(
      turns: turns,
      tools: tools,
      audio: AudioPlayerQueue(),
      language: () => runtime.language,
      starterSuggestions: runtime._starterSuggestions,
    );
    // A write is made only for an action the user confirmed in the chat.
    tools.takeConfirmed = runtime.chat.takeConfirmed;
    unawaited(runtime.loadConfig());
    return runtime;
  }

  /// Asks for `GET /v1/config`; calls made while one is under way share it.
  /// Never throws: a failure keeps the settings the SDK has.
  Future<void> loadConfig() => _configLoad ??= _fetchConfig().whenComplete(() => _configLoad = null);

  Future<void> _fetchConfig() async {
    try {
      settings.value = ZiChatSettings.fromJson(await api.getJson('/v1/config'));
      available.value = true;
    } on ZiApiException catch (e) {
      if (e.code == 'spec_not_found') available.value = false;
    } on Object catch (e) {
      debugPrint('zehn_intelligence: the chat settings could not be read: $e');
    }
  }

  /// The app's choice ([ZehnIntelligence.setLanguage]), else the phone's if
  /// the assistant offers it, else the assistant's default, else `en`.
  String get language {
    final chosen = _language;
    if (chosen != null) return chosen;
    final current = settings.value;
    final offered = current.languages.isNotEmpty ? current.languages : const ['uz', 'ru', 'en'];
    final device = PlatformDispatcher.instance.locale.languageCode;
    if (offered.contains(device)) return device;
    return current.defaultLanguage ?? offered.first;
  }

  set language(String value) => _language = value;

  /// A Zehn user token from the app's backend; null goes back to no token
  /// (the user is known by the install id).
  void setUserToken(FutureOr<String?> Function()? fetch) {
    _tokens = fetch != null ? CallbackTokenSource(fetch) : const AnonymousTokenSource();
  }

  /// Sign-out: forget the conversation and the user's token.
  Future<void> clearUser() async {
    chat.reset();
    setUserToken(null);
  }

  Future<void> openChat(BuildContext context, {String? title}) {
    if (!available.value) {
      debugPrint('zehn_intelligence: nothing is published for this app yet; the chat stays closed');
      return Future.value();
    }
    unawaited(loadConfig());
    return ZiChatSheet.show(
    context,
    cubit: chat,
    settings: settings,
    language: () => language,
    builders: builders,
    openRoute: openRoute,
    title: title,
  );
  }

  Future<List<String>> _starterSuggestions() async {
    Future<Object?> get(String? token) =>
        api.getJson('/v1/suggestions', query: {'language': language}, userToken: token);
    Object? body;
    try {
      body = await get(await _tokens.token());
    } on ZiApiException catch (e) {
      final fresh = e.code == 'user_token_expired' || e.code == 'user_token_required' ? await _tokens.refresh() : null;
      if (fresh == null) rethrow;
      body = await get(fresh);
    }
    final list = body is Map ? body['suggestions'] : null;
    return list is List ? [for (final s in list) if (s is String) s] : const [];
  }
}
