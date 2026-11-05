import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../chat/agent_chat_bloc.dart';
import '../scope/agent_scope.dart';

/// A text field and a send button. [leading] and [trailing] take extra
/// controls — the voice package's microphone button, say.
class AgentComposer extends StatefulWidget {
  const AgentComposer({super.key, this.leading, this.trailing});

  final Widget? leading;
  final Widget? trailing;

  @override
  State<AgentComposer> createState() => _AgentComposerState();
}

class _AgentComposerState extends State<AgentComposer> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _send(BuildContext context) {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    AgentScope.of(context).speech?.stop();
    context.read<AgentChatBloc>().add(AgentMessageSent(text));
    _controller.clear();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = AgentScope.themeOf(context);
    final strings = AgentScope.stringsOf(context);
    final busy = context.select<AgentChatBloc, bool>((b) => b.state.isBusy);
    final canSend = !busy && _controller.text.trim().isNotEmpty;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
      decoration: BoxDecoration(
        color: theme.surface,
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: theme.border),
      ),
      child: Row(
        children: [
          if (widget.leading != null) widget.leading!,
          Expanded(
            child: TextField(
              controller: _controller,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.send,
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _send(context),
              style: theme.body.copyWith(color: theme.textPrimary),
              decoration: InputDecoration(
                hintText: strings.typeMessage,
                hintStyle: theme.body.copyWith(color: theme.textSecondary),
                border: InputBorder.none,
                filled: false,
                isDense: true,
              ),
            ),
          ),
          if (widget.trailing != null) widget.trailing!,
          IconButton.filled(
            tooltip: strings.send,
            onPressed: canSend ? () => _send(context) : null,
            style: IconButton.styleFrom(
              backgroundColor: theme.accent,
              foregroundColor: theme.onAccent,
            ),
            icon: const Icon(Icons.arrow_upward_rounded),
          ),
        ],
      ),
    );
  }
}
