import 'package:flutter/widgets.dart';

import '../scope/agent_scope.dart';

enum AgentTextTone { neutral, success, warning }

/// Plain prose from the agent.
///
/// Renders as text and nothing else: no markdown, no auto-linking, no remote
/// images.
class AgentTextBlock extends StatelessWidget {
  const AgentTextBlock({
    super.key,
    required this.text,
    this.tone = AgentTextTone.neutral,
  });

  final String text;
  final AgentTextTone tone;

  @override
  Widget build(BuildContext context) {
    final theme = AgentScope.themeOf(context);
    final (background, border) = switch (tone) {
      AgentTextTone.neutral => (theme.surface, theme.border),
      AgentTextTone.success => (theme.successBackground, theme.successBorder),
      AgentTextTone.warning => (theme.warningBackground, theme.warningBorder),
    };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(theme.radius),
        border: Border.all(color: border),
      ),
      child: Text(text, style: theme.body.copyWith(color: theme.textPrimary)),
    );
  }
}
