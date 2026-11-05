import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/model/agent_message.dart';
import '../chat/agent_chat_bloc.dart';
import '../scope/agent_scope.dart';

/// Voice in, voice out: when the answer to a spoken question lands, reads it
/// aloud once. Typed questions get silent answers.
///
/// Wrap the chat in it; without a speech output in the scope it does
/// nothing.
class AgentVoiceReplies extends StatefulWidget {
  const AgentVoiceReplies({super.key, required this.child});

  final Widget child;

  @override
  State<AgentVoiceReplies> createState() => _AgentVoiceRepliesState();
}

class _AgentVoiceRepliesState extends State<AgentVoiceReplies> {
  /// Replies already spoken, so a rebuild never reads one twice.
  final Set<String> _spoken = {};

  void _speakNewReplies(BuildContext context, AgentChatState state) {
    final scope = AgentScope.of(context);
    final speech = scope.speech;
    if (speech == null || !speech.isAvailable || state.messages.isEmpty) {
      return;
    }
    final last = state.messages.last;
    if (last.isUser ||
        !last.viaVoice ||
        last.status != AgentMessageStatus.complete ||
        !_spoken.add(last.id)) {
      return;
    }
    speech.speak(
      last.id,
      last.speechText,
      last.language ?? scope.agent.session.languageCode,
    );
  }

  @override
  Widget build(BuildContext context) =>
      BlocListener<AgentChatBloc, AgentChatState>(
        listener: _speakNewReplies,
        child: widget.child,
      );
}
