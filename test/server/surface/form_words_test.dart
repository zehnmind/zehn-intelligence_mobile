import 'package:flutter_test/flutter_test.dart';
import 'package:zehn_intelligence/src/server/surface/form_words.dart';

void main() {
  test('twenty keys, each in uz, ru and en', () {
    expect(ziFormWords.keys.toSet(), {
      'required', 'length', 'length_min', 'length_max', 'range', 'range_min', 'range_max', 'items', 'items_min',
      'items_max', 'number', 'email', 'phone', 'date', 'option', 'sent', 'not_answered', 'not_sent', 'update_app', 'choose',
    });
    for (final words in ziFormWords.values) {
      expect(words.keys.toSet(), {'uz', 'ru', 'en'});
      expect(words.values.every((w) => w.isNotEmpty), isTrue);
    }
  });

  test('fills {min} and {max}; a whole number has no decimals', () {
    expect(ziFormWord('length', 'en', min: 2, max: 60.0), 'Use 2 to 60 characters');
    expect(ziFormWord('range_min', 'ru', min: 1.5), 'Введите 1.5 или больше');
    expect(ziFormWord('not_sent', 'uz'), 'Yuborilmadi. Qayta urinib ko‘ring.');
  });

  test('another language reads English; an unknown key is empty', () {
    expect(ziFormWord('sent', 'kk'), 'Sent');
    expect(ziFormWord('nope', 'en'), '');
  });
}
