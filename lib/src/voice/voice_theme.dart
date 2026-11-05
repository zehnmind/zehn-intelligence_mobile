import 'package:flutter/material.dart';
import '../ui/theme/agent_theme.dart';

/// How the voice controls look, beyond the colours and type they take from
/// the chat's `AgentTheme`.
class AgentVoiceTheme extends ThemeExtension<AgentVoiceTheme> {
  const AgentVoiceTheme({
    this.barColor,
    this.barPressedColor,
    this.disabledLabelColor,
    this.keyboardIcon,
    this.micIcon,
  });

  /// The hold-to-speak bar at rest. Defaults to the secondary button colour.
  final Color? barColor;

  /// The bar while a finger is on it. Defaults to the border colour.
  final Color? barPressedColor;

  /// The bar's label while it cannot be used.
  final Color? disabledLabelColor;

  /// The button that switches to typing.
  final Widget? keyboardIcon;

  /// The button that switches back to speaking.
  final Widget? micIcon;

  static AgentVoiceTheme of(BuildContext context) =>
      Theme.of(context).extension<AgentVoiceTheme>() ?? const AgentVoiceTheme();

  Color bar(AgentTheme chat) => barColor ?? chat.secondaryButton;

  Color barPressed(AgentTheme chat) => barPressedColor ?? chat.border;

  Color disabledLabel(AgentTheme chat) =>
      disabledLabelColor ?? chat.textSecondary.withValues(alpha: 0.6);

  Widget keyboard(AgentTheme chat) =>
      keyboardIcon ?? Icon(Icons.keyboard_outlined, color: chat.textPrimary);

  Widget mic(AgentTheme chat) =>
      micIcon ?? Icon(Icons.mic_none_rounded, color: chat.textPrimary);

  @override
  AgentVoiceTheme copyWith({
    Color? barColor,
    Color? barPressedColor,
    Color? disabledLabelColor,
    Widget? keyboardIcon,
    Widget? micIcon,
  }) => AgentVoiceTheme(
    barColor: barColor ?? this.barColor,
    barPressedColor: barPressedColor ?? this.barPressedColor,
    disabledLabelColor: disabledLabelColor ?? this.disabledLabelColor,
    keyboardIcon: keyboardIcon ?? this.keyboardIcon,
    micIcon: micIcon ?? this.micIcon,
  );

  @override
  AgentVoiceTheme lerp(covariant AgentVoiceTheme? other, double t) =>
      t < 0.5 ? this : (other ?? this);
}
