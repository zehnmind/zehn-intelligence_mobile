import 'package:flutter_test/flutter_test.dart';
import 'package:zehn_intelligence/src/server/surface/formats.dart';

/// The space inside a number and before a currency: it never breaks a line.
const nb = ' ';

void main() {
  String all(Object? value, String format) =>
      [for (final l in ['uz', 'ru', 'en']) ziFormat(value, format, l)].join(' | ');

  test('time: the hour and minute, the same in every language', () {
    expect(all('2026-11-10T12:30:00', 'time'), '12:30 | 12:30 | 12:30');
    expect(ziFormat('12:30:00', 'time', 'uz'), '12:30');
    expect(ziFormat('09:05', 'time', 'en'), '09:05');
  });

  test('a time with a zone shows in the phone\'s time; one without, as written', () {
    final local = DateTime.parse('2026-11-10T07:30:00Z').toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    expect(ziFormat('2026-11-10T07:30:00Z', 'time', 'en'), '${two(local.hour)}:${two(local.minute)}');
    expect(ziFormat('2026-11-10T07:30:00', 'time', 'en'), '07:30');
  });

  test('date: the day and month in the language', () {
    expect(all('2026-11-10', 'date'), '10-noyabr | 10 ноября | Nov 10');
    expect(all('2026-03-01T10:00:00', 'date'), '1-mart | 1 марта | Mar 1');
    expect(ziFormat('2026-05-09', 'date', 'ru'), '9 мая');
  });

  test('datetime: the date, then the time', () {
    expect(all('2026-11-10T12:30:00', 'datetime'), '10-noyabr, 12:30 | 10 ноября, 12:30 | Nov 10, 12:30');
  });

  test('number: thousands grouped the language\'s way', () {
    expect(all(10000, 'number'), '10${nb}000 | 10${nb}000 | 10,000');
    expect(all('10000', 'number'), '10${nb}000 | 10${nb}000 | 10,000');
    expect(ziFormat(1234567, 'number', 'ru'), '1${nb}234${nb}567');
    expect(ziFormat(999, 'number', 'uz'), '999');
    expect(ziFormat(-2500, 'number', 'en'), '-2,500');
    expect(ziFormat(10000.0, 'number', 'uz'), '10${nb}000');
    expect(all(12.5, 'number'), '12,5 | 12,5 | 12.5');
  });

  test('money: the number, then the currency code', () {
    expect(all(10000, 'money:UZS'), '10${nb}000${nb}UZS | 10${nb}000${nb}UZS | 10,000${nb}UZS');
    expect(ziFormat('25000', 'money:USD', 'en'), '25,000${nb}USD');
    expect(ziFormat(10000, 'money', 'en'), '10,000');
  });

  test('duration: minutes as hours and minutes', () {
    expect(all(90, 'duration'), '1 soat 30 daqiqa | 1 ч 30 мин | 1 h 30 min');
    expect(all(45, 'duration'), '45 daqiqa | 45 мин | 45 min');
    expect(all('120', 'duration'), '2 soat | 2 ч | 2 h');
    expect(ziFormat(0, 'duration', 'en'), '0 min');
  });

  test('a value that does not parse, or an unknown format, shows raw', () {
    expect(ziFormat('soon', 'time', 'en'), 'soon');
    expect(ziFormat('abc', 'number', 'en'), 'abc');
    expect(ziFormat(-5, 'duration', 'en'), '-5');
    expect(ziFormat(10000, 'shout', 'en'), '10000');
    expect(ziFormat(null, 'number', 'en'), '');
  });

  test('another language is drawn the English way', () {
    expect(ziFormat('2026-11-10', 'date', 'kk'), 'Nov 10');
    expect(ziFormat(10000, 'number', 'kk'), '10,000');
  });

  test('the formats the catalog lists', () {
    expect(ziFormats, {'time', 'date', 'datetime', 'number', 'money', 'duration'});
  });
}
