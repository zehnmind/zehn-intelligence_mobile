/// The chat's own words in uz, ru and en. Errors are grouped the way
/// `MOBILE_INTEGRATION.md` section 7 says to show them.
class ZiStrings {
  const ZiStrings._(this._w);

  static ZiStrings of(String language) => switch (language) {
    'ru' => const ZiStrings._(_ru),
    'en' => const ZiStrings._(_en),
    _ => const ZiStrings._(_uz),
  };

  final Map<String, String> _w;

  String get title => _w['title']!;
  String get placeholder => _w['placeholder']!;
  String get send => _w['send']!;
  String get holdToSpeak => _w['holdToSpeak']!;
  String get listening => _w['listening']!;
  String get retry => _w['retry']!;
  String get newChat => _w['newChat']!;
  String get close => _w['close']!;
  String get typeInstead => _w['typeInstead']!;

  String error(String code) => _w[switch (code) {
    'network_error' || 'stream_interrupted' || 'server_unavailable' => 'e.connection',
    'sdk_too_old' || 'key_revoked' => 'e.update',
    'app_disabled' || 'llm_unavailable' => 'e.unavailable',
    'turn_expired' => 'e.tooLong',
    'speech_not_recognized' => 'e.notHeard',
    'speech_unavailable' => 'e.voiceDown',
    'user_token_required' || 'user_token_expired' => 'e.signIn',
    'payload_too_large' => 'e.tooBig',
    _ => 'e.generic',
  }]!;

  static const _uz = {
    'title': 'Yordamchi',
    'placeholder': 'Savol yozing…',
    'send': 'Yuborish',
    'holdToSpeak': 'Gapirish uchun bosib turing',
    'listening': 'Tinglayapman…',
    'retry': 'Qayta urinish',
    'newChat': 'Yangi suhbat',
    'close': 'Yopish',
    'typeInstead': 'Yozib yuboring',
    'e.connection': 'Internet bilan aloqa yo‘q. Qayta urinib ko‘ring.',
    'e.update': 'Ilovani yangilang.',
    'e.unavailable': 'Yordamchi hozir ishlamayapti.',
    'e.tooLong': 'Juda uzoq davom etdi, yana so‘rang.',
    'e.notHeard': 'Eshitmadim, yana urinib ko‘ring.',
    'e.voiceDown': 'Ovoz hozir ishlamayapti, yozib yuboring.',
    'e.signIn': 'Qaytadan kiring.',
    'e.tooBig': 'Yozuv juda uzun.',
    'e.generic': 'Nimadir xato ketdi.',
  };

  static const _ru = {
    'title': 'Ассистент',
    'placeholder': 'Напишите вопрос…',
    'send': 'Отправить',
    'holdToSpeak': 'Удерживайте, чтобы говорить',
    'listening': 'Слушаю…',
    'retry': 'Повторить',
    'newChat': 'Новый чат',
    'close': 'Закрыть',
    'typeInstead': 'Напишите текстом',
    'e.connection': 'Нет связи. Попробуйте ещё раз.',
    'e.update': 'Обновите приложение.',
    'e.unavailable': 'Ассистент сейчас недоступен.',
    'e.tooLong': 'Это заняло слишком много времени, спросите ещё раз.',
    'e.notHeard': 'Не расслышал, попробуйте ещё раз.',
    'e.voiceDown': 'Голос сейчас недоступен, напишите текстом.',
    'e.signIn': 'Войдите снова.',
    'e.tooBig': 'Запись слишком длинная.',
    'e.generic': 'Что-то пошло не так.',
  };

  static const _en = {
    'title': 'Assistant',
    'placeholder': 'Ask a question…',
    'send': 'Send',
    'holdToSpeak': 'Hold to speak',
    'listening': 'Listening…',
    'retry': 'Try again',
    'newChat': 'New chat',
    'close': 'Close',
    'typeInstead': 'Type instead',
    'e.connection': 'No connection. Please try again.',
    'e.update': 'Please update the app.',
    'e.unavailable': 'The assistant is not available right now.',
    'e.tooLong': 'That took too long, ask again.',
    'e.notHeard': "I didn't catch that, try again.",
    'e.voiceDown': 'Voice is not available right now, please type.',
    'e.signIn': 'Please sign in again.',
    'e.tooBig': 'The recording is too long.',
    'e.generic': 'Something went wrong.',
  };
}
