import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zehn_intelligence/src/server/surface/form_draft.dart';
import 'package:zehn_intelligence/src/server/surface/surface.dart';
import 'package:zehn_intelligence/src/server/surface/surface_view.dart';

import '../../support/form_cards.dart';
import '../../support/form_pump.dart';

const two = [
  {
    'id': 'root',
    'component': 'Column',
    'gap': 12,
    'children': ['hello', 'name', 'mail', 'send'],
  },
  {'id': 'hello', 'component': 'Text', 'text': 'Hello, {/form/name}'},
  {
    'id': 'name',
    'component': 'TextField',
    'field': 'name',
    'label': 'Your name',
    'hint': 'As in your passport',
    'placeholder': 'Ali Valiyev',
    'maxLength': 20,
    'checks': [
      {
        'rule': 'required',
        'message': {'en': 'Tell us your name'},
      },
    ],
  },
  {'id': 'mail', 'component': 'TextField', 'field': 'mail', 'label': 'Email', 'input': 'email'},
  {
    'id': 'send',
    'component': 'Button',
    'label': 'Book',
    'action': {'name': 'submit'},
  },
];

void main() {
  testWidgets('label above, placeholder inside, hint under; typing reaches the draft and other blocks', (tester) async {
    final p = await pumpForm(tester, two);
    expect(find.text('Your name'), findsOneWidget);
    expect(find.text('Ali Valiyev'), findsOneWidget);
    expect(find.text('As in your passport'), findsOneWidget);
    await tester.enterText(editable('name'), ' Ali ');
    await tester.pump();
    expect(p.draft.raw['name'], ' Ali ');
    expect(p.draft.values['name'], 'Ali');
    expect(find.text('Hello, Ali'), findsOneWidget);
  });

  testWidgets('the keyboard matches input; Next on every text field but the last, Done on the last', (tester) async {
    await pumpForm(tester, two);
    TextField box(String id) => tester.widget(find.descendant(of: field(id), matching: find.byType(TextField)));
    expect(box('name').keyboardType, TextInputType.text);
    expect(box('name').textInputAction, TextInputAction.next);
    expect(box('mail').keyboardType, TextInputType.emailAddress);
    expect(box('mail').textInputAction, TextInputAction.done);
    await tester.enterText(editable('name'), 'a' * 30);
    expect(tester.widget<EditableText>(editable('name')).controller.text, hasLength(20));
  });

  testWidgets('number, phone and multiline', (tester) async {
    await pumpForm(tester, [
      {
        'id': 'root',
        'component': 'Column',
        'children': ['n', 'p', 'm'],
      },
      {'id': 'n', 'component': 'TextField', 'field': 'n', 'label': 'N', 'input': 'number'},
      {'id': 'p', 'component': 'TextField', 'field': 'p', 'label': 'P', 'input': 'phone'},
      {'id': 'm', 'component': 'TextField', 'field': 'm', 'label': 'M', 'input': 'multiline'},
    ]);
    TextField box(String id) => tester.widget(find.descendant(of: field(id), matching: find.byType(TextField)));
    expect(box('n').keyboardType, const TextInputType.numberWithOptions(decimal: true, signed: true));
    expect(box('p').keyboardType, TextInputType.phone);
    expect(
      (box('m').keyboardType, box('m').textInputAction, box('m').minLines, box('m').maxLines),
      (TextInputType.multiline, TextInputAction.newline, 3, 6),
    );
  });

  testWidgets('an error shows under the field once it was left, in place of the hint, and goes when fixed', (
    tester,
  ) async {
    await pumpForm(tester, two);
    await tester.enterText(editable('mail'), 'ali@');
    await tester.pump();
    expect(find.byKey(const ValueKey('zi-error-mail')), findsNothing);
    await tester.tap(editable('name')); // leaves the email field
    await tester.pump();
    expect(tester.widget<Text>(find.byKey(const ValueKey('zi-error-mail'))).data, 'Enter an email address');
    await tester.enterText(editable('mail'), 'ali@example.uz');
    await tester.pump();
    expect(find.byKey(const ValueKey('zi-error-mail')), findsNothing);
  });

  testWidgets("a failed Send sends nothing, shows the check's own message and focuses the first failing field", (
    tester,
  ) async {
    final p = await pumpForm(tester, two);
    await tester.tap(find.byKey(const ValueKey('zi-form-send')));
    await tester.pumpAndSettle();
    expect(p.sent, 0);
    expect(find.text('Tell us your name'), findsOneWidget);
    expect(find.text('As in your passport'), findsNothing);
    expect(tester.widget<EditableText>(editable('name')).focusNode.hasFocus, isTrue);
  });

  testWidgets('sending turns the fields off; sent shows label and value as text, "—" when empty', (tester) async {
    final p = await pumpForm(tester, two, prefill: {'name': 'Ali'}, status: ZiFormStatus.sending);
    expect(
      tester.widget<TextField>(find.descendant(of: field('name'), matching: find.byType(TextField))).enabled,
      isFalse,
    );
    await pumpForm(tester, two, draft: p.draft, status: ZiFormStatus.submitted);
    expect(find.byType(TextField), findsNothing);
    expect(find.text('Your name'), findsOneWidget);
    expect(find.text('Ali'), findsOneWidget);
    expect(find.text('—'), findsOneWidget); // the email
  });

  testWidgets('a field is at least 48 px tall, named for a screen reader, and survives double-size text', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pumpForm(tester, two);
    expect(
      tester.getSize(find.descendant(of: field('name'), matching: find.byType(TextField))).height,
      greaterThanOrEqualTo(48),
    );
    expect(find.byWidgetPredicate((w) => w is Semantics && w.properties.label == 'Your name'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('drawn without a form, a field is its label and the value in the data', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ZiSurfaceView(
            surface: card(two),
            data: const {
              'form': {'name': 'Ali'},
            },
            theme: const ZiTheme({}),
            language: 'en',
            onAction: (_) {},
          ),
        ),
      ),
    );
    expect(find.byType(TextField), findsNothing);
    expect(find.text('Ali'), findsOneWidget);
  });

  group('a field keeps its State when a sibling before it comes and goes', () {
    List<Map<String, Object?>> shown(String parent, Map<String, Object?> extra) => [
      {
        'id': 'root',
        'component': parent,
        'children': ['a', 'b'],
      },
      {
        'id': 'a',
        'component': 'TextField',
        'field': 'a',
        'label': 'A',
        'visible': {'path': '/form/b'},
        ...extra,
      },
      {'id': 'b', 'component': 'TextField', 'field': 'b', 'label': 'B', ...extra},
    ];

    Future<void> typeIntoB(WidgetTester tester, Map<String, Object?> extra, {String parent = 'Column'}) async {
      final p = await pumpForm(tester, shown(parent, extra));
      expect(field('a'), findsNothing);
      await tester.tap(editable('b'));
      await tester.enterText(editable('b'), 'x');
      await tester.pump();
      expect(field('a'), findsOneWidget);
      final box = tester.widget<EditableText>(editable('b'));
      expect(box.focusNode.hasFocus, isTrue);
      expect(box.controller.text, 'x');
      expect(box.controller.selection.baseOffset, 1);
      expect(p.draft.raw['b'], 'x');
    }

    testWidgets('padded, in a Column', (tester) => typeIntoB(tester, {'padding': 4}));
    testWidgets('with flex, in a Row', (tester) => typeIntoB(tester, {'flex': 1}, parent: 'Row'));
  });

  testWidgets('typing keeps focus and the cursor', (tester) async {
    await pumpForm(tester, two);
    await tester.tap(editable('name'));
    await tester.enterText(editable('name'), 'Ali');
    await tester.pump();
    await tester.enterText(editable('name'), 'Alis');
    await tester.pump();
    final box = tester.widget<EditableText>(editable('name'));
    expect(box.focusNode.hasFocus, isTrue);
    expect(box.controller.selection.baseOffset, 4);
  });

  testWidgets('the edit box itself carries the name and the hint for a screen reader', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpForm(tester, two);
    final node = tester.getSemantics(editable('name'));
    expect(node.flagsCollection.isTextField, isTrue);
    expect(node.label, contains('Your name'));
    handle.dispose();
  });
}
