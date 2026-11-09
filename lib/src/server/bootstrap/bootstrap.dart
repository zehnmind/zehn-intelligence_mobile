import 'package:flutter/foundation.dart';

/// What `GET /v1/bootstrap` gives the SDK at start-up: the app's settings,
/// every tool's customer endpoint, the console-made components and theme.
///
/// Parsing never fails on a single bad entry: a broken tool or component is
/// left out (and logged), the rest stays. Unknown fields are ignored.
class ZiBootstrap {
  ZiBootstrap._({
    required Map<String, Object?> raw,
    required this.specVersion,
    required this.track,
    required this.services,
    required this.languages,
    required this.defaultLanguage,
    required this.api,
    required this.tools,
    required this.components,
    required this.theme,
    required this.welcomeTitle,
    required this.welcomeSubtitle,
  }) : _raw = raw;

  factory ZiBootstrap.fromJson(Object? json) {
    if (json is! Map) throw const FormatException('Start-up data must be a JSON object');
    final map = json.cast<String, Object?>();
    final tools = <String, ZiHttpTool>{};
    final toolsJson = map['tools'];
    if (toolsJson is Map) {
      toolsJson.forEach((name, value) {
        final tool = ZiHttpTool._read(value);
        if (tool != null) {
          tools['$name'] = tool;
        } else {
          debugPrint('zehn_intelligence: tool "$name" in start-up data is broken; left out');
        }
      });
    }
    final components = <String, ZiComponentDef>{};
    final componentsJson = map['components'];
    if (componentsJson is Map) {
      componentsJson.forEach((name, value) {
        final def = ZiComponentDef._read(value);
        if (def != null) {
          components['$name'] = def;
        } else {
          debugPrint('zehn_intelligence: component "$name" in start-up data is broken; left out');
        }
      });
    }
    final theme = map['theme'];
    final copy = map['copy'];
    return ZiBootstrap._(
      raw: map,
      specVersion: _string(map['spec_version']),
      track: _string(map['track']),
      services: _strings(map['services']).toSet(),
      languages: _strings(map['languages']),
      defaultLanguage: _string(map['default_language']),
      api: ZiApiSettings._read(map['api']),
      tools: tools,
      components: components,
      theme: theme is Map ? theme.cast<String, Object?>() : const {},
      welcomeTitle: copy is Map ? _stringMap(copy['welcome_title']) : const {},
      welcomeSubtitle: copy is Map ? _stringMap(copy['welcome_subtitle']) : const {},
    );
  }

  final Map<String, Object?> _raw;
  final String? specVersion;

  /// `test` or `prod`: the app key's track.
  final String? track;

  /// `llm`, `stt`, `tts`.
  final Set<String> services;
  final List<String> languages;
  final String? defaultLanguage;
  final ZiApiSettings api;
  final Map<String, ZiHttpTool> tools;
  final Map<String, ZiComponentDef> components;
  final Map<String, Object?> theme;

  /// The chat's welcome words per language, from the console (`copy`).
  /// Empty: the SDK's own words.
  final Map<String, String> welcomeTitle;
  final Map<String, String> welcomeSubtitle;

  Map<String, Object?> toJson() => _raw;
}

/// How to reach the customer's API.
class ZiApiSettings {
  const ZiApiSettings({
    this.baseUrl,
    this.allowedHosts = const {},
    this.authHeader = 'Authorization',
    this.authScheme = 'Bearer',
    this.headers = const {},
  });

  factory ZiApiSettings._read(Object? json) {
    if (json is! Map) return const ZiApiSettings();
    final base = _string(json['base_url']);
    final auth = json['auth'];
    return ZiApiSettings(
      baseUrl: base == null ? null : Uri.tryParse(base),
      allowedHosts: _strings(json['allowed_hosts']).toSet(),
      authHeader: (auth is Map ? _string(auth['header']) : null) ?? 'Authorization',
      authScheme: (auth is Map ? _string(auth['scheme']) : null) ?? 'Bearer',
      headers: _stringMap(json['headers']),
    );
  }

  /// Used when the app gives no `Dio` client of its own.
  final Uri? baseUrl;
  final Set<String> allowedHosts;
  final String authHeader;
  final String authScheme;

  /// Sent with every tool request; values may hold `{language}`,
  /// `{app_version}`, `{platform}`.
  final Map<String, String> headers;
}

/// `body` puts the argument in the JSON body (not allowed on GET).
enum ZiParamIn { path, query, header, body }

/// Where one tool argument goes in the request.
class ZiParam {
  const ZiParam({required this.name, required this.location, String? key}) : key = key ?? name;

  final String name;
  final ZiParamIn location;

  /// The name in the request, when it differs from the argument's.
  final String key;
}

/// One tool, as a request to the customer's API.
class ZiHttpTool {
  const ZiHttpTool({
    required this.method,
    required this.path,
    this.params = const [],
    this.headers = const {},
    this.auth = false,
    this.result,
    bool? confirm,
    this.confirmTitle = const {},
  }) : confirm = confirm ?? method != 'GET';

  static const methods = {'GET', 'POST', 'PUT', 'PATCH', 'DELETE'};

  static ZiHttpTool? _read(Object? json) {
    if (json is! Map) return null;
    final rawMethod = json['method'];
    final path = json['path'];
    if (rawMethod is! String || path is! String || path.isEmpty) return null;
    final method = rawMethod.toUpperCase();
    if (!methods.contains(method)) return null;
    final params = <ZiParam>[];
    final rawParams = json['params'];
    if (rawParams != null) {
      if (rawParams is! List) return null;
      for (final p in rawParams) {
        if (p is! Map || p['name'] is! String) return null;
        final location = switch (p['in']) {
          'path' => ZiParamIn.path,
          'query' => ZiParamIn.query,
          'header' => ZiParamIn.header,
          'body' => ZiParamIn.body,
          _ => null,
        };
        if (location == null || (location == ZiParamIn.body && method == 'GET')) return null;
        params.add(ZiParam(name: p['name'] as String, location: location, key: _string(p['key'])));
      }
    }
    final auth = json['auth'];
    // `confirm`: true / false, or {"title": {"uz": …, "en": …}}. Writes
    // default to true.
    final rawConfirm = json['confirm'];
    return ZiHttpTool(
      method: method,
      path: path,
      params: params,
      headers: _stringMap(json['headers']),
      auth: auth is bool && auth,
      result: ZiResultRule._read(json['result']),
      confirm: rawConfirm is bool ? rawConfirm : (rawConfirm is Map ? true : null),
      confirmTitle: rawConfirm is Map ? _stringMap(rawConfirm['title']) : const {},
    );
  }

  /// `GET`, `POST`, `PUT`, `PATCH` or `DELETE`.
  final String method;

  /// The user must allow the call in the chat first. Defaults to true for
  /// every method but GET.
  final bool confirm;

  /// The question the user is asked, per language; `{arg}` placeholders are
  /// filled from the call's arguments. Empty: the SDK's own words.
  final Map<String, String> confirmTitle;

  /// Starts with `/`; `{name}` marks a path parameter.
  final String path;
  final List<ZiParam> params;
  final Map<String, String> headers;

  /// Needs the user's login.
  final bool auth;
  final ZiResultRule? result;
}

/// What part of the answer the model gets.
class ZiResultRule {
  const ZiResultRule({this.root, this.fields = const [], this.maxItems = 10});

  static ZiResultRule? _read(Object? json) {
    if (json is! Map) return null;
    final max = json['max_items'];
    return ZiResultRule(
      root: _string(json['root']),
      fields: _strings(json['fields']),
      maxItems: max is num && max > 0 ? max.toInt() : 10,
    );
  }

  /// A `/`-path into the answer; null keeps the whole answer.
  final String? root;

  /// `/`-paths kept from each object; empty keeps all.
  final List<String> fields;
  final int maxItems;
}

enum ZiComponentKind { inline, sheet, route }

/// A console-made component: a surface to draw, or an app route to open.
class ZiComponentDef {
  const ZiComponentDef({required this.kind, this.surface, this.route});

  static ZiComponentDef? _read(Object? json) {
    if (json is! Map) return null;
    final kind = switch (json['kind']) {
      'inline' => ZiComponentKind.inline,
      'sheet' => ZiComponentKind.sheet,
      'route' => ZiComponentKind.route,
      _ => null,
    };
    if (kind == null) return null;
    if (kind == ZiComponentKind.route) {
      final route = _string(json['route']);
      return route == null ? null : ZiComponentDef(kind: kind, route: route);
    }
    final surface = json['surface'];
    return surface is Map ? ZiComponentDef(kind: kind, surface: surface.cast<String, Object?>()) : null;
  }

  final ZiComponentKind kind;
  final Map<String, Object?>? surface;
  final String? route;
}

String? _string(Object? v) => v is String && v.isNotEmpty ? v : null;

List<String> _strings(Object? v) => v is List ? [for (final x in v) if (x is String) x] : const [];

Map<String, String> _stringMap(Object? v) =>
    v is Map ? {for (final e in v.entries) if (e.value is String) '${e.key}': e.value as String} : const {};
