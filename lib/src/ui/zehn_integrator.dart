import 'dart:async';

import 'package:flutter/material.dart';

import '../server/runtime.dart';
import '../server/ui/launcher_button.dart';
import '../server/ui/strings.dart';
import 'widgets/agent_button.dart';
import 'zehn_intelligence.dart';

/// Exception thrown when Zehn Intelligence configuration is missing or invalid.
class ZiConfigException implements Exception {
  const ZiConfigException(this.message);
  final String message;

  @override
  String toString() => 'ZiConfigException: $message';
}

/// An error returned from a tool call.
class ZiToolError implements Exception {
  const ZiToolError(this.code, this.message);
  final String code;
  final String message;

  @override
  String toString() => 'ZiToolError($code): $message';
}

/// Controller passed to registered UI components.
class ZiComponentController {
  const ZiComponentController({this.onCompleted});
  final VoidCallback? onCompleted;

  void markCompleted() => onCompleted?.call();
}

/// The assistant button widget placed in the app scaffold.
class ZehnAiButton extends StatelessWidget {
  const ZehnAiButton({
    super.key,
    this.label,
    this.icon,
    this.title,
    this.mini = false,
  });

  final String? label;
  final Widget? icon;
  final String? title;
  final bool mini;

  @override
  Widget build(BuildContext context) {
    final runtime = ZiRuntime.instance;
    if (runtime != null) {
      // Hidden while the console has nothing published for the app.
      return ValueListenableBuilder<bool>(
        valueListenable: runtime.available,
        builder: (context, available, _) => available
            // The zehn/intelligence launcher: a living soap bubble.
            ? ZiLauncherButton(
                size: mini ? 48 : 64,
                icon: icon,
                label: label ?? ZiStrings.of(runtime.language).ask,
                onTap: () => unawaited(runtime.openChat(context, title: title)),
              )
            : const SizedBox.shrink(),
      );
    }
    if (!ZehnIntelligence.isInitialized) {
      return const SizedBox.shrink();
    }
    return AgentButton(label: label, icon: icon, title: title, mini: mini);
  }
}
