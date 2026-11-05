import '../engine/agent_state.dart';
import 'config_caps.dart';

part 'agent_card_config.dart';

/// What the dashboard sets for one app's assistant: words, switches, and
/// cards built from the plugin's blocks, over what the app's code declares.
///
/// Every field is optional, and an absent one keeps the code's own value. It
/// can change text — the app context, prompt paragraphs, a tool's
/// description, example questions — switch tools and packs off, and
/// add cards that show fields the app's code exposes. It can never add a
/// tool, a screen or a link, change what a tool does, its arguments, its
/// sign-in or its confirmation, or touch the package's own protocol and
/// safety wording: new capabilities still need app code.
class AgentRemoteConfig {
  const AgentRemoteConfig({
    this.help = const {},
    this.failed = const {},
    this.limitations,
    this.languages,
    this.defaultLanguage,
    this.tools = const {},
    this.packs = const {},
    this.components = const {},
    this.cards = const {},
  });

  /// Parses the `config` object of a response.
  ///
  /// Never throws: a field of the wrong type, over its cap, or holding a link
  /// where users read it, is left out and described in [problems]. Unknown
  /// fields are ignored (a newer dashboard may know more), and noted there
  /// too.
  factory AgentRemoteConfig.fromJson(Object? json, {List<String>? problems}) {
    final r = _Reader(problems ?? []);
    final map = r.map(json, 'config');
    if (map == null) return const AgentRemoteConfig();
    r.known(map, '', const {
      'copy',
      'limitations',
      'languages',
      'tools',
      'packs',
      'components',
      'cards',
    });

    final copy = r.map(map['copy'], 'copy') ?? const {};
    r.known(copy, 'copy', const {'help', 'failed'});
    final languages = r.map(map['languages'], 'languages') ?? const {};
    r.known(languages, 'languages', const {'enabled', 'default'});

    return AgentRemoteConfig(
      help: r.perLanguage(copy['help'], 'copy.help', AgentConfigCaps.copy),
      failed: r.perLanguage(
        copy['failed'],
        'copy.failed',
        AgentConfigCaps.copy,
      ),
      limitations: _readLimitations(r, map['limitations']),
      languages: r.languageList(languages['enabled'], 'languages.enabled'),
      defaultLanguage: r.language(languages['default'], 'languages.default'),
      tools: r.byName(map['tools'], 'tools', ToolOverride._read),
      packs: r.byName(map['packs'], 'packs', (r, value, path) {
        final pack = r.map(value, path);
        if (pack == null) return null;
        r.known(pack, path, const {'enabled'});
        return r.flag(pack['enabled'], '$path.enabled');
      }),
      components: r.byName(map['components'], 'components', (r, value, path) {
        final component = r.map(value, path);
        if (component == null) return null;
        r.known(component, path, const {'use'});
        final use = r.text(
          component['use'],
          '$path.use',
          AgentConfigCaps.componentUse,
        );
        return use == null || use.trim().isEmpty ? null : use;
      }),
      cards: _readCards(r, map['cards']),
    );
  }

  /// The help line, per language, merged over the app's.
  final Map<String, String> help;

  /// The failure line, per language, merged over the app's.
  final Map<String, String> failed;

  /// What the assistant cannot do, for the capabilities page. Null keeps the
  /// app's list; empty clears it.
  final List<AgentLimitation>? limitations;

  /// The reply languages, a subset of the app's. Null keeps them all.
  final List<String>? languages;
  final String? defaultLanguage;

  /// Per tool name. Names the app does not have are ignored.
  final Map<String, ToolOverride> tools;

  /// Per pack id: false switches the pack's tools off and hides its cards
  /// from the model.
  final Map<String, bool> packs;

  /// Per card type: what the model is told about when to show it.
  final Map<String, String> components;

  /// Cards the dashboard added, per type, in the order it gave them.
  final Map<String, AgentCardSpec> cards;

  bool get isEmpty =>
      help.isEmpty &&
      failed.isEmpty &&
      limitations == null &&
      languages == null &&
      defaultLanguage == null &&
      tools.isEmpty &&
      packs.isEmpty &&
      components.isEmpty &&
      cards.isEmpty;

  Map<String, Object?> toJson() => {
    if (help.isNotEmpty || failed.isNotEmpty)
      'copy': {
        if (help.isNotEmpty) 'help': help,
        if (failed.isNotEmpty) 'failed': failed,
      },
    if (limitations != null)
      'limitations': [
        for (final l in limitations!) {'what': l.what, 'instead': l.instead},
      ],
    if (languages != null || defaultLanguage != null)
      'languages': {'enabled': ?languages, 'default': ?defaultLanguage},
    if (tools.isNotEmpty)
      'tools': {for (final e in tools.entries) e.key: e.value.toJson()},
    if (packs.isNotEmpty)
      'packs': {
        for (final e in packs.entries) e.key: {'enabled': e.value},
      },
    if (components.isNotEmpty)
      'components': {
        for (final e in components.entries) e.key: {'use': e.value},
      },
    if (cards.isNotEmpty)
      'cards': {for (final e in cards.entries) e.key: e.value.toJson()},
  };

  static Map<String, AgentCardSpec> _readCards(_Reader r, Object? value) {
    final entries = r.map(value, 'cards');
    if (entries == null) return const {};
    if (entries.length > AgentConfigCaps.cards) {
      r.problem('cards', 'has more than ${AgentConfigCaps.cards} cards');
      return const {};
    }
    final out = <String, AgentCardSpec>{};
    for (final MapEntry(:key, :value) in entries.entries) {
      final card = AgentCardSpec._read(r, key, value, 'cards.$key');
      if (card != null) out[key] = card;
    }
    return out;
  }

  static List<AgentLimitation>? _readLimitations(_Reader r, Object? value) {
    if (value == null) return null;
    if (value is! List) {
      r.problem('limitations', 'is not a list');
      return null;
    }
    if (value.length > AgentConfigCaps.limitations) {
      r.problem(
        'limitations',
        'has more than ${AgentConfigCaps.limitations} items',
      );
      return null;
    }
    final out = <AgentLimitation>[];
    for (var i = 0; i < value.length; i++) {
      final path = 'limitations[$i]';
      final item = r.map(value[i], path);
      if (item == null) {
        if (value[i] == null) r.problem(path, 'is not an object');
        return null;
      }
      for (final field in const ['what', 'instead']) {
        if (item[field] == null) r.problem('$path.$field', 'is missing');
      }
      r.known(item, path, const {'what', 'instead'});
      final what = r.text(
        item['what'],
        '$path.what',
        AgentConfigCaps.limitationWhat,
        forUsers: true,
      );
      final instead = r.text(
        item['instead'],
        '$path.instead',
        AgentConfigCaps.limitationInstead,
        forUsers: true,
      );
      if (what == null || instead == null) return null;
      out.add(AgentLimitation(what, instead));
    }
    return out;
  }
}

/// What the dashboard set for one tool: its words and its switch. Never its
/// kind, arguments, sign-in or confirmation.
class ToolOverride {
  const ToolOverride({
    this.enabled,
    this.description,
    this.args = const {},
    this.decideNotes,
    this.renderNotes,
    this.examples = const {},
    this.found = const {},
    this.empty = const {},
    this.always = const {},
  });

  static ToolOverride? _read(_Reader r, Object? value, String path) {
    final map = r.map(value, path);
    if (map == null) return null;
    r.known(map, path, const {
      'enabled',
      'description',
      'args',
      'decideNotes',
      'renderNotes',
      'examples',
      'fallback',
    });
    final description = r.text(
      map['description'],
      '$path.description',
      AgentConfigCaps.toolDescription,
    );
    final fallback = r.map(map['fallback'], '$path.fallback') ?? const {};
    r.known(fallback, '$path.fallback', const {'found', 'empty', 'always'});
    final args = <String, String>{};
    final argMap = r.map(map['args'], '$path.args') ?? const {};
    for (final MapEntry(key: arg, value: item) in argMap.entries) {
      final argPath = '$path.args.$arg';
      final entry = r.map(item, argPath);
      if (entry == null) continue;
      r.known(entry, argPath, const {'description'});
      final text = r.text(
        entry['description'],
        '$argPath.description',
        AgentConfigCaps.argDescription,
      );
      if (text != null && text.trim().isNotEmpty) args[arg] = text;
    }
    return ToolOverride(
      enabled: r.flag(map['enabled'], '$path.enabled'),
      description: description == null || description.trim().isEmpty
          ? null
          : description,
      args: args,
      decideNotes: r.text(
        map['decideNotes'],
        '$path.decideNotes',
        AgentConfigCaps.toolNotes,
      ),
      renderNotes: r.text(
        map['renderNotes'],
        '$path.renderNotes',
        AgentConfigCaps.toolNotes,
      ),
      examples: r.listsPerLanguage(
        map['examples'],
        '$path.examples',
        count: AgentConfigCaps.examples,
        cap: AgentConfigCaps.example,
      ),
      found: r.perLanguage(
        fallback['found'],
        '$path.fallback.found',
        AgentConfigCaps.leadLine,
      ),
      empty: r.perLanguage(
        fallback['empty'],
        '$path.fallback.empty',
        AgentConfigCaps.leadLine,
      ),
      always: r.perLanguage(
        fallback['always'],
        '$path.fallback.always',
        AgentConfigCaps.leadLine,
      ),
    );
  }

  /// False switches the tool off. Remote can only switch off: true keeps
  /// whatever the app's code says.
  final bool? enabled;

  /// Shown to the model. Null keeps the app's.
  final String? description;

  /// Argument descriptions shown to the model, per argument name.
  final Map<String, String> args;

  /// Planning notes. Null keeps the app's; blank removes them.
  final String? decideNotes;

  /// Reply notes. Null keeps the app's; blank removes them.
  final String? renderNotes;

  /// Example questions per language. Replaces the
  /// app's for each language given.
  final Map<String, List<String>> examples;

  /// Lead lines per language, merged over the app's.
  final Map<String, String> found;
  final Map<String, String> empty;
  final Map<String, String> always;

  bool get changesText =>
      description != null ||
      args.isNotEmpty ||
      decideNotes != null ||
      renderNotes != null ||
      examples.isNotEmpty ||
      found.isNotEmpty ||
      empty.isNotEmpty ||
      always.isNotEmpty;

  /// This override with only its switch kept.
  ToolOverride get switchOnly => ToolOverride(enabled: enabled);

  Map<String, Object?> toJson() => {
    'enabled': ?enabled,
    'description': ?description,
    if (args.isNotEmpty)
      'args': {
        for (final e in args.entries) e.key: {'description': e.value},
      },
    'decideNotes': ?decideNotes,
    'renderNotes': ?renderNotes,
    if (examples.isNotEmpty) 'examples': examples,
    if (found.isNotEmpty || empty.isNotEmpty || always.isNotEmpty)
      'fallback': {
        if (found.isNotEmpty) 'found': found,
        if (empty.isNotEmpty) 'empty': empty,
        if (always.isNotEmpty) 'always': always,
      },
  };
}

/// What `ZehnIntelligence.applyConfig` did with a config.
class AgentConfigReport {
  const AgentConfigReport({required this.revision, this.problems = const []});

  /// The revision now in force; 0 when none.
  final int revision;

  /// What was ignored, or kept at the app's own value, and why.
  final List<String> problems;
}

/// One config response: which revision it is, and the config itself.
class AgentConfigEnvelope {
  const AgentConfigEnvelope({
    required this.schemaVersion,
    required this.agentId,
    required this.channel,
    required this.revision,
    required this.config,
    this.publishedAt,
    this.problems = const [],
  });

  /// Reads a response body. Null when it is not one, or speaks a schema
  /// newer than this build understands — the phone then keeps what it has.
  static AgentConfigEnvelope? fromJson(Object? json, {List<String>? problems}) {
    final notes = problems ?? <String>[];
    if (json is! Map) {
      notes.add('response is not an object');
      return null;
    }
    final schema = json['schemaVersion'];
    if (schema is! num || schema != schema.toInt()) {
      notes.add('response has no schemaVersion');
      return null;
    }
    if (schema > AgentConfigCaps.schemaVersion) {
      notes.add(
        'response speaks schema $schema; this build understands '
        '${AgentConfigCaps.schemaVersion}',
      );
      return null;
    }
    final revision = json['revision'];
    final configProblems = <String>[];
    final config = AgentRemoteConfig.fromJson(
      json['config'] ?? const <String, Object?>{},
      problems: configProblems,
    );
    notes.addAll(configProblems);
    return AgentConfigEnvelope(
      schemaVersion: schema.toInt(),
      agentId: '${json['agentId'] ?? ''}',
      channel: '${json['channel'] ?? 'live'}',
      revision: revision is num ? revision.toInt() : 0,
      publishedAt: DateTime.tryParse('${json['publishedAt'] ?? ''}'),
      config: config,
      problems: configProblems,
    );
  }

  final int schemaVersion;
  final String agentId;
  final String channel;

  /// 0 when nothing is published for this app.
  final int revision;
  final DateTime? publishedAt;
  final AgentRemoteConfig config;

  /// What was left out of [config] while reading it.
  final List<String> problems;
}

typedef _ReadItem<T> = T? Function(_Reader r, Object? value, String path);

/// Reads JSON leniently, writing down what it left out and why.
class _Reader {
  _Reader(this.problems);

  final List<String> problems;

  /// Problems that left something out — every one but an unknown key, which
  /// is only noted. A dashboard card with any of them is left out whole.
  int serious = 0;

  static final RegExp _language = RegExp(r'^[a-z]{2,3}$');

  void problem(String path, String what) {
    serious++;
    problems.add('$path $what');
  }

  Map<String, Object?>? map(Object? value, String path) {
    if (value == null) return null;
    if (value is Map) {
      return {
        for (final MapEntry(:key, :value) in value.entries) '$key': value,
      };
    }
    problem(path, 'is not an object');
    return null;
  }

  /// [path] '' is the config itself: its fields' paths are bare names.
  void known(Map<String, Object?> map, String path, Set<String> fields) {
    for (final key in map.keys) {
      if (!fields.contains(key)) {
        problems.add(
          '${path.isEmpty ? key : '$path.$key'} is not known; ignored',
        );
      }
    }
  }

  String? text(Object? value, String path, int cap, {bool forUsers = false}) {
    if (value == null) return null;
    if (value is! String) {
      problem(path, 'is not text');
      return null;
    }
    final normal = value.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    if (normal.length > cap) {
      problem(path, 'is longer than $cap characters');
      return null;
    }
    if (forUsers && _unsafeForUsers(normal)) {
      problem(path, 'holds a link or a long number, which users must not see');
      return null;
    }
    return normal;
  }

  List<String>? texts(
    Object? value,
    String path, {
    required int count,
    required int cap,
    bool forUsers = false,
  }) {
    if (value == null) return null;
    if (value is! List) {
      problem(path, 'is not a list');
      return null;
    }
    if (value.length > count) {
      problem(path, 'has more than $count items');
      return null;
    }
    final out = <String>[];
    for (var i = 0; i < value.length; i++) {
      if (value[i] == null) {
        problem('$path[$i]', 'is not text');
        return null;
      }
      final item = text(value[i], '$path[$i]', cap, forUsers: forUsers);
      if (item == null) return null;
      if (item.trim().isNotEmpty) out.add(item);
    }
    return out;
  }

  String? language(Object? value, String path) {
    if (value == null) return null;
    if (value is String && _language.hasMatch(value)) return value;
    problem(path, 'is not a language code');
    return null;
  }

  List<String>? languageList(Object? value, String path) {
    if (value == null) return null;
    if (value is! List) {
      problem(path, 'is not a list');
      return null;
    }
    final out = <String>[];
    for (var i = 0; i < value.length; i++) {
      if (value[i] == null) problem('$path[$i]', 'is not a language code');
      final code = language(value[i], '$path[$i]');
      if (code != null && !out.contains(code)) out.add(code);
    }
    return out.isEmpty ? null : out;
  }

  /// `{language: text}`. A blank text keeps the app's own for that language.
  Map<String, String> perLanguage(Object? value, String path, int cap) {
    final entries = map(value, path);
    if (entries == null) return const {};
    final out = <String, String>{};
    for (final MapEntry(:key, :value) in entries.entries) {
      if (language(key, '$path.$key') == null) continue;
      final item = text(value, '$path.$key', cap, forUsers: true);
      if (item != null && item.trim().isNotEmpty) out[key] = item;
    }
    return out;
  }

  /// `{language: [text]}`, every item something users read.
  Map<String, List<String>> listsPerLanguage(
    Object? value,
    String path, {
    required int count,
    required int cap,
  }) {
    final entries = map(value, path);
    if (entries == null) return const {};
    final out = <String, List<String>>{};
    for (final MapEntry(:key, :value) in entries.entries) {
      if (language(key, '$path.$key') == null) continue;
      final items = texts(
        value,
        '$path.$key',
        count: count,
        cap: cap,
        forUsers: true,
      );
      if (items != null && items.isNotEmpty) out[key] = items;
    }
    return out;
  }

  Map<String, T> byName<T>(Object? value, String path, _ReadItem<T> read) {
    final entries = map(value, path);
    if (entries == null) return const {};
    final out = <String, T>{};
    for (final MapEntry(:key, :value) in entries.entries) {
      final item = read(this, value, '$path.$key');
      if (item != null) out[key] = item;
    }
    return out;
  }

  bool? flag(Object? value, String path) {
    if (value == null) return null;
    if (value is bool) return value;
    problem(path, 'is not true or false');
    return null;
  }

  int? integer(Object? value, String path, (int, int) range) {
    final number = _whole(value, path);
    if (number == null) return null;
    final (low, high) = range;
    if (number < low || number > high) {
      problem(path, 'is outside $low–$high; clamped');
      return number.clamp(low, high);
    }
    return number;
  }

  int? atLeast(Object? value, String path, int low) {
    final number = _whole(value, path);
    if (number == null) return null;
    if (number < low) {
      problem(path, 'is below $low; raised');
      return low;
    }
    return number;
  }

  double? number(Object? value, String path, (double, double) range) {
    if (value == null) return null;
    if (value is! num) {
      problem(path, 'is not a number');
      return null;
    }
    final (low, high) = range;
    final number = value.toDouble();
    if (number < low || number > high) {
      problem(path, 'is outside $low–$high; clamped');
      return number.clamp(low, high);
    }
    return number;
  }

  int? _whole(Object? value, String path) {
    if (value == null) return null;
    if (value is num && value == value.roundToDouble()) return value.toInt();
    problem(path, 'is not a whole number');
    return null;
  }

  static final _longNumber = RegExp(r'(?:\d[\s-]?){9,}');
  static final _iban = RegExp(r'\b[A-Z]{2}\d{2}[A-Z0-9]{10,30}\b');

  static bool _unsafeForUsers(String text) =>
      text.contains('://') ||
      text.toLowerCase().contains('www.') ||
      _longNumber.hasMatch(text) ||
      _iban.hasMatch(text.toUpperCase());
}

/// Picks between a dashboard value and the code's, the same way everywhere.
///
/// A dashboard value equal to the code's apart from trailing whitespace is
/// the code's: editors and databases trim, and the prompt must not change by
/// a byte when nobody changed a word.
abstract final class AgentConfigPick {
  /// Null keeps [code]; blank clears it (null); anything else replaces it.
  static String? text(String? override, String? code) {
    if (override == null) return code;
    if (override.trim().isEmpty) return null;
    if (code != null && override.trimRight() == code.trimRight()) return code;
    return override;
  }

  /// Null keeps [code]; anything else replaces it, unless it is the same
  /// list apart from trailing whitespace.
  static List<String>? list(List<String>? override, List<String>? code) {
    if (override == null) return code;
    if (code != null && override.length == code.length) {
      var same = true;
      for (var i = 0; i < code.length && same; i++) {
        same = override[i].trimRight() == code[i].trimRight();
      }
      if (same) return code;
    }
    return override;
  }
}
