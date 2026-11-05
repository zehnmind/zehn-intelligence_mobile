import '../model/component_spec.dart';

/// The app-specific parts of the prompt, gathered for one turn.
///
/// The package owns the protocol and the rules that hold for every app; each
/// of these comes from the app's [AgentProfile] or from its tools.
class AgentPromptParts {
  const AgentPromptParts({
    this.decideGuidance,
    this.decideNotes = const [],
    this.decideTrailer,
    this.renderRules,
    this.renderNotes = const [],
    this.renderTrailer = const [],
  });

  /// When to use a tool at all. Null uses the generic paragraph.
  final String? decideGuidance;

  /// One paragraph per enabled tool that has planning notes.
  final List<String> decideNotes;
  final String? decideTrailer;

  /// Reply rules. Null uses the generic rules.
  final List<String>? renderRules;

  /// One bullet per enabled tool that has reply notes.
  final List<String> renderNotes;
  final List<String> renderTrailer;
}

/// Everything the planner is told about this turn.
///
/// Note what is absent: no auth token, no raw entity payloads, and no way to
/// express a network call. The catalogs are generated from the registries, so
/// the planner is never offered something the app cannot render or run.
class AgentTurnRequest {
  const AgentTurnRequest({
    required this.userText,
    required this.languageCode,
    required this.toolCatalog,
    required this.componentCatalog,
    this.languages = const ['en'],
    this.history = const [],
    this.prompt = const AgentPromptParts(),
  });

  final String userText;

  /// The app's language this turn, so the reply is written in the language
  /// the user is actually reading.
  final String languageCode;

  /// Every language the assistant may answer in.
  final List<String> languages;

  final List<Map<String, Object?>> toolCatalog;

  /// Component ids the planner may emit, each with a one-line description and
  /// an example. Generated from the registry.
  final List<Map<String, Object?>> componentCatalog;

  /// Earlier turns of this conversation, oldest first.
  final List<AgentHistoryEntry> history;

  final AgentPromptParts prompt;
}

/// One earlier turn, flattened to text.
class AgentHistoryEntry {
  const AgentHistoryEntry({required this.isUser, required this.text});

  final bool isUser;
  final String text;
}

/// What the planner wants shown, and which language it wrote it in.
class AgentReply {
  const AgentReply({this.components = const [], this.language});

  const AgentReply.empty() : components = const [], language = null;

  final List<ComponentSpec> components;

  /// As reported by the planner. Picks the voice for text-to-speech, since
  /// the reply can legitimately differ from the app's language when the user
  /// writes in another one.
  final String? language;

  bool get isEmpty => components.isEmpty;
}

/// Step one of a turn: which tool, if any, to run.
class AgentDecision {
  const AgentDecision({this.tool, this.args = const {}, this.reply});

  const AgentDecision.none() : tool = null, args = const {}, reply = null;

  /// `null` means no tool.
  final String? tool;
  final Map<String, Object?> args;

  /// Set when the planner answered directly — a greeting, a thank-you, a
  /// question no tool covers. Saves the second round trip entirely.
  final AgentReply? reply;

  bool get hasTool => tool != null;
}
