/// The words the chat's own chrome uses: the badge, the thinking row, the
/// confirmation buttons, the history sheet.
///
/// Built-in in Uzbek, Russian and English. An app with its own translations
/// passes them in through `AgentScope.strings`, so its localization stays the
/// source of truth and no ARB file is needed for the agent.
class AgentStrings {
  const AgentStrings({
    required this.assistantLabel,
    required this.thinking,
    required this.actionFailed,
    required this.confirm,
    required this.cancel,
    required this.confirmCancelled,
    required this.newChat,
    required this.clear,
    required this.typeMessage,
    required this.send,
    required this.stepUpFailed,
    this.ask = 'Ask',
  });

  /// The built-in strings for [languageCode], English when unknown.
  factory AgentStrings.forLanguage(String languageCode) =>
      switch (languageCode) {
        'uz' => uz,
        'ru' => ru,
        _ => en,
      };

  /// Marks everything below it as assistant-generated rather than app UI.
  final String assistantLabel;
  final String thinking;
  final String actionFailed;

  /// The confirm button, when the card does not name its own.
  final String confirm;

  /// The dismiss button, when the card does not name its own.
  final String cancel;
  final String confirmCancelled;
  final String newChat;
  final String clear;
  final String typeMessage;
  final String send;

  /// Shown when a write needs the user verified again and they were not.
  final String stepUpFailed;

  /// The button that opens the assistant (`AgentButton`).
  final String ask;

  AgentStrings copyWith({
    String? assistantLabel,
    String? thinking,
    String? actionFailed,
    String? confirm,
    String? cancel,
    String? confirmCancelled,
    String? newChat,
    String? clear,
    String? typeMessage,
    String? send,
    String? stepUpFailed,
    String? ask,
  }) => AgentStrings(
    assistantLabel: assistantLabel ?? this.assistantLabel,
    thinking: thinking ?? this.thinking,
    actionFailed: actionFailed ?? this.actionFailed,
    confirm: confirm ?? this.confirm,
    cancel: cancel ?? this.cancel,
    confirmCancelled: confirmCancelled ?? this.confirmCancelled,
    newChat: newChat ?? this.newChat,
    clear: clear ?? this.clear,
    typeMessage: typeMessage ?? this.typeMessage,
    send: send ?? this.send,
    stepUpFailed: stepUpFailed ?? this.stepUpFailed,
    ask: ask ?? this.ask,
  );

  static const AgentStrings en = AgentStrings(
    assistantLabel: 'Assistant',
    thinking: 'Thinking...',
    actionFailed: "I couldn't run that action.",
    confirm: 'Confirm',
    cancel: 'Cancel',
    confirmCancelled: 'Alright, nothing was changed.',
    newChat: 'New chat',
    clear: 'Clear',
    typeMessage: 'Type a message',
    send: 'Send',
    stepUpFailed: 'Not confirmed — nothing was changed.',
    ask: 'Ask',
  );

  static const AgentStrings uz = AgentStrings(
    assistantLabel: 'Yordamchi',
    thinking: 'O‘ylayapman...',
    actionFailed: 'Bu amalni bajara olmadim.',
    confirm: 'Tasdiqlash',
    cancel: 'Bekor qilish',
    confirmCancelled: 'Yaxshi, hech narsa o‘zgartirilmadi.',
    newChat: 'Yangi suhbat',
    clear: 'Tozalash',
    typeMessage: 'Xabar yozing',
    send: 'Yuborish',
    stepUpFailed: 'Tasdiqlanmadi — hech narsa o‘zgartirilmadi.',
    ask: 'So‘rash',
  );

  static const AgentStrings ru = AgentStrings(
    assistantLabel: 'Ассистент',
    thinking: 'Думаю...',
    actionFailed: 'Не удалось выполнить это действие.',
    confirm: 'Подтвердить',
    cancel: 'Отмена',
    confirmCancelled: 'Хорошо, ничего не изменено.',
    newChat: 'Новый чат',
    clear: 'Очистить',
    typeMessage: 'Напишите сообщение',
    send: 'Отправить',
    stepUpFailed: 'Не подтверждено — ничего не изменено.',
    ask: 'Спросить',
  );
}
