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

/// The name of a tool the catalog can hold: dotted lower case, one to four
/// segments (`map.route`), at most 48 characters, never starting with `ui`
/// or `zi`.
final RegExp ziToolName = RegExp(
  r'^(?!(ui|zi)(\.|$))[a-z][a-z0-9]*(_[a-z0-9]+)*(\.[a-z][a-z0-9]*(_[a-z0-9]+)*){0,3}$',
);

/// The name of a component the catalog can hold: one lower-case segment
/// (`map_route`), at most 40 characters.
final RegExp ziComponentName = RegExp(r'^[a-z][a-z0-9]*(_[a-z0-9]+)*$');

bool ziIsToolName(String name) => name.length <= 48 && ziToolName.hasMatch(name);

bool ziIsComponentName(String name) => name.length <= 40 && ziComponentName.hasMatch(name);

/// What a value of a [ZiArg] is.
enum ZiArgType { string, integer, number, boolean }

/// One argument of a tool the app registers, or one prop of a component:
/// what it is, and the words the model reads about it.
///
/// ```dart
/// args: {
///   'to': ZiArg.string('Where to go: a shop, the toilets, an exit', required: true),
///   'floor': ZiArg.integer('The floor', oneOf: [-1, 1, 2, 3]),
///   'accessible': ZiArg.boolean('True for a step-free route'),
/// }
/// ```
///
/// Write each one as a literal, in the call that registers the tool: the
/// console's code analysis reads the declaration from the source to draft
/// the tool in the app's catalog, and it reads only what is written there.
class ZiArg {
  const ZiArg.string(this.description, {this.required = false, List<String>? this.oneOf}) : type = ZiArgType.string;

  const ZiArg.integer(this.description, {this.required = false, List<int>? this.oneOf}) : type = ZiArgType.integer;

  const ZiArg.number(this.description, {this.required = false}) : type = ZiArgType.number, oneOf = null;

  const ZiArg.boolean(this.description, {this.required = false}) : type = ZiArgType.boolean, oneOf = null;

  final ZiArgType type;

  /// For the model: what to pass here.
  final String description;

  /// True when a call without it is refused.
  final bool required;

  /// The only values allowed; null allows any of its type.
  final List<Object>? oneOf;

  /// What is wrong with [value] as the argument [name], for the model to
  /// read; null when it is fine. A missing optional one is fine.
  String? problem(String name, Object? value) {
    if (value == null) return required ? 'The argument "$name" is required.' : null;
    final fits = switch (type) {
      ZiArgType.string => value is String,
      ZiArgType.integer => value is int,
      ZiArgType.number => value is num,
      ZiArgType.boolean => value is bool,
    };
    if (!fits) return 'The argument "$name" must be ${_article(type.name)} ${type.name}.';
    final allowed = oneOf;
    if (allowed != null && !allowed.contains(value)) {
      return 'The argument "$name" must be one of: ${allowed.join(', ')}.';
    }
    return null;
  }

  static String _article(String word) => word.startsWith('i') ? 'an' : 'a';
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
      runtime.readAppLanguage(context);
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
