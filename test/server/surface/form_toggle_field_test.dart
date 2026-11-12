import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zehn_intelligence/src/server/surface/form_draft.dart';

import '../../support/form_pump.dart';

const terms = [
  {
    'id': 'root',
    'component': 'Column',
    'children': ['agree', 'news', 'more', 'send'],
  },
  {
    'id': 'agree',
    'component': 'Checkbox',
    'field': 'agree',
    'label': 'I agree',
    'checks': [
      {'rule': 'required'},
    ],
  },
  {'id': 'news', 'component': 'Switch', 'field': 'news', 'label': 'Send me news', 'hint': 'Once a month'},
  {
    'id': 'more',
    'component': 'Text',
    'text': 'We will write to you',
    'visible': {'path': '/form/news'},
  },
  {
    'id': 'send',
    'component': 'Button',
    'label': 'OK',
    'action': {'name': 'submit'},
  },
];

void main() {
  testWidgets('a tap anywhere on the row flips the value, and blocks that read it follow', (tester) async {
    final p = await pumpForm(tester, terms);
    expect(p.draft.raw, {'agree': false, 'news': false});
    expect(find.text('We will write to you'), findsNothing);
    await tester.tap(find.text('Send me news'));
    await tester.pump();
    expect(p.draft.raw['news'], isTrue);
    expect(find.text('We will write to you'), findsOneWidget);
    expect(find.descendant(of: field('agree'), matching: find.byType(Checkbox)), findsOneWidget);
    expect(find.descendant(of: field('news'), matching: find.byType(Switch)), findsOneWidget);
  });

  testWidgets('a required box that is not ticked stops Send', (tester) async {
    final p = await pumpForm(tester, terms);
    await tester.tap(find.byKey(const ValueKey('zi-form-send')));
    await tester.pumpAndSettle();
    expect(p.sent, 0);
    expect(tester.widget<Text>(find.byKey(const ValueKey('zi-error-agree'))).data, 'Fill this in');
  });

  testWidgets('rows are 48 px tall or more and named for a screen reader', (tester) async {
    await pumpForm(tester, terms);
    expect(tester.getSize(field('agree')).height, greaterThanOrEqualTo(48));
    expect(find.byWidgetPredicate((w) => w is Semantics && w.properties.label == 'I agree'), findsOneWidget);
  });

  testWidgets('read-only: the label, then ✓ or —; sending takes no tap', (tester) async {
    final p = await pumpForm(tester, terms, prefill: {'agree': true}, status: ZiFormStatus.sending);
    await tester.tap(find.text('Send me news'));
    expect(p.draft.raw['news'], isFalse);
    await pumpForm(tester, terms, draft: p.draft, status: ZiFormStatus.submitted);
    expect(find.byType(Checkbox), findsNothing);
    expect(find.text('✓'), findsOneWidget);
    expect(find.text('—'), findsOneWidget);
  });
}
