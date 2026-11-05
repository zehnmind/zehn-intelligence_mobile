import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/engine/agent_engine.dart';
import '../../core/entities/entity_store.dart';
import '../../core/log.dart';
import '../../core/model/agent_message.dart';
import '../../core/model/component_spec.dart';
import '../../core/protocol/turn.dart';
import '../../core/tools/tool_result.dart';

part 'agent_chat_event.dart';
part 'agent_chat_state.dart';

/// The live conversation: the transcript, whose turn it is, and what is
/// saved.
///
/// Every turn is run by the [AgentEngine] — this bloc only keeps the
/// messages in step with it. Provided above the app's navigator, so the
/// conversation outlives the chat sheet.
class AgentChatBloc extends Bloc<AgentChatEvent, AgentChatState> {
  AgentChatBloc({
    required AgentEngine engine,
    required EntityStore entities,
    AgentLog log = silentAgentLog,
  }) : _engine = engine,
       _entities = entities,
       _log = log,
       super(const AgentChatState()) {
    on<AgentMessageSent>(_onMessageSent);
    on<AgentInvokeRequested>(_onInvokeRequested);
    on<AgentConfirmationAccepted>(_onConfirmationAccepted);
    on<AgentConfirmationDeclined>(_onConfirmationDeclined);
    on<AgentConversationCleared>(_onCleared);
    on<AgentNotePosted>(_onNotePosted);
  }

  final AgentEngine _engine;
  final EntityStore _entities;
  final AgentLog _log;

  int _idSeed = 0;
  String _lastUserText = '';

  /// Which saved conversation the live transcript belongs to. A fresh one is
  /// minted on clear, and adopted from the session being resumed.
  String _sessionId = DateTime.now().microsecondsSinceEpoch.toString();

  String get sessionId => _sessionId;

  String _nextId() => 'm${_idSeed++}';

  String get _language => _engine.session.languageCode;

  // ── Turns ─────────────────────────────────────────────────────────────────

  Future<void> _onMessageSent(
    AgentMessageSent event,
    Emitter<AgentChatState> emit,
  ) async {
    final text = event.text.trim();
    if (text.isEmpty || state.isBusy) return;
    _lastUserText = text;

    final assistantId = _nextId();
    emit(
      state.copyWith(
        messages: [
          ...state.messages,
          AgentMessage(
            id: _nextId(),
            role: AgentMessageRole.user,
            text: text,
            viaVoice: event.viaVoice,
          ),
          AgentMessage(
            id: assistantId,
            role: AgentMessageRole.assistant,
            text: '',
            status: AgentMessageStatus.thinking,
            // Voice in, voice out: the reply to a spoken question is spoken.
            viaVoice: event.viaVoice,
          ),
        ],
      ),
    );

    // Read after the new turn is on screen, as the planner sees it: the live
    // user message is dropped from history, and anything before it kept.
    final history = _historyEntries();
    await _run(emit, assistantId, () => _engine.send(text, history: history));
  }

  Future<void> _onInvokeRequested(
    AgentInvokeRequested event,
    Emitter<AgentChatState> emit,
  ) async {
    if (state.isBusy || !_engine.canInvoke(event.tool)) return;

    final echo = event.echo?.trim() ?? '';
    if (echo.isNotEmpty) _lastUserText = echo;

    final assistantId = _nextId();
    emit(
      state.copyWith(
        messages: [
          ...state.messages,
          if (echo.isNotEmpty)
            AgentMessage(
              id: _nextId(),
              role: AgentMessageRole.user,
              text: echo,
            ),
          AgentMessage(
            id: assistantId,
            role: AgentMessageRole.assistant,
            text: '',
            status: AgentMessageStatus.thinking,
          ),
        ],
      ),
    );

    final history = _historyEntries();
    await _run(
      emit,
      assistantId,
      () => _engine.invoke(
        event.tool,
        event.args,
        userText: _lastUserText,
        history: history,
      ),
    );
  }

  Future<void> _onConfirmationAccepted(
    AgentConfirmationAccepted event,
    Emitter<AgentChatState> emit,
  ) async {
    final message = _messageById(event.messageId);
    final pending = message?.pendingConfirmation;
    if (message == null || pending == null) return;
    if (pending.requiresStepUp && !event.verified) {
      // The card stays: the user can still confirm once verified.
      _log('intelligence: ${pending.tool} needs step-up — not run');
      return;
    }

    _update(
      emit,
      message.id,
      (m) => m.copyWith(
        status: AgentMessageStatus.thinking,
        clearPendingConfirmation: true,
      ),
    );

    await _run(
      emit,
      message.id,
      () => _engine.accept(
        pending,
        userText: _lastUserText,
        history: _historyEntries(),
      ),
    );
  }

  void _onConfirmationDeclined(
    AgentConfirmationDeclined event,
    Emitter<AgentChatState> emit,
  ) {
    _update(
      emit,
      event.messageId,
      (message) => message.copyWith(
        status: AgentMessageStatus.cancelled,
        clearPendingConfirmation: true,
      ),
    );
  }

  void _onNotePosted(AgentNotePosted event, Emitter<AgentChatState> emit) {
    final assistantId = _nextId();
    emit(
      state.copyWith(
        messages: [
          ...state.messages,
          AgentMessage(
            id: assistantId,
            role: AgentMessageRole.assistant,
            text: '',
            status: AgentMessageStatus.thinking,
          ),
        ],
      ),
    );
    try {
      _apply(emit, assistantId, _engine.note(event.result));
    } catch (e) {
      _log('intelligence: could not post a note: $e');
      _fail(emit, assistantId);
    }
  }

  /// Starts a new conversation.
  void _onCleared(
    AgentConversationCleared event,
    Emitter<AgentChatState> emit,
  ) {
    _entities.clear();
    _sessionId = DateTime.now().microsecondsSinceEpoch.toString();
    _lastUserText = '';
    emit(const AgentChatState());
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  /// Runs one engine call and settles the assistant message whatever
  /// happens: nothing may leave a message thinking forever, because a busy
  /// chat drops every later turn.
  Future<void> _run(
    Emitter<AgentChatState> emit,
    String assistantId,
    Future<TurnResult> Function() turn,
  ) async {
    try {
      _apply(emit, assistantId, await turn());
    } catch (e) {
      _log('intelligence: turn failed: $e');
      _fail(emit, assistantId);
    }
  }

  void _apply(Emitter<AgentChatState> emit, String id, TurnResult result) {
    switch (result) {
      case TurnFinished(:final components, :final language, :final result):
        _finish(emit, id, components, result: result, language: language);
      case TurnAwaitingConfirmation(:final confirmation):
        _update(
          emit,
          id,
          (message) => message.copyWith(
            status: AgentMessageStatus.awaitingConfirmation,
            pendingConfirmation: confirmation,
          ),
        );
      case TurnFailed():
        _fail(emit, id);
    }
  }

  /// Earlier turns, oldest first, for the planner to read as conversation.
  ///
  /// The turn currently being planned is excluded: it is sent as the live
  /// message, and sending it twice makes the model answer itself.
  List<AgentHistoryEntry> _historyEntries() {
    final entries = <AgentHistoryEntry>[];
    for (final message in state.messages) {
      if (message.status == AgentMessageStatus.thinking) continue;
      final text = message.text.trim();
      if (text.isEmpty) continue;
      entries.add(AgentHistoryEntry(isUser: message.isUser, text: text));
    }
    if (entries.isNotEmpty && entries.last.isUser) entries.removeLast();
    const window = 12;
    return entries.length > window
        ? entries.sublist(entries.length - window)
        : entries;
  }

  AgentMessage? _messageById(String id) {
    for (final message in state.messages) {
      if (message.id == id) return message;
    }
    return null;
  }

  void _update(
    Emitter<AgentChatState> emit,
    String id,
    AgentMessage Function(AgentMessage message) transform,
  ) {
    emit(
      state.copyWith(
        messages: [
          for (final message in state.messages)
            if (message.id == id) transform(message) else message,
        ],
      ),
    );
  }

  void _finish(
    Emitter<AgentChatState> emit,
    String id,
    List<ComponentSpec> components, {
    ToolResult? result,
    String? language,
  }) {
    _update(
      emit,
      id,
      (message) => message.copyWith(
        components: components,
        // The accessible summary of whatever the cards show — and what the
        // planner is shown of this turn when it is replayed as history.
        text: components.isEmpty
            ? (result?.summary ?? '')
            : components.map((c) => c.fallbackText).join(' '),
        status: components.isEmpty
            ? AgentMessageStatus.failed
            : AgentMessageStatus.complete,
        language: language ?? _language,
      ),
    );
  }

  void _fail(Emitter<AgentChatState> emit, String id) {
    _update(
      emit,
      id,
      (message) => message.copyWith(
        status: AgentMessageStatus.failed,
        clearPendingConfirmation: true,
      ),
    );
  }
}
