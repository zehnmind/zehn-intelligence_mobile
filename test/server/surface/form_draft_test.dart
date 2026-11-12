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
}
