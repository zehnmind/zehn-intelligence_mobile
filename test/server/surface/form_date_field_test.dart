import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zehn_intelligence/src/server/surface/form_draft.dart';
import 'package:zehn_intelligence/src/server/surface/surface.dart';
import 'package:zehn_intelligence/src/server/surface/surface_view.dart';

import '../../support/form_cards.dart';
import '../../support/form_pump.dart';

DateTime day() => DateTime(2026, 11, 12);

List<Map<String, Object?>> when(Map<String, Object?> more) => [
  {
    'id': 'root',
    'component': 'Column',
    'children': ['date'],
  },
  {'id': 'date', 'component': 'DateField', 'field': 'date', 'label': 'Date', ...more},
];

DatePickerDialog dialog(WidgetTester tester) => tester.widget(find.byType(DatePickerDialog));

void main() {
  testWidgets('Choose when empty; the calendar opens on today inside the bounds; OK keeps the day', (tester) async {
    final p = await pumpForm(tester, when({'min': 'today', 'max': '2026-12-31'}), today: day);
    await tester.tap(find.text('Choose'));
    await tester.pumpAndSettle();
    expect(
      (dialog(tester).firstDate, dialog(tester).lastDate, dialog(tester).initialDate),
      (DateTime(2026, 11, 12), DateTime(2026, 12, 31), DateTime(2026, 11, 12)),
    );
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(p.draft.raw['date'], '2026-11-12');
    expect(find.text('Nov 12'), findsOneWidget);
  });

  testWidgets('bounds that leave today out, or a min after the max, open without an error', (tester) async {
    await pumpForm(tester, when({'min': '2030-01-01'}), today: day);
    await tester.tap(find.text('Choose'));
    await tester.pumpAndSettle();
    expect(dialog(tester).initialDate, DateTime(2030));
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await pumpForm(tester, when({'min': '2030-01-01', 'max': '2029-01-01'}), today: day);
    await tester.tap(find.text('Choose'));
    await tester.pumpAndSettle();
    expect((dialog(tester).firstDate, dialog(tester).lastDate), (DateTime(2030), DateTime(2100)));
    expect(tester.takeException(), isNull);
  });

  testWidgets('the date reads in the language; read-only is the label and the date', (tester) async {
    final p = await pumpForm(tester, when(const {}), prefill: {'date': '2026-11-14'}, language: 'uz', today: day);
    expect(find.text('14-noyabr'), findsOneWidget);
    await pumpForm(tester, when(const {}), draft: p.draft, status: ZiFormStatus.submitted, language: 'ru');
    expect(find.text('14 ноября'), findsOneWidget);
  });

  testWidgets('the form leaves pending while the calendar is open: the calendar closes and the draft stays', (
    tester,
  ) async {
    final p = await pumpForm(tester, when(const {}), prefill: {'date': '2026-11-14'}, today: day);
    await tester.tap(find.text('Nov 14'));
    await tester.pumpAndSettle();
    expect(find.byType(DatePickerDialog), findsOneWidget);
    await pumpForm(tester, when(const {}), draft: p.draft, status: ZiFormStatus.dismissed);
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.byType(DatePickerDialog), findsNothing);
    expect(p.draft.raw['date'], '2026-11-14');
    expect(find.byType(Scaffold), findsOneWidget);
  });

  testWidgets('the card goes while the calendar is open: the calendar closes, the page stays, nothing throws', (
    tester,
  ) async {
    final surface = card(when(const {}));
    final draft = ZiFormDraft(surface, today: day);
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
    expect(find.byType(DatePickerDialog), findsOneWidget);
    body.value = const SizedBox();
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.byType(DatePickerDialog), findsNothing);
    expect(find.byType(Scaffold), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(draft.raw.containsKey('date'), isFalse);
  });
}
