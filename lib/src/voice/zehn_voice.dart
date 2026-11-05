import '../core/log.dart';
import '../core/transport/zehn.dart';

import 'voice_input_cubit.dart';
import 'zehn_speaker.dart';
import 'zehn_speech_client.dart';

/// Zehn speech for an app, in one object: recognition for hold-to-speak and
/// synthesis for spoken replies. Zehn is the provider because it serves
/// Uzbek in both directions, which the phones' own engines do not.
///
/// Without a key, voice is off rather than broken: holding to speak says
/// why, and replies stay silent.
class ZehnVoice {
  ZehnVoice({
    required String apiKey,
    String baseUrl = Zehn.baseUrl,
    String? sttModel,
    String? ttsModel,
    String? ttsVoice,
    AgentLog log = silentAgentLog,
  }) : this._(
         apiKey.trim().isEmpty && baseUrl == Zehn.baseUrl
             ? null
             : ZehnSpeechClient(
                 apiKey: apiKey,
                 baseUrl: baseUrl,
                 sttModel: sttModel,
                 ttsModel: ttsModel,
                 ttsVoice: ttsVoice,
                 log: log,
               ),
         log,
       );

  /// Voice switched off.
  ZehnVoice.off({AgentLog log = silentAgentLog}) : this._(null, log);

  /// Over a client built elsewhere — for tests and tools that answer its
  /// requests themselves, through `ZehnSpeechClient(httpClient: …)`.
  ZehnVoice.withClient(ZehnSpeechClient client, {AgentLog log = silentAgentLog})
    : this._(client, log);

  ZehnVoice._(this.client, AgentLog log)
    : speaker = ZehnSpeaker(client, log: log);

  /// Null when voice is off.
  final ZehnSpeechClient? client;

  /// Pass to `AgentScope(speech: ...)` for spoken replies.
  final ZehnSpeaker speaker;

  /// False without a key, or when the dashboard switched voice off.
  bool get isAvailable => client?.enabled ?? false;

  /// For [AgentVoiceInputCubit]: null when voice is off.
  AgentTranscribe? get transcribe => client?.transcribe;
}
