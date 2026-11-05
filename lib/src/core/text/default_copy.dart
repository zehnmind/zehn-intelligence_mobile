import 'localized_text.dart';

/// App-written lines the agent falls back on, in Uzbek, Russian and English.
/// An app replaces any of them through its profile.
abstract final class AgentDefaultCopy {
  /// A tool failed without a reason meant for the user.
  static const LocalizedText failed = LocalizedText({
    'en': "I couldn't do that just now. Please try again.",
    'uz': 'Hozir buni bajara olmadim. Qaytadan urinib ko‘ring.',
    'ru': 'Сейчас не получилось. Попробуйте ещё раз.',
  });

  /// Above a list of results, when a tool gives no lead line of its own.
  static const LocalizedText found = LocalizedText({
    'en': 'Here’s what I found:',
    'uz': 'Mana topilganlari:',
    'ru': 'Вот что нашлось:',
  });

  /// When a list comes back empty.
  static const LocalizedText empty = LocalizedText({
    'en': 'Nothing matched that.',
    'uz': 'Hech narsa topilmadi.',
    'ru': 'Ничего не нашлось.',
  });

  /// The model produced nothing usable.
  static const LocalizedText help = LocalizedText({
    'en': 'I can help with what this app does. What are you looking for?',
    'uz':
        'Men shu ilova qila oladigan ishlarda yordam beraman. Nima '
        'qidiryapsiz?',
    'ru': 'Я помогу с тем, что умеет это приложение. Что вы ищете?',
  });
}
