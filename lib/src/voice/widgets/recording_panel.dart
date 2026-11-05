import 'package:flutter/material.dart';
import '../../ui/scope/agent_scope.dart';

import '../voice_strings.dart';
import 'voice_waveform.dart';

/// Shown while the user holds to speak, over the bottom of the chat: "Release
/// to send, swipe up to cancel", a waveform that follows the voice, and a
/// timer.
///
/// Turns red once the finger has moved far enough up that letting go cancels.
class RecordingPanel extends StatelessWidget {
  const RecordingPanel({
    super.key,
    required this.level,
    required this.elapsed,
    required this.willCancel,
    this.strings,
  });

  /// Microphone loudness, 0..1.
  final double level;
  final Duration elapsed;
  final bool willCancel;

  /// Defaults to the built-in strings for the app's language.
  final AgentVoiceStrings? strings;

  @override
  Widget build(BuildContext context) {
    final words =
        strings ??
        AgentVoiceStrings.forLanguage(
          Localizations.maybeLocaleOf(context)?.languageCode ?? 'en',
        );
    final theme = AgentScope.themeOf(context);
    final tone = willCancel ? theme.danger : theme.accent;

    // Clamped like the chat's other cards: at 2x the hint alone would fill
    // the screen, and the panel sits over the conversation.
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.5,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(0, 20, 0, 16),
        decoration: BoxDecoration(
          color: theme.surface,
          borderRadius: BorderRadius.circular(theme.sheetRadius),
          border: Border.all(
            color: willCancel ? theme.dangerBorder : theme.border,
          ),
          boxShadow: [
            BoxShadow(
              color: tone.withValues(alpha: 0.22),
              blurRadius: 32,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                willCancel ? words.releaseToCancel : words.releaseToSend,
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: willCancel
                    ? theme.smallStrong.copyWith(color: theme.danger)
                    : theme.small.copyWith(color: theme.textSecondary),
              ),
            ),
            const SizedBox(height: 12),
            VoiceWaveform(level: level, color: tone),
            const SizedBox(height: 8),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: theme.danger,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _clock(elapsed),
                  style: theme.captionStrong.copyWith(
                    color: theme.textSecondary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// `0:07` — minutes and seconds.
  static String _clock(Duration elapsed) {
    final seconds = (elapsed.inSeconds % 60).toString().padLeft(2, '0');
    return '${elapsed.inMinutes}:$seconds';
  }
}
