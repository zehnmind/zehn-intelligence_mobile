import 'package:flutter_test/flutter_test.dart';
import 'package:zehn_intelligence/src/server/surface/form_draft.dart';
import 'package:zehn_intelligence/src/server/surface/surface.dart';

import '../../support/form_cards.dart';

void main() {
  ZiFormDraft draft({Map<String, Object?> prefill = const {}}) =>
      ZiFormDraft(ZiSurface.parse(bookCard), prefill: prefill, today: () => DateTime(2026, 11, 12, 18, 30));

  final party = card([
    {
      'id': 'root',
      'component': 'Column',
      'children': ['guests', 'agree', 'date', 'city'],
    },
    {'id': 'guests', 'component': 'TextField', 'field': 'guests', 'label': 'Guests', 'input': 'number', 'value': 2},
    {'id': 'agree', 'component': 'Switch', 'field': 'agree', 'label': 'Agree'},
    {'id': 'date', 'component': 'DateField', 'field': 'date', 'label': 'Date', 'value': 'today'},
    {
      'id': 'city',
      'component': 'Select',
      'field': 'city',
      'label': 'City',
      'options': [
        {'value': 'tashkent', 'label': 'Tashkent'},
      ],
    },
  ]);

  test("starts from the prefill, then each field's own value", () {
    final d = ZiFormDraft(party, prefill: {'guests': 4}, today: () => DateTime(2026, 11, 12));
    expect(d.raw, {'guests': '4', 'agree': false, 'date': '2026-11-12'});
    expect(d.today, DateTime(2026, 11, 12));
  });
  test('a prefill of the wrong type, or for a key the form does not have, is dropped', () {
    final d = ZiFormDraft(
      party,
      prefill: {'guests': 'two', 'agree': 'yes', 'city': 'paris', 'other': 1},
      today: () => DateTime(2026, 11, 12),
    );
    expect(d.raw, {'guests': '2', 'agree': false, 'date': '2026-11-12'});
    expect(
      draft(
        prefill: {
          'name': 7,
          'phone': ['x'],
        },
      ).raw,
      isEmpty,
    );
  });
  test('an error shows only after the field was left or a send was tried, and goes when fixed', () {
    final d = draft();
    expect(d.errorOf('name'), isNull);
    d.touch('name');
    expect(d.errorOf('name')?.rule, 'required');
    d.set('name', 'Ali');
    expect(d.errorOf('name'), isNull);
  });
  test('check() names the first failing field and tells the listeners', () {
    final d = draft();
    var told = 0;
    d.addListener(() => told++);
    expect(d.check(), isFalse);
    expect((d.focusField, d.focusTick), ('name', 1));
    expect(told, greaterThan(0));
    d.set('name', 'Ali');
    expect(d.check(), isTrue);
  });
  test('a server error shows at once and goes when the field changes', () {
    final d = draft(prefill: {'name': 'Ali', 'phone': '+998 90 123 45 67'})..serverErrors({'phone': 'phone'});
    expect(d.errorOf('phone')?.rule, 'phone');
    expect(d.notSent, isFalse);
    d.set('phone', '+998 90 123 45 68');
    expect(d.errorOf('phone'), isNull);
  });
  test('a server rule with no words, or for no field of the form, says Not sent', () {
    expect((draft()..serverErrors({'phone': 'type'})).notSent, isTrue);
    expect((draft()..serverErrors({'nope': 'required'})).notSent, isTrue);
  });
  test('values are what is sent: trimmed, a number as a number', () {
    final d = ZiFormDraft(party, today: () => DateTime(2026, 11, 12))..set('guests', ' 3 ');
    expect(d.values, {'guests': 3, 'agree': false, 'date': '2026-11-12'});
  });

  final rich = card([
    {
      'id': 'root',
      'component': 'Column',
      'children': ['note', 'qty', 'tags', 'city', 'when', 'agree', 'extra'],
    },
    {
      'id': 'note',
      'component': 'TextField',
      'field': 'note',
      'label': 'Note',
      'maxLength': 10,
      'checks': [
        {'rule': 'length', 'min': 3, 'message': 'Too short'},
      ],
    },
    {
      'id': 'qty',
      'component': 'TextField',
      'field': 'qty',
      'label': 'Qty',
      'input': 'number',
      'checks': [
        {'rule': 'range', 'min': 1, 'max': 5},
      ],
    },
    {
      'id': 'tags',
      'component': 'Select',
      'field': 'tags',
      'label': 'Tags',
      'multiple': true,
      'options': [
        {'value': 'a', 'label': 'A'},
        {'value': 'b', 'label': 'B'},
        {'value': 'c', 'label': 'C'},
      ],
    },
    {
      'id': 'city',
      'component': 'Select',
      'field': 'city',
      'label': 'City',
      'options': [
        {'value': 'tashkent', 'label': 'Tashkent'},
      ],
    },
    {'id': 'when', 'component': 'DateField', 'field': 'when', 'label': 'When'},
    {'id': 'agree', 'component': 'Switch', 'field': 'agree', 'label': 'Agree'},
    {
      'id': 'extra',
      'component': 'TextField',
      'field': 'extra',
      'label': 'Extra',
      'visible': {'path': '/form/agree'},
      'checks': [
        {'rule': 'required'},
      ],
    },
  ]);
  ZiFormDraft richDraft({Map<String, Object?> prefill = const {}}) =>
      ZiFormDraft(rich, prefill: prefill, today: () => DateTime(2026, 11, 12));

  test('a Select prefill keeps known options only; a multiple one keeps a list of them', () {
    final d = richDraft(
      prefill: {
        'city': 'tashkent',
        'tags': ['c', 'zzz', 'a'],
      },
    );
    expect(d.raw['city'], 'tashkent');
    expect(d.raw['tags'], ['c', 'a']);
    expect(richDraft(prefill: {'city': 'paris', 'tags': 'a'}).raw.containsKey('city'), isFalse);
    expect(
      richDraft(
        prefill: {
          'tags': ['zzz'],
        },
      ).raw.containsKey('tags'),
      isFalse,
    );
    expect(
      richDraft(
        prefill: {
          'city': ['tashkent'],
        },
      ).raw.containsKey('city'),
      isFalse,
    );
  });
  test('a DateField prefill is a real day or "today"', () {
    expect(richDraft(prefill: {'when': '2026-03-01'}).raw['when'], '2026-03-01');
    expect(richDraft(prefill: {'when': 'today'}).raw['when'], '2026-11-12');
    expect(richDraft(prefill: {'when': '2026-02-30'}).raw.containsKey('when'), isFalse);
    expect(richDraft(prefill: {'when': 5}).raw.containsKey('when'), isFalse);
  });
  test('a hidden field has no error and check() does not stop at it', () {
    final d = richDraft(prefill: {'note': 'hello', 'qty': '2'});
    expect(d.hidden, {'extra'});
    d.touch('extra');
    expect(d.errorOf('extra'), isNull);
    expect(d.check(), isTrue);
    d.set('agree', true);
    expect(d.errorOf('extra')?.rule, 'required');
    expect(d.check(), isFalse);
    expect(d.focusField, 'extra');
  });
  test('each failed check() grows focusTick', () {
    final d = draft();
    d.check();
    d.check();
    expect((d.focusField, d.focusTick), ('name', 2));
  });
  test('set(field, null) removes the key', () {
    final d = draft(prefill: {'name': 'Ali'})..set('name', null);
    expect(d.raw, isEmpty);
    expect(d.values, isEmpty);
  });
  test('markNotSent sets and clears, telling listeners only on a change', () {
    final d = draft();
    var told = 0;
    d.addListener(() => told++);
    d.markNotSent(false);
    expect(told, 0);
    d.markNotSent(true);
    expect((d.notSent, told), (true, 1));
    d.markNotSent(false);
    expect(d.notSent, isFalse);
  });
  test('a server error believes what the field holds now, with its own bounds and message', () {
    final d = richDraft(prefill: {'note': 'ab', 'qty': '9'})..serverErrors({'note': 'length', 'qty': 'range'});
    expect(d.errorOf('note')?.message, 'Too short');
    expect((d.errorOf('note')?.min, d.errorOf('note')?.max), (3, null));
    expect((d.errorOf('qty')?.min, d.errorOf('qty')?.max), (1, 5));
    expect(d.notSent, isFalse);
  });
  test('a too-long text is told by its maxLength, not by a lone min', () {
    final d = richDraft(prefill: {'note': 'abcdefghijklmn'})..serverErrors({'note': 'length'});
    expect((d.errorOf('note')?.min, d.errorOf('note')?.max), (null, 10));
    expect(d.errorOf('note')?.word, 'length_max');
  });
  test('a server error takes the check bounds when the phone sees no fault', () {
    final d = richDraft(prefill: {'qty': '3'})..serverErrors({'qty': 'range'});
    expect((d.errorOf('qty')?.min, d.errorOf('qty')?.max), (1, 5));
  });
  test('length without a check says the field maxLength, else 500', () {
    final d = draft(prefill: {'name': 'Ali'})..serverErrors({'name': 'length'});
    expect(d.errorOf('name')?.max, 500);
  });
  test('range or items with no bounds to name, or for a hidden field, is not kept: Not sent', () {
    final d = richDraft(prefill: {'city': 'tashkent'})..serverErrors({'city': 'items'});
    expect(d.errorOf('city'), isNull);
    expect(d.notSent, isTrue);
    final e = richDraft()..serverErrors({'extra': 'required'});
    expect(e.errorOf('extra'), isNull);
    expect(e.notSent, isTrue);
    final f = draft()..serverErrors({'phone': 'range'});
    expect(f.errorOf('phone'), isNull);
    expect(f.notSent, isTrue);
  });
  test('a second serverErrors replaces the first', () {
    final d = draft(prefill: {'name': 'Ali', 'phone': '+998 90 123 45 67'})
      ..serverErrors({'phone': 'phone'})
      ..serverErrors({'name': 'required'});
    expect(d.errorOf('phone'), isNull);
    expect(d.errorOf('name')?.rule, 'required');
  });
  test('serverErrors asks to show the first kept field in drawn order, and only when it kept one', () {
    final d = draft(prefill: {'name': 'Ali', 'phone': '+998 90 123 45 67'});
    d.serverErrors({'phone': 'phone', 'name': 'required'});
    expect((d.focusField, d.focusTick), ('name', 1));
    d.serverErrors({'phone': 'type'});
    expect((d.focusField, d.focusTick), ('name', 1));
  });
}
