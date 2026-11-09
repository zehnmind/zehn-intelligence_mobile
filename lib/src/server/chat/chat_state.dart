import 'package:equatable/equatable.dart';

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

enum ZiComponentKind { inline, sheet, route }

final class ZiComponentItem extends ZiChatItem {
  const ZiComponentItem(this.callId, this.component, this.kind, this.data, {this.surface, this.route});

  final String callId;
  final String component;
  final ZiComponentKind kind;

  /// What the component draws: `mount_component.props`. (Named `data`
  /// because Equatable owns `props`.)
  final Map<String, Object?> data;

  /// The card template from the event; null when the app draws it.
  final Map<String, Object?>? surface;

  /// The route template from the event, for [ZiComponentKind.route].
  final String? route;

  @override
  List<Object?> get props => [callId, component, kind, data, surface, route];
}

enum ZiConfirmStatus { pending, confirmed, cancelled, expired }

/// A data-changing call (the `confirm` event) waiting for, or past, the
/// user's Confirm or Cancel.
final class ZiConfirmItem extends ZiChatItem {
  const ZiConfirmItem({
    required this.actionId,
    required this.tool,
    required this.method,
    this.surface,
    this.data = const {},
    this.label,
    this.status = ZiConfirmStatus.pending,
  });

  final String actionId;
  final String tool;
  final String method;

  /// The card's template; null shows the SDK's own question.
  final Map<String, Object?>? surface;

  /// What the template reads: `confirm.props`.
  final Map<String, Object?> data;

  /// The Confirm button's word; null uses the SDK's.
  final String? label;
  final ZiConfirmStatus status;

  ZiConfirmItem withStatus(ZiConfirmStatus next) =>
      ZiConfirmItem(actionId: actionId, tool: tool, method: method, surface: surface, data: data, label: label, status: next);

  @override
  List<Object?> get props => [actionId, tool, method, surface, data, label, status];
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
