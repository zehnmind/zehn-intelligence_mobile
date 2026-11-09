import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../api/turn_client.dart';
import '../api/turn_events.dart';
import '../bootstrap/bootstrap.dart';
import '../proxy/tool_runner.dart';
import 'audio_queue.dart';
import 'chat_state.dart';

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
       super(const ZiChatState());

  static const maxTextLength = 4000;
  static const _conversationErrors = {'conversation_not_found', 'conversation_spec_changed', 'conversation_full'};

  final ZiTurnClient _turns;
  final ZiToolRunner _tools;
  final ZiAudioQueue _audio;
  final String Function() _language;
  final Future<List<String>> Function()? _starterSuggestions;
  final int Function() _utcOffset;
  final StreamController<ZiComponentItem> _opens = StreamController.broadcast();

  StreamSubscription<TurnEvent>? _sub;
  Completer<TurnEvent?>? _leg;
  TurnInput? _last;
  int _generation = 0;
  int _assistantIds = 0;

  /// `sheet` and `route` components, for the UI to open.
  Stream<ZiComponentItem> get opens => _opens.stream;

  Future<void> sendText(String text) async {
    var t = text.trim();
    if (t.isEmpty || state.busy || isClosed) return;
    if (t.length > maxTextLength) t = t.substring(0, maxTextLength);
    final input = TurnInput.text(
      conversationId: state.conversationId,
      text: t,
      language: _language(),
      utcOffsetMinutes: _utcOffset(),
    );
    await _begin(input, ZiUserItem(t));
  }

  Future<void> sendAudio(String base64, String format, {required bool voiceReply}) async {
    if (state.busy || isClosed) return;
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

  /// Sends the last question again, after a retryable error.
  Future<void> retry() async {
    final last = _last;
    if (last == null || state.busy || isClosed) return;
    final items = [...state.items];
    if (items.isNotEmpty && items.last is ZiErrorItem) items.removeLast();
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

  /// Forgets the conversation (sign-out, "new chat").
  void reset() {
    _hangUp();
    _last = null;
    _emit(const ZiChatState());
  }

  @override
  Future<void> close() async {
    _hangUp();
    await _opens.close();
    return super.close();
  }

  Future<void> _begin(TurnInput input, ZiUserItem user) async {
    await _audio.stop();
    _last = input;
    _emit(state.copyWith(items: [...state.items, user], busy: true, suggestions: const []));
    await _run(input, _generation);
  }

  Future<void> _run(TurnInput input, int generation) async {
    var current = input;
    var stream = _turns.start(current);
    var conversationRetried = false;
    while (true) {
      final calls = <ClientApiRequest>[];
      final end = await _consume(stream, calls);
      if (end == null || generation != _generation || isClosed) return;
      switch (end) {
        case TurnPaused():
          final results = await _tools.runAll(calls);
          if (generation != _generation || isClosed) return;
          stream = _turns.sendResults(end.turnId, results, deadline: end.deadline);
        case TurnDone():
          _emit(state.copyWith(busy: false));
          return;
        case TurnFailed():
          final code = end.error.code;
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
            items: [...state.items, ZiErrorItem(code, retryable: end.error.retryable)],
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
          case TranscriptEvent():
            _replaceSpoken(event.text);
          case TextDelta():
            _appendText(event.text);
          case ClientApiRequest():
            calls.add(event);
          case MountComponent():
            _mount(event);
          case AudioClip():
            _audio.add(event.seq, event.data, event.format);
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

  void _appendText(String delta) {
    final items = [...state.items];
    final last = items.isEmpty ? null : items.last;
    if (last is ZiAssistantItem) {
      items[items.length - 1] = ZiAssistantItem(last.id, last.text + delta);
    } else {
      items.add(ZiAssistantItem('a${++_assistantIds}', delta));
    }
    _emit(state.copyWith(items: items));
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
    final item = ZiComponentItem(event.callId, event.component, kind, event.props);
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
