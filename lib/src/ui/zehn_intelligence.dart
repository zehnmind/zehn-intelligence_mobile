import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'package:dio/dio.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../core/cards/card_check.dart';
import '../core/config/agent_config_client.dart';
import '../core/config/agent_config_sync.dart';
import '../core/config/agent_remote_config.dart';
import '../core/engine/agent_engine.dart';
import '../core/engine/agent_state.dart';
import '../core/entities/entity_store.dart';
import '../core/log.dart';
import '../core/schema/prop_schema.dart';
import '../core/text/default_copy.dart';
import '../core/text/localized_text.dart';
import '../core/tools/agent_tool.dart';
import '../core/tools/tool_registry.dart';
import '../core/tools/tool_result.dart';
import '../core/transport/agent_transport.dart';
import '../core/transport/example_transport.dart';
import '../core/transport/fallback_transport.dart';
import '../core/transport/openai_compatible_transport.dart';
import '../core/transport/zehn.dart';
import '../server/api/client_info.dart';
import '../server/runtime.dart';
import '../version.dart';
import '../voice/zehn_voice.dart';
import 'chat/agent_chat_bloc.dart';
import 'components/agent_component.dart';
import 'components/agent_component_registry.dart';
import 'components/agent_pack.dart';
import 'components/dashboard_card_component.dart';
import 'destinations/agent_destination.dart';
import 'destinations/agent_link.dart';
import 'scope/agent_scope.dart';
import 'zehn_integrator.dart';

/// The in-app ZehnIntelligence: one per app, created at start-up and kept for the life
/// of the app.
///
/// ```dart
/// final intelligence = ZehnIntelligence(
///   profile: AgentProfile(appName: 'Demo Bank', languages: ['uz', 'ru', 'en']),
///   transport: OpenAiCompatibleTransport.zehn(apiKey: zehnKey),
///   session: MySession(),
///   packs: [accountsPack(repo), cardsPack(repo)],
/// );
/// ```
///
/// Everything the model may do is registered here and can change at run
/// time: [install] and [uninstall] packs, switch tools with [setEnabled],
/// and tell `availableWhen` predicates what the user is looking at with
/// [setFlag]. The catalog, the prompt and the gate read the registries on
/// every turn.
class ZehnIntelligence {
  ZehnIntelligence({
    required this.profile,
    required AgentTransport transport,
    required this.session,
    Iterable<AgentPack> packs = const [],
    Iterable<AgentTool> tools = const [],
    Iterable<AgentComponent> components = const [],
    Iterable<AgentDestination> destinations = const [],
    this.log = silentAgentLog,
    this.voice,
    this.stepUp,
    this.openLink,
    this.agentId,
    String textExample = 'Your order will arrive tomorrow.',
  }) : entities = EntityStore(),
       tools = AgentToolRegistry(order: profile.catalogOrder) {
    this.components = AgentComponentRegistry(
      entities: entities,
      log: log,
      textExample: textExample,
    );
    this.destinations = AgentDestinationRegistry(log: log);

    this.tools.addAll(tools);
    components.forEach(this.components.add);
    destinations.forEach(this.destinations.add);
    packs.forEach(install);

    engine = AgentEngine(
      tools: this.tools,
      transport: transport,
      session: session,
      entities: entities,
      components: this.components,
      profile: profile,
      log: log,
    );
  }

  /// The intelligence `start` made, for widgets with no `AgentScope` above them.
  static ZehnIntelligence? instance;

  /// True when the assistant has been started and is ready.
  static bool get isInitialized => ZiRuntime.instance != null || instance != null;

  /// Changes the active language of the assistant.
  static void setLanguage(String language) {
    instance?.displayLanguage = language;
    ZiRuntime.instance?.language = language;
  }

  /// Informs the assistant that the user has signed in. A [token] is a Zehn
  /// user token from the app's own backend.
  static void signedIn({String? token}) {
    if (token != null && token.isNotEmpty) setUser(token);
  }

  /// A Zehn user token from the app's backend (`POST /v1/user-tokens` with
  /// its server key). [onTokenExpired] gets a new one when the server says it
  /// expired. Without one, the assistant uses an anonymous token per install.
  static void setUser(dynamic token, {FutureOr<dynamic> Function()? onTokenExpired}) {
    var first = true;
    ZiRuntime.instance?.setUserToken(() async {
      if (first) {
        first = false;
        if (token is String && token.isNotEmpty) return token;
      }
      final next = await onTokenExpired?.call();
      return next is String && next.isNotEmpty ? next : null;
    });
  }

  /// Informs the assistant that the user has signed out.
  static void signedOut() => clearUser();

  /// Forgets the user's token and conversation.
  static void clearUser() {
    instance?.clearUserData();
    unawaited(ZiRuntime.instance?.clearUser());
  }

  /// Registry of tools added via the integrator.
  static final Map<String, Future<Map<String, Object?>> Function(Map<String, Object?>)> registeredTools = {};

  /// Registers a tool handler by name.
  static void registerTool(String name, Future<Map<String, Object?>> Function(Map<String, Object?>) handler) {
    registeredTools[name] = handler;
    if (instance != null) {
      final parts = name.split('.');
      final domain = parts.first.replaceAll('_', ' ');
      final verb = parts.length > 1 ? parts.last.replaceAll('_', ' ') : '';
      instance!.tools.add(
        AgentTool(
          name: name,
          description: name,
          kind: ToolKind.read,
          doc: ToolDoc(
            summary: name,
            examples: {
              'en': [domain, '$domain $verb', '$verb $domain', ...domain.split(' ')],
              'uz': [domain, ...domain.split(' ')],
              'ru': [domain, ...domain.split(' ')],
            },
          ),
          run: (call) async {
            try {
              final res = await handler(call.args);
              return ToolResult(tool: name, ok: true, summary: 'OK', data: res);
            } catch (e) {
              return ToolResult.failure(name, e.toString());
            }
          },
        ),
      );
    }
  }

  /// Registry of components added via the integrator.
  static final Map<String, Widget Function(BuildContext, Map<String, Object?>, ZiComponentController)> registeredComponents = {};

  /// Registers a UI component builder by name.
  static void registerComponent(
    String name,
    Widget Function(BuildContext, Map<String, Object?>, ZiComponentController) builder,
  ) {
    registeredComponents[name] = builder;
  }

  /// Starts the assistant. The only call an app needs, in `main()`:
  ///
  /// ```dart
  /// await ZehnIntelligence.init(
  ///   token: 'zi_prod_…',                    // the app key from the console
  ///   client: di<Dio>(),                     // or accessToken: / onUnauthorized:
  ///   openRoute: (route) => router.push(route),
  /// );
  /// ```
  ///
  /// The assistant talks only to the Zehn console ([consoleUrl], default
  /// `https://zi-console-api.zehnmind.com`). Tools run as requests to the
  /// app's own API, built from what the console publishes: through the app's
  /// [client] (its base URL, auth and refresh), or with [accessToken],
  /// [onUnauthorized] and the console's (or [apiBaseUrl]'s) base URL.
  /// [isSignedIn] keeps login-only tools from being called for a signed-out
  /// user (pass it with [client]: the app's own 401 handling may sign the
  /// user out). Pages open through [openRoute]. [userToken] is a Zehn user token from the
  /// app's backend; without one an anonymous token per install is used.
  ///
  /// [token] falls back to the config file at [configPath] and then to
  /// `--dart-define`. Throws [ZiConfigException] when there is no app key; a
  /// network problem never throws (the last saved start-up data is used).
  /// [appName] and [onOpenRoute] are accepted for older code and unused.
  static Future<void> init({
    String? token,
    Uri? consoleUrl,
    Dio? client,
    FutureOr<String?> Function()? accessToken,
    FutureOr<bool> Function()? onUnauthorized,
    Uri? apiBaseUrl,
    FutureOr<bool> Function()? isSignedIn,
    FutureOr<String?> Function()? userToken,
    FutureOr<void> Function(String route)? openRoute,
    String? appName,
    String configPath = 'lib/config/zehn-intelligence.prod.json',
    FutureOr<void> Function(BuildContext, dynamic)? onOpenRoute,
  }) async {
    WidgetsFlutterBinding.ensureInitialized();
    final config = resolveInitConfig(
      token: token,
      consoleUrl: consoleUrl,
      fileConfig: await _readConfigFile(configPath),
      defines: const {
        'zi_app_key': String.fromEnvironment('zi_app_key'),
        'ZEHN_API_KEY': String.fromEnvironment('ZEHN_API_KEY'),
        'zi_console_url': String.fromEnvironment('zi_console_url'),
        'ZEHN_INTELLIGENCE_CONFIG_URL': String.fromEnvironment('ZEHN_INTELLIGENCE_CONFIG_URL'),
        'zi_spec_version': String.fromEnvironment('zi_spec_version'),
      },
    );
    final package = await PackageInfo.fromPlatform();
    final build = package.buildNumber.isEmpty ? '' : '+${package.buildNumber}';
    ZiRuntime.instance = await ZiRuntime.create(
      config: config,
      info: ZiClientInfo(
        appKey: config.appKey,
        packageName: package.packageName,
        appVersion: '${package.version}$build',
        sdkVersion: zehnIntelligenceVersion,
        platform: Platform.isIOS ? 'ios' : (Platform.isAndroid ? 'android' : Platform.operatingSystem),
      ),
      client: client,
      accessToken: accessToken,
      onUnauthorized: onUnauthorized,
      apiBaseUrl: apiBaseUrl,
      isSignedIn: isSignedIn,
      userToken: userToken,
      openRoute: openRoute,
      handlers: registeredTools,
      builders: registeredComponents,
    );
  }

  /// The console config file, if the app bundles one; only for fallbacks.
  static Future<Map<String, Object?>?> _readConfigFile(String configPath) async {
    Map<String, dynamic>? config;

    for (final path in [
      configPath,
      'config/zehn-intelligence.prod.json',
      'assets/config/zehn-intelligence.prod.json',
    ]) {
      try {
        final text = await rootBundle.loadString(path);
        if (text.trim().isNotEmpty) {
          config = jsonDecode(text) as Map<String, dynamic>?;
          if (config != null) break;
        }
      } catch (_) {}
    }

    if (config == null) {
      for (final path in [
        configPath,
        'config/zehn-intelligence.prod.json',
      ]) {
        try {
          final file = File(path);
          if (file.existsSync()) {
            final text = file.readAsStringSync();
            if (text.trim().isNotEmpty) {
              config = jsonDecode(text) as Map<String, dynamic>?;
              if (config != null) break;
            }
          }
        } catch (_) {}
      }
    }

    return config;
  }

  /// Everything set up in one call — the model, voice, tools and packs:
  ///
  /// ```dart
  /// await ZehnIntelligence.start(
  ///   appName: 'My Shop',
  ///   apiKey: const String.fromEnvironment('ZEHN_API_KEY'),
  ///   packs: [ordersPack],
  /// );
  /// runApp(const MyApp());          // then AgentButton() in any Scaffold
  /// ```
  ///
  /// * **The model:** Zehn with [apiKey], or your own backend at [proxy]
  ///   (which keeps the key off the device). With neither, the assistant
  ///   answers from each tool's example questions only — enough to try it.
  ///   With one, those examples still answer when the network fails.
  /// * **Voice:** from the same key or proxy, unless [voice] is false.
  /// * **The user:** [isSignedIn] and [languageCode] read the
  ///   app's own state — or pass a whole [session]. Without [isSignedIn],
  ///   tools that need sign-in are never offered. Without [languageCode], the
  ///   language is the one the chat is shown in.
  /// * **The dashboard:** with an [agentId], what the dashboard publishes for
  ///   this app — app context, switches — is read, kept on the
  ///   phone, and refreshed when the chat opens. With [configUrl], that is
  ///   the Zehn Intelligence console's backend, read with [configKey], the project
  ///   key the console gives the app: the model's [apiKey] never goes there,
  ///   nor [configKey] to the model. Without [configUrl], it is what
  ///   zehn/devs publishes, read with the same key or proxy as the model.
  ///   [configChannel] `draft` reads the unpublished draft, for debug builds
  ///   with a key allowed to.
  /// * **Links:** destinations declared with a link open as the phone
  ///   delivers a deep link, unless [openLink] says otherwise — for
  ///   go_router, `AgentLinks.goOrPush(go: router.go, push: router.push)`.
  ///
  /// The intelligence is also [instance], so `AgentButton` and `AgentChatSheet`
  /// work without an `AgentScope`.
  ///
  /// Deprecated: this runs the model on the phone against `api.zehnmind.com`,
  /// which the console backend no longer allows.
  @Deprecated('Use ZehnIntelligence.init')
  static Future<ZehnIntelligence> start({
    String? appName,
    AgentProfile? profile,
    String apiKey = '',
    Uri? proxy,
    Iterable<AgentPack> packs = const [],
    Iterable<AgentTool> tools = const [],
    Iterable<AgentComponent> components = const [],
    Iterable<AgentDestination> destinations = const [],
    List<String> languages = const ['uz', 'ru', 'en'],
    AgentSession? session,
    bool Function()? isSignedIn,
    String Function()? languageCode,
    AgentStepUp? stepUp,
    AgentLinkOpener? openLink,
    String? agentId,
    String? appVersion,
    Uri? configUrl,
    String configKey = '',
    AgentConfigChannel configChannel = AgentConfigChannel.live,
    bool voice = true,
    AgentTransport? offline,
    String textExample = 'Your order will arrive tomorrow.',
    AgentLog? log,
  }) async {
    assert(
      appName != null || profile != null,
      'ZehnIntelligence.start needs an appName or a profile',
    );
    WidgetsFlutterBinding.ensureInitialized();
    final logger = log ?? (kDebugMode ? debugPrint : silentAgentLog);
    final theProfile =
        profile ??
        AgentProfile(
          appName: appName!,
          languages: languages,
          defaultLanguage: languages.first,
        );

    late final ZehnIntelligence intelligence;
    String shownLanguage() {
      final shown = intelligence.displayLanguage;
      if (shown != null && theProfile.languages.contains(shown)) return shown;
      final device =
          WidgetsBinding.instance.platformDispatcher.locale.languageCode;
      return theProfile.languages.contains(device)
          ? device
          : theProfile.defaultLanguage;
    }

    final theSession =
        session ??
        AgentSession.from(
          isSignedIn: isSignedIn,
          languageCode: languageCode ?? shownLanguage,
        );

    final examples = offline ?? ExampleTransport(() => intelligence.tools);
    final model = proxy != null
        ? OpenAiCompatibleTransport(
            baseUrl: '$proxy',
            apiKey: '',
            label: 'proxy',
            log: logger,
          )
        : apiKey.trim().isNotEmpty
        ? OpenAiCompatibleTransport.zehn(apiKey: apiKey, log: logger)
        : null;
    if (model == null) {
      logger(
        'zehn_intelligence: no apiKey or proxy — answering from the tools\' example '
        'questions only. Pass apiKey: const String.fromEnvironment('
        '\'ZEHN_API_KEY\') and run with '
        '--dart-define-from-file=config/zehn.json.',
      );
    }

    intelligence = ZehnIntelligence(
      profile: theProfile,
      transport: model == null
          ? examples
          : FallbackTransport([model, examples], log: logger),
      session: theSession,
      packs: packs,
      tools: tools,
      components: components,
      destinations: destinations,
      textExample: textExample,
      log: logger,
      voice: voice
          ? ZehnVoice(
              apiKey: apiKey,
              baseUrl: proxy == null ? Zehn.baseUrl : '$proxy',
              log: logger,
            )
          : null,
      stepUp: stepUp,
      openLink: openLink,
      agentId: agentId,
    );
    final target = configTarget(
      proxy: proxy,
      apiKey: apiKey,
      configUrl: configUrl,
      configKey: configKey,
    );
    if (agentId != null && target != null) {
      intelligence.connectConfig(
        appVersion: appVersion ?? await _appVersion(),
        baseUrl: target.baseUrl,
        apiKey: target.apiKey,
        channel: configChannel,
      );
    }
    return instance = intelligence;
  }

  final AgentProfile profile;
  final AgentSession session;

  /// Hold to speak and spoken replies; null when the app turned voice off.
  /// Chats pick it up by themselves.
  final ZehnVoice? voice;

  /// How the app verifies the user again before a write whose card asks
  /// for it. An `AgentScope(stepUp:)` above the app wins over it.
  final AgentStepUp? stepUp;

  /// How destinations declared with a link open. Null means
  /// [AgentLinks.deliver]: as the phone delivers a deep link.
  final AgentLinkOpener? openLink;

  /// The language the chat is shown in, as the chat last saw it. The session
  /// `start` builds answers in it.
  String? displayLanguage;

  final AgentLog log;

  /// The id the dashboard knows this app's assistant by, e.g. `my_shop`. Null
  /// when the app is not configured from a dashboard.
  final String? agentId;

  /// What this conversation fetched, and the id lists the app vouches for.
  final EntityStore entities;
  final AgentToolRegistry tools;
  late final AgentComponentRegistry components;
  late final AgentDestinationRegistry destinations;
  late final AgentEngine engine;

  final Map<String, AgentPack> _packs = {};
  AgentChatBloc? _chat;

  /// The live conversation. Provide it above the app's navigator —
  /// `AgentScope` does — so it outlives the chat sheet.
  AgentChatBloc get chat =>
      _chat ??= AgentChatBloc(engine: engine, entities: entities, log: log);

  /// Swaps the model, e.g. once a key arrives from remote config.
  set transport(AgentTransport transport) {
    engine.transport = transport;
  }

  Iterable<String> get installedPacks => _packs.keys;

  /// The installed packs, in the order they were installed.
  Iterable<AgentPack> get packs => _packs.values;

  /// Adds a pack's tools, components, destinations and id lists. Throws if
  /// any of them is declared unsafely or clashes with one already there.
  void install(AgentPack pack) {
    if (_packs.containsKey(pack.id)) {
      throw AgentRegistrationError('pack "${pack.id}" is already installed');
    }
    tools.addAll(pack.tools);
    pack.components.forEach(components.add);
    pack.destinations.forEach(destinations.add);
    pack.allowlists.forEach(entities.addSource);
    _packs[pack.id] = pack;
    log('intelligence: installed pack ${pack.id}');
    // A pack the dashboard switched off stays off when the app installs it.
    if (_config != null) applyConfig(_config, revision: _configRevision);
  }

  /// The installed pack [id], or null.
  AgentPack? pack(String id) => _packs[id];

  /// Removes everything [install] added for the pack [id].
  bool uninstall(String id) {
    final pack = _packs.remove(id);
    if (pack == null) return false;
    for (final tool in pack.tools) {
      tools.remove(tool.name);
    }
    for (final component in pack.components) {
      components.remove(component.type);
    }
    for (final destination in pack.destinations) {
      destinations.remove(destination.id);
    }
    pack.allowlists.forEach(entities.removeSource);
    log('intelligence: uninstalled pack $id');
    return true;
  }

  /// Switches a tool on or off without removing it.
  void setEnabled(String tool, bool enabled) => tools.setEnabled(tool, enabled);

  /// Tells `availableWhen` predicates something about the app — which
  /// screen is open, which feature is on. Null removes the flag.
  void setFlag(String name, Object? value) {
    if (value == null) {
      engine.flags.remove(name);
    } else {
      engine.flags[name] = value;
    }
  }

  /// Forgets everything the assistant holds about the user: the live
  /// conversation and the ids it fetched, the saved conversations, and the
  /// notes. Call it on sign-out.
  Future<void> clearUserData() async {
    entities.clear();
    chat.add(const AgentConversationCleared());
  }

  static const _builtInTools = <String>{};

  // ── What the dashboard set ────────────────────────────────────────────────

  AgentConfigSync? _sync;

  /// Where a debug or profile build reads its config instead, to try a
  /// dashboard that is not built yet against the mock backend
  /// (`dart run zehn_intelligence:mock_server`):
  ///
  /// ```sh
  /// flutter run --dart-define=ZEHN_INTELLIGENCE_CONFIG_URL=http://localhost:8787/v1/
  /// ```
  ///
  /// The key is `ZEHN_INTELLIGENCE_CONFIG_KEY`, the mock's client key by default.
  /// What it reads is kept apart from the real config. Always empty in
  /// release builds.
  static const String configUrlOverride = kReleaseMode
      ? ''
      : String.fromEnvironment(
          'ZEHN_INTELLIGENCE_CONFIG_URL',
          defaultValue: String.fromEnvironment('ZEHN_AGENT_CONFIG_URL'),
        );
  static const String _configKeyOverride = String.fromEnvironment(
    'ZEHN_INTELLIGENCE_CONFIG_KEY',
    defaultValue: String.fromEnvironment(
      'ZEHN_AGENT_CONFIG_KEY',
      defaultValue: 'client-key',
    ),
  );

  /// Where [start] reads the config, and with which key; null when there is
  /// none to read. The first that applies:
  ///
  /// 1. [configUrl] with [configKey]: the Zehn Intelligence console's backend,
  ///    which has project keys of its own.
  /// 2. [proxy], with no key.
  /// 3. The Zehn gateway, with [apiKey] unless it is blank.
  /// 4. The Zehn gateway with no key, when [configUrlOverride] is set: a
  ///    trial against a mock backend needs no model.
  ///
  /// The model's key never goes to the console, nor the console's key to the
  /// model.
  static ({String baseUrl, String apiKey})? configTarget({
    Uri? proxy,
    String apiKey = '',
    Uri? configUrl,
    String configKey = '',
  }) {
    if (configUrl != null) return (baseUrl: '$configUrl', apiKey: configKey);
    if (proxy != null) return (baseUrl: '$proxy', apiKey: '');
    if (apiKey.trim().isNotEmpty) {
      return (baseUrl: Zehn.baseUrl, apiKey: apiKey);
    }
    if (configUrlOverride.isNotEmpty) {
      return (baseUrl: Zehn.baseUrl, apiKey: '');
    }
    return null;
  }

  /// Reads this agent's config from the dashboard's backend: the last one
  /// kept on the phone at once, then what is published, in the background.
  /// Call once, at start-up; `ZehnIntelligence.start(agentId: …)` does.
  ///
  /// [appVersion] is the app's own, like `2.4.0+31` — a revision can be
  /// published for app versions from one on. Through a proxy, pass its URL
  /// as [baseUrl] and no key: it must forward `agents/{id}/config` as is.
  /// For the Zehn Intelligence console, pass its address as [baseUrl] and its
  /// project key as [apiKey]. [configUrlOverride], when set, wins over both.
  void connectConfig({
    required String appVersion,
    String? agentId,
    String baseUrl = Zehn.baseUrl,
    String apiKey = '',
    AgentConfigChannel channel = AgentConfigChannel.live,
    Duration minInterval = const Duration(minutes: 5),
    HttpClientAdapter? httpClientAdapter,
  }) {
    final id = agentId ?? this.agentId;
    if (id == null) {
      throw StateError('connectConfig needs an agentId');
    }
    final trial = configUrlOverride.isNotEmpty;
    if (trial) log('intelligence: config from $configUrlOverride (a trial)');
    final sync = _sync = AgentConfigSync(
      client: AgentConfigClient(
        baseUrl: trial ? configUrlOverride : baseUrl,
        apiKey: trial ? _configKeyOverride : apiKey,
        httpClientAdapter: httpClientAdapter,
        log: log,
      ),
      agentId: id,
      appVersion: appVersion,
      pluginVersion: zehnIntelligenceVersion,
      channel: channel,
      minInterval: configInterval(minInterval, trial: trial),
      log: log,
    );
    final cached = sync.cached();
    if (cached != null) _applyEnvelope(cached);
    unawaited(refreshConfig(force: true));
  }

  /// How often the config is checked: [minInterval], except in a trial
  /// against a mock backend, which checks every time the chat opens so a
  /// publish shows at once.
  static Duration configInterval(Duration minInterval, {required bool trial}) =>
      trial ? Duration.zero : minInterval;

  /// Asks the backend for what is published now. True when something new
  /// was applied — it takes effect on the next turn.
  Future<bool> refreshConfig({bool force = false}) async {
    final sync = _sync;
    if (sync == null) return false;
    switch (await sync.refresh(force: force)) {
      case ConfigChanged(:final envelope):
        _applyEnvelope(envelope);
        return true;
      case ConfigCleared():
        applyConfig(null);
        return true;
      case ConfigKept():
        return false;
    }
  }

  /// Refreshes if the last check is older than its interval, without
  /// waiting. Call it when the app resumes; the chat sheet calls it when it
  /// opens.
  void refreshConfigIfStale() {
    if (_sync?.isStale ?? false) unawaited(refreshConfig());
  }

  void _applyEnvelope(AgentConfigEnvelope envelope) {
    // What reading left out: a field over its cap, a link in text users
    // read, a field this build doesn't know. applyConfig logs the rest.
    for (final problem in envelope.problems) {
      log('intelligence: config — $problem');
    }
    if (envelope.revision == 0 && envelope.config.isEmpty) {
      applyConfig(null);
    } else {
      applyConfig(envelope.config, revision: envelope.revision);
    }
  }

  static Future<String> _appVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      return info.buildNumber.isEmpty
          ? info.version
          : '${info.version}+${info.buildNumber}';
    } catch (_) {
      return '0.0.0';
    }
  }

  AgentRemoteConfig? _config;
  int _configRevision = 0;
  final ValueNotifier<AgentRemoteConfig?> _configChanges = ValueNotifier(null);

  /// What the dashboard set, as last applied. Null: the code's own
  /// behaviour.
  AgentRemoteConfig? get config => _config;

  /// The published revision last applied; 0 when none.
  int get configRevision => _configRevision;

  /// Fires when [applyConfig] changes what the dashboard set.
  ValueListenable<AgentRemoteConfig?> get configChanges => _configChanges;

  /// The profile in force: the app's, or the dashboard's version of it.
  AgentProfile get effectiveProfile => engine.profile;

  /// Applies what the dashboard set, from the next turn on, over the app's
  /// own values; null puts the app's own values back exactly.
  ///
  /// Words and switches only. Text in the prompt, lead
  /// lines and example questions change; tools and packs can be
  /// switched off. A tool's
  /// kind, arguments, sign-in and confirmation, every screen, and the
  /// package's own protocol and safety wording — built-in tools' words
  /// included — stay as the code has them. Names this build does not have
  /// are ignored and listed in the report.
  AgentConfigReport applyConfig(AgentRemoteConfig? config, {int revision = 0}) {
    final problems = <String>[];
    _config = config;
    _configRevision = config == null ? 0 : revision;

    engine.profile = config == null
        ? profile
        : _effectiveProfile(config, problems);

    if (config == null) {
      tools.overlay = const AgentToolOverlay();
      components.applyOverlay();
    } else {
      tools.overlay = _toolOverlay(config, problems);
      final hidden = <String>{};
      for (final MapEntry(key: id, value: enabled) in config.packs.entries) {
        final pack = _packs[id];
        if (pack == null) {
          problems.add('packs.$id is not a pack of this app; ignored');
        } else if (!enabled) {
          hidden.addAll(pack.components.map((c) => c.type));
        }
      }
      final use = <String, String>{};
      for (final MapEntry(key: type, value: text)
          in config.components.entries) {
        if (components[type] == null) {
          problems.add('components.$type is not a card of this app; ignored');
        } else {
          use[type] = text;
        }
      }
      components.applyOverlay(
        use: use,
        hidden: hidden,
        cards: _dashboardCards(config, problems),
      );
    }

    _configChanges.value = config;
    for (final problem in problems) {
      log('intelligence: config — $problem');
    }
    return AgentConfigReport(revision: _configRevision, problems: problems);
  }

  /// The dashboard's cards that this build's code can back: each checked
  /// against the cards, fields, destinations and tools it names, and left
  /// out whole on any problem.
  List<AgentComponent> _dashboardCards(
    AgentRemoteConfig config,
    List<String> problems,
  ) {
    if (config.cards.isEmpty) return const [];
    final coded = {
      for (final component in components.all)
        component.type:
            component.cardData != null &&
                component.contract(entities).isEntityCard
            ? component.cardData!.schema
            : null,
    };
    Set<String> required(Map<String, PropSchema> args) => {
      for (final MapEntry(:key, :value) in args.entries)
        if (value.isRequired) key,
    };
    final screens = {
      for (final destination in destinations.all)
        destination.id: CardTarget(
          args: destination.args.keys.toSet(),
          required: required(destination.args),
        ),
    };
    final reads = {
      for (final tool in tools.all)
        tool.name: CardTarget(
          args: tool.args.keys.toSet(),
          required: required(tool.args),
          read: tool.kind == ToolKind.read,
        ),
    };
    final idOnly = {
      for (final destination in destinations.all)
        if (destination.args.length == 1 && destination.args.containsKey('id'))
          destination.id,
    };
    return [
      for (final card in config.cards.values)
        if (_checked(card, coded, screens, reads, problems))
          DashboardCardComponent(
            spec: card,
            base: components[card.base]!,
            data: components[card.base]!.cardData!,
            defaultLanguage: engine.profile.defaultLanguage,
            idOnly: idOnly,
          ),
    ];
  }

  static bool _checked(
    AgentCardSpec card,
    Map<String, List<CardFieldSchema>?> coded,
    Map<String, CardTarget> screens,
    Map<String, CardTarget> reads,
    List<String> problems,
  ) {
    final found = AgentCardCheck.problems(
      card,
      cards: coded,
      destinations: screens,
      tools: reads,
    );
    if (found.isEmpty) return true;
    problems
      ..addAll(found)
      ..add('cards.${card.type} is left out');
    return false;
  }

  AgentProfile _effectiveProfile(
    AgentRemoteConfig config,
    List<String> problems,
  ) {
    final code = profile;
    final wanted = config.languages;
    if (wanted != null) {
      for (final language in wanted) {
        if (!code.languages.contains(language)) {
          problems.add(
            'languages.enabled: "$language" is not one of the '
            "app's; ignored",
          );
        }
      }
    }
    final chosen = wanted == null
        ? code.languages
        : [
            for (final language in code.languages)
              if (wanted.contains(language)) language,
          ];
    final languages = chosen.isEmpty || chosen.length == code.languages.length
        ? code.languages
        : chosen;
    final wantedDefault = config.defaultLanguage;
    if (wantedDefault != null && !languages.contains(wantedDefault)) {
      problems.add(
        'languages.default: "$wantedDefault" is not offered; '
        'ignored',
      );
    }
    final defaultLanguage =
        wantedDefault != null && languages.contains(wantedDefault)
        ? wantedDefault
        : languages.contains(code.defaultLanguage)
        ? code.defaultLanguage
        : languages.first;

    LocalizedText? merge(
      LocalizedText? text,
      LocalizedText packageText,
      Map<String, String> override,
    ) => override.isEmpty
        ? text
        : LocalizedText({...(text ?? packageText).values, ...override});

    return AgentProfile(
      appName: code.appName,
      languages: languages,
      defaultLanguage: defaultLanguage,
      decideGuidance: code.decideGuidance,
      decideTrailer: code.decideTrailer,
      renderRules: code.renderRules,
      renderTrailer: code.renderTrailer,
      catalogOrder: code.catalogOrder,
      helpText: merge(code.helpText, AgentDefaultCopy.help, config.help),
      failedText: merge(
        code.failedText,
        AgentDefaultCopy.failed,
        config.failed,
      ),
      limitations: config.limitations ?? code.limitations,
      docs: code.docs,
    );
  }

  AgentToolOverlay _toolOverlay(
    AgentRemoteConfig config,
    List<String> problems,
  ) {
    final off = <String>{};
    final text = <String, ToolOverride>{};
    for (final MapEntry(key: name, value: override) in config.tools.entries) {
      if (!tools.contains(name)) {
        problems.add('tools.$name is not a tool of this app; ignored');
        continue;
      }
      if (override.enabled == false) off.add(name);
      if (!override.changesText) continue;
      if (_builtInTools.contains(name)) {
        problems.add(
          "tools.$name: a built-in tool's words are the "
          "package's; only its switch applies",
        );
      } else {
        text[name] = override;
      }
    }
    for (final MapEntry(key: id, value: enabled) in config.packs.entries) {
      final pack = _packs[id];
      if (pack != null && !enabled) off.addAll(pack.tools.map((t) => t.name));
    }
    return AgentToolOverlay(off: off, text: text);
  }

  Future<void> dispose() async {
    await _chat?.close();
    await tools.dispose();
  }
}

/// Alias for [ZehnIntelligence].
typedef ZehnAgent = ZehnIntelligence;
