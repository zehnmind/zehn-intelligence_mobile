import 'dart:async';

import 'package:dio/dio.dart';

import '../../ui/zehn_integrator.dart' show ziIsComponentName, ziIsToolName;
import '../auth/token_source.dart';
import 'api_client.dart';
import 'sse.dart';
import 'turn_events.dart';

/// The body of `POST /v1/turns`.
class TurnInput {
  TurnInput.text({this.conversationId, required String text, required this.language, this.utcOffsetMinutes})
    : input = {'type': 'text', 'text': text},
      voiceReply = false;

  TurnInput.audio({
    this.conversationId,
    required String base64,
    required String format,
    required this.language,
    this.utcOffsetMinutes,
    this.voiceReply = true,
  }) : input = {'type': 'audio', 'format': format, 'data': base64};

  /// The user's tap on a `confirm` card.
  TurnInput.action({
    this.conversationId,
    required String actionId,
    required bool confirm,
    required this.language,
    this.utcOffsetMinutes,
  }) : input = {'type': 'action', 'action_id': actionId, 'decision': confirm ? 'confirm' : 'cancel'},
       voiceReply = false;

  /// The user's send of a `form` card: [values] by field key.
  TurnInput.form({
    this.conversationId,
    required String formId,
    required Map<String, Object?> values,
    required this.language,
    this.utcOffsetMinutes,
  }) : input = {'type': 'form', 'form_id': formId, 'values': values},
       voiceReply = false;

  const TurnInput._(this.conversationId, this.input, this.language, this.utcOffsetMinutes, this.voiceReply);

  /// Null starts a new chat.
  final String? conversationId;
  final Map<String, Object?> input;
  final String language;
  final int? utcOffsetMinutes;
  final bool voiceReply;

  bool get isAudio => input['type'] == 'audio';
  bool get isAction => input['type'] == 'action';
  bool get isForm => input['type'] == 'form';

  TurnInput withConversation(String? id) => TurnInput._(id, input, language, utcOffsetMinutes, voiceReply);

  Map<String, Object?> toJson() => {
    'conversation_id': conversationId,
    'input': input,
    'language': language,
    'utc_offset_minutes': ?utcOffsetMinutes,
    'voice_reply': voiceReply,
  };
}

/// The names of the tools the app registered handlers for and of the
/// components it registered builders for, as they stand now.
typedef ZiRegistered = ({Iterable<String> tools, Iterable<String> components}) Function();

/// The most names of each kind a turn carries (the server's limits).
const ziMaxToolNames = 128;
const ziMaxComponentNames = 32;

/// What a turn says of the app's own code: `tools` and `components`, each
/// the valid names once, sorted, and left out when there are none. The
/// server offers the model a tool the app's handler runs, or a component its
/// builder draws, only when the turn names it.
Map<String, Object?> registeredNames(ZiRegistered? registered) {
  if (registered == null) return const {};
  final (:tools, :components) = registered();
  List<String> names(Iterable<String> all, bool Function(String) valid, int most) =>
      ({for (final name in all) if (valid(name)) name}.toList()..sort()).take(most).toList();
  final toolNames = names(tools, ziIsToolName, ziMaxToolNames);
  final componentNames = names(components, ziIsComponentName, ziMaxComponentNames);
  return {
    if (toolNames.isNotEmpty) 'tools': toolNames,
    if (componentNames.isNotEmpty) 'components': componentNames,
  };
}

/// One entry of `POST /v1/turns/{id}/tool-results`.
class ToolCallResult {
  ToolCallResult.ok(this.callId, this.data) : ok = true, errorCode = null, errorMessage = null;

  ToolCallResult.error(this.callId, String code, String message)
    : ok = false,
      data = null,
      errorCode = code,
      errorMessage = message.length > 500 ? message.substring(0, 500) : message;

  final String callId;
  final bool ok;
  final Object? data;
  final String? errorCode;
  final String? errorMessage;

  Map<String, Object?> toJson() => ok
      ? {'call_id': callId, 'ok': true, 'data': data}
      : {'call_id': callId, 'ok': false, 'error': {'code': errorCode, 'message': errorMessage}};
}

/// Runs the legs of a turn. Every failure arrives as a [TurnFailed] event;
/// each stream ends after its terminal event ([TurnPaused], [TurnDone] or
/// [TurnFailed]). Pings are not passed on.
class ZiTurnClient {
  ZiTurnClient({
    required ZiApiClient api,
    required ZiTokenSource Function() tokens,
    this.registered,
    this.pingTimeout = const Duration(seconds: 45),
    this.retryDelay = const Duration(seconds: 1),
  }) : _api = api,
       _tokens = tokens;

  final ZiApiClient _api;
  final ZiTokenSource Function() _tokens;

  /// What the app registered in its code; read as each turn starts.
  final ZiRegistered? registered;
  final Duration pingTimeout;
  final Duration retryDelay;

  Stream<TurnEvent> start(TurnInput input) {
    final body = {...input.toJson(), ...registeredNames(registered)};
    return _leg((cancel) => _open('/v1/turns', body, cancel));
  }

  /// Retries once, after [retryDelay], only when there was no HTTP status at
  /// all and the [deadline] has not passed.
  Stream<TurnEvent> sendResults(String turnId, List<ToolCallResult> results, {required DateTime deadline}) {
    final body = {'results': [for (final r in results) r.toJson()]};
    final path = '/v1/turns/$turnId/tool-results';
    return _leg((cancel) async {
      try {
        return await _open(path, body, cancel);
      } on ZiApiException catch (e) {
        final retryAt = DateTime.now().add(retryDelay);
        if (e.status != null || e.code != 'network_error' || !retryAt.isBefore(deadline) || cancel.isCancelled) {
          rethrow;
        }
        await Future<void>.delayed(retryDelay);
        return _open(path, body, cancel);
      }
    });
  }

  /// Opens a stream with the current token; on a token error, once more with
  /// a fresh one.
  Future<ResponseBody> _open(String path, Object body, CancelToken cancel) async {
    final tokens = _tokens();
    final token = await tokens.token();
    try {
      return await _api.postStream(path, body, userToken: token, cancelToken: cancel);
    } on ZiApiException catch (e) {
      if (e.code != 'user_token_expired' && e.code != 'user_token_required') rethrow;
      final fresh = await tokens.refresh();
      if (fresh == null) rethrow;
      return _api.postStream(path, body, userToken: fresh, cancelToken: cancel);
    }
  }

  Stream<TurnEvent> _leg(Future<ResponseBody> Function(CancelToken cancel) open) {
    late final StreamController<TurnEvent> out;
    final cancel = CancelToken();
    StreamSubscription<SseFrame>? frames;
    Timer? watchdog;
    var finished = false;

    // Closes the connection without waiting: a subscription to a stream the
    // server keeps open may never finish cancelling.
    void hangUp() {
      watchdog?.cancel();
      frames?.cancel().ignore();
      if (!cancel.isCancelled) cancel.cancel('turn leg ended');
    }

    void finish([TurnEvent? last]) {
      if (finished) return;
      finished = true;
      hangUp();
      if (last != null) out.add(last);
      unawaited(out.close());
    }

    TurnFailed failed(String code, String message) =>
        TurnFailed(ZiApiException(code, message: message, retryable: true));

    void arm() {
      watchdog?.cancel();
      watchdog = Timer(pingTimeout, () => finish(failed('stream_interrupted', 'No event for $pingTimeout.')));
    }

    Future<void> run() async {
      // Armed before connecting too: a server that never answers is a dropped stream.
      arm();
      final ResponseBody body;
      try {
        body = await open(cancel);
      } on ZiApiException catch (e) {
        finish(TurnFailed(e));
        return;
      } on Object catch (e) {
        // The app's token callback or a file write failed: never leave the turn hanging.
        finish(failed('network_error', '$e'));
        return;
      }
      if (finished) return;
      arm();
      frames = parseSse(body.stream).listen(
        (frame) {
          arm();
          final TurnEvent? event;
          try {
            event = TurnEvent.fromFrame(frame);
          } on FormatException catch (e) {
            finish(failed('invalid_response', e.message));
            return;
          }
          if (event == null || event is PingEvent) return;
          if (event is TurnPaused || event is TurnDone || event is TurnFailed) {
            finish(event);
          } else {
            out.add(event);
          }
        },
        onError: (Object e) => finish(failed('stream_interrupted', '$e')),
        onDone: () => finish(failed('stream_interrupted', 'The stream closed early.')),
      );
    }

    out = StreamController<TurnEvent>(
      onListen: () => unawaited(run()),
      onCancel: () {
        finished = true;
        hangUp();
      },
    );
    return out.stream;
  }
}
