import 'component_spec.dart';
import 'confirmation.dart';

enum AgentMessageRole { user, assistant }

enum AgentMessageStatus {
  /// The turn is still being planned or executed.
  thinking,

  /// A write is waiting on the user's confirmation.
  awaitingConfirmation,

  complete,

  /// The user declined a write. Nothing ran.
  cancelled,

  failed,
}

/// One entry in the conversation.
///
/// Immutable; [copyWith] produces a new instance so the bloc never mutates
/// state in place.
class AgentMessage {
  const AgentMessage({
    required this.id,
    required this.role,
    required this.text,
    this.components = const [],
    this.status = AgentMessageStatus.complete,
    this.pendingConfirmation,
    this.language,
    this.viaVoice = false,
  });

  final String id;
  final AgentMessageRole role;

  /// Plain text for a user turn. For an assistant turn this is the spoken /
  /// accessible summary of whatever the components show.
  final String text;

  final List<ComponentSpec> components;
  final AgentMessageStatus status;
  final PendingConfirmation? pendingConfirmation;

  /// Language of an assistant reply, for the text-to-speech voice.
  final String? language;

  /// True when this turn began with the user speaking, so the reply should be
  /// spoken back. Voice in, voice out; typed in, silent out.
  final bool viaVoice;

  bool get isUser => role == AgentMessageRole.user;

  /// What text-to-speech reads aloud: the prose, not the cards.
  ///
  /// A card's content is already on screen, and reading every card after a
  /// sentence that said the same thing is noise. If there is no prose at all,
  /// the first card's summary stands in.
  String get speechText {
    final prose = [
      for (final c in components)
        if (c.type == kAgentTextComponent)
          c.stringProp('text') ?? c.fallbackText,
    ].where((t) => t.trim().isNotEmpty).join(' ');
    if (prose.isNotEmpty) return prose;
    for (final c in components) {
      if (c.fallbackText.trim().isNotEmpty) return c.fallbackText;
    }
    return text;
  }

  /// Persisted form. A pending confirmation is deliberately dropped: it is
  /// transient, and a write the user never confirmed must not come back to
  /// life days later in a restored transcript.
  Map<String, Object?> toJson() => {
    'id': id,
    'role': role.name,
    'text': text,
    'status': status == AgentMessageStatus.awaitingConfirmation
        ? AgentMessageStatus.cancelled.name
        : status.name,
    if (components.isNotEmpty)
      'components': [for (final c in components) c.toJson()],
    if (language != null) 'language': language,
    if (viaVoice) 'viaVoice': true,
  };

  static AgentMessage? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    if (id is! String || id.isEmpty) return null;

    final role = AgentMessageRole.values.firstWhere(
      (r) => r.name == json['role'],
      orElse: () => AgentMessageRole.assistant,
    );
    var status = AgentMessageStatus.values.firstWhere(
      (s) => s.name == json['status'],
      orElse: () => AgentMessageStatus.complete,
    );
    // A turn that was mid-flight when the app died is not still thinking.
    if (status == AgentMessageStatus.thinking ||
        status == AgentMessageStatus.awaitingConfirmation) {
      status = AgentMessageStatus.cancelled;
    }

    final components = <ComponentSpec>[];
    final raw = json['components'];
    if (raw is List) {
      for (final item in raw) {
        final spec = ComponentSpec.fromJson(item);
        if (spec != null) components.add(spec);
      }
    }

    return AgentMessage(
      id: id,
      role: role,
      text: json['text'] is String ? json['text'] as String : '',
      components: components,
      status: status,
      language: json['language'] is String ? json['language'] as String : null,
      viaVoice: json['viaVoice'] == true,
    );
  }

  AgentMessage copyWith({
    String? text,
    List<ComponentSpec>? components,
    AgentMessageStatus? status,
    PendingConfirmation? pendingConfirmation,
    bool clearPendingConfirmation = false,
    String? language,
  }) => AgentMessage(
    id: id,
    role: role,
    text: text ?? this.text,
    components: components ?? this.components,
    status: status ?? this.status,
    pendingConfirmation: clearPendingConfirmation
        ? null
        : pendingConfirmation ?? this.pendingConfirmation,
    language: language ?? this.language,
    viaVoice: viaVoice,
  );
}
