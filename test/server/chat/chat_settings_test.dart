import 'package:flutter_test/flutter_test.dart';
import 'package:zehn_intelligence/src/server/chat/chat_settings.dart';

void main() {
  test('reads the chat field of GET /v1/suggestions', () {
    final s = ZiChatSettings.fromJson({
      'services': ['llm', 'stt', 'tts'],
      'languages': ['uz', 'ru'],
      'default_language': 'uz',
      'theme': {'primary': '#1E66F5'},
      'welcome_title': 'Salom!',
      'welcome_subtitle': 'Nima qilamiz?',
      'spec_version': 'v7',
    });
    expect(s.services, {'llm', 'stt', 'tts'});
    expect(s.languages, ['uz', 'ru']);
    expect(s.defaultLanguage, 'uz');
    expect(s.theme, {'primary': '#1E66F5'});
    expect(s.welcomeTitle, 'Salom!');
    expect(s.welcomeSubtitle, 'Nima qilamiz?');
    expect(s.specVersion, 'v7');
    expect(s.speech, isTrue);
    expect(s.voiceReply, isTrue);
  });

  test('anything missing or of the wrong type falls back to the SDK defaults', () {
    for (final json in <Object?>[null, 'nope', <String, Object?>{}, {'services': 'stt', 'languages': 3, 'theme': [], 'welcome_title': ''}]) {
      final s = ZiChatSettings.fromJson(json);
      expect(s.services, isEmpty, reason: '$json');
      expect(s.languages, isEmpty);
      expect(s.defaultLanguage, isNull);
      expect(s.theme, isEmpty);
      expect(s.welcomeTitle, isNull);
      expect(s.welcomeSubtitle, isNull);
      expect(s.specVersion, isNull);
      expect(s.speech, isFalse);
      expect(s.voiceReply, isFalse);
    }
  });
}
