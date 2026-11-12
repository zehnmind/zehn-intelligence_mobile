import 'dart:collection';

import 'package:flutter_test/flutter_test.dart';
import 'package:zehn_intelligence/src/server/surface/form_check.dart';
import 'package:zehn_intelligence/src/server/surface/form_words.dart';
import 'package:zehn_intelligence/src/server/surface/surface.dart';
import 'package:zehn_intelligence/src/server/surface/values.dart';

import '../../support/form_cards.dart';

void main() {
  final today = DateTime(2026, 11, 12);
  ZiCheckFailure? check(Map<String, Object?> spec, Object? raw) =>
      ziCheckField({'component': 'TextField', 'field': 'f', 'label': 'L', ...spec}, raw, today: today);

  test('a number is digits with one comma or point; it is sent as a number', () {
    expect(check({'input': 'number'}, '2,5'), isNull);
    expect(check({'input': 'number'}, '-3'), isNull);
    expect(check({'input': 'number'}, '1 000')?.rule, 'number');
    expect(check({'input': 'number'}, '1.2.3')?.rule, 'number');
    expect(ziFieldValue({'component': 'TextField', 'input': 'number'}, ' 2,5 '), 2.5);
    expect(ziFieldValue({'component': 'TextField', 'input': 'number'}, '2'), 2);
  });

  test('a number a field already holds is a value; it is checked like the typed text', () {
    final number = {'component': 'TextField', 'input': 'number'};
    expect(ziFieldValue(number, 4), 4);
    expect(ziFieldValue(number, 2.5), 2.5);
    expect(ziFieldValue(number, 4.0), 4);
    final guests = {
      'input': 'number',
      'checks': [
        {'rule': 'required'},
        {'rule': 'range', 'min': 1, 'max': 12},
      ],
    };
    expect(check(guests, 4), isNull);
    expect(check(guests, 13)?.word, 'range');
    expect(check(guests, 13)?.word, check(guests, '13')?.word);
  });

  test('a number text too long to be finite fails as a number', () {
    final huge = '9' * 400;
    expect(check({'input': 'number'}, huge)?.rule, 'number');
    expect(ziFieldValue({'component': 'TextField', 'input': 'number'}, huge), huge);
  });

  test('a number has at most 15 digits, the sign and the decimal mark aside; it is sent exactly', () {
    final number = {'component': 'TextField', 'input': 'number'};
    expect(check({'input': 'number'}, '123456789012345'), isNull);
    expect(ziFieldValue(number, '123456789012345'), 123456789012345);
    expect(check({'input': 'number'}, '1234567890.12345'), isNull);
    expect(ziFieldValue(number, '1234567890.12345'), 1234567890.12345);
    expect('${ziFieldValue(number, '1234567890.12345')}', '1234567890.12345');
    expect(check({'input': 'number'}, '-123456789012345'), isNull);
    expect(ziFieldValue(number, '-123456789012345'), -123456789012345);
    expect(check({'input': 'number'}, '1234567890123456')?.rule, 'number');
    expect(check({'input': 'number'}, '1234567890.123456789')?.rule, 'number');
    expect(check({'input': 'number'}, '20208000900123456789')?.rule, 'number');
  });

  test('a date field is read without looking at input', () {
    final spec = _NoInput({'component': 'DateField', 'field': 'f'});
    expect(ziFieldValue(spec, ' 2026-11-12 '), '2026-11-12');
    expect(ziCheckField(spec, '2026-11-12', today: today), isNull);
  });

  test('email and phone; a phone is sent as typed', () {
    expect(check({'input': 'email'}, 'ali@example.uz'), isNull);
    expect(check({'input': 'email'}, 'ali@example')?.rule, 'email');
    expect(check({'input': 'phone'}, '+998 (90) 123-45-67'), isNull);
    expect(check({'input': 'phone'}, '12345')?.rule, 'phone');
    expect(check({'input': 'phone'}, '90 123 45 6x')?.rule, 'phone');
    expect(ziFieldValue({'component': 'TextField', 'input': 'phone'}, ' +998 90 123 45 67 '), '+998 90 123 45 67');
  });

  test('required; an empty optional field passes everything else', () {
    expect(
      check({
        'checks': [
          {'rule': 'required'},
        ],
      }, '   ')?.rule,
      'required',
    );
    expect(check({'input': 'email'}, ''), isNull);
    final box = {
      'component': 'Checkbox',
      'field': 'f',
      'checks': [
        {'rule': 'required'},
      ],
    };
    expect(ziCheckField(box, false, today: today)?.rule, 'required');
    expect(ziCheckField(box, true, today: today), isNull);
  });

  test('length counts UTF-16 code units, and maxLength is always checked', () {
    expect(
      check({
        'checks': [
          {'rule': 'length', 'min': 2, 'max': 3},
        ],
      }, 'a')?.word,
      'length',
    );
    expect(
      check({
        'checks': [
          {'rule': 'length', 'min': 2},
        ],
      }, 'a')?.word,
      'length_min',
    );
    expect(
      check({
        'checks': [
          {'rule': 'length', 'max': 3},
        ],
      }, '👍👍')?.word,
      'length_max',
    ); // four units
    expect(check({'maxLength': 5}, 'abcdef')?.max, 5);
    expect(check(const {}, 'a' * 501)?.max, 500);
  });

  test('range, and the automatic check comes first', () {
    final guests = {
      'input': 'number',
      'checks': [
        {'rule': 'required'},
        {'rule': 'range', 'min': 1, 'max': 12},
      ],
    };
    expect(check(guests, '13')?.word, 'range');
    expect(
      check({
        'input': 'number',
        'checks': [
          {'rule': 'range', 'min': 1},
        ],
      }, '0')?.word,
      'range_min',
    );
    expect(check(guests, 'abc')?.rule, 'number');
  });

  test('select: a value outside the options, and how many are picked', () {
    final select = {
      'component': 'Select',
      'field': 'f',
      'options': [
        {'value': 'a', 'label': 'A'},
        {'value': 'b', 'label': 'B'},
      ],
    };
    expect(ziCheckField(select, 'c', today: today)?.rule, 'option');
    expect(
      ziCheckField(
        {
          ...select,
          'multiple': true,
          'checks': [
            {'rule': 'items', 'min': 2},
          ],
        },
        ['a'],
        today: today,
      )?.word,
      'items_min',
    );
    expect(ziFieldValue({...select, 'multiple': true}, <String>[]), isNull);
  });

  test("date: a real day, inside min and max, where today is the phone's day", () {
    final date = {'component': 'DateField', 'field': 'f', 'min': 'today', 'max': '2026-12-31'};
    expect(ziCheckField(date, '2026-11-12', today: today), isNull);
    expect(ziCheckField(date, '2026-11-11', today: today)?.rule, 'date');
    expect(ziCheckField(date, '2027-01-01', today: today)?.rule, 'date');
    expect(ziCheckField(date, '2026-02-30', today: today)?.rule, 'date');
  });

  test("the message is the check's own, else the words", () {
    const v = ZiValues(null, 'en');
    expect(ziCheckMessage(const ZiCheckFailure('length', min: 2, max: 60), v), 'Use 2 to 60 characters');
    expect(
      ziCheckMessage(
        const ZiCheckFailure('required', message: {'uz': 'Ismingizni yozing', 'en': 'Tell us your name'}),
        v,
      ),
      'Tell us your name',
    );
  });

  test('fields come in the order they are drawn', () {
    expect(ziFormFields(ZiSurface.parse(bookCard)).map((f) => f['field']), ['name', 'phone']);
  });

  test('a hidden field is not sent, and a field only it would show stays hidden', () {
    final chain = card([
      {
        'id': 'root',
        'component': 'Column',
        'children': ['a', 'b', 'c'],
      },
      {'id': 'a', 'component': 'Switch', 'field': 'a', 'label': 'A'},
      {
        'id': 'b',
        'component': 'TextField',
        'field': 'b',
        'label': 'B',
        'visible': {'path': '/form/a'},
      },
      {
        'id': 'c',
        'component': 'TextField',
        'field': 'c',
        'label': 'C',
        'visible': {'path': '/form/b', 'equals': 'x'},
      },
    ]);
    final off = ziFormValues(chain, {'a': false, 'b': 'x', 'c': 'kept'});
    expect(off.values, {'a': false});
    expect(off.hidden, {'b', 'c'});
    expect(ziFormValues(chain, {'a': true, 'b': 'x', 'c': 'kept'}).values, {'a': true, 'b': 'x', 'c': 'kept'});
  });

  test('a field inside a hidden block is hidden; false is a value, empty text and an empty list are not', () {
    final nested = card([
      {
        'id': 'root',
        'component': 'Column',
        'children': ['s', 'more'],
      },
      {'id': 's', 'component': 'Switch', 'field': 's', 'label': 'S'},
      {
        'id': 'more',
        'component': 'Column',
        'visible': {'path': '/form/s'},
        'children': ['t', 'm'],
      },
      {'id': 't', 'component': 'TextField', 'field': 't', 'label': 'T'},
      {
        'id': 'm',
        'component': 'Select',
        'field': 'm',
        'label': 'M',
        'multiple': true,
        'options': [
          {'value': 'a', 'label': 'A'},
        ],
      },
    ]);
    expect(ziFormValues(nested, {'s': false, 't': 'x'}).hidden, {'t', 'm'});
    expect(ziFormValues(nested, {'s': true, 't': '  ', 'm': <String>[]}).values, {'s': true});
  });

  test('every rule the phone can report has words', () {
    for (final rule in ziCheckRules) {
      expect(ziFormWords, contains(rule), reason: rule);
    }
  });
}

/// A spec that fails the test when `input` is read.
class _NoInput extends MapBase<String, Object?> {
  _NoInput(this._m);
  final Map<String, Object?> _m;
  @override
  Object? operator [](Object? key) {
    if (key == 'input') fail('read input');
    return _m[key];
  }

  @override
  void operator []=(String key, Object? value) => _m[key] = value;
  @override
  void clear() => _m.clear();
  @override
  Iterable<String> get keys => _m.keys;
  @override
  Object? remove(Object? key) => _m.remove(key);
}
