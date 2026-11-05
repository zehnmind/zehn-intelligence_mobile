import '../protocol/turn.dart';
import '../tools/tool_result.dart';
import 'agent_transport.dart';

/// What an offline rule sees of the turn.
class OfflineTurn {
  OfflineTurn(this.request) : text = request.userText.toLowerCase();

  final AgentTurnRequest request;

  /// The user's words, lowercased.
  final String text;

  String get original => request.userText;

  String get languageCode => request.languageCode;

  /// Whether any of [needles] occurs in [text].
  bool hasAny(List<String> needles) => needles.any(text.contains);

  /// The user's words, cut to [max] characters — for a `localText` argument.
  String clipped(int max) =>
      original.length <= max ? original : original.substring(0, max);
}

/// One offline rule: a decision, or null to let the next rule try.
typedef OfflineRule = AgentDecision? Function(OfflineTurn turn);

/// A deterministic, offline stand-in for the model.
///
/// It matches keywords and does not pretend to be anything more. It exists so
/// the app still works with no key or no network, and so tests get the same
/// answer every run. Rules run in order and the first decision wins — order
/// matters ("cancel my order" must be tried before "order").
///
/// It never writes a reply: `render` returns nothing, and the engine renders
/// the result deterministically from the tool's own fallback copy. The gates
/// all live in the engine, so this planner gains no power a model lacks.
class RuleBasedTransport implements AgentTransport {
  const RuleBasedTransport({
    required this.rules,
    this.fallback,
    this.delay = const Duration(milliseconds: 300),
  });

  final List<OfflineRule> rules;

  /// Used when no rule matched. Null answers with the help line.
  final OfflineRule? fallback;

  /// A short pause, so the thinking state is visible as it would be live.
  final Duration delay;

  /// A rule that proposes [tool] when any of [words] occurs, optionally only
  /// if any of [alsoAny] occurs as well.
  static OfflineRule keywords(
    List<String> words, {
    required String tool,
    Map<String, Object?> args = const {},
    List<String>? alsoAny,
  }) =>
      (turn) => turn.hasAny(words) && (alsoAny == null || turn.hasAny(alsoAny))
      ? AgentDecision(tool: tool, args: args)
      : null;

  @override
  Future<AgentDecision> decide(AgentTurnRequest request) async {
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    final turn = OfflineTurn(request);
    for (final rule in rules) {
      final decision = rule(turn);
      if (decision != null) return decision;
    }
    return fallback?.call(turn) ?? const AgentDecision.none();
  }

  @override
  Future<AgentReply> render(
    AgentTurnRequest request,
    ToolResult? result,
  ) async => const AgentReply.empty();
}
