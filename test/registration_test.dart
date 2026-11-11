import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zehn_intelligence/zehn_intelligence.dart';

void main() {
  tearDown(() {
    ZehnIntelligence.registeredTools.clear();
    ZehnIntelligence.registeredToolArgs.clear();
    ZehnIntelligence.registeredComponents.clear();
  });

  test('a tool is registered with its handler and the arguments it declared', () async {
    ZehnIntelligence.registerTool(
      'map.route',
      (args) async => {'to': args['to']},
      description: 'Walking directions inside the mall.',
      args: const {
        'to': ZiArg.string('Where to go', required: true),
        'accessible': ZiArg.boolean('Lifts only'),
      },
      examples: const {
        'en': ['How do I get to Zara?'],
      },
      resultNote: 'steps are in order',
    );
    expect(await ZehnIntelligence.registeredTools['map.route']!({'to': 'Zara'}), {'to': 'Zara'});
    expect(ZehnIntelligence.registeredToolArgs['map.route']!.keys, ['to', 'accessible']);
  });

  test('the two-argument form still registers, with nothing to check', () {
    ZehnIntelligence.registerTool('tours.search', (args) async => const {});
    expect(ZehnIntelligence.registeredTools.keys, ['tours.search']);
    expect(ZehnIntelligence.registeredToolArgs, isEmpty);
  });

  test('a component is registered with its builder', () {
    ZehnIntelligence.registerComponent(
      'map_route',
      (context, props, controller) => const SizedBox.shrink(),
      kind: 'inline',
      description: 'The route on the mall map.',
      props: const {'to': ZiArg.string('`card.to` from map.route', required: true)},
    );
    expect(ZehnIntelligence.registeredComponents.keys, ['map_route']);
  });

  test('start takes the tools and the widgets by name, then never throws without the console file', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final started = await ZehnIntelligence.start(
      dio: Dio.new,
      handlers: {
        'map.locate': (args) async => {'target': args['target']},
        'map.route': (args) async => const {},
      },
      builders: {'map_spot': (context, props, controller) => const SizedBox.shrink()},
    );
    expect(started, isNull);
    expect(ZehnIntelligence.registeredTools.keys, ['map.locate', 'map.route']);
    expect(await ZehnIntelligence.registeredTools['map.locate']!({'target': 'Zara'}), {'target': 'Zara'});
    expect(ZehnIntelligence.registeredToolArgs, isEmpty);
    expect(ZehnIntelligence.registeredComponents.keys, ['map_spot']);
  });

  test('a name the catalog cannot hold is refused when it is registered', () {
    expect(() => ZehnIntelligence.registerTool('Map Route', (args) async => const {}), throwsAssertionError);
    expect(() => ZehnIntelligence.registerTool('ui.route', (args) async => const {}), throwsAssertionError);
    expect(
      () => ZehnIntelligence.registerComponent('map.route', (context, props, controller) => const SizedBox.shrink()),
      throwsAssertionError,
    );
    expect(
      () => ZehnIntelligence.registerComponent('map_route', (context, props, controller) => const SizedBox.shrink(), kind: 'page'),
      throwsAssertionError,
    );
    expect(ZehnIntelligence.registeredTools, isEmpty);
    expect(ZehnIntelligence.registeredComponents, isEmpty);
  });

  test('an argument says what is wrong with a value, or nothing', () {
    const to = ZiArg.string('Where to go', required: true, oneOf: ['zara', 'aldo']);
    expect(to.problem('to', null), contains('"to"'));
    expect(to.problem('to', 3), contains('string'));
    expect(to.problem('to', 'gant'), contains('zara'));
    expect(to.problem('to', 'zara'), isNull);

    const floor = ZiArg.integer('The floor');
    expect(floor.problem('floor', null), isNull);
    expect(floor.problem('floor', 2.5), contains('integer'));
    expect(floor.problem('floor', 2), isNull);

    const metres = ZiArg.number('How far');
    expect(metres.problem('metres', 2), isNull);
    expect(metres.problem('metres', 2.5), isNull);
    expect(metres.problem('metres', '2'), contains('number'));

    const lifts = ZiArg.boolean('Lifts only');
    expect(lifts.problem('lifts', true), isNull);
    expect(lifts.problem('lifts', 'true'), contains('boolean'));
  });
}
