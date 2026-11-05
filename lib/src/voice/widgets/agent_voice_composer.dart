import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../ui/chat/agent_chat_bloc.dart';
import '../../ui/scope/agent_scope.dart';
import '../../ui/widgets/agent_composer.dart';

import '../voice_input_cubit.dart';
import '../voice_strings.dart';
import '../voice_theme.dart';
import '../zehn_voice.dart';
import 'hold_to_speak_bar.dart';
import 'recording_panel.dart';

/// A ready input for `AgentChatView(composer: ...)`: hold to speak, with a
/// keyboard button that swaps in a text field and a microphone button that
/// swaps it back.
///
/// * **Hold:** recording starts the moment the finger lands; a panel shows
///   the waveform and a timer above the bar.
/// * **Let go:** the recording is transcribed and sent as the user's
///   message, marked as spoken so the reply is read aloud.
/// * **Slide up:** the panel turns red; letting go sends nothing.
/// * **A tap, silence, no permission, no key:** a short notice says why.
class AgentVoiceComposer extends StatefulWidget {
  const AgentVoiceComposer({super.key, required this.voice, this.strings});

  final ZehnVoice voice;

  /// Defaults to the built-in strings for the app's language.
  final AgentVoiceStrings? strings;

  @override
  State<AgentVoiceComposer> createState() => _AgentVoiceComposerState();
}

class _AgentVoiceComposerState extends State<AgentVoiceComposer> {
  late final AgentVoiceInputCubit _voice = AgentVoiceInputCubit(
    transcribe: widget.voice.transcribe,
    language: () => AgentScope.of(context).agent.session.languageCode,
  );

  /// The bar shows the text field rather than "hold to speak".
  bool _typing = false;

  @override
  void dispose() {
    _voice.close();
    super.dispose();
  }

  AgentVoiceStrings _strings(BuildContext context) =>
      widget.strings ??
      AgentVoiceStrings.forLanguage(
        Localizations.maybeLocaleOf(context)?.languageCode ?? 'en',
      );

  void _onOutcome(BuildContext context, AgentVoiceInputState state) {
    final scope = AgentScope.of(context);
    final words = _strings(context);
    switch (state.outcome) {
      case AgentVoiceOutcome.sent:
        scope.speech?.stop();
        context.read<AgentChatBloc>().add(
          AgentMessageSent(state.transcript ?? '', viaVoice: true),
        );
      case AgentVoiceOutcome.tooShort:
        scope.notice(context, words.holdToSpeak);
      case AgentVoiceOutcome.notHeard:
        scope.notice(context, words.didNotHear);
      case AgentVoiceOutcome.micDenied:
        scope.notice(context, words.micDenied);
      case AgentVoiceOutcome.unavailable:
        scope.notice(context, words.voiceUnavailable);
      case AgentVoiceOutcome.cancelled:
      case AgentVoiceOutcome.none:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final words = _strings(context);
    final theme = AgentScope.themeOf(context);
    final busy = context.select<AgentChatBloc, bool>((b) => b.state.isBusy);

    if (_typing) {
      return AgentComposer(
        leading: IconButton(
          tooltip: words.holdToSpeak,
          onPressed: () => setState(() => _typing = false),
          icon: AgentVoiceTheme.of(context).mic(theme),
        ),
      );
    }

    return MultiBlocListener(
      listeners: [
        BlocListener<AgentVoiceInputCubit, AgentVoiceInputState>(
          bloc: _voice,
          listenWhen: (previous, next) =>
              previous.attempt != next.attempt ||
              previous.outcome != next.outcome,
          listener: _onOutcome,
        ),
        // The phone confirms what the finger cannot see: recording has
        // begun, and letting go now would cancel.
        BlocListener<AgentVoiceInputCubit, AgentVoiceInputState>(
          bloc: _voice,
          listenWhen: (previous, next) =>
              previous.phase != AgentVoicePhase.recording &&
              next.phase == AgentVoicePhase.recording,
          listener: (_, _) => HapticFeedback.mediumImpact(),
        ),
        BlocListener<AgentVoiceInputCubit, AgentVoiceInputState>(
          bloc: _voice,
          listenWhen: (previous, next) =>
              previous.willCancel != next.willCancel && next.isCapturing,
          listener: (_, _) => HapticFeedback.selectionClick(),
        ),
      ],
      child: BlocBuilder<AgentVoiceInputCubit, AgentVoiceInputState>(
        bloc: _voice,
        builder: (context, voice) => Stack(
          clipBehavior: Clip.none,
          children: [
            HoldToSpeakBar(
              strings: words,
              enabled: voice.phase == AgentVoicePhase.idle && !busy,
              pressed: voice.isCapturing,
              transcribing: voice.phase == AgentVoicePhase.transcribing,
              onKeyboard: () => setState(() => _typing = true),
              onHoldStart: () {
                AgentScope.of(context).speech?.stop();
                _voice.hold();
              },
              onHoldMove: _voice.drag,
              onHoldEnd: _voice.release,
              onHoldCancel: _voice.cancel,
            ),
            if (voice.isCapturing)
              Positioned(
                left: 0,
                right: 0,
                bottom: HoldToSpeakBar.height + 12,
                child: IgnorePointer(
                  child: RecordingPanel(
                    strings: words,
                    level: voice.level,
                    elapsed: voice.elapsed,
                    willCancel: voice.willCancel,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
