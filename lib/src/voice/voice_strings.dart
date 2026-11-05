/// The words of the voice controls, built-in in Uzbek, Russian and English.
class AgentVoiceStrings {
  const AgentVoiceStrings({
    required this.holdToSpeak,
    required this.typeMessage,
    required this.listening,
    required this.transcribing,
    required this.releaseToSend,
    required this.releaseToCancel,
    required this.didNotHear,
    required this.micDenied,
    required this.voiceUnavailable,
  });

  factory AgentVoiceStrings.forLanguage(String languageCode) =>
      switch (languageCode) {
        'uz' => uz,
        'ru' => ru,
        _ => en,
      };

  final String holdToSpeak;

  /// The keyboard button's label: switch to typing.
  final String typeMessage;
  final String listening;
  final String transcribing;
  final String releaseToSend;
  final String releaseToCancel;
  final String didNotHear;
  final String micDenied;

  /// Shown when a hold starts and no speech provider is configured.
  final String voiceUnavailable;

  static const AgentVoiceStrings en = AgentVoiceStrings(
    holdToSpeak: 'Hold to speak',
    typeMessage: 'Type a message',
    listening: 'Listening...',
    transcribing: 'Transcribing...',
    releaseToSend: 'Release to send, swipe up to cancel',
    releaseToCancel: 'Release to cancel',
    didNotHear: "I didn't catch that — please try again.",
    micDenied: 'Microphone access is off. Turn it on in Settings.',
    voiceUnavailable: 'Voice is not set up in this app.',
  );

  static const AgentVoiceStrings uz = AgentVoiceStrings(
    holdToSpeak: 'Gapirish uchun bosib turing',
    typeMessage: 'Xabar yozing',
    listening: 'Tinglayapman...',
    transcribing: 'Matnga aylantiryapman...',
    releaseToSend:
        'Yuborish uchun qo‘yib yuboring, bekor qilish uchun yuqoriga suring',
    releaseToCancel: 'Bekor qilish uchun qo‘yib yuboring',
    didNotHear: 'Eshitmadim — qaytadan urinib ko‘ring.',
    micDenied: 'Mikrofonga ruxsat berilmagan. Uni sozlamalardan yoqing.',
    voiceUnavailable: 'Bu ilovada ovozli rejim sozlanmagan.',
  );

  static const AgentVoiceStrings ru = AgentVoiceStrings(
    holdToSpeak: 'Удерживайте, чтобы говорить',
    typeMessage: 'Напишите сообщение',
    listening: 'Слушаю...',
    transcribing: 'Распознаю речь...',
    releaseToSend: 'Отпустите, чтобы отправить, или проведите вверх для отмены',
    releaseToCancel: 'Отпустите, чтобы отменить',
    didNotHear: 'Не расслышал — попробуйте ещё раз.',
    micDenied: 'Нет доступа к микрофону. Включите его в настройках.',
    voiceUnavailable: 'Голосовой режим в этом приложении не настроен.',
  );
}
