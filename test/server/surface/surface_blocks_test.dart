import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zehn_intelligence/src/server/surface/surface.dart';
import 'package:zehn_intelligence/src/server/surface/surface_view.dart';

const _theme = {
  'colors': {'accent': '#FF0000FF', 'chip': '#FFEEEEEE', 'on_surface': '#FF111111'},
};

Future<void> pumpBlocks(WidgetTester tester, List<Map<String, Object?>> components, {Object? data}) =>
    tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: ZiSurfaceView(
            surface: ZiSurface.parse({
              'createSurface': {'surfaceId': 's', 'catalogId': 'zehn.basic.v1', 'root': 'root', 'components': components},
            }),
            data: data,
            theme: const ZiTheme(_theme),
            language: 'en',
            onAction: (_) {},
          ),
        ),
      ),
    ));

void main() {
  testWidgets('Stack: children over the first, each at its own position', (tester) async {
    await pumpBlocks(tester, [
      {'id': 'root', 'component': 'Stack', 'width': 200, 'children': ['photo', 'tag']},
      {'id': 'photo', 'component': 'Box', 'height': 100, 'color': '#FF000000'},
      {'id': 'tag', 'component': 'Text', 'text': 'NEW', 'position': 'bottom_end', 'padding': 8},
    ]);
    expect(tester.getBottomRight(find.text('NEW')), const Offset(192, 92));
  });

  testWidgets("Stack: alignment places a child that has no position; the first child's position is ignored", (tester) async {
    await pumpBlocks(tester, [
      {'id': 'root', 'component': 'Stack', 'width': 200, 'alignment': 'center', 'children': ['photo', 'tag']},
      {'id': 'photo', 'component': 'Box', 'height': 100, 'position': 'bottom_end'},
      {'id': 'tag', 'component': 'Text', 'text': 'NEW'},
    ]);
    expect(tester.getCenter(find.text('NEW')), const Offset(100, 50));
  });

  testWidgets('Wrap: blocks flow onto the next line, gap between blocks and runGap between lines', (tester) async {
    Map<String, Object?> box(String id) => {'id': id, 'component': 'Box', 'width': 40, 'height': 20, 'child': '${id}t'};
    await pumpBlocks(tester, [
      {'id': 'root', 'component': 'Wrap', 'width': 100, 'gap': 8, 'runGap': 6, 'children': ['a', 'b', 'c']},
      for (final id in ['a', 'b', 'c']) ...[box(id), {'id': '${id}t', 'component': 'Text', 'text': id}],
    ]);
    expect(tester.getTopLeft(find.text('b')), const Offset(48, 0));
    expect(tester.getTopLeft(find.text('c')), const Offset(0, 26));
  });

  testWidgets('Wrap: runGap is gap when not set', (tester) async {
    Map<String, Object?> box(String id) => {'id': id, 'component': 'Box', 'width': 40, 'height': 20, 'child': '${id}t'};
    await pumpBlocks(tester, [
      {'id': 'root', 'component': 'Wrap', 'width': 100, 'gap': 8, 'children': ['a', 'b', 'c']},
      for (final id in ['a', 'b', 'c']) ...[box(id), {'id': '${id}t', 'component': 'Text', 'text': id}],
    ]);
    expect(tester.getTopLeft(find.text('c')), const Offset(0, 28));
  });

  testWidgets('Progress: a bar filled to value, held to 0..1, 6 px tall unless said', (tester) async {
    await pumpBlocks(tester, [
      {'id': 'root', 'component': 'Progress', 'value': {'path': '/done'}},
    ], data: {'done': 0.4});
    final bar = tester.widget<FractionallySizedBox>(find.byType(FractionallySizedBox));
    expect(bar.widthFactor, 0.4);
    expect(tester.getSize(find.byType(FractionallySizedBox)).height, 6);
    await pumpBlocks(tester, [
      {'id': 'root', 'component': 'Progress', 'value': 7, 'height': 100},
    ]);
    expect(tester.widget<FractionallySizedBox>(find.byType(FractionallySizedBox)).widthFactor, 1);
    expect(tester.getSize(find.byType(FractionallySizedBox)).height, 40);
  });

  testWidgets('Avatar: a circle; with no image, the first two letters of text', (tester) async {
    await pumpBlocks(tester, [
      {'id': 'root', 'component': 'Avatar', 'text': ' cinematica', 'size': 48},
    ]);
    expect(find.text('CI'), findsOneWidget);
    expect(tester.getSize(find.byType(ClipOval)), const Size(48, 48));
    await pumpBlocks(tester, [
      {'id': 'root', 'component': 'Avatar'},
    ]);
    expect(tester.getSize(find.byType(ClipOval)), const Size(40, 40));
  });
}
