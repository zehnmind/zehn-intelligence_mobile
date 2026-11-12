import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zehn_intelligence/src/server/surface/form_draft.dart';
import 'package:zehn_intelligence/src/server/surface/surface.dart';
import 'package:zehn_intelligence/src/server/surface/surface_view.dart';

import 'form_cards.dart';

class Pumped {
  Pumped(this.draft);
  final ZiFormDraft draft;

  /// Send taps that passed the checks.
  int sent = 0;
  final actions = <ZiSurfaceAction>[];
}

/// Pumps one card as form `f1` in a scrolling page, top-left of the screen. Pass [draft] to
/// draw the same form again in another [status].
Future<Pumped> pumpForm(
  WidgetTester tester,
  List<Map<String, Object?>> components, {
  Map<String, Object?> prefill = const {},
  ZiFormStatus status = ZiFormStatus.pending,
  bool busy = false,
  String language = 'en',
  Map<String, Object?> theme = const {},
  DateTime Function()? today,
  ZiFormDraft? draft,
}) async {
  final surface = card(components);
  final pumped = Pumped(draft ?? ZiFormDraft(surface, prefill: prefill, today: today));
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SingleChildScrollView(
            child: ZiSurfaceView(
              surface: surface,
              data: const {},
              theme: ZiTheme(theme),
              language: language,
              onAction: pumped.actions.add,
              form: ZiFormScope(
                formId: 'f1',
                draft: pumped.draft,
                status: status,
                busy: busy,
                onSubmit: () {
                  if (pumped.draft.check()) pumped.sent++;
                },
              ),
            ),
          ),
        ),
      ),
    ),
  );
  return pumped;
}

Finder field(String blockId) => find.byKey(ValueKey('zi-field-f1-$blockId'));
Finder editable(String blockId) => find.descendant(of: field(blockId), matching: find.byType(EditableText));
