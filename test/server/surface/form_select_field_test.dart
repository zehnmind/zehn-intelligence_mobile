import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zehn_intelligence/src/server/surface/form_draft.dart';

import 'package:zehn_intelligence/src/server/surface/surface.dart';
import 'package:zehn_intelligence/src/server/surface/surface_view.dart';

import '../../support/form_cards.dart';
import '../../support/form_pump.dart';

List<Map<String, Object?>> pick(Map<String, Object?> more) => [
  {
    'id': 'root',
    'component': 'Column',
    'children': ['city', 'send'],
  },
  {
    'id': 'city',
    'component': 'Select',
    'field': 'city',
    'label': 'City',
    ...more,
    'options': [
      {
        'value': 'tashkent',
        'label': {'uz': 'Toshkent', 'en': 'Tashkent'},
      },
      {'value': 'samarkand', 'label': 'Samarkand'},
      {'value': 'bukhara', 'label': 'Bukhara'},
    ],
  },
  {
    'id': 'send',
    'component': 'Button',
    'label': 'OK',
    'action': {'name': 'submit'},
  },
];

Finder option(String value) => find.byKey(ValueKey('zi-option-$value'));

void main() {
  testWidgets('dropdown: Choose, then a list in a sheet; a tap picks and closes it', (tester) async {
    final p = await pumpForm(tester, pick(const {}));
    expect(option('tashkent'), findsNothing);
    await tester.tap(find.text('Choose'));
    await tester.pumpAndSettle();
    await tester.tap(option('samarkand'));
    await tester.pumpAndSettle();
    expect(p.draft.raw['city'], 'samarkand');
    expect(option('samarkand'), findsNothing);
    expect(find.text('Samarkand'), findsOneWidget);
  });

  testWidgets("dropdown, multiple: taps add and remove; the list is in the options' order", (tester) async {
    final p = await pumpForm(tester, pick({'multiple': true, 'placeholder': 'Any city'}));
    await tester.tap(find.text('Any city'));
    await tester.pumpAndSettle();
    await tester.tap(option('bukhara'));
    await tester.tap(option('tashkent'));
    await tester.pump();
    expect(p.draft.raw['city'], ['tashkent', 'bukhara']);
    await tester.tap(option('bukhara'));
    await tester.pump();
    expect(p.draft.raw['city'], ['tashkent']);
  });

  testWidgets('list: every option is a row in the card; a tap on the picked one clears it', (tester) async {
    final p = await pumpForm(tester, pick({'look': 'list'}), language: 'uz');
    expect(find.text('Toshkent'), findsOneWidget);
    await tester.tap(option('tashkent'));
    await tester.pump();
    expect(p.draft.raw['city'], 'tashkent');
    await tester.tap(option('tashkent'));
    await tester.pump();
    expect(p.draft.raw.containsKey('city'), isFalse);
  });

  testWidgets('chips, multiple, with how many to pick', (tester) async {
    final p = await pumpForm(
      tester,
      pick({
        'look': 'chips',
        'multiple': true,
        'checks': [
          {'rule': 'items', 'min': 2},
        ],
      }),
    );
    await tester.tap(option('bukhara'));
    await tester.tap(find.byKey(const ValueKey('zi-form-send')));
    await tester.pumpAndSettle();
    expect(p.sent, 0);
    expect(tester.widget<Text>(find.byKey(const ValueKey('zi-error-city'))).data, 'Choose at least 2');
  });

  testWidgets('a chip is 40 px tall to look at; what takes its tap is 48 px high', (tester) async {
    final p = await pumpForm(tester, pick({'look': 'chips'}));
    final chip = tester.getRect(option('bukhara'));
    expect(chip.height, 40);
    await tester.tapAt(Offset(chip.center.dx, chip.top - 3));
    await tester.pump();
    expect(p.draft.raw['city'], 'bukhara');
    await tester.tapAt(Offset(chip.center.dx, chip.bottom + 3));
    await tester.pump();
    expect(p.draft.raw.containsKey('city'), isFalse);
  });

  testWidgets('the dropdown sheet closing does not give the focus, and the keyboard, back to a text field', (
    tester,
  ) async {
    await pumpForm(tester, [
      {
        'id': 'root',
        'component': 'Column',
        'children': ['name', 'city'],
      },
      {'id': 'name', 'component': 'TextField', 'field': 'name', 'label': 'Name'},
      ...pick(const {}).where((c) => c['id'] == 'city'),
    ]);
    await tester.tap(editable('name'));
    await tester.pump();
    expect(tester.testTextInput.isVisible, isTrue);
    await tester.tap(find.text('Choose'));
    await tester.pumpAndSettle();
    await tester.tap(option('samarkand'));
    await tester.pumpAndSettle();
    expect(tester.widget<EditableText>(editable('name')).focusNode.hasFocus, isFalse);
    expect(tester.testTextInput.isVisible, isFalse);
  });

  testWidgets('read-only: the picked labels, or —; sending takes no tap', (tester) async {
    final p = await pumpForm(
      tester,
      pick({'look': 'chips', 'multiple': true}),
      prefill: {
        'city': ['tashkent', 'samarkand'],
      },
      status: ZiFormStatus.sending,
    );
    await tester.tap(option('bukhara'));
    expect(p.draft.raw['city'], ['tashkent', 'samarkand']);
    await pumpForm(tester, pick({'look': 'chips', 'multiple': true}), draft: p.draft, status: ZiFormStatus.submitted);
    expect(find.text('Tashkent, Samarkand'), findsOneWidget);
  });

  testWidgets('a single dropdown: a tap on the picked option clears it and closes the sheet', (tester) async {
    final p = await pumpForm(tester, pick(const {}), prefill: {'city': 'bukhara'});
    await tester.tap(find.text('Bukhara'));
    await tester.pumpAndSettle();
    await tester.tap(option('bukhara'));
    await tester.pumpAndSettle();
    expect(p.draft.raw.containsKey('city'), isFalse);
    expect(option('bukhara'), findsNothing);
  });

  testWidgets('a screen reader hears the dropdown as its label and what it shows', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpForm(tester, pick(const {}), prefill: {'city': 'bukhara'});
    final node = tester.getSemantics(find.text('Bukhara'));
    expect(node.label, 'City');
    expect(node.value, contains('Bukhara'));
    await pumpForm(tester, pick(const {}));
    expect(tester.getSemantics(find.text('Choose')).value, contains('Choose'));
    handle.dispose();
  });

  testWidgets('a screen reader hears each option row and chip as a button that says whether it is picked', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    // A single dropdown's rows look like radio buttons.
    await pumpForm(tester, pick(const {}), prefill: {'city': 'bukhara'});
    await tester.tap(find.text('Bukhara'));
    await tester.pumpAndSettle();
    expect(tester.getSemantics(option('bukhara')), isSemantics(isButton: true, hasCheckedState: true, isChecked: true));
    expect(tester.getSemantics(option('samarkand')), isSemantics(isButton: true, hasCheckedState: true, isChecked: false));
    Navigator.of(tester.element(option('bukhara'))).pop();
    await tester.pumpAndSettle();
    // Several rows look like checkboxes.
    await pumpForm(tester, pick({'look': 'list', 'multiple': true}), prefill: {'city': ['bukhara']});
    expect(tester.getSemantics(option('bukhara')), isSemantics(isButton: true, hasCheckedState: true, isChecked: true));
    expect(tester.getSemantics(option('tashkent')), isSemantics(isButton: true, hasCheckedState: true, isChecked: false));
    // One chip is selected; several chips are checked.
    await pumpForm(tester, pick({'look': 'chips'}), prefill: {'city': 'bukhara'});
    expect(tester.getSemantics(option('bukhara')), isSemantics(isButton: true, hasSelectedState: true, isSelected: true));
    expect(tester.getSemantics(option('tashkent')), isSemantics(isButton: true, hasSelectedState: true, isSelected: false));
    await pumpForm(tester, pick({'look': 'chips', 'multiple': true}), prefill: {'city': ['bukhara']});
    expect(tester.getSemantics(option('bukhara')), isSemantics(isButton: true, hasCheckedState: true, isChecked: true));
    expect(tester.getSemantics(option('tashkent')), isSemantics(isButton: true, hasCheckedState: true, isChecked: false));
    handle.dispose();
  });

  testWidgets('the form is locked while the dropdown sheet is open: the sheet closes and the draft stays', (
    tester,
  ) async {
    final p = await pumpForm(
      tester,
      pick({'multiple': true}),
      prefill: {
        'city': ['tashkent'],
      },
    );
    await tester.tap(find.text('Tashkent'));
    await tester.pumpAndSettle();
    expect(option('bukhara'), findsOneWidget);
    await pumpForm(tester, pick({'multiple': true}), draft: p.draft, status: ZiFormStatus.dismissed);
    await tester.pump();
    await tester.pumpAndSettle();
    expect(option('bukhara'), findsNothing);
    expect(p.draft.raw['city'], ['tashkent']);
  });

  testWidgets('the card goes while the dropdown sheet is open: the sheet closes, the page stays, nothing throws', (
    tester,
  ) async {
    final surface = card(pick(const {}));
    final draft = ZiFormDraft(surface);
    final body = ValueNotifier<Widget>(
      ZiSurfaceView(
        surface: surface,
        data: const {},
        theme: const ZiTheme({}),
        language: 'en',
        onAction: (_) {},
        form: ZiFormScope(formId: 'f1', draft: draft, onSubmit: () {}),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ValueListenableBuilder<Widget>(valueListenable: body, builder: (_, w, _) => w),
        ),
      ),
    );
    await tester.tap(find.text('Choose'));
    await tester.pumpAndSettle();
    expect(option('bukhara'), findsOneWidget);
    body.value = const SizedBox();
    await tester.pump();
    await tester.pumpAndSettle();
    expect(option('bukhara'), findsNothing);
    expect(find.byType(Scaffold), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
