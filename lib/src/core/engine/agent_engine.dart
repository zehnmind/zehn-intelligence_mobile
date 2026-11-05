import '../entities/entity_store.dart';
import '../log.dart';
import '../model/component_spec.dart';
import '../model/confirmation.dart';
import '../protocol/turn.dart';
import '../tools/agent_tool.dart';
import '../tools/tool_registry.dart';
import '../tools/tool_result.dart';
import '../transport/agent_transport.dart';
import 'agent_state.dart';
import 'component_catalog.dart';
import 'fallback_renderer.dart';

/// How a turn ended.
sealed class TurnResult {
  const TurnResult();
}

/// The reply is ready. Empty [components] means there was nothing to show.
final class TurnFinished extends TurnResult {
  const TurnFinished(this.components, {this.language, this.result});

  final List<ComponentSpec> components;
  final String? language;

  /// The tool result behind the reply, if a tool ran.
  final ToolResult? result;
}

/// A write is waiting for the user to confirm it.
final class TurnAwaitingConfirmation extends TurnResult {
  const TurnAwaitingConfirmation(this.confirmation);

  final PendingConfirmation confirmation;
}

/// The turn could not be completed: the model was unreachable, or it proposed
/// something the gate refused.
final class TurnFailed extends TurnResult {
  const TurnFailed(this.reason);

  final String reason;
}

/// Runs turns: plans with the model, checks every proposal, asks before any
/// write, runs the app's own code, and makes sure a reply is shown.
///
/// Every path to a tool — the model's proposal, a button on a card, a
/// confirmed write — goes through the same gate: the tool must be registered,
/// enabled, available to this user right now, and called with valid
/// arguments. A write never runs without a confirmation card the app wrote.
///
/// Pure Dart. It holds no transcript: the caller passes history in and gets
/// a [TurnResult] back.
class AgentEngine {
  AgentEngine({
    required this.tools,
    required this.transport,
    required this.session,
    required this.entities,
    required this.components,
    required AgentProfile profile,
    this.log = silentAgentLog,
  }) : _profile = profile,
       _fallback = AgentFallbackRenderer(tools, profile);

  final AgentToolRegistry tools;
  AgentTransport transport;
  final AgentSession session;
  final EntityStore entities;
  final AgentComponentCatalog components;
  final AgentLog log;

  AgentProfile _profile;
  AgentFallbackRenderer _fallback;

  /// Who the assistant is and how it is told to behave — the app's profile,
  /// or the dashboard's version of it. Read on every turn.
  AgentProfile get profile => _profile;

  set profile(AgentProfile value) {
    _profile = value;
    _fallback = AgentFallbackRenderer(tools, value);
  }

  AgentFallbackRenderer get fallback => _fallback;

  /// The host's flags, read by `availableWhen` predicates: which screen is
  /// open, which feature is switched on.
  final Map<String, Object?> flags = {};

  /// The session as it is right now, plus the flags.
  AgentState snapshot() => AgentState(
    languageCode: session.languageCode,
    isSignedIn: session.isSignedIn,
    flags: Map.unmodifiable(flags),
  );

  /// What the model is told for a turn starting with [userText].
  AgentTurnRequest requestFor(
    String userText, {
    List<AgentHistoryEntry> history = const [],
    AgentState? state,
  }) {
    final now = state ?? snapshot();
    return AgentTurnRequest(
      userText: userText,
      languageCode: now.languageCode,
      languages: profile.languages,
      toolCatalog: tools.catalog(now, allowlists: entities),
      componentCatalog: components.catalogEntries(),
      history: history,
      prompt: AgentPromptParts(
        decideGuidance: profile.decideGuidance,
        decideNotes: tools.decideNotes,
        decideTrailer: profile.decideTrailer,
        renderRules: profile.renderRules,
        renderNotes: tools.renderNotes,
        renderTrailer: profile.renderTrailer,
      ),
    );
  }

  // ── Turns ─────────────────────────────────────────────────────────────────

  /// A typed or spoken turn.
  Future<TurnResult> send(
    String text, {
    List<AgentHistoryEntry> history = const [],
  }) async {
    final state = snapshot();

    // Load reference data before the model is offered the lists built from it.
    await _prime(state);
    final request = requestFor(text, history: history, state: state);

    final AgentDecision decision;
    try {
      decision = await transport.decide(request);
    } catch (e) {
      log('intelligence: planner failed: $e');
      return const TurnFailed('the model could not be reached');
    }

    if (!decision.hasTool) {
      // Either the model answered directly — a greeting, a thank-you — or it
      // produced nothing usable, in which case the user gets the help line
      // rather than an empty bubble.
      final reply = decision.reply;
      final shown = reply == null
          ? const <ComponentSpec>[]
          : components.hydrate(
              reply.components,
              languageCode: state.languageCode,
            );
      if (shown.isNotEmpty) {
        return TurnFinished(shown, language: reply?.language);
      }
      final help = fallback.help(state.languageCode);
      return TurnFinished(
        components.hydrate(help.components, languageCode: state.languageCode),
        language: help.language,
      );
    }

    return _runOrConfirm(decision.tool!, decision.args, request, state);
  }

  /// Whether a button may run [tool]: only a read the user may run right
  /// now. Anything that changes something goes through the model and its
  /// confirmation card.
  bool canInvoke(String tool) {
    final found = tools.usable(tool, snapshot());
    return found != null && found.isRead;
  }

  /// A button on a card asked to run a read. Planning is skipped; the gate
  /// is not.
  Future<TurnResult> invoke(
    String tool,
    Map<String, Object?> args, {
    required String userText,
    List<AgentHistoryEntry> history = const [],
  }) async {
    final state = snapshot();
    if (!canInvoke(tool)) {
      log('intelligence: blocked button for "$tool"');
      return TurnFailed('"$tool" cannot run from a button');
    }
    final request = requestFor(userText, history: history, state: state);
    return _runOrConfirm(tool, args, request, state);
  }

  /// The user tapped confirm. The whole gate runs again on the captured
  /// arguments: the user may have signed out, the tool may have been
  /// switched off, the reservation may have gone while the card sat there.
  Future<TurnResult> accept(
    PendingConfirmation pending, {
    required String userText,
    List<AgentHistoryEntry> history = const [],
  }) async {
    final state = snapshot();
    final tool = tools.usable(pending.tool, state);
    if (tool == null) {
      log(
        'intelligence: refused confirmed ${pending.tool} — no longer available',
      );
      return TurnFailed('"${pending.tool}" is no longer available');
    }
    final validation = tool.validate(pending.args, allowlists: entities);
    if (!validation.isValid) {
      log(
        'intelligence: refused confirmed ${tool.name} — ${validation.summary}',
      );
      return TurnFailed(validation.summary);
    }

    final request = requestFor(userText, history: history, state: state);
    final result = await _execute(tool, pending.args, state);
    return _present(request, result, state);
  }

  /// Something the app did outside the chat — a booking made in its own
  /// screen — shown in the conversation from the tool's own copy.
  TurnFinished note(ToolResult result) {
    final language = session.languageCode;
    final reply = fallback.render(result, language);
    return TurnFinished(
      components.hydrate(reply.components, languageCode: language),
      language: reply.language,
      result: result,
    );
  }

  // ── The gate ──────────────────────────────────────────────────────────────

  /// The single path by which any proposal reaches a tool.
  Future<TurnResult> _runOrConfirm(
    String name,
    Map<String, Object?> args,
    AgentTurnRequest request,
    AgentState state,
  ) async {
    // Withheld from the catalog when unavailable, and refused here as well:
    // the catalog is a hint to the model, this is the check.
    final tool = tools.usable(name, state);
    if (tool == null) {
      log('intelligence: refused "$name" — unknown, off, or not for this user');
      return TurnFailed('"$name" is not available');
    }

    final validation = tool.validate(args, allowlists: entities);
    if (!validation.isValid) {
      log('intelligence: rejected ${tool.name} — ${validation.summary}');
      return TurnFailed(validation.summary);
    }

    if (tool.requiresConfirmation) {
      ConfirmStep? step;
      try {
        step = await tool.confirm!(_call(tool, args, state));
      } catch (e) {
        log('intelligence: ${tool.name} confirmation failed: $e');
      }
      switch (step) {
        case AskToConfirm(:final confirmation):
          return TurnAwaitingConfirmation(confirmation);
        case RefuseWith(:final result):
          // Said now, not after the user has already tapped confirm.
          return _present(request, result, state);
        case null:
          return TurnFailed('"${tool.name}" could not be confirmed');
      }
    }

    final result = await _execute(tool, args, state);
    return _present(request, result, state);
  }

  /// Runs a tool, turning anything it throws into a failure the user sees —
  /// a throwing tool must never leave the chat stuck mid-turn.
  Future<ToolResult> _execute(
    AgentTool tool,
    Map<String, Object?> args,
    AgentState state,
  ) async {
    try {
      return await tool.run(_call(tool, args, state));
    } catch (e) {
      log('intelligence: ${tool.name} threw: $e');
      return ToolResult.failure(tool.name, 'Could not do that just now.');
    }
  }

  ToolCall _call(AgentTool tool, Map<String, Object?> args, AgentState state) =>
      ToolCall(
        tool: tool.name,
        args: args,
        state: state,
        entities: entities,
        log: log,
      );

  Future<void> _prime(AgentState state) async {
    try {
      await tools.prime(state);
    } catch (e) {
      log('intelligence: priming failed: $e');
    }
  }

  /// Asks the model to present a result, and guarantees the user sees it.
  ///
  /// If the model's reply is empty, unparseable, or made entirely of cards
  /// for entities that do not exist, the result is rendered deterministically
  /// instead. A successful lookup never ends in a blank bubble.
  Future<TurnFinished> _present(
    AgentTurnRequest request,
    ToolResult result,
    AgentState state,
  ) async {
    AgentReply reply;
    try {
      reply = await transport.render(request, result);
    } catch (e) {
      log('intelligence: render failed: $e');
      reply = const AgentReply.empty();
    }

    final language = state.languageCode;
    var shown = components.hydrate(reply.components, languageCode: language);
    var replyLanguage = reply.language;

    if (shown.isEmpty) {
      log(
        'intelligence: model reply unusable, rendering ${result.tool} directly',
      );
      final direct = fallback.render(result, language);
      shown = components.hydrate(direct.components, languageCode: language);
      replyLanguage = direct.language;
    }

    return TurnFinished(shown, language: replyLanguage, result: result);
  }
}
