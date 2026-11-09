import 'package:flutter_test/flutter_test.dart';
import 'package:zehn_intelligence/src/server/chat/chat_settings.dart';

void main() {
  test('reads GET /v1/config', () {
    final s = ZiChatSettings.fromJson({
      'spec_version': '1.2.0',
      'assistant_name': 'Mall guide',
      'app_name': 'Tashkent City Mall',
      'services': ['llm', 'stt', 'tts'],
      'languages': ['uz', 'ru'],
      'default_language': 'uz',
      'theme': {'font': 'CeraPro'},
      'copy': {
        'welcome_title': {'uz': 'Salom!', 'ru': 'Привет!'},
        'welcome_subtitle': 'Find stores.',
      },
    });
    expect(s.services, {'llm', 'stt', 'tts'});
    expect(s.languages, ['uz', 'ru']);
    expect(s.defaultLanguage, 'uz');
    expect(s.theme, {'font': 'CeraPro'});
    expect(s.assistantName, 'Mall guide');
    expect(s.appName, 'Tashkent City Mall');
    expect(s.speech, isTrue);
    expect(s.voiceReply, isTrue);
    expect(s.welcomeTitle('ru'), 'Привет!');
    expect(s.welcomeSubtitle('ru'), 'Find stores.');
  });

  test('a welcome map falls back to the default language, then en, then the first', () {
    ZiChatSettings settings(Map<String, String> title, {String? fallback}) =>
        ZiChatSettings.fromJson({'default_language': ?fallback, 'copy': {'welcome_title': title}});
    expect(settings({'uz': 'Salom', 'en': 'Hi'}, fallback: 'uz').welcomeTitle('kk'), 'Salom');
    expect(settings({'ru': 'Привет', 'en': 'Hi'}).welcomeTitle('kk'), 'Hi');
    expect(settings({'kk': 'Сәлем', 'tg': 'Салом'}).welcomeTitle('ru'), 'Сәлем');
  });

  test('anything missing or of the wrong type falls back to the SDK defaults', () {
    for (final json in <Object?>[
      null,
      'nope',
      <String, Object?>{},
      {'services': 'stt', 'languages': 3, 'theme': [], 'copy': <String, Object?>{}, 'assistant_name': ''},
      {'copy': {'welcome_title': '', 'welcome_subtitle': 7}},
    ]) {
      final s = ZiChatSettings.fromJson(json);
      expect(s.services, isEmpty, reason: '$json');
      expect(s.languages, isEmpty);
      expect(s.defaultLanguage, isNull);
      expect(s.theme, isEmpty);
      expect(s.assistantName, isNull);
      expect(s.welcomeTitle('en'), isNull);
      expect(s.welcomeSubtitle('en'), isNull);
      expect(s.speech, isFalse);
      expect(s.voiceReply, isFalse);
    }
  });
}
