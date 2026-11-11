import 'package:flutter_test/flutter_test.dart';
import 'package:zehn_intelligence/src/server/ui/strings.dart';

void main() {
  group('a rate limit says how long to wait', () {
    String say(String language, Duration? wait, {String code = 'user_rate_limited'}) =>
        ZiStrings.of(language).error(code, wait: wait);

    test('in seconds, minutes or hours, rounded up, never cut short', () {
      expect(say('en', const Duration(seconds: 30)), 'Too many requests. Try again in 30 s.');
      expect(say('en', const Duration(milliseconds: 1200)), 'Too many requests. Try again in 2 s.');
      expect(say('en', const Duration(seconds: 60)), 'Too many requests. Try again in 1 min.');
      expect(say('en', const Duration(seconds: 61)), 'Too many requests. Try again in 2 min.');
      expect(say('en', const Duration(seconds: 3599)), 'Too many requests. Try again in 60 min.');
      expect(say('en', const Duration(seconds: 3600)), 'Too many requests. Try again in 1 h.');
      expect(say('en', const Duration(seconds: 3601)), 'Too many requests. Try again in 2 h.');
      expect(say('en', const Duration(hours: 5)), 'Too many requests. Try again in 5 h.');
    });

    test('in uz and ru', () {
      expect(say('uz', const Duration(seconds: 30)), 'Juda ko‘p so‘rov yuborildi. 30 soniyadan keyin qayta urinib ko‘ring.');
      expect(say('uz', const Duration(minutes: 2)), 'Juda ko‘p so‘rov yuborildi. 2 daqiqadan keyin qayta urinib ko‘ring.');
      expect(say('ru', const Duration(seconds: 30)), 'Слишком много запросов. Попробуйте через 30 с.');
      expect(say('ru', const Duration(minutes: 2)), 'Слишком много запросов. Попробуйте через 2 мин.');
    });

    test('quota_exceeded too; with no wait, or no usable one, "later"', () {
      expect(say('en', const Duration(seconds: 10), code: 'quota_exceeded'), 'Too many requests. Try again in 10 s.');
      for (final language in ['uz', 'ru', 'en']) {
        final later = ZiStrings.of(language).error('user_rate_limited');
        expect(later, isNot(contains('{')), reason: language);
        expect(say(language, null), later);
        expect(say(language, Duration.zero), later);
      }
      expect(say('en', null), 'Too many requests. Try again later.');
    });

    test('another code is not given a wait', () {
      expect(ZiStrings.of('en').error('llm_unavailable', wait: const Duration(seconds: 5)), 'The assistant is not available right now.');
      expect(ZiStrings.of('en').error('nonsense'), 'Something went wrong.');
    });
  });
}
