part of 'voice_input_cubit.dart';

enum AgentVoicePhase {
  /// Nothing is being recorded.
  idle,

  /// The finger is down and the microphone is starting — which, the first
  /// time, includes the permission prompt.
  starting,

  /// Recording while the finger stays down.
  recording,

  /// Let go; the recording is being turned into text.
  transcribing,
}

/// How the last hold ended.
enum AgentVoiceOutcome {
  none,

  /// Transcribed: [AgentVoiceInputState.transcript] goes to the chat.
  sent,

  /// Slid up before letting go, or the system took the touch away.
  cancelled,

  /// Let go too soon to be a question — usually a tap.
  tooShort,

  /// Too quiet to be speech, or nothing came back from the recogniser.
  notHeard,

  micDenied,

  /// No speech provider is configured.
  unavailable,
}

final class AgentVoiceInputState extends Equatable {
  const AgentVoiceInputState({
    this.phase = AgentVoicePhase.idle,
    this.level = 0,
    this.elapsed = Duration.zero,
    this.willCancel = false,
    this.outcome = AgentVoiceOutcome.none,
    this.transcript,
    this.attempt = 0,
  });

  final AgentVoicePhase phase;

  /// Microphone loudness, 0..1.
  final double level;

  /// How long this recording has run.
  final Duration elapsed;

  /// The finger has moved far enough up that letting go cancels.
  final bool willCancel;

  final AgentVoiceOutcome outcome;

  /// What was said, when [outcome] is [AgentVoiceOutcome.sent].
  final String? transcript;

  /// Counts holds, so the same outcome twice in a row is still two events.
  final int attempt;

  /// The finger is down and the recording panel is showing.
  bool get isCapturing =>
      phase == AgentVoicePhase.starting || phase == AgentVoicePhase.recording;

  AgentVoiceInputState copyWith({
    AgentVoicePhase? phase,
    double? level,
    Duration? elapsed,
    bool? willCancel,
  }) => AgentVoiceInputState(
    phase: phase ?? this.phase,
    level: level ?? this.level,
    elapsed: elapsed ?? this.elapsed,
    willCancel: willCancel ?? this.willCancel,
    outcome: outcome,
    transcript: transcript,
    attempt: attempt,
  );

  @override
  List<Object?> get props => [
    phase,
    level,
    elapsed,
    willCancel,
    outcome,
    transcript,
    attempt,
  ];
}
