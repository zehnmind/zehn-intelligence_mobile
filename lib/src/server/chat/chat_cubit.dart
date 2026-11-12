import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../api/api_client.dart';
import '../api/turn_client.dart';
import '../api/turn_events.dart';
import '../proxy/tool_runner.dart';
import '../surface/form_draft.dart';
import '../surface/surface.dart';
import '../surface/surface_view.dart';
import 'audio_queue.dart';
import 'chat_state.dart';
import 'history.dart';

/// Runs the conversation over the server's turn flow: one turn at a time,
/// tool rounds through [ZiToolRunner], components into the chat or out
/// through [opens].
class ZiChatCubit extends Cubit<ZiChatState> {
  ZiChatCubit({
    required ZiTurnClient turns,
    required ZiToolRunner tools,
    required ZiAudioQueue audio,
    required String Function() language,
    Future<List<String>> Function()? starterSuggestions,
    int Function()? utcOffsetMinutes,
  }) : _turns = turns,
       _tools = tools,
       _audio = audio,
       _language = language,
       _starterSuggestions = starterSuggestions,
       _utcOffset = utcOffsetMinutes ?? (() => DateTime.now().timeZoneOffset.inMinutes),
       super(const ZiChatState()) {
    _drained = _audio.drained.listen((_) => _emit(state.copyWith(clearPlaying: true)));
  }

  static const maxTextLength = 4000;

  /// Spoken answers held to play again: the latest ones, in memory only.
  static const maxSpokenAnswers = 20;
  static const _conversationErrors = {'conversation_not_found', 'conversation_spec_changed', 'conversation_full'};

  /// The card can no longer be answered.
  static const _actionErrors = {'action_used', 'action_expired', 'action_not_found'};

  final ZiTurnClient _turns;
  final ZiToolRunner _tools;
  final ZiAudioQueue _audio;
  final String Function() _language;
  final Future<List<String>> Function()? _starterSuggestions;
  final int Function() _utcOffset;
  final StreamController<ZiComponentItem> _opens = StreamController.broadcast();

  StreamSubscription<TurnEvent>? _sub;
  StreamSubscription<void>? _drained;

  /// Each turn's `audio` clips, oldest turn first; never written to disk.
  final Map<String, List<AudioClip>> _clips = {};

  /// The user stopped the answer that is still coming: the rest of it is
  /// held, not played.
  bool _quiet = false;

  /// Actions the user confirmed whose write has not been made yet.
  final Set<String> _confirmed = {};
  final Map<String, Timer> _expiry = {};

  /// What the person typed into each form of this chat, by form id. Kept here, not in the
  /// widgets, so it outlives a card scrolled away and the chat closed and opened again.
  final Map<String, ZiFormDraft> _forms = {};

  /// The forms the running turn showed: locked if that turn fails.
  final Set<String> _shownThisTurn = {};

  /// The form whose answers the running turn sends.
  String? _sending;
  Completer<TurnEvent?>? _leg;
  TurnInput? _last;
  int _generation = 0;
  int _assistantIds = 0;

  /// `sheet` and `route` components, for the UI to open.
  Stream<ZiComponentItem> get opens => _opens.stream;

  Future<void> sendText(String text) async {
    var t = text.trim();
    if (t.isEmpty || state.busy || state.readOnly || isClosed) return;
    if (t.length > maxTextLength) t = t.substring(0, maxTextLength);
    _dismissPendingForms();
    final input = TurnInput.text(
      conversationId: state.conversationId,
      text: t,
      language: _language(),
      utcOffsetMinutes: _utcOffset(),
    );
    await _begin(input, ZiUserItem(t));
  }

  Future<void> sendAudio(String base64, String format, {required bool voiceReply}) async {
    if (state.busy || state.readOnly || isClosed) return;
    _dismissPendingForms();
    final input = TurnInput.audio(
      conversationId: state.conversationId,
      base64: base64,
      format: format,
      language: _language(),
      utcOffsetMinutes: _utcOffset(),
      voiceReply: voiceReply,
    );
    await _begin(input, const ZiUserItem('', spoken: true));
  }

  /// Sends the last question again, after a retryable error. A form is sent
  /// with what it holds now, not what the failed send carried.
  Future<void> retry() async {
    final last = _last;
    if (last == null || state.busy || isClosed) return;
    final items = [...state.items];
    if (items.isNotEmpty && items.last is ZiErrorItem) items.removeLast();
    final formId = last.input['form_id'];
    if (last.isForm && formId is String) {
      _emit(state.copyWith(items: items));
      await submitForm(formId);
      return;
    }
    _quiet = false;
    _emit(state.copyWith(items: items, busy: true, suggestions: const []));
    await _run(last.withConversation(state.conversationId), _generation);
  }

  Future<void> loadStarterSuggestions() async {
    final load = _starterSuggestions;
    if (load == null || state.items.isNotEmpty) return;
    try {
      final items = await load();
      if (state.items.isEmpty) _emit(state.copyWith(suggestions: items.take(4).toList()));
    } on Object {
      // Best effort: an empty chat simply shows no chips.
    }
  }

  /// The user's tap on a pending confirm card: a new turn with the
  /// decision. Only the first tap counts; an expired card sends nothing.
  Future<void> decide(String actionId, {required bool confirm}) async {
    if (state.busy || isClosed) return;
    final card = state.items.whereType<ZiConfirmItem>().where((c) => c.actionId == actionId).firstOrNull;
    if (card == null || card.status != ZiConfirmStatus.pending) return;
    _dismissPendingForms();
    _expiry.remove(actionId)?.cancel();
    _setStatus(actionId, confirm ? ZiConfirmStatus.confirmed : ZiConfirmStatus.cancelled);
    if (confirm) _confirmed.add(actionId);
    await _audio.stop();
    _quiet = false;
    final input = TurnInput.action(
      conversationId: state.conversationId,
      actionId: actionId,
      confirm: confirm,
      language: _language(),
      utcOffsetMinutes: _utcOffset(),
    );
    _last = input;
    _emit(state.copyWith(busy: true, suggestions: const [], clearPlaying: true));
    await _run(input, _generation);
  }

  /// True, once, for an action the user confirmed: the tool runner asks
  /// before it makes a write.
  bool takeConfirmed(String actionId) => _confirmed.remove(actionId);

  void _showConfirm(ConfirmEvent event) {
    if (state.items.any((i) => i is ZiConfirmItem && i.actionId == event.actionId)) return;
    final card = ZiConfirmItem(
      actionId: event.actionId,
      tool: event.tool,
      method: event.method,
      surface: event.surface,
      data: event.props,
      label: event.confirmLabel,
    );
    _emit(state.copyWith(items: [...state.items, card]));
    _expiry[event.actionId]?.cancel();
    _expiry[event.actionId] = Timer(event.expiresIn, () {
      _expiry.remove(event.actionId);
      _setStatus(event.actionId, ZiConfirmStatus.expired, onlyPending: true);
    });
  }

  void _setStatus(String actionId, ZiConfirmStatus status, {bool onlyPending = false}) {
    _emit(state.copyWith(items: [
      for (final item in state.items)
        item is ZiConfirmItem && item.actionId == actionId && (!onlyPending || item.status == ZiConfirmStatus.pending)
            ? item.withStatus(status)
            : item,
    ]));
  }

  /// The draft of a form in this chat; null for an id it does not hold.
  ZiFormDraft? formDraft(String formId) => _forms[formId];

  /// The person's tap on Send: checks the draft, then a new turn with its values.
  /// Only the first tap counts. A form with a block this build cannot draw is
  /// never sent: it would go without that field.
  Future<void> submitForm(String formId) async {
    final conversationId = state.conversationId;
    if (state.busy || state.readOnly || isClosed || conversationId == null) return;
    final form = state.items.whereType<ZiFormItem>().where((f) => f.formId == formId).firstOrNull;
    final draft = _forms[formId];
    if (form == null || form.status != ZiFormStatus.pending || draft == null || !ziDraws(draft.surface)) return;
    if (!draft.check()) return;
    draft.markNotSent(false);
    _sending = formId;
    // Set before anything is awaited, so a second tap finds it no longer pending.
    _moveForms((f) => switch (f) {
      _ when f.formId == formId => ZiFormStatus.sending,
      ZiFormItem(status: ZiFormStatus.pending) => ZiFormStatus.dismissed,
      _ => null,
    });
    await _audio.stop();
    _quiet = false;
    final input = TurnInput.form(
      conversationId: conversationId,
      formId: formId,
      values: draft.values,
      language: _language(),
      utcOffsetMinutes: _utcOffset(),
    );
    _last = input;
    _emit(state.copyWith(busy: true, suggestions: const [], clearPlaying: true));
    await _run(input, _generation);
  }

  void _showForm(FormEvent event) {
    if (state.items.any((i) => i is ZiFormItem && i.formId == event.formId)) return;
    final draft = _draftOf(event.surface, event.props);
    if (draft == null) return;
    _forms[event.formId] = draft;
    _shownThisTurn.add(event.formId);
    final form = ZiFormItem(
      formId: event.formId,
      callId: event.callId,
      component: event.component,
      tool: event.tool,
      surface: event.surface,
      data: event.props,
    );
    _emit(state.copyWith(items: [...state.items, form]));
  }

  /// A draft of [surface] holding the prefill in [data]; null for a template
  /// that does not parse, which shows no form.
  ZiFormDraft? _draftOf(Map<String, Object?> surface, Map<String, Object?> data) {
    final ZiSurface parsed;
    try {
      parsed = ZiSurface.parse(surface);
    } on FormatException catch (e) {
      debugPrint('zehn_intelligence: a form template could not be read: ${e.message}');
      return null;
    }
    final prefill = data['form'];
    return ZiFormDraft(parsed, prefill: prefill is Map<String, Object?> ? prefill : const {});
  }

  /// Gives each form the status [next] names for it; null leaves it as it is.
  void _moveForms(ZiFormStatus? Function(ZiFormItem form) next) {
    ZiChatItem moved(ZiChatItem item) {
      if (item is! ZiFormItem) return item;
      final status = next(item);
      return status == null || status == item.status ? item : item.withStatus(status);
    }

    _emit(state.copyWith(items: [for (final item in state.items) moved(item)]));
  }

  void _setFormStatus(String formId, ZiFormStatus status) => _moveForms((f) => f.formId == formId ? status : null);

  /// A new turn takes the place of every form still waiting for an answer.
  void _dismissPendingForms() => _moveForms((f) => f.status == ZiFormStatus.pending ? ZiFormStatus.dismissed : null);

  /// The turn that showed these forms failed: it is not remembered, so its
  /// forms can no longer be answered.
  void _dismissShownForms() {
    if (_shownThisTurn.isEmpty) return;
    _moveForms((f) => _shownThisTurn.contains(f.formId) && f.status == ZiFormStatus.pending ? ZiFormStatus.dismissed : null);
    _shownThisTurn.clear();
  }

  /// What a failed form turn does to its form. True when the form says it all
  /// and the chat shows no error.
  bool _formFailed(ZiApiException error) {
    final formId = _sending;
    if (formId == null) return false;
    final status = switch (error.code) {
      'form_invalid' => ZiFormStatus.pending,
      'form_used' => error.params['status'] == 'submitted' ? ZiFormStatus.submitted : ZiFormStatus.dismissed,
      'form_not_found' => ZiFormStatus.dismissed,
      // A form belongs to its conversation: it can't be carried into a new one.
      final code when _conversationErrors.contains(code) => ZiFormStatus.dismissed,
      _ => null,
    };
    if (status == null) {
      _formNotSent();
      return false;
    }
    _sending = null;
    _setFormStatus(formId, status);
    if (error.code == 'form_invalid') _showServerErrors(formId, error.params['errors']);
    if (_conversationErrors.contains(error.code)) _emit(state.copyWith(clearConversation: true));
    return true;
  }

  /// The form's send failed for a reason of its own: open again, every value
  /// kept, saying Not sent.
  void _formNotSent() {
    final formId = _sending;
    if (formId == null) return;
    _sending = null;
    _setFormStatus(formId, ZiFormStatus.pending);
    _forms[formId]?.markNotSent(true);
  }

  /// `form_invalid`'s `params.errors` on their fields. A refusal that names
  /// nothing the form can show says Not sent instead, so a Send never fails
  /// without a word.
  void _showServerErrors(String formId, Object? errors) {
    final draft = _forms[formId];
    if (draft == null) return;
    final rules = <String, String>{};
    var unread = errors is! List || errors.isEmpty;
    for (final e in errors is List ? errors : const <Object?>[]) {
      if (e is Map && e['field'] is String && e['rule'] is String) {
        rules[e['field'] as String] = e['rule'] as String;
      } else {
        unread = true;
      }
    }
    draft.serverErrors(rules);
    if (unread) draft.markNotSent(true);
  }

  /// Shows an error the SDK found itself, before anything was sent (a
  /// recording over 1 MiB).
  void showError(String code, {bool retryable = false}) =>
      _emit(state.copyWith(items: [...state.items, ZiErrorItem(code, retryable: retryable)]));

  /// Forgets the conversation (sign-out, "new chat").
  void reset() {
    _forget();
    _emit(const ZiChatState());
  }

  /// Shows a conversation from the history in place of the current one. One
  /// that can go on takes the next question; one that can't is read-only,
  /// and its unanswered confirm cards and forms are past answering. Each form
  /// gets a draft holding what it was sent or offered with; one whose
  /// template does not parse is left out. Picking the open conversation again
  /// keeps what was typed into its forms that are still waiting.
  void resume(ZiConversation conversation) {
    final kept = <String, ZiFormDraft>{};
    if (conversation.id == state.conversationId) {
      for (final item in conversation.items) {
        if (item is ZiFormItem && item.status == ZiFormStatus.pending) {
          if (_forms.remove(item.formId) case final draft?) kept[item.formId] = draft;
        }
      }
    }
    _forget();
    final open = conversation.canContinue;
    final items = <ZiChatItem>[];
    for (final item in conversation.items) {
      if (item is ZiFormItem) {
        final draft = kept.remove(item.formId) ?? _draftOf(item.surface, item.data);
        if (draft == null) continue;
        _forms[item.formId]?.dispose();
        _forms[item.formId] = draft;
      }
      items.add(switch (item) {
        ZiConfirmItem(status: ZiConfirmStatus.pending) when !open => item.withStatus(ZiConfirmStatus.expired),
        ZiFormItem(status: ZiFormStatus.pending) when !open => item.withStatus(ZiFormStatus.dismissed),
        _ => item,
      });
    }
    _emit(ZiChatState(items: items, conversationId: open ? conversation.id : null, readOnly: !open));
  }

  void _forget() {
    _hangUp();
    _clips.clear();
    _quiet = false;
    _last = null;
    _confirmed.clear();
    for (final timer in _expiry.values) {
      timer.cancel();
    }
    _expiry.clear();
    _dropForms();
  }

  void _dropForms() {
    for (final draft in _forms.values) {
      draft.dispose();
    }
    _forms.clear();
    _shownThisTurn.clear();
    _sending = null;
  }

  @override
  Future<void> close() async {
    _hangUp();
    unawaited(_drained?.cancel());
    for (final timer in _expiry.values) {
      timer.cancel();
    }
    _dropForms();
    await _opens.close();
    return super.close();
  }

  Future<void> _begin(TurnInput input, ZiUserItem user) async {
    await _audio.stop();
    _quiet = false;
    _last = input;
    _emit(state.copyWith(items: [...state.items, user], busy: true, suggestions: const [], clearPlaying: true));
    await _run(input, _generation);
  }

  /// Stops the spoken answer (the chat sheet closed); the rest of an answer
  /// still coming stays quiet.
  Future<void> stopAudio() async {
    if (state.busy) _quiet = true;
    await _audio.stop();
    _emit(state.copyWith(clearPlaying: true));
  }

  /// Plays a turn's answer again from the clips held, in `seq` order; a tap
  /// on the answer being spoken stops it. Nothing else plays while a turn
  /// runs.
  Future<void> replay(String turnId) async {
    if (isClosed) return;
    if (state.playing == turnId) {
      if (state.busy) _quiet = true;
      await _audio.stop();
      _emit(state.copyWith(clearPlaying: true));
      return;
    }
    final clips = _clips[turnId];
    if (state.busy || clips == null) return;
    await _audio.stop();
    _emit(state.copyWith(playing: turnId));
    for (final clip in [...clips]..sort((a, b) => a.seq.compareTo(b.seq))) {
      _audio.add(clip.seq, clip.data, clip.format);
    }
  }

  Future<void> _run(TurnInput input, int generation) async {
    _shownThisTurn.clear();
    try {
      await _loop(input, generation);
    } on Object catch (e) {
      // Last resort: a bug or a thrown callback must not leave the chat busy.
      if (generation != _generation || isClosed) return;
      _dismissShownForms();
      _formNotSent();
      _emit(state.copyWith(busy: false, items: [...state.items, const ZiErrorItem('internal_error', retryable: true)]));
      assert(() {
        debugPrint('zehn_intelligence: the turn failed: $e');
        return true;
      }());
    }
  }

  Future<void> _loop(TurnInput input, int generation) async {
    var current = input;
    var stream = _turns.start(current);
    var conversationRetried = false;
    while (true) {
      final calls = <ClientApiRequest>[];
      final end = await _consume(stream, calls);
      if (end == null || generation != _generation || isClosed) return;
      switch (end) {
        case TurnPaused():
          final results = await _tools.runAll(calls, expiresIn: end.expiresIn, maxResultBytes: end.maxResultBytes);
          if (generation != _generation || isClosed) return;
          stream = _turns.sendResults(end.turnId, results, deadline: end.deadline);
        case TurnDone():
          // A form is answered only by a turn that ends done.
          final form = _sending;
          _sending = null;
          if (form != null) _setFormStatus(form, ZiFormStatus.submitted);
          _emit(state.copyWith(busy: false));
          return;
        case TurnFailed():
          final code = end.error.code;
          _dismissShownForms();
          if (_formFailed(end.error)) {
            _emit(state.copyWith(busy: false));
            return;
          }
          final action = current.input['action_id'];
          if (current.isAction && action is String && _actionErrors.contains(code)) {
            // Already used, expired or unknown: the card says so.
            _confirmed.remove(action);
            _setStatus(action, ZiConfirmStatus.expired);
            _emit(state.copyWith(busy: false));
            return;
          }
          if (!conversationRetried && _conversationErrors.contains(code)) {
            conversationRetried = true;
            current = current.withConversation(null);
            _last = current;
            _emit(state.copyWith(clearConversation: true));
            stream = _turns.start(current);
            continue;
          }
          _emit(state.copyWith(
            busy: false,
            items: [...state.items, ZiErrorItem(code, retryable: end.error.retryable, retryAfter: end.error.retryAfter)],
          ));
          return;
        default:
          return;
      }
    }
  }

  /// Applies one leg's events; completes with its terminal event, or null
  /// when the leg was cut off.
  Future<TurnEvent?> _consume(Stream<TurnEvent> stream, List<ClientApiRequest> calls) {
    final leg = _leg = Completer<TurnEvent?>();
    _sub = stream.listen(
      (event) {
        if (isClosed || leg.isCompleted) return;
        switch (event) {
          case TurnStarted():
            _emit(state.copyWith(conversationId: event.conversationId));
            // The server took the answers: the form draws as sent.
            if (_sending case final form?) _setFormStatus(form, ZiFormStatus.submitted);
          case TranscriptEvent():
            _replaceSpoken(event.text);
          case TextDelta():
            _appendText(event.text, event.turnId);
          case ClientApiRequest():
            calls.add(event);
          case MountComponent():
            _mount(event);
          case ConfirmEvent():
            _showConfirm(event);
          case FormEvent():
            _showForm(event);
          case AudioClip():
            _speak(event);
          case SuggestionsEvent():
            _emit(state.copyWith(suggestions: event.items));
          case TurnPaused() || TurnDone() || TurnFailed():
            leg.complete(event);
          case PingEvent():
            break;
        }
      },
      onError: (Object _) {
        if (!leg.isCompleted) leg.complete(null);
      },
      onDone: () {
        if (!leg.isCompleted) leg.complete(null);
      },
    );
    return leg.future;
  }

  void _appendText(String delta, String turnId) {
    final items = [...state.items];
    final last = items.isEmpty ? null : items.last;
    if (last is ZiAssistantItem) {
      items[items.length - 1] = ZiAssistantItem(last.id, last.text + delta, turnId: last.turnId);
    } else {
      items.add(ZiAssistantItem('a${++_assistantIds}', delta, turnId: turnId));
    }
    _emit(state.copyWith(items: items));
  }

  /// Plays a clip as it comes (unless the user stopped this answer) and
  /// keeps it, so the answer can be played again.
  void _speak(AudioClip clip) {
    _keep(clip);
    if (_quiet) return;
    _audio.add(clip.seq, clip.data, clip.format);
    if (clip.turnId.isNotEmpty && state.playing != clip.turnId) _emit(state.copyWith(playing: clip.turnId));
  }

  void _keep(AudioClip clip) {
    final turn = clip.turnId;
    if (turn.isEmpty) return;
    final held = _clips[turn];
    if (held != null) {
      held.add(clip);
      return;
    }
    _clips[turn] = [clip];
    while (_clips.length > maxSpokenAnswers) {
      _clips.remove(_clips.keys.first);
    }
    _emit(state.copyWith(voiced: {..._clips.keys}));
  }

  void _replaceSpoken(String text) {
    final items = [...state.items];
    final i = items.lastIndexWhere((item) => item is ZiUserItem);
    if (i < 0) return;
    items[i] = ZiUserItem(text, spoken: true);
    _emit(state.copyWith(items: items));
  }

  void _mount(MountComponent event) {
    final kind = switch (event.kind) {
      'sheet' => ZiComponentKind.sheet,
      'route' => ZiComponentKind.route,
      _ => ZiComponentKind.inline,
    };
    final item = ZiComponentItem(event.callId, event.component, kind, event.props, surface: event.surface, route: event.route);
    if (kind == ZiComponentKind.inline) {
      _emit(state.copyWith(items: [...state.items, item]));
    } else if (!_opens.isClosed) {
      _opens.add(item);
    }
  }

  void _hangUp() {
    _generation++;
    unawaited(_sub?.cancel());
    _sub = null;
    final leg = _leg;
    if (leg != null && !leg.isCompleted) leg.complete(null);
    unawaited(_audio.stop());
  }

  void _emit(ZiChatState next) {
    if (!isClosed) emit(next);
  }
}
