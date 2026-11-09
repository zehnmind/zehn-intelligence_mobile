import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zehn_intelligence/src/server/api/turn_events.dart';
import 'package:zehn_intelligence/src/server/bootstrap/bootstrap.dart';
import 'package:zehn_intelligence/src/server/chat/chat_cubit.dart';
import 'package:zehn_intelligence/src/server/ui/chat_sheet.dart';
import 'package:zehn_intelligence/zehn_intelligence.dart' show ZiComponentController;

import '../../support/bootstrap_fixture.dart';
import '../../support/chat_fakes.dart';

typedef ComponentBuilder = Widget Function(BuildContext, Map<String, Object?>, ZiComponentController);

void main() {
  late FakeTurns turns;
  late FakeAudio audio;
  late ZiChatCubit cubit;
  late List<String> routes;

  const started = TurnStarted(conversationId: 'c1', conversationNew: true, turnId: 't1');
  const done = TurnDone(outcome: 'answered', turnId: 't1');

  setUp(() {
    turns = FakeTurns();
    audio = FakeAudio();
    routes = [];
    cubit = ZiChatCubit(
      turns: turns,
      tools: FakeRunner(),
      audio: audio,
      language: () => 'en',
      starterSuggestions: () async => ['Where is the cinema?'],
    );
  });

  tearDown(() => cubit.close());

  Future<void> open(
    WidgetTester tester, {
    Map<String, Object?>? boot,
    Map<String, ComponentBuilder> builders = const {},
  }) async {
    final data = ZiBootstrap.fromJson(boot ?? bootstrapJson());
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => ZiChatSheet.show(
                context,
                cubit: cubit,
                bootstrap: FixedBootstrap(data),
                language: () => 'en',
                builders: builders,
                openRoute: routes.add,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Future<void> send(WidgetTester tester, String text) async {
    await tester.enterText(find.byType(TextField), text);
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pumpAndSettle();
  }

  testWidgets('typing and sending shows the user bubble and the streamed reply', (tester) async {
    turns.script([started, const TextDelta(text: '**Salom** dunyo'), done]);
    await open(tester);
    await send(tester, 'hi');
    expect(find.text('hi'), findsOneWidget);
    expect(find.byType(MarkdownBody), findsOneWidget);
    final bold = find.byWidgetPredicate((w) {
      if (w is! RichText) return false;
      var found = false;
      w.text.visitChildren((span) {
        if (span is TextSpan && span.text == 'Salom' && span.style?.fontWeight == FontWeight.bold) found = true;
        return true;
      });
      return found;
    });
    expect(bold, findsOneWidget);
  });

  testWidgets('inline component from start-up data is drawn', (tester) async {
    turns.script([
      started,
      const MountComponent(callId: 'm1', component: 'cinema_details', kind: 'inline', props: {'name': 'Cinematica'}),
      done,
    ]);
    await open(tester);
    await send(tester, 'kino');
    expect(find.text('Cinematica'), findsOneWidget);
  });

  testWidgets('in-app builder wins over start-up data', (tester) async {
    turns.script([
      started,
      const MountComponent(callId: 'm1', component: 'cinema_details', kind: 'inline', props: {'name': 'Cinematica'}),
      done,
    ]);
    await open(tester, builders: {'cinema_details': (c, data, ctl) => Text('from app ${data['name']}')});
    await send(tester, 'kino');
    expect(find.text('from app Cinematica'), findsOneWidget);
    expect(find.text('Cinematica'), findsNothing);
  });

  testWidgets('route component closes the sheet and calls openRoute with filled placeholders', (tester) async {
    final boot = bootstrapJson();
    (boot['components']! as Map)['cinema_page'] = {'kind': 'route', 'route': '/explore/cinema/{id}'};
    turns.script([
      started,
      const MountComponent(callId: 'm1', component: 'cinema_page', kind: 'route', props: {'id': 1}),
      done,
    ]);
    await open(tester, boot: boot);
    await send(tester, 'kino');
    expect(routes, ['/explore/cinema/1']);
    expect(find.byType(ZiChatSheet), findsNothing);
  });

  testWidgets('mic is hidden without stt', (tester) async {
    final boot = bootstrapJson()..['services'] = ['llm'];
    await open(tester, boot: boot);
    expect(find.byIcon(Icons.mic_rounded), findsNothing);
  });

  testWidgets('mic shows with stt', (tester) async {
    await open(tester);
    expect(find.byIcon(Icons.mic_rounded), findsOneWidget);
  });

  testWidgets('suggestion chip sends its text', (tester) async {
    turns.script([started, done]);
    await open(tester);
    await tester.tap(find.text('Where is the cinema?'));
    await tester.pumpAndSettle();
    expect((turns.starts.single.toJson()['input']! as Map)['text'], 'Where is the cinema?');
  });

  testWidgets('retry button appears only for retryable errors', (tester) async {
    turns
      ..script([failure('invalid_request')])
      ..script([failure('llm_unavailable', retryable: true)]);
    await open(tester);
    await send(tester, 'one');
    expect(find.text('Try again'), findsNothing);
    await send(tester, 'two');
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('closing the sheet stops spoken replies', (tester) async {
    await open(tester);
    final before = audio.stops;
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    expect(find.byType(ZiChatSheet), findsNothing);
    expect(audio.stops, greaterThan(before));
  });

  testWidgets('two route components in one turn close only the chat', (tester) async {
    final boot = bootstrapJson();
    (boot['components']! as Map)['cinema_page'] = {'kind': 'route', 'route': '/explore/cinema/{id}'};
    final data = ZiBootstrap.fromJson(boot);
    turns.script([
      started,
      const MountComponent(callId: 'm1', component: 'cinema_page', kind: 'route', props: {'id': 1}),
      const MountComponent(callId: 'm2', component: 'loyalty_page', kind: 'route', props: {}),
      done,
    ]);
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (context) => Scaffold(
                body: Column(children: [
                  const Text('page b'),
                  TextButton(
                    onPressed: () => ZiChatSheet.show(
                      context,
                      cubit: cubit,
                      bootstrap: FixedBootstrap(data),
                      language: () => 'en',
                      builders: const {},
                      openRoute: routes.add,
                    ),
                    child: const Text('open'),
                  ),
                ]),
              ),
            )),
            child: const Text('next'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('next'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await send(tester, 'kino');
    expect(routes, ['/explore/cinema/1', '/loyalty']);
    expect(find.byType(ZiChatSheet), findsNothing);
    expect(find.text('page b'), findsOneWidget);
  });
}
