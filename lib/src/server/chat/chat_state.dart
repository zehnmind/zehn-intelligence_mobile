import 'package:equatable/equatable.dart';

import '../bootstrap/bootstrap.dart';

/// One thing shown in the chat.
sealed class ZiChatItem extends Equatable {
  const ZiChatItem();
}

final class ZiUserItem extends ZiChatItem {
  const ZiUserItem(this.text, {this.spoken = false});

  /// Empty for a spoken question until the transcript arrives.
  final String text;
  final bool spoken;

  @override
  List<Object?> get props => [text, spoken];
}

/// Assistant prose; may contain Markdown.
final class ZiAssistantItem extends ZiChatItem {
  const ZiAssistantItem(this.id, this.text);

  final String id;
  final String text;

  @override
  List<Object?> get props => [id, text];
}

final class ZiComponentItem extends ZiChatItem {
  const ZiComponentItem(this.callId, this.component, this.kind, this.data);

  final String callId;
  final String component;
  final ZiComponentKind kind;

  /// What the component draws: `mount_component.props`. (Named `data`
  /// because Equatable owns `props`.)
  final Map<String, Object?> data;

  @override
  List<Object?> get props => [callId, component, kind, data];
}

final class ZiErrorItem extends ZiChatItem {
  const ZiErrorItem(this.code, {this.retryable = false});

  final String code;
  final bool retryable;

  @override
  List<Object?> get props => [code, retryable];
}

class ZiChatState extends Equatable {
  const ZiChatState({this.items = const [], this.busy = false, this.suggestions = const [], this.conversationId});

  final List<ZiChatItem> items;

  /// A turn is running.
  final bool busy;

  /// Chips: starter questions for an empty chat, follow-ups after an answer.
  final List<String> suggestions;
  final String? conversationId;

  ZiChatState copyWith({
    List<ZiChatItem>? items,
    bool? busy,
    List<String>? suggestions,
    String? conversationId,
    bool clearConversation = false,
  }) => ZiChatState(
    items: items ?? this.items,
    busy: busy ?? this.busy,
    suggestions: suggestions ?? this.suggestions,
    conversationId: clearConversation ? null : conversationId ?? this.conversationId,
  );

  @override
  List<Object?> get props => [items, busy, suggestions, conversationId];
}
