import 'package:flutter/material.dart';

import '../scope/agent_scope.dart';
import 'agent_chat_view.dart';

/// Opens the assistant: a floating button with a sparkle and "Ask" in the
/// app's language. Put it in any screen's `Scaffold`:
///
/// ```dart
/// Scaffold(floatingActionButton: const AgentButton(), …)
/// ```
///
/// Works with an `AgentScope` above the app or with just
/// `ZehnIntelligence.start(…)`. Hold-to-speak and spoken replies come
/// from the intelligence.
class AgentButton extends StatelessWidget {
  const AgentButton({
    super.key,
    this.label,
    this.icon,
    this.title,
    this.mini = false,
  });

  /// Defaults to "Ask" in the app's language.
  final String? label;

  /// Defaults to a sparkle.
  final Widget? icon;

  /// The chat's title. Defaults to "Assistant" in the app's language.
  final String? title;

  /// An icon-only button.
  final bool mini;

  @override
  Widget build(BuildContext context) {
    final words = AgentScope.stringsOf(context);
    void open() => AgentChatSheet.show(context, title: title);
    final glyph = icon ?? const Icon(Icons.auto_awesome);
    if (mini) {
      return FloatingActionButton(
        onPressed: open,
        tooltip: label ?? words.ask,
        child: glyph,
      );
    }
    return FloatingActionButton.extended(
      onPressed: open,
      icon: glyph,
      label: Text(label ?? words.ask),
    );
  }
}
