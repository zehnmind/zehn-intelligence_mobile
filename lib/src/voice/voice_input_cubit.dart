import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'voice_recorder.dart';

part 'voice_input_state.dart';

/// Turns a recording into text — `ZehnSpeechClient.transcribe` in the app.
typedef AgentTranscribe =
    Future<String?> Function(String wavPath, {String? language});

/// Hold to speak: records while the finger is down and, on letting go, turns
/// the recording into text for the chat.
///
/// The chat reports the gesture — [hold], [drag], [release], [cancel] — and
/// acts on [AgentVoiceInputState.outcome]. Everything in between lives here,
/// where it can be tested without a microphone or a finger.
///
/// There are no timers. The elapsed time and the length cap advance on the
/// recorder's level ticks, which arrive every 80 ms while it records.
class AgentVoiceInputCubit extends Cubit<AgentVoiceInputState> {
  AgentVoiceInputCubit({
    required AgentTranscribe? transcribe,
    required String Function() language,
    AgentVoiceRecorder Function()? recorderFactory,
    DateTime Function()? now,
  }) : _transcribe = transcribe,
       _language = language,
       _recorderFactory = recorderFactory ?? AgentVoiceRecorder.new,
       _now = now ?? DateTime.now,
       super(const AgentVoiceInputState());

  /// Shorter than this is a tap, not a question.
  static const Duration minDuration = Duration(milliseconds: 600);

  /// A question longer than this is sent as it stands.
  static const Duration maxDuration = Duration(seconds: 60);

  /// How far up the finger moves before letting go cancels.
  static const double cancelDistance = 72;

  /// A recording that never gets louder than this is not sent to be
  /// transcribed: about -38 dBFS on the recorder's meter. Room noise measured
  /// through the simulator sat at -42 to -50 dBFS — and Whisper still "heard"
  /// whole sentences in it, which then went to the chat as questions. Speech
  /// into a phone is -30 to -15.
  static const double speechLevel = 0.44;

  /// Null when no speech provider is configured.
  final AgentTranscribe? _transcribe;
  final String Function() _language;
  final AgentVoiceRecorder Function() _recorderFactory;
  final DateTime Function() _now;

  /// Created on the first hold, disposed with the cubit.
  AgentVoiceRecorder? _recorder;
  StreamSubscription<double>? _levels;
  DateTime? _startedAt;

  /// The loudest level in this recording, and how many readings it had.
  double _loudest = 0;
  int _readings = 0;

  /// How the hold ends when the finger comes up while the microphone is
  /// still starting — typically because the permission prompt took the touch.
  AgentVoiceOutcome? _endedWhileStarting;

  /// The recorder's last stop or cancel. A new recording waits for it.
  Future<void>? _settling;

  bool get isAvailable => _transcribe != null;

  Future<void> hold() async {
    if (isClosed || state.phase != AgentVoicePhase.idle) return;
    final attempt = state.attempt + 1;

    if (_transcribe == null) {
      emit(
        AgentVoiceInputState(
          attempt: attempt,
          outcome: AgentVoiceOutcome.unavailable,
        ),
      );
      return;
    }

    _endedWhileStarting = null;
    emit(
      AgentVoiceInputState(attempt: attempt, phase: AgentVoicePhase.starting),
    );

    await _settling;
    if (isClosed) return;
    final recorder = _recorder ??= _recorderFactory();
    final started = await recorder.start();

    if (isClosed) {
      if (started) await recorder.cancel();
      return;
    }
    if (!started) {
      _finish(AgentVoiceOutcome.micDenied);
      return;
    }

    final ended = _endedWhileStarting;
    if (ended != null) {
      _finish(ended);
      await (_settling = recorder.cancel());
      return;
    }

    _startedAt = _now();
    _loudest = 0;
    _readings = 0;
    _levels = recorder.levels().listen(_onLevel);
    emit(state.copyWith(phase: AgentVoicePhase.recording));
  }

  /// [dy] is how far the finger has moved since it landed; negative is up.
  void drag(double dy) {
    if (isClosed || !state.isCapturing) return;
    final willCancel = dy <= -cancelDistance;
    if (willCancel != state.willCancel) {
      emit(state.copyWith(willCancel: willCancel));
    }
  }

  Future<void> release() async {
    if (isClosed) return;
    switch (state.phase) {
      case AgentVoicePhase.starting:
        _endedWhileStarting ??= state.willCancel
            ? AgentVoiceOutcome.cancelled
            : AgentVoiceOutcome.tooShort;
        return;
      case AgentVoicePhase.recording:
        break;
      case AgentVoicePhase.idle:
      case AgentVoicePhase.transcribing:
        return;
    }

    final recorder = _recorder!;
    final heldFor = _now().difference(_startedAt!);
    _stopLevels();

    final outcome = state.willCancel
        ? AgentVoiceOutcome.cancelled
        : heldFor < minDuration
        ? AgentVoiceOutcome.tooShort
        // Judged only when there were readings to judge by.
        : _readings > 0 && _loudest < speechLevel
        ? AgentVoiceOutcome.notHeard
        : null;
    if (outcome != null) {
      _finish(outcome);
      await (_settling = recorder.cancel());
      return;
    }

    emit(state.copyWith(phase: AgentVoicePhase.transcribing, level: 0));
    final stopping = recorder.stop();
    _settling = stopping;
    final path = await stopping;

    final text = path == null
        ? null
        : await _transcribe!(path, language: _language());
    await AgentVoiceRecorder.discard(path);

    if (text == null) {
      _finish(AgentVoiceOutcome.notHeard);
    } else {
      _finish(AgentVoiceOutcome.sent, transcript: text);
    }
  }

  /// The system took the touch away — a call, the permission prompt. Nothing
  /// is sent.
  Future<void> cancel() async {
    if (isClosed) return;
    switch (state.phase) {
      case AgentVoicePhase.starting:
        // Most often the permission prompt: once it is answered, the hint to
        // hold the button is the useful thing to show.
        _endedWhileStarting ??= AgentVoiceOutcome.tooShort;
      case AgentVoicePhase.recording:
        _stopLevels();
        _finish(AgentVoiceOutcome.cancelled);
        await (_settling = _recorder!.cancel());
      case AgentVoicePhase.idle:
      case AgentVoicePhase.transcribing:
        break;
    }
  }

  void _onLevel(double level) {
    final startedAt = _startedAt;
    if (isClosed ||
        startedAt == null ||
        state.phase != AgentVoicePhase.recording) {
      return;
    }

    final elapsed = _now().difference(startedAt);
    _readings++;
    if (level > _loudest) _loudest = level;
    emit(state.copyWith(level: level, elapsed: elapsed));
    if (elapsed >= maxDuration) unawaited(release());
  }

  void _stopLevels() {
    unawaited(_levels?.cancel());
    _levels = null;
    _startedAt = null;
  }

  void _finish(AgentVoiceOutcome outcome, {String? transcript}) {
    if (isClosed) return;
    emit(
      AgentVoiceInputState(
        attempt: state.attempt,
        outcome: outcome,
        transcript: transcript,
      ),
    );
  }

  @override
  Future<void> close() async {
    _stopLevels();
    final recorder = _recorder;
    _recorder = null;
    if (recorder != null) {
      await recorder.cancel();
      await recorder.dispose();
    }
    return super.close();
  }
}
