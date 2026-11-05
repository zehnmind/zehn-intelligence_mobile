part of 'agent_chat_bloc.dart';

class AgentChatState extends Equatable {
  const AgentChatState({this.messages = const []});

  final List<AgentMessage> messages;

  bool get isEmpty => messages.isEmpty;

  /// True while a turn is planning or executing. Derived rather than stored so
  /// it cannot fall out of step with the messages.
  bool get isBusy =>
      messages.any((m) => m.status == AgentMessageStatus.thinking);

  AgentChatState copyWith({List<AgentMessage>? messages}) =>
      AgentChatState(messages: messages ?? this.messages);

  @override
  List<Object?> get props => [messages];
}
