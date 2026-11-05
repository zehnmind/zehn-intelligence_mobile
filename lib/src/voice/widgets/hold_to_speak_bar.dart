import 'package:flutter/material.dart';
import '../../ui/scope/agent_scope.dart';

import '../voice_strings.dart';
import '../voice_theme.dart';
import 'hold_to_speak_detector.dart';

/// The chat's input bar in voice mode: a pill that records while held, with
/// a keyboard button on the left for typing.
///
/// The keyboard button sits above the hold area in the stack, so tapping it
/// never starts a recording.
class HoldToSpeakBar extends StatelessWidget {
  const HoldToSpeakBar({
    super.key,
    required this.onKeyboard,
    required this.onHoldStart,
    required this.onHoldMove,
    required this.onHoldEnd,
    required this.onHoldCancel,
    this.enabled = true,
    this.pressed = false,
    this.transcribing = false,
    this.strings,
  });

  final VoidCallback onKeyboard;
  final VoidCallback onHoldStart;
  final ValueChanged<double> onHoldMove;
  final VoidCallback onHoldEnd;
  final VoidCallback onHoldCancel;

  /// False while the assistant is answering or the last recording is still
  /// being transcribed.
  final bool enabled;

  /// A finger is on the bar.
  final bool pressed;

  /// Let go; the recording is being turned into text.
  final bool transcribing;

  /// Defaults to the built-in strings for the app's language.
  final AgentVoiceStrings? strings;

  static const double height = 48;

  @override
  Widget build(BuildContext context) {
    final words =
        strings ??
        AgentVoiceStrings.forLanguage(
          Localizations.maybeLocaleOf(context)?.languageCode ?? 'en',
        );
    final theme = AgentScope.themeOf(context);
    final voice = AgentVoiceTheme.of(context);

    return SizedBox(
      height: height,
      child: Stack(
        children: [
          Positioned.fill(
            child: Semantics(
              button: true,
              enabled: enabled,
              label: words.holdToSpeak,
              excludeSemantics: true,
              child: HoldToSpeakDetector(
                enabled: enabled,
                onStart: onHoldStart,
                onMove: onHoldMove,
                onEnd: onHoldEnd,
                onCancel: onHoldCancel,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  decoration: BoxDecoration(
                    color: pressed ? voice.barPressed(theme) : voice.bar(theme),
                    borderRadius: BorderRadius.circular(100),
                  ),
                  // Clear of the keyboard button on the left, and the same on
                  // the right so the label stays centred on the whole bar.
                  padding: const EdgeInsets.symmetric(horizontal: height),
                  alignment: Alignment.center,
                  child: transcribing
                      ? _Transcribing(words.transcribing)
                      : Text(
                          words.holdToSpeak,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.bodyStrong.copyWith(
                            color: enabled
                                ? theme.textPrimary
                                : voice.disabledLabel(theme),
                          ),
                        ),
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: Semantics(
              button: true,
              label: words.typeMessage,
              child: GestureDetector(
                onTap: onKeyboard,
                behavior: HitTestBehavior.opaque,
                child: SizedBox(
                  width: height,
                  child: Center(child: voice.keyboard(theme)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Transcribing extends StatelessWidget {
  const _Transcribing(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = AgentScope.themeOf(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox.square(
          dimension: 16,
          child: CircularProgressIndicator(strokeWidth: 2, color: theme.accent),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.small.copyWith(color: theme.textSecondary),
          ),
        ),
      ],
    );
  }
}
