import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zehn_intelligence/src/server/surface/surface.dart';
import 'package:zehn_intelligence/src/server/surface/surface_view.dart';

Map<String, Object?> surfaceJson(List<Map<String, Object?>> components) => {
  'createSurface': {'surfaceId': 's', 'catalogId': 'zehn.basic.v0', 'root': 'root', 'components': components},
};

Future<List<ZiSurfaceAction>> pump(
  WidgetTester tester,
  List<Map<String, Object?>> components, {
  Object? data,
  String language = 'uz',
}) async {
  final actions = <ZiSurfaceAction>[];
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: ZiSurfaceView(
        surface: ZiSurface.parse(surfaceJson(components)),
        data: data,
        theme: const ZiTheme({}),
        language: language,
        onAction: actions.add,
      ),
    ),
  ));
  return actions;
}

void main() {
  testWidgets('draws text from a data path in the chosen language', (tester) async {
    await pump(tester, [
      {'id': 'root', 'component': 'Text', 'text': {'path': '/cinema/category'}},
    ], data: {
      'cinema': {
        'category': {'uz': 'Kinoteatr', 'ru': 'Кинотеатр', 'en': 'Cinema'},
      },
    }, language: 'ru');
    expect(find.text('Кинотеатр'), findsOneWidget);
  });

  testWidgets('a language map literal picks the language', (tester) async {
    await pump(tester, [
      {'id': 'root', 'component': 'Text', 'text': {'uz': 'Salom', 'ru': 'Привет', 'en': 'Hi'}},
    ], language: 'en');
    expect(find.text('Hi'), findsOneWidget);
  });

  testWidgets('fills {/path} placeholders', (tester) async {
    await pump(tester, [
      {'id': 'root', 'component': 'Chip', 'text': {'uz': '{/floor}-qavat', 'en': 'Floor {/floor}'}},
    ], data: {'floor': '4'});
    expect(find.text('4-qavat'), findsOneWidget);
  });

  testWidgets('a placeholder can name a format', (tester) async {
    await pump(tester, [
      {'id': 'root', 'component': 'Column', 'children': ['hours', 'price', 'odd']},
      {'id': 'hours', 'component': 'Text', 'text': '{/start|time} – {/end|time}'},
      {'id': 'price', 'component': 'Text', 'text': '{/price|money:UZS}/soat'},
      {'id': 'odd', 'component': 'Text', 'text': '{/price|shout}'},
    ], data: {'start': '2026-11-10T12:30:00', 'end': '2026-11-10T14:00:00', 'price': 10000});
    expect(find.text('12:30 – 14:00'), findsOneWidget);
    expect(find.text('10\u00a0000\u00a0UZS/soat'), findsOneWidget);
    expect(find.text('10000'), findsOneWidget);
  });

  testWidgets('a path value can name a format', (tester) async {
    await pump(tester, [
      {'id': 'root', 'component': 'Text', 'text': {'path': '/price', 'format': 'money:UZS'}},
    ], data: {'price': '10000'}, language: 'en');
    expect(find.text('10,000\u00a0UZS'), findsOneWidget);
  });

  testWidgets('the icons added for 0.5.0 draw', (tester) async {
    const expected = {
      'car': Icons.directions_car_outlined,
      'store': Icons.storefront_outlined,
      'calendar': Icons.calendar_today_outlined,
      'wallet': Icons.account_balance_wallet_outlined,
      'person': Icons.person_outline,
      'restaurant': Icons.restaurant,
      'bus': Icons.directions_bus_outlined,
      'gift': Icons.card_giftcard,
    };
    for (final e in expected.entries) {
      await pump(tester, [
        {'id': 'root', 'component': 'Chip', 'text': 'x', 'icon': e.key},
      ]);
      expect(find.byIcon(e.value), findsOneWidget, reason: e.key);
    }
  });

  testWidgets('repeats a template over a list with relative paths', (tester) async {
    await pump(tester, [
      {'id': 'root', 'component': 'Column', 'children': {'componentId': 'row', 'path': '/movies'}},
      {'id': 'row', 'component': 'Text', 'text': {'path': 'title'}},
    ], data: {
      'movies': [
        {'title': 'Michael'},
        {'title': 'F1'},
      ],
    });
    expect(find.text('Michael'), findsOneWidget);
    expect(find.text('F1'), findsOneWidget);
  });

  testWidgets('hides a component whose visible path is empty', (tester) async {
    await pump(tester, [
      {'id': 'root', 'component': 'Column', 'children': ['a', 'b']},
      {'id': 'a', 'component': 'Text', 'text': 'shown'},
      {'id': 'b', 'component': 'Text', 'text': 'hidden', 'visible': {'path': '/missing'}},
    ], data: {});
    expect(find.text('shown'), findsOneWidget);
    expect(find.text('hidden'), findsNothing);
  });

  testWidgets('button sends open_route with an arg named path intact', (tester) async {
    final actions = await pump(tester, [
      {
        'id': 'root',
        'component': 'Button',
        'label': 'Go',
        'action': {
          'name': 'open_route',
          'args': {'path': '/x', 'route': '/cinema/{/id}', 'id': {'path': '/id'}},
        },
      },
    ], data: {'id': 7});
    await tester.tap(find.text('Go'));
    expect(actions.single.name, 'open_route');
    expect(actions.single.args, {'path': '/x', 'route': '/cinema/7', 'id': 7});
  });

  testWidgets('ask and open_url are passed on', (tester) async {
    final actions = await pump(tester, [
      {'id': 'root', 'component': 'Column', 'children': ['a', 'b']},
      {'id': 'a', 'component': 'InfoRow', 'text': 'Call', 'action': {'name': 'open_url', 'args': {'url': 'tel:1'}}},
      {'id': 'b', 'component': 'Header', 'title': 'More', 'action': {'name': 'ask', 'args': {'text': 'More?'}}},
    ]);
    await tester.tap(find.text('Call'));
    await tester.tap(find.text('More'));
    expect(actions.map((a) => a.name), ['open_url', 'ask']);
  });

  testWidgets('run_js action is not passed on', (tester) async {
    final actions = await pump(tester, [
      {'id': 'root', 'component': 'Button', 'label': 'Run', 'action': {'name': 'run_js', 'args': {'code': 'x'}}},
    ]);
    await tester.tap(find.text('Run'));
    expect(actions, isEmpty);
  });

  testWidgets('unknown component shows a note in debug builds', (tester) async {
    await pump(tester, [
      {'id': 'root', 'component': 'Column', 'children': ['a', 'gone']},
      {'id': 'a', 'component': 'WebView', 'url': 'https://evil.example'},
    ]);
    expect(find.textContaining('not in catalog'), findsOneWidget);
    expect(find.textContaining('No component "gone"'), findsOneWidget);
  });

  test('parse rejects a surface without its root', () {
    expect(
      () => ZiSurface.parse(surfaceJson([{'id': 'a', 'component': 'Text'}])),
      throwsFormatException,
    );
  });

  test('theme colors parse #RRGGBB and #AARRGGBB', () {
    expect(parseColor('#BE7C6C'), const Color(0xFFBE7C6C));
    expect(parseColor('#99FFFFFF'), const Color(0x99FFFFFF));
    expect(parseColor('red'), isNull);
  });
}
