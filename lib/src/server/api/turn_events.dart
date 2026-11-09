import 'dart:convert';

import 'api_client.dart';
import 'sse.dart';

/// One event of a turn's stream (`MOBILE_INTEGRATION.md`, section 3).
sealed class TurnEvent {
  const TurnEvent({this.turnId = '', this.seq = -1});

  final String turnId;
  final int seq;

  /// Null for an event type this SDK does not know (ignore it). Throws
  /// [FormatException] for a known type with a broken body.
  static TurnEvent? fromFrame(SseFrame frame) {
    if (frame.isPing) return const PingEvent();
    const known = {
      'turn.started',
      'transcript',
      'text.delta',
      'client_api_request',
      'mount_component',
      'confirm',
      'audio',
      'suggestions',
      'turn.paused',
      'done',
      'error',
    };
    if (!known.contains(frame.event)) return null;
    final Object? decoded;
    try {
      decoded = jsonDecode(frame.data);
    } on FormatException {
      throw FormatException('${frame.event}: data is not JSON');
    }
    if (decoded is! Map) throw FormatException('${frame.event}: data is not an object');
    final d = _Body(frame.event, decoded.cast<String, Object?>());
    final turnId = d.optString('turn_id') ?? '';
    final seq = d.optInt('seq') ?? -1;
    return switch (frame.event) {
      'turn.started' => TurnStarted(
        conversationId: d.string('conversation_id'),
        conversationNew: d.optBool('conversation_new') ?? false,
        turnId: turnId,
        seq: seq,
      ),
      'transcript' => TranscriptEvent(
        text: d.string('text'),
        language: d.optString('language'),
        turnId: turnId,
        seq: seq,
      ),
      'text.delta' => TextDelta(text: d.string('text'), turnId: turnId, seq: seq),
      'client_api_request' => ClientApiRequest(
        callId: d.string('call_id'),
        tool: d.string('tool'),
        args: d.optMap('args') ?? const {},
        request: d.optMap('request'),
        actionId: d.optString('action_id') ?? _actionIn(d.optMap('request')),
        turnId: turnId,
        seq: seq,
      ),
      'mount_component' => MountComponent(
        callId: d.optString('call_id') ?? '',
        component: d.string('component'),
        kind: d.optString('kind') ?? 'inline',
        props: d.optMap('props') ?? const {},
        surface: d.optMap('surface'),
        route: d.optString('route'),
        turnId: turnId,
        seq: seq,
      ),
      'confirm' => ConfirmEvent(
        callId: d.optString('call_id') ?? '',
        actionId: d.string('action_id'),
        tool: d.optString('tool') ?? '',
        method: (d.optString('method') ?? 'POST').toUpperCase(),
        surface: d.optMap('surface'),
        props: d.optMap('props') ?? const {},
        confirmLabel: d.optString('confirm_label'),
        expiresIn: Duration(seconds: d.optInt('expires_in') ?? 600),
        turnId: turnId,
        seq: seq,
      ),
      'audio' => AudioClip(
        format: d.optString('format') ?? 'mp3',
        text: d.optString('text') ?? '',
        data: d.string('data'),
        turnId: turnId,
        seq: seq,
      ),
      'suggestions' => SuggestionsEvent(
        items: d.stringList('items'),
        turnId: turnId,
        seq: seq,
      ),
      'turn.paused' => TurnPaused(
        callIds: d.stringList('call_ids'),
        deadline: d.deadline(),
        maxResultBytes: d.optInt('max_result_bytes') ?? 32768,
        turnId: turnId,
        seq: seq,
      ),
      'done' => TurnDone(outcome: d.optString('outcome') ?? 'answered', turnId: turnId, seq: seq),
      _ => TurnFailed(d.error(), turnId: turnId, seq: seq),
    };
  }
}

final class TurnStarted extends TurnEvent {
  const TurnStarted({required this.conversationId, required this.conversationNew, super.turnId, super.seq});

  final String conversationId;
  final bool conversationNew;
}

/// What the server heard, for a spoken question.
final class TranscriptEvent extends TurnEvent {
  const TranscriptEvent({required this.text, this.language, super.turnId, super.seq});

  final String text;
  final String? language;
}

final class TextDelta extends TurnEvent {
  const TextDelta({required this.text, super.turnId, super.seq});

  final String text;
}

final class ClientApiRequest extends TurnEvent {
  const ClientApiRequest({
    required this.callId,
    required this.tool,
    required this.args,
    this.request,
    this.actionId,
    super.turnId,
    super.seq,
  });

  final String callId;
  final String tool;
  final Map<String, Object?> args;

  /// The customer API request the server built for this call (method, path,
  /// query, body, and optionally headers, auth, result, base_url); null for a
  /// tool the app handles itself. Checked by `ZiHttpCall.fromJson`.
  final Map<String, Object?>? request;

  /// For a write: the `confirm` card the user tapped Confirm on.
  final String? actionId;
}

final class MountComponent extends TurnEvent {
  const MountComponent({
    required this.callId,
    required this.component,
    required this.kind,
    required this.props,
    this.surface,
    this.route,
    super.turnId,
    super.seq,
  });

  final String callId;
  final String component;

  /// `inline`, `sheet` or `route`.
  final String kind;
  final Map<String, Object?> props;

  /// The card template to draw [props] with (`docs/DYNAMIC_CARDS.md`), for
  /// `inline` and `sheet`; null when the app registered its own widget.
  final Map<String, Object?>? surface;

  /// The app route to open, for `route`: final, filled and escaped by the
  /// server. Opened as it is.
  final String? route;
}

/// A data-changing call waiting for the user's tap: nothing reaches the
/// app's API until they confirm. The tap is a new turn
/// ([TurnInput.action]).
final class ConfirmEvent extends TurnEvent {
  const ConfirmEvent({
    required this.callId,
    required this.actionId,
    required this.tool,
    required this.method,
    this.surface,
    required this.props,
    this.confirmLabel,
    required this.expiresIn,
    super.turnId,
    super.seq,
  });

  final String callId;
  final String actionId;
  final String tool;

  /// `POST`, `PUT`, `PATCH` or `DELETE`.
  final String method;

  /// The card's template, drawn with [props].
  final Map<String, Object?>? surface;
  final Map<String, Object?> props;

  /// The Confirm button's word, in the user's language; null uses the SDK's.
  final String? confirmLabel;
  final Duration expiresIn;
}

final class AudioClip extends TurnEvent {
  const AudioClip({required this.format, required this.text, required this.data, super.turnId, super.seq});

  final String format;
  final String text;

  /// Base64.
  final String data;
}

final class SuggestionsEvent extends TurnEvent {
  const SuggestionsEvent({required this.items, super.turnId, super.seq});

  final List<String> items;
}

/// Ends a leg: post the results of [callIds] before [deadline].
final class TurnPaused extends TurnEvent {
  const TurnPaused({required this.callIds, required this.deadline, required this.maxResultBytes, super.turnId, super.seq});

  final List<String> callIds;
  final DateTime deadline;
  final int maxResultBytes;
}

final class TurnDone extends TurnEvent {
  const TurnDone({required this.outcome, super.turnId, super.seq});

  /// `answered`, `refused` or `limit`.
  final String outcome;
}

/// Ends the turn with an error: the server's `error` event, or one the SDK
/// names itself.
final class TurnFailed extends TurnEvent {
  const TurnFailed(this.error, {super.turnId, super.seq});

  final ZiApiException error;
}

final class PingEvent extends TurnEvent {
  const PingEvent();
}

String? _actionIn(Map<String, Object?>? request) {
  final id = request?['action_id'];
  return id is String && id.isNotEmpty ? id : null;
}

class _Body {
  _Body(this.event, this.map);

  final String event;
  final Map<String, Object?> map;

  Never _broken(String field) => throw FormatException('$event: "$field" is missing or has the wrong type');

  String string(String field) {
    final v = map[field];
    return v is String ? v : _broken(field);
  }

  String? optString(String field) => map[field] is String ? map[field] as String : null;

  int? optInt(String field) => map[field] is num ? (map[field] as num).toInt() : null;

  bool? optBool(String field) => map[field] is bool ? map[field] as bool : null;

  Map<String, Object?>? optMap(String field) {
    final v = map[field];
    if (v == null) return null;
    return v is Map ? v.cast<String, Object?>() : _broken(field);
  }

  List<String> stringList(String field) {
    final v = map[field];
    if (v is! List) _broken(field);
    return [for (final item in v) if (item is String) item];
  }

  DateTime deadline() {
    final raw = optString('deadline');
    final parsed = raw == null ? null : DateTime.tryParse(raw);
    if (parsed != null) return parsed;
    return DateTime.now().add(Duration(seconds: optInt('expires_in') ?? 60));
  }

  ZiApiException error() {
    final e = optMap('error') ?? _broken('error');
    final code = e['code'];
    final message = e['message'];
    final params = e['params'];
    return ZiApiException(
      code is String ? code : 'internal_error',
      message: message is String ? message : '',
      params: params is Map ? params.cast<String, Object?>() : const {},
      retryable: optBool('retryable') ?? false,
    );
  }
}
