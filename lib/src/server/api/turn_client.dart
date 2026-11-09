import 'dart:async';

import 'package:dio/dio.dart';

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

  const TurnInput._(this.conversationId, this.input, this.language, this.utcOffsetMinutes, this.voiceReply);

  /// Null starts a new chat.
  final String? conversationId;
  final Map<String, Object?> input;
  final String language;
  final int? utcOffsetMinutes;
  final bool voiceReply;

  bool get isAudio => input['type'] == 'audio';

  TurnInput withConversation(String? id) => TurnInput._(id, input, language, utcOffsetMinutes, voiceReply);

  Map<String, Object?> toJson() => {
    'conversation_id': conversationId,
    'input': input,
    'language': language,
    'utc_offset_minutes': ?utcOffsetMinutes,
    'voice_reply': voiceReply,
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
    this.pingTimeout = const Duration(seconds: 45),
    this.retryDelay = const Duration(seconds: 1),
  }) : _api = api,
       _tokens = tokens;

  final ZiApiClient _api;
  final ZiTokenSource Function() _tokens;
  final Duration pingTimeout;
  final Duration retryDelay;

  Stream<TurnEvent> start(TurnInput input) => _leg((cancel) => _open('/v1/turns', input.toJson(), cancel));

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
      return _api.postStream(path, body, userToken: await tokens.refresh(), cancelToken: cancel);
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
      final ResponseBody body;
      try {
        body = await open(cancel);
      } on ZiApiException catch (e) {
        finish(TurnFailed(e));
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
