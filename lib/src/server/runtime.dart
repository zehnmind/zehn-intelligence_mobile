import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../ui/zehn_integrator.dart' show ZiArg, ZiConfigException;
import 'api/api_client.dart';
import 'api/client_info.dart';
import 'api/turn_client.dart';
import 'auth/file_store.dart';
import 'auth/sign_out_watch.dart';
import 'auth/token_source.dart';
import 'chat/audio_queue.dart';
import 'chat/chat_cubit.dart';
import 'chat/chat_settings.dart';
import 'chat/history.dart';
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

/// Whose config a kept file is: the server and the key, so another app key
/// (the test key, then the production one) or another server never reads it.
/// The key itself stays out of the file: only a fingerprint of it is kept.
String _configOwner(ZiInitConfig config) {
  // FNV-1a, 32 bits: stable across launches, which String.hashCode isn't promised to be.
  var hash = 0x811c9dc5;
  for (final unit in config.appKey.codeUnits) {
    hash = ((hash ^ unit) * 0x01000193) & 0xffffffff;
  }
  return '${config.consoleUrl}|${hash.toRadixString(16)}';
}

/// The language the app is shown in above [context]: the locale its
/// `MaterialApp` (or any `WidgetsApp`) resolved. Null with no app above, or
/// when the app never chose one (no `locale:` and only Flutter's default
/// `en_US` supported), so Flutter's `en` isn't taken for the app's choice.
String? ziAppLanguageOf(BuildContext context) {
  final locale = Localizations.maybeLocaleOf(context);
  if (locale == null) return null;
  final app = context.findAncestorWidgetOfExactType<WidgetsApp>();
  final unchosen = app != null &&
      app.locale == null &&
      app.supportedLocales.length == 1 &&
      app.supportedLocales.single == const Locale('en', 'US');
  return unchosen ? null : locale.languageCode;
}

/// Everything `ZehnIntelligence.init` builds for the server flow.
class ZiRuntime {
  ZiRuntime._({
    required this.api,
    required this.info,
    required this.openRoute,
    required ZiTokenSource tokens,
    required this.builders,
    required ZiFileStore store,
    required String configFor,
  }) : _tokens = tokens,
       _store = store,
       _configFor = configFor;

  static ZiRuntime? instance;

  /// The file the last good `GET /v1/config` is kept in (`ZiFileStore`).
  static const _configFile = 'config';

  final ZiApiClient api;
  final ZiClientInfo info;

  /// From the last good `GET /v1/config`, this launch's or the one kept from
  /// an earlier launch; the SDK's defaults until there is one.
  final ValueNotifier<ZiChatSettings> settings = ValueNotifier(const ZiChatSettings());

  /// False once the console says nothing is published (`spec_not_found`):
  /// the assistant stays hidden.
  final ValueNotifier<bool> available = ValueNotifier(true);

  /// Whether [settings] is a config of the console's (this launch's, or the
  /// one kept from an earlier launch) and not the SDK's defaults. Until it
  /// is, the SDK's own button stays hidden: it can't know yet which screens
  /// it may show on, and without the server the chat can't answer anyway.
  final ValueNotifier<bool> hasConfig = ValueNotifier(false);

  /// Which build's config the kept file is: the server and the key.
  final String _configFor;

  /// The kept config as JSON, to write the file again only when it changed.
  String? _keptConfig;

  /// True until a config has loaded; set again by a failed try, so coming back
  /// to the foreground tries again ([retryConfig]).
  bool _configNeeded = true;
  Future<void>? _configLoad;

  /// Whether the SDK's own button shows on [screen], the open screen's path
  /// as the app's router writes it; null when the screen isn't known (then it
  /// shows, if there is a config at all).
  bool showsButtonOn(String? screen) =>
      available.value && hasConfig.value && settings.value.button.showsOn(screen);

  /// Notices a sign-out in the app's own Dio; null without one.
  ZiSignOutWatch? _signOut;

  /// Set once in [create]: the cubit reads the runtime's language and tokens.
  late final ZiChatCubit chat;
  final FutureOr<void> Function(String route)? openRoute;
  final Map<String, ZiComponentBuilder> builders;
  final ZiFileStore _store;
  ZiTokenSource _tokens;

  /// The user's past conversations (`/v1/conversations`).
  late final ZiHistory history = ZiHistory(api: api, tokens: () => _tokens);
  String? _language;
  String? _appLanguage;
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
    Map<String, Map<String, ZiArg>> toolArgs = const {},
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
      store: files,
      configFor: _configOwner(config),
    );
    // Any call, the chat's too, can learn the key or the app is refused.
    api.onUnavailable = runtime._assistantUnavailable;
    // The last good config, kept in a file: the button follows it from the
    // first frame, before the server answers (and with no network at all).
    await runtime._useKeptConfig();
    // The maps are the app's registrations themselves: one made after the
    // start is named from the next turn on.
    final turns = ZiTurnClient(
      api: api,
      tokens: () => runtime._tokens,
      registered: () => (tools: handlers.keys, components: builders.keys),
    );
    final tools = runtime._tools = ZiToolRunner(handlers: handlers, args: toolArgs, proxy: proxy);
    runtime.chat = ZiChatCubit(
      turns: turns,
      tools: tools,
      audio: AudioPlayerQueue(),
      language: () => runtime.language,
      starterSuggestions: runtime._starterSuggestions,
    );
    // A write is made only for an action the user confirmed in the chat.
    tools.takeConfirmed = runtime.chat.takeConfirmed;
    // With the app's own Dio, a sign-out (or another person signing in) is
    // noticed from the requests the app makes through it.
    if (client != null) {
      runtime._signOut = ZiSignOutWatch(dio: client, store: files, onSignOut: runtime.clearUser)..attach();
    }
    unawaited(runtime.loadConfig());
    return runtime;
  }

  /// The console refused this build (`invalid_key`, `key_revoked`,
  /// `app_mismatch`, `invalid_header`, `app_disabled`) or has nothing
  /// published (`spec_not_found`): hidden, whichever call it came to. It is
  /// tried again at the next start of the app, not before: the kept config is
  /// forgotten, so the button doesn't show in the meantime.
  void _assistantUnavailable(ZiApiException error) {
    debugPrint('zehn_intelligence: the console answered ${error.code}; the assistant is hidden');
    available.value = false;
    hasConfig.value = false;
    _configNeeded = false;
    _forgetting = _forgetConfig();
  }

  /// The deletion of the kept config that [_assistantUnavailable] began.
  Future<void>? _forgetting;

  /// Asks for `GET /v1/config`; calls made while one is under way share it.
  /// Never throws: a failure keeps the settings the SDK has, the kept config
  /// of an earlier launch among them.
  Future<void> loadConfig() => _configLoad ??= _fetchConfig().whenComplete(() => _configLoad = null);

  /// The app came back to the foreground: asks for the config again if the
  /// last try failed (offline, a 5xx) or none has loaded yet. With the button
  /// hidden the chat can't open, so opening the chat is no way to try again.
  Future<void> retryConfig() => _configNeeded ? loadConfig() : Future.value();

  Future<void> _fetchConfig() async {
    try {
      final body = await api.getJson('/v1/config');
      if (body is! Map) {
        throw const ZiApiException('invalid_response', message: 'The config is not a JSON object.');
      }
      settings.value = ZiChatSettings.fromJson(body);
      available.value = true;
      hasConfig.value = true;
      _configNeeded = false;
      await _keepConfig(body);
    } on ZiApiException catch (e) {
      if (ziUnavailableCodes.contains(e.code)) {
        // Already handled, by [_assistantUnavailable], as the call failed:
        // hidden, and nothing kept. Done once the file is gone.
        await _forgetting;
      } else {
        _configNeeded = true;
        debugPrint('zehn_intelligence: the chat settings could not be read: $e');
      }
    } on Object catch (e) {
      _configNeeded = true;
      debugPrint('zehn_intelligence: the chat settings could not be read: $e');
    }
  }

  /// Reads the config an earlier launch kept, if it is this build's.
  Future<void> _useKeptConfig() async {
    final kept = await _store.read(_configFile);
    final config = kept?['config'];
    if (kept == null || kept['for'] != _configFor || config is! Map) return;
    settings.value = ZiChatSettings.fromJson(config);
    _keptConfig = jsonEncode(config);
    hasConfig.value = true;
  }

  Future<void> _keepConfig(Map<Object?, Object?> config) async {
    final json = jsonEncode(config);
    if (json == _keptConfig) return;
    try {
      await _store.write(_configFile, {'for': _configFor, 'config': config});
      _keptConfig = json;
    } on Object catch (e) {
      debugPrint('zehn_intelligence: the chat settings could not be kept: $e');
    }
  }

  Future<void> _forgetConfig() async {
    _keptConfig = null;
    try {
      await _store.delete(_configFile);
    } on Object catch (e) {
      debugPrint('zehn_intelligence: the kept chat settings could not be deleted: $e');
    }
  }

  /// [ZehnIntelligence.setLanguage]'s, else the one the app is shown in, else
  /// the phone's, of those the assistant offers; else the assistant's default,
  /// else the first it offers.
  String get language {
    final chosen = _language;
    if (chosen != null) return chosen;
    final current = settings.value;
    final offered = current.languages.isNotEmpty ? current.languages : const ['uz', 'ru', 'en'];
    for (final code in [_appLanguage, PlatformDispatcher.instance.locale.languageCode]) {
      if (code != null && offered.contains(code)) return code;
    }
    return current.defaultLanguage ?? offered.first;
  }

  set language(String value) => _language = value;

  /// Takes the app's language from the widget tree ([ziAppLanguageOf]). The
  /// SDK's buttons call it as they draw, and they draw again when the app's
  /// language changes, so the next turn is in the new one.
  void readAppLanguage(BuildContext context) => _appLanguage = ziAppLanguageOf(context);

  /// A Zehn user token from the app's backend; null goes back to no token
  /// (the user is known by the install id).
  void setUserToken(FutureOr<String?> Function()? fetch) {
    _tokens = fetch != null ? CallbackTokenSource(fetch) : const AnonymousTokenSource();
  }

  /// Sign-out: forget the conversation and the user's token, and become a
  /// new install, so the next person on the phone doesn't see the history.
  Future<void> clearUser() async {
    chat.reset();
    setUserToken(null);
    api.installId = await renewInstallId(_store);
  }

  /// Asks the app's Dio who is signed in now ([ZiSignOutWatch.check]): after
  /// a sign-out, or another person signing in, a new install starts, so the
  /// chat opens empty. Done before the chat opens; never throws.
  Future<void> checkUser() async => _signOut?.check();

  /// Completes when what the sign-out watch has seen is dealt with (tests).
  @visibleForTesting
  Future<void> get signOutIdle async => _signOut?.idle;

  Future<void> openChat(BuildContext context, {String? title}) async {
    if (!available.value) {
      debugPrint('zehn_intelligence: nothing is published for this app yet; the chat stays closed');
      return;
    }
    unawaited(loadConfig());
    await checkUser();
    if (!context.mounted) return;
    await ZiChatSheet.show(
      context,
      cubit: chat,
      settings: settings,
      language: () => language,
      builders: builders,
      openRoute: openRoute,
      title: title,
      history: history,
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
