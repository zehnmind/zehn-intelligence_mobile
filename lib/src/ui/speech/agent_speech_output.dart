import 'package:flutter/foundation.dart';

/// Reads replies aloud. Implemented by `ZehnSpeaker`; the chat uses it
/// only when one is given.
abstract interface class AgentSpeechOutput {
  /// False when speech cannot work — no key, no provider.
  bool get isAvailable;

  /// The id of the message being read, or null.
  ValueListenable<String?> get speaking;

  Future<void> speak(String messageId, String text, String languageCode);

  Future<void> stop();
}
