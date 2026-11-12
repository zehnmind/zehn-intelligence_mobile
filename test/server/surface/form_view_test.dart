import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zehn_intelligence/src/server/surface/form_draft.dart';
import 'package:zehn_intelligence/src/server/surface/surface.dart';
import 'package:zehn_intelligence/src/server/surface/surface_view.dart';

import '../../support/form_cards.dart';
import '../../support/form_pump.dart';

const greet = [
  {'id': 'root', 'component': 'Column', 'children': ['hello', 'extra', 'send']},
  {'id': 'hello', 'component': 'Text', 'text': 'Hello, {/form/name}'},
  {'id': 'extra', 'component': 'Text', 'text': 'Tell us more', 'visible': {'path': '/form/reason', 'equals': 'other'}},
  {'id': 'send', 'component': 'Button', 'label': 'Book', 'action': {'name': 'submit'}},
];

void main() {
  testWidgets('with nothing typed, /form reads as empty', (tester) async {
    await pumpForm(tester, greet);
    expect(find.text('Hello, '), findsOneWidget);
    expect(find.text('Tell us more'), findsNothing);
  });
  testWidgets('Send calls the form, not onAction; busy and sending take no tap', (tester) async {
    final p = await pumpForm(tester, greet);
    await tester.tap(find.byKey(const ValueKey('zi-form-send')));
    expect(p.sent, 1);
    expect(p.actions, isEmpty);
    final busy = await pumpForm(tester, greet, draft: p.draft, busy: true);
    await tester.tap(find.byKey(const ValueKey('zi-form-send')));
    expect(busy.sent, 0);
    await pumpForm(tester, greet, draft: p.draft, status: ZiFormStatus.sending);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Book'), findsNothing);
  });
  testWidgets('a sent form says Sent and a dismissed one Not answered, in place of the button', (tester) async {
    final p = await pumpForm(tester, greet, status: ZiFormStatus.submitted, language: 'ru');
    expect(find.byKey(const ValueKey('zi-form-send')), findsNothing);
    expect(tester.widget<Text>(find.byKey(const ValueKey('zi-form-status'))).data, 'Отправлено');
    await pumpForm(tester, greet, draft: p.draft, status: ZiFormStatus.dismissed);
    expect(find.text('Not answered'), findsOneWidget);
  });
  testWidgets('a failed send says so under the button, in the error colour', (tester) async {
    final p = await pumpForm(tester, greet, theme: {'colors': {'error': '#FF112233'}});
    p.draft.markNotSent(true);
    await tester.pump();
    final line = tester.widget<Text>(find.byKey(const ValueKey('zi-form-not-sent')));
    expect((line.data, line.style!.color), ('Not sent. Try again.', const Color(0xFF112233)));
  });
  testWidgets('drawn without a form, the submit button draws nothing', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: ZiSurfaceView(
        surface: card(greet), data: const {'form': {'name': 'Ali'}}, theme: const ZiTheme({}), language: 'en', onAction: (_) {}))));
    expect(find.text('Hello, Ali'), findsOneWidget);
    expect(find.text('Book'), findsNothing);
  });
  testWidgets('a button is announced as a button', (tester) async {
    await pumpForm(tester, greet);
    expect(find.byWidgetPredicate((w) => w is Semantics && w.properties.button == true), findsOneWidget);
  });
  test('ziDraws is false for a block this build has no widget for', () {
    expect(ziDraws(card(greet)), isTrue);
    expect(ziDraws(card([{'id': 'root', 'component': 'Slider'}])), isFalse);
  });
}
