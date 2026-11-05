import '../engine/agent_state.dart';
import '../entities/entity_store.dart';
import '../log.dart';
import '../model/confirmation.dart';
import '../schema/prop_schema.dart';
import '../text/localized_text.dart';
import 'tool_result.dart';

/// How much a tool can change, and therefore how it is gated.
enum ToolKind {
  /// Reads only. Runs without asking. May also be run from a button on a
  /// card.
  read,

  /// Changes something on this device that is cheap and reversible — the
  /// app's language, a saved note. Runs without asking, and says so after.
  localWrite,

  /// Changes something on a server, or something the user cannot get back.
  /// Never runs until the user taps confirm on a card the app wrote.
  remoteWrite,
}

/// One call of a tool, with everything its handler may use.
class ToolCall {
  const ToolCall({
    required this.tool,
    required this.args,
    required this.state,
    required this.entities,
    this.log = silentAgentLog,
  });

  /// The tool's name, for building its [ToolResult].
  final String tool;

  /// Already validated against the tool's schema.
  final Map<String, Object?> args;
  final AgentState state;
  final EntityStore entities;
  final AgentLog log;

  /// The language to write any user-facing text in.
  String get language => state.languageCode;

  String? string(String key) {
    final value = args[key];
    return value is String && value.isNotEmpty ? value : null;
  }

  int? integer(String key) {
    final value = args[key];
    return value is int ? value : null;
  }

  bool flag(String key) => args[key] == true;
}

typedef ToolRunner = Future<ToolResult> Function(ToolCall call);
typedef ToolConfirmer = Future<ConfirmStep?> Function(ToolCall call);
typedef ToolPrimer = Future<void> Function(AgentState state);
typedef ToolAvailability = bool Function(AgentState state);

/// The sentence shown above a tool's cards when the model's reply is
/// unusable — or when there is no model at all.
class ToolFallback {
  const ToolFallback({this.found, this.empty, this.always, this.tone});

  /// Lead line when the result has cards: "Here's what I found:".
  final LocalizedText? found;

  /// Lead line when it has none: "Nothing matched.".
  final LocalizedText? empty;

  /// Lead line either way. Wins over [found] and [empty].
  final LocalizedText? always;

  /// `success`, `warning` or `neutral`. Null: `success` for writes,
  /// `neutral` for reads.
  final String? tone;

  String? leadFor(
    String language, {
    required bool hasItems,
    String fallbackLanguage = 'en',
  }) {
    final text = always ?? (hasItems ? found : empty);
    return text?.resolve(language, fallback: fallbackLanguage);
  }
}

/// How a tool is described in the generated capabilities document.
class ToolDoc {
  const ToolDoc({
    required this.summary,
    this.title,
    this.source,
    this.examples = const {},
    this.returns,
    this.notes = const [],
  });

  /// "What it does", one line.
  final String summary;

  /// A short title for the tool's section, e.g. "find a place".
  final String? title;

  /// Where the data comes from, e.g. "`GET /accounts`" or "The device".
  final String? source;

  /// What users say to trigger it, by language.
  final Map<String, List<String>> examples;

  /// What the result carries.
  final String? returns;

  /// Anything else worth knowing, one bullet each.
  final List<String> notes;
}

/// A tool the model may propose: its schema, its gate and its handler.
///
/// Every tool should be backed by something the app already does — a
/// repository method, a controller, a store. Never add a tool that composes a
/// URL or calls "any endpoint": the model would then be writing requests.
class AgentTool {
  AgentTool({
    required this.name,
    required this.description,
    required this.kind,
    required this.run,
    this.args = const {},
    this.requiresSignIn = false,
    this.availableWhen,
    this.prime,
    this.confirm,
    this.decideNotes,
    this.renderNotes,
    this.fallback = const ToolFallback(),
    this.doc,
  });

  /// `domain.verb`, e.g. `accounts.list` or `card.freeze`.
  final String name;

  /// Shown to the model verbatim: what it does and when to use it.
  final String description;
  final ToolKind kind;
  final Map<String, PropSchema> args;

  /// Only offered to a signed-in user, and refused otherwise.
  final bool requiresSignIn;

  /// Evaluated every turn. False withholds the tool from the model and
  /// refuses it if proposed anyway.
  final ToolAvailability? availableWhen;

  /// Loads what the catalog needs before the model sees it — the categories
  /// behind a `choiceFrom` argument, say. Run before planning each typed turn.
  final ToolPrimer? prime;

  /// Runs the tool. Only called with validated arguments, after every gate.
  final ToolRunner run;

  /// For [ToolKind.remoteWrite]: builds the confirmation card from the app's
  /// own data. Null result means it cannot be confirmed — the turn fails.
  final ToolConfirmer? confirm;

  /// A paragraph added to the planning prompt while this tool is enabled:
  /// when to use it, what to pass.
  final String? decideNotes;

  /// A bullet added to the reply-writing prompt's rules while this tool is
  /// enabled: how to present its results.
  final String? renderNotes;

  final ToolFallback fallback;
  final ToolDoc? doc;

  static final RegExp _namePattern = RegExp(r'^[a-z]+(\.[a-zA-Z]+)+$');

  bool get isRead => kind == ToolKind.read;
  bool get requiresConfirmation => kind == ToolKind.remoteWrite;

  /// What is wrong with this declaration. Checked when the tool is added.
  List<String> problems() => [
    if (!_namePattern.hasMatch(name))
      'name "$name" is not domain.verb (lowercase domain, dot, camelCase verb)',
    if (description.trim().isEmpty) 'has no description',
    if (kind == ToolKind.remoteWrite && confirm == null)
      'is a remote write without a confirm step',
    if (kind == ToolKind.read && confirm != null)
      'is a read with a confirm step — reads never ask',
    for (final MapEntry(key: arg, value: schema) in args.entries)
      for (final problem in schema.problems()) 'argument "$arg" $problem',
    for (final arg in args.keys)
      if (_looksLikeAddress(arg))
        'argument "$arg" looks like a URL or path — tools never take one',
  ];

  static bool _looksLikeAddress(String name) => RegExp(
    r'(url|uri|href|link|endpoint|path)$',
    caseSensitive: false,
  ).hasMatch(name);

  SchemaValidation validate(
    Map<String, Object?> args, {
    AgentAllowlists? allowlists,
  }) => SchemaValidation.run(this.args, args, allowlists: allowlists);

  /// True when a required argument draws on a list that is currently empty —
  /// no reservations to cancel, no notes to forget.
  ///
  /// Such a tool cannot succeed this turn, so it is withheld from the catalog
  /// entirely rather than offered and then rejected.
  bool isUnusable({AgentAllowlists? allowlists}) {
    for (final schema in args.values) {
      if (!schema.isRequired) continue;
      if (schema.hasNoValidValue(allowlists: allowlists)) return true;
    }
    return false;
  }

  /// Arguments worth showing the model this turn.
  ///
  /// An optional argument whose list is empty is omitted. Offering a field
  /// that has nothing valid to put in it simply invites the model to invent a
  /// value — observed in practice, with a live model confidently passing
  /// `categoryId: "sports"` when no category had been loaded.
  Map<String, PropSchema> visibleArgs({AgentAllowlists? allowlists}) {
    final visible = <String, PropSchema>{};
    for (final entry in args.entries) {
      final schema = entry.value;
      if (!schema.isRequired &&
          schema.hasNoValidValue(allowlists: allowlists)) {
        continue;
      }
      visible[entry.key] = schema;
    }
    return visible;
  }

  /// The tool definition shown to the model. Generated, never hand-written.
  Map<String, Object?> toJsonSchema({AgentAllowlists? allowlists}) {
    final visible = visibleArgs(allowlists: allowlists);
    return {
      'name': name,
      'description': description,
      'parameters': {
        'type': 'object',
        'properties': {
          for (final entry in visible.entries)
            entry.key: entry.value.toJsonSchema(allowlists: allowlists),
        },
        'required': [
          for (final entry in visible.entries)
            if (entry.value.isRequired) entry.key,
        ],
        'additionalProperties': false,
      },
      if (requiresConfirmation) 'confirmation': 'required',
    };
  }

  @override
  String toString() => 'AgentTool($name, ${kind.name})';
}
