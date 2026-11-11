import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zehn_intelligence/src/server/surface/surface.dart';
import 'package:zehn_intelligence/src/server/surface/surface_view.dart';

/// The vocabulary that lets a template look like an app's own widgets: padding, shadow, alignment,
/// justify, text overrides, spans, icons, image fit and repeat separators.
const _theme = {
  'font': 'CeraPro',
  'colors': {'accent': '#FFBE7C6C', 'on_surface': '#FF111111', 'muted': '#FF777777'},
  'text': {
    'body': {'size': 15, 'weight': 400, 'height': 1.4, 'letterSpacing': -0.01},
    'title': {'size': 17, 'weight': 500, 'height': 1.25},
  },
};

Future<void> pumpSurface(
  WidgetTester tester,
  List<Map<String, Object?>> components, {
  Object? data,
  String language = 'en',
}) => tester.pumpWidget(MaterialApp(
  home: Scaffold(
    body: Align(
      alignment: Alignment.topLeft,
      child: ZiSurfaceView(
        surface: ZiSurface.parse({
          'createSurface': {'surfaceId': 's', 'catalogId': 'zehn.basic.v0', 'root': 'root', 'components': components},
        }),
        data: data,
        theme: const ZiTheme(_theme),
        language: language,
        onAction: (_) {},
      ),
    ),
  ),
));

TextStyle styleOf(WidgetTester tester, String text) => tester.widget<Text>(find.text(text)).style!;

void main() {
  tearDown(ziCustomIcons.clear);

  group('padding', () {
    testWidgets('a number pads every side, an object each side or an axis', (tester) async {
      await pumpSurface(tester, [
        {'id': 'root', 'component': 'Column', 'children': ['a', 'b']},
        {'id': 'a', 'component': 'Text', 'text': 'a', 'padding': 10},
        {'id': 'b', 'component': 'Text', 'text': 'b', 'padding': {'x': 4, 'y': 6, 'left': 20, 'bottom': 1}},
      ]);
      final a = tester.getTopLeft(find.text('a'));
      expect((a.dx, a.dy), (10, 10));
      final b = tester.getTopLeft(find.text('b'));
      expect(b.dx, 20); // left beats x
      expect(b.dy, tester.getBottomLeft(find.text('a')).dy + 10 + 6); // a's bottom pad, then b's top
      // b's height: its text + top 6 + bottom 1
      final box = tester.getSize(find.ancestor(of: find.text('b'), matching: find.byType(Padding)).first);
      expect(box.height, tester.getSize(find.text('b')).height + 7);
    });

    testWidgets('a sideways row pads its content, not its frame', (tester) async {
      await pumpSurface(tester, [
        {'id': 'root', 'component': 'Row', 'scroll': true, 'padding': {'x': 16}, 'children': ['a']},
        {'id': 'a', 'component': 'Text', 'text': 'a'},
      ]);
      expect(tester.getTopLeft(find.text('a')).dx, 16);
      expect(find.byType(SingleChildScrollView), findsOneWidget);
      expect(tester.widget<SingleChildScrollView>(find.byType(SingleChildScrollView)).padding, const EdgeInsets.symmetric(horizontal: 16));
    });

    testWidgets('padding is inside the size, and held to a sane range', (tester) async {
      tester.view.physicalSize = const Size(800, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await pumpSurface(tester, [
        {'id': 'root', 'component': 'Column', 'children': ['a', 'b']},
        {'id': 'a', 'component': 'Text', 'text': 'a', 'padding': {'x': 10}, 'width': 100},
        {'id': 'b', 'component': 'Text', 'text': 'b', 'padding': {'left': -50, 'top': 99999}},
      ]);
      expect(tester.getSize(find.ancestor(of: find.text('a'), matching: find.byType(SizedBox)).first).width, 100);
      expect(tester.getTopLeft(find.text('b')).dx, 0);
      expect(tester.getTopLeft(find.text('b')).dy, greaterThan(1000)); // top 1000, below a
    });
  });

  group('Box', () {
    testWidgets('draws a shadow and places its child', (tester) async {
      await pumpSurface(tester, [
        {
          'id': 'root', 'component': 'Box', 'width': 100, 'height': 80, 'color': '#FFFFFFFF', 'alignment': 'center',
          'shadow': {'y': 4, 'blur': 10, 'color': '#08000000'}, 'child': 'a',
        },
        {'id': 'a', 'component': 'Text', 'text': 'a'},
      ]);
      final decoration = tester.widget<DecoratedBox>(find.byType(DecoratedBox).first).decoration as BoxDecoration;
      expect(decoration.boxShadow, [
        const BoxShadow(color: Color(0x08000000), offset: Offset(0, 4), blurRadius: 10),
      ]);
      expect(tester.getCenter(find.text('a')), tester.getCenter(find.byType(DecoratedBox).first));
    });

    testWidgets('a shadow of a token colour, with no numbers, still draws', (tester) async {
      await pumpSurface(tester, [
        {'id': 'root', 'component': 'Box', 'width': 50, 'height': 50, 'shadow': {'color': 'accent'}},
      ]);
      final decoration = tester.widget<DecoratedBox>(find.byType(DecoratedBox).first).decoration as BoxDecoration;
      expect(decoration.boxShadow!.single.color, const Color(0xFFBE7C6C));
      expect(decoration.boxShadow!.single.blurRadius, 0);
    });
  });

  group('justify', () {
    testWidgets('a row spreads its children', (tester) async {
      await pumpSurface(tester, [
        {'id': 'root', 'component': 'Box', 'width': 300, 'child': 'row'},
        {'id': 'row', 'component': 'Row', 'justify': 'space_between', 'children': ['a', 'b']},
        {'id': 'a', 'component': 'Text', 'text': 'aa'},
        {'id': 'b', 'component': 'Text', 'text': 'bb'},
      ]);
      expect(tester.getTopLeft(find.text('aa')).dx, 0);
      expect(tester.getTopRight(find.text('bb')).dx, 300);
    });

    testWidgets('a column with a height centres its children', (tester) async {
      await pumpSurface(tester, [
        {'id': 'root', 'component': 'Column', 'height': 100, 'justify': 'center', 'children': ['a']},
        {'id': 'a', 'component': 'Text', 'text': 'aa'},
      ]);
      expect(tester.getCenter(find.text('aa')).dy, 50);
    });
  });

  group('Text', () {
    testWidgets('size, weight, line height and letter spacing override the style', (tester) async {
      await pumpSurface(tester, [
        {'id': 'root', 'component': 'Text', 'text': 'x', 'style': 'body', 'size': 24, 'weight': 500, 'lineHeight': 1.3, 'letterSpacing': 0.0625},
      ]);
      final s = styleOf(tester, 'x');
      expect(s.fontSize, 24);
      expect(s.fontWeight, FontWeight.w500);
      expect(s.height, 1.3);
      expect(s.letterSpacing, closeTo(1.5, 1e-9)); // em
      expect(s.fontFamily, 'CeraPro');
    });

    testWidgets('the theme can set a letter spacing (em) for a style', (tester) async {
      await pumpSurface(tester, [
        {'id': 'root', 'component': 'Text', 'text': 'x', 'style': 'body'},
      ]);
      expect(styleOf(tester, 'x').letterSpacing, closeTo(-0.15, 1e-9));
    });

    testWidgets('font names a family the app ships, or system for the platform font', (tester) async {
      await pumpSurface(tester, [
        {'id': 'root', 'component': 'Column', 'children': ['a', 'b', 'c']},
        {'id': 'a', 'component': 'Text', 'text': 'a', 'font': 'TenorSans'},
        {'id': 'b', 'component': 'Text', 'text': 'b', 'font': 'system'},
        {'id': 'c', 'component': 'Text', 'text': 'c'},
      ]);
      expect(styleOf(tester, 'a').fontFamily, 'TenorSans');
      expect(styleOf(tester, 'b').fontFamily, isNull);
      expect(styleOf(tester, 'c').fontFamily, 'CeraPro');
    });

    testWidgets('numbers are held to a sane range', (tester) async {
      await pumpSurface(tester, [
        {'id': 'root', 'component': 'Text', 'text': 'x', 'size': 100000, 'weight': 5000, 'lineHeight': 50, 'letterSpacing': 9},
      ]);
      final s = styleOf(tester, 'x');
      expect(s.fontSize, 96);
      expect(s.fontWeight, FontWeight.w900);
      expect(s.height, 3);
      expect(s.letterSpacing, closeTo(0.5 * 96, 1e-9));
    });

    testWidgets('textAlign aligns', (tester) async {
      await pumpSurface(tester, [
        {'id': 'root', 'component': 'Text', 'text': 'x', 'textAlign': 'center'},
      ]);
      expect(tester.widget<Text>(find.text('x')).textAlign, TextAlign.center);
    });

    testWidgets('spans colour parts of a line, and can differ per language', (tester) async {
      final components = <Map<String, Object?>>[
        {
          'id': 'root', 'component': 'Text', 'size': 30,
          'spans': {
            'uz': [
              {'text': '{/amount}', 'color': 'accent'},
              {'text': ' so\'m'},
            ],
            'en': [
              {'text': 'From '},
              {'text': '{/amount}', 'color': 'accent', 'weight': 700},
              {'text': ' UZS'},
            ],
          },
        },
      ];
      await pumpSurface(tester, components, data: {'amount': '2 500'}, language: 'en');
      var rich = tester.widget<RichText>(find.byType(RichText).first);
      expect(rich.text.toPlainText(), 'From 2 500 UZS');
      final spans = (((rich.text as TextSpan).children!.single as TextSpan).children!).cast<TextSpan>();
      expect(spans[1].style!.color, const Color(0xFFBE7C6C));
      expect(spans[1].style!.fontWeight, FontWeight.w700);
      expect(spans[0].style, isNull);

      await pumpSurface(tester, components, data: {'amount': '2 500'}, language: 'uz');
      rich = tester.widget<RichText>(find.byType(RichText).first);
      expect(rich.text.toPlainText(), '2 500 so\'m');
    });
  });

  group('Icon', () {
    testWidgets('draws a built-in icon at a size and colour', (tester) async {
      await pumpSurface(tester, [
        {'id': 'root', 'component': 'Icon', 'name': 'car', 'size': 48, 'color': 'accent'},
      ]);
      final icon = tester.widget<Icon>(find.byIcon(Icons.directions_car_outlined));
      expect(icon.size, 48);
      expect(icon.color, const Color(0xFFBE7C6C));
    });

    testWidgets('an unknown name keeps its room and draws nothing', (tester) async {
      await pumpSurface(tester, [
        {'id': 'root', 'component': 'Icon', 'name': 'nope', 'size': 30},
      ]);
      expect(find.byType(Icon), findsNothing);
      expect(tester.getSize(find.byType(SizedBox).first), const Size(30, 30));
    });

    testWidgets("an app's own icon is drawn by the app, and beats a built-in of the same name", (tester) async {
      final seen = <(double, Color)>[];
      ziCustomIcons['cinema'] = (context, size, color) {
        seen.add((size, color));
        return SizedBox(key: const Key('cinema'), width: size, height: size);
      };
      ziCustomIcons['forward'] = (context, size, color) => SizedBox(key: const Key('mine'), width: size, height: size);
      await pumpSurface(tester, [
        {'id': 'root', 'component': 'Row', 'children': ['a', 'b', 'c']},
        {'id': 'a', 'component': 'Icon', 'name': 'cinema', 'size': 24, 'color': 'accent'},
        {'id': 'b', 'component': 'Icon', 'name': 'forward'},
        {'id': 'c', 'component': 'Chip', 'text': 'x', 'icon': 'cinema'},
      ]);
      expect(seen.first, (24.0, const Color(0xFFBE7C6C)));
      expect(find.byKey(const Key('mine')), findsOneWidget);
      expect(find.byIcon(Icons.chevron_right), findsNothing);
      expect(find.byKey(const Key('cinema')), findsNWidgets(2)); // the Icon block and the Chip's icon
    });

    testWidgets('size is held to a sane range', (tester) async {
      await pumpSurface(tester, [
        {'id': 'root', 'component': 'Icon', 'name': 'car', 'size': 9999},
      ]);
      expect(tester.widget<Icon>(find.byIcon(Icons.directions_car_outlined)).size, 96);
    });
  });

  testWidgets('Image fit: cover by default, fill or contain when asked', (tester) async {
    await pumpSurface(tester, [
      {'id': 'root', 'component': 'Column', 'children': ['a', 'b', 'c']},
      {'id': 'a', 'component': 'Image', 'src': 'https://x.example/a.jpg', 'height': 10},
      {'id': 'b', 'component': 'Image', 'src': 'https://x.example/b.jpg', 'height': 10, 'fit': 'fill'},
      {'id': 'c', 'component': 'Image', 'src': 'https://x.example/c.jpg', 'height': 10, 'fit': 'contain'},
    ]);
    expect(tester.widgetList<Image>(find.byType(Image)).map((i) => i.fit), [BoxFit.cover, BoxFit.fill, BoxFit.contain]);
  });

  group('separator', () {
    final list = <Map<String, Object?>>[
      {'id': 'root', 'component': 'Column', 'children': {'componentId': 'row', 'path': '/items', 'separator': 'line'}},
      {'id': 'row', 'component': 'Text', 'text': {'path': 'name'}, 'visible': {'path': 'on'}},
      {'id': 'line', 'component': 'Text', 'text': '---'},
    ];

    testWidgets('sits between repeats, never before the first or after the last', (tester) async {
      await pumpSurface(tester, list, data: {
        'items': [
          {'name': 'a', 'on': true},
          {'name': 'b', 'on': true},
          {'name': 'c', 'on': true},
        ],
      });
      expect(find.text('---'), findsNWidgets(2));
      final order = tester.widgetList<Text>(find.byType(Text)).map((t) => t.data).toList();
      expect(order, ['a', '---', 'b', '---', 'c']);
    });

    testWidgets('one item has none, and a hidden item leaves no stray one', (tester) async {
      await pumpSurface(tester, list, data: {
        'items': [
          {'name': 'a', 'on': true},
          {'name': 'b', 'on': false},
          {'name': 'c', 'on': true},
        ],
      });
      expect(tester.widgetList<Text>(find.byType(Text)).map((t) => t.data).toList(), ['a', '---', 'c']);
      await pumpSurface(tester, list, data: {
        'items': [
          {'name': 'a', 'on': true},
        ],
      });
      expect(find.text('---'), findsNothing);
    });
  });
}
