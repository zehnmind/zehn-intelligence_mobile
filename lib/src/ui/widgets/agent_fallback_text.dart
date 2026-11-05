import 'package:flutter/widgets.dart';

import '../scope/agent_scope.dart';

/// What renders when a component type is unknown, its props fail validation,
/// or its entity is gone (a resumed conversation).
///
/// Every component carries a `fallbackText` precisely so this path is a
/// readable sentence rather than a hole. It is also what text-to-speech
/// reads aloud.
class AgentFallbackText extends StatelessWidget {
  const AgentFallbackText(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    if (text.trim().isEmpty) return const SizedBox.shrink();
    final theme = AgentScope.themeOf(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: theme.surfaceMuted,
        borderRadius: BorderRadius.circular(theme.radius),
      ),
      child: Text(
        text,
        style: theme.small.copyWith(color: theme.textSecondary),
      ),
    );
  }
}
