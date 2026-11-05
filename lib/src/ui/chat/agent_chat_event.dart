part of 'agent_chat_bloc.dart';

sealed class AgentChatEvent extends Equatable {
  const AgentChatEvent();

  @override
  List<Object?> get props => [];
}

/// The user sent a turn.
final class AgentMessageSent extends AgentChatEvent {
  const AgentMessageSent(this.text, {this.viaVoice = false});

  final String text;

  /// The text came from speech, so the reply should be spoken back.
  final bool viaVoice;

  @override
  List<Object?> get props => [text, viaVoice];
}

/// The user tapped confirm on a pending write.
///
/// A write whose card asks for step-up runs only when [verified] is true —
/// the host checked the user again (a fingerprint, a PIN) before sending
/// this. `AgentMessageList` does that through `AgentScope.stepUp`; an app
/// with its own confirmation UI must do the same.
final class AgentConfirmationAccepted extends AgentChatEvent {
  const AgentConfirmationAccepted(this.messageId, {this.verified = false});

  final String messageId;

  /// The host verified the user again for this confirmation.
  final bool verified;

  @override
  List<Object?> get props => [messageId, verified];
}

/// The user backed out of a pending write.
final class AgentConfirmationDeclined extends AgentChatEvent {
  const AgentConfirmationDeclined(this.messageId);

  final String messageId;

  @override
  List<Object?> get props => [messageId];
}

/// A button on a card asked to run a read.
///
/// Goes through exactly the same gate as a tool the model proposed — a
/// button is not a way around it.
final class AgentInvokeRequested extends AgentChatEvent {
  const AgentInvokeRequested(this.tool, {this.args = const {}, this.echo});

  final String tool;
  final Map<String, Object?> args;

  /// What the user tapped, said back as their turn — "West entrance" — so the
  /// conversation reads as it happened. Null for a tap that is not an answer.
  final String? echo;

  @override
  List<Object?> get props => [tool, args, echo];
}

final class AgentConversationCleared extends AgentChatEvent {
  const AgentConversationCleared();
}

/// The app did something on a screen opened from the chat — reserved,
/// froze, paid — and records it in the conversation, with its card.
///
/// Written by the app, not the model: nothing is being planned.
final class AgentNotePosted extends AgentChatEvent {
  const AgentNotePosted(this.result);

  final ToolResult result;

  @override
  List<Object?> get props => [result.tool, result.summary];
}
