import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zehn_intelligence/src/server/api/turn_events.dart';
import 'package:zehn_intelligence/src/server/bootstrap/bootstrap.dart';
import 'package:zehn_intelligence/src/server/chat/chat_cubit.dart';
import 'package:zehn_intelligence/src/server/ui/chat_sheet.dart';
import 'package:zehn_intelligence/src/server/ui/voice.dart';
import 'package:zehn_intelligence/zehn_intelligence.dart' show ZiComponentController;

import '../../support/bootstrap_fixture.dart';
import '../../support/chat_fakes.dart';

typedef ComponentBuilder = Widget Function(BuildContext, Map<String, Object?>, ZiComponentController);

class FakeRecorder implements ZiVoiceRecorder {
  FakeRecorder(this.bytes);

  final Uint8List bytes;
  int starts = 0;
  int cancels = 0;

  @override
  Future<bool> start() async {
    starts++;
    return true;
  }

  @override
  Stream<double> levels() => const Stream.empty();

  @override
  Future<Uint8List?> stop() async => bytes;

  @override
  Future<void> cancel() async => cancels++;

  @override
  Future<void> dispose() async {}
}

/// The design's phone (402×874 points), with reduced motion so the bubble holds still.
void phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(1206, 2622);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
}

void main() {
  late FakeTurns turns;
  late FakeAudio audio;
  late ZiChatCubit cubit;
  late List<String> routes;
  late FakeRecorder recorder;

  const started = TurnStarted(conversationId: 'c1', conversationNew: true, turnId: 't1');
  const done = TurnDone(outcome: 'answered', turnId: 't1');

  setUp(() {
    turns = FakeTurns();
    audio = FakeAudio();
    routes = [];
    recorder = FakeRecorder(Uint8List.fromList([1, 2, 3]));
    cubit = ZiChatCubit(
      turns: turns,
      tools: FakeRunner(),
      audio: audio,
      language: () => 'en',
      starterSuggestions: () async => ['Where is the cinema?'],
    );
  });

  tearDown(() => cubit.close());

  Widget sheetLauncher(ZiBootstrap data, Map<String, ComponentBuilder> builders) => Builder(
    builder: (context) => TextButton(
      onPressed: () => ZiChatSheet.show(
        context,
        cubit: cubit,
        bootstrap: FixedBootstrap(data),
        language: () => 'en',
        builders: builders,
        openRoute: routes.add,
        recorderFactory: () => recorder,
      ),
      child: const Text('open'),
    ),
  );

  Future<void> open(WidgetTester tester, {Map<String, Object?>? boot, Map<String, ComponentBuilder> builders = const {}}) async {
    phone(tester);
    final data = ZiBootstrap.fromJson(boot ?? bootstrapJson());
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Center(child: sheetLauncher(data, builders)))));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  /// From the landing: "Type a message", then type and send.
  Future<void> type(WidgetTester tester, String text) async {
    if (find.byType(TextField).evaluate().isEmpty) {
      await tester.tap(find.text('Type a message'));
      await tester.pumpAndSettle();
    }
    await tester.enterText(find.byType(TextField), text);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('zi-send')));
    await tester.pumpAndSettle();
  }

  testWidgets('an empty chat shows the landing', (tester) async {
    await open(tester);
    expect(find.text('Assistant'), findsOneWidget);
    expect(find.text('Powered by zehnmind.ai'), findsOneWidget);
    expect(find.text('How can I help you?'), findsOneWidget);
    expect(find.text('Tap to speak'), findsOneWidget);
    expect(find.text('Try asking'), findsOneWidget);
    expect(find.text('Where is the cinema?'), findsOneWidget);
    expect(find.text('Type a message'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('console copy overrides the welcome text', (tester) async {
    await open(tester, boot: {
      ...bootstrapJson(),
      'copy': {
        'welcome_title': {'en': 'Welcome to the mall'},
        'welcome_subtitle': {'en': 'Find stores, restaurants and offers.'},
      },
    });
    expect(find.text('Welcome to the mall'), findsOneWidget);
    expect(find.text('Find stores, restaurants and offers.'), findsOneWidget);
  });

  testWidgets('a suggestion chip sends its text and shows the conversation', (tester) async {
    turns.script([started, const TextDelta(text: '**Salom** dunyo'), done]);
    await open(tester);
    await tester.tap(find.text('Where is the cinema?'));
    await tester.pumpAndSettle();
    expect((turns.starts.single.toJson()['input']! as Map)['text'], 'Where is the cinema?');
    expect(find.text('Where is the cinema?'), findsOneWidget);
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
    expect(find.text('How can I help you?'), findsNothing);
    expect(find.text('Chat'), findsOneWidget);
  });

  testWidgets('"Type a message" opens the conversation and sends', (tester) async {
    turns.script([started, const TextDelta(text: 'Hello back'), done]);
    await open(tester);
    await type(tester, 'hi');
    expect(find.text('hi'), findsOneWidget);
    expect(find.textContaining('Hello back', findRichText: true), findsOneWidget);
  });

  testWidgets('thinking shows while waiting for the answer', (tester) async {
    final leg = StreamController<TurnEvent>();
    turns.legs.add(leg.stream);
    await open(tester);
    await type(tester, 'hi');
    expect(find.text('Thinking…'), findsOneWidget);
    leg
      ..add(const TextDelta(text: 'ok'))
      ..add(done);
    await leg.close();
    await tester.pumpAndSettle();
    expect(find.text('Thinking…'), findsNothing);
  });

  testWidgets('inline component from start-up data is drawn', (tester) async {
    turns.script([
      started,
      const MountComponent(callId: 'm1', component: 'cinema_details', kind: 'inline', props: {'name': 'Cinematica'}),
      done,
    ]);
    await open(tester);
    await type(tester, 'kino');
    expect(find.text('Cinematica'), findsOneWidget);
  });

  testWidgets('in-app builder wins over start-up data', (tester) async {
    turns.script([
      started,
      const MountComponent(callId: 'm1', component: 'cinema_details', kind: 'inline', props: {'name': 'Cinematica'}),
      done,
    ]);
    await open(tester, builders: {'cinema_details': (c, data, ctl) => Text('from app ${data['name']}')});
    await type(tester, 'kino');
    expect(find.text('from app Cinematica'), findsOneWidget);
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
    await type(tester, 'kino');
    expect(routes, ['/explore/cinema/1']);
    expect(find.byType(ZiChatSheet), findsNothing);
  });

  testWidgets('two route components in one turn close only the chat', (tester) async {
    phone(tester);
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
              builder: (context) => Scaffold(body: Column(children: [const Text('page b'), sheetLauncher(data, const {})])),
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
    await type(tester, 'kino');
    expect(routes, ['/explore/cinema/1', '/loyalty']);
    expect(find.byType(ZiChatSheet), findsNothing);
    expect(find.text('page b'), findsOneWidget);
  });

  testWidgets('closing the sheet stops spoken replies', (tester) async {
    await open(tester);
    final before = audio.stops;
    await tester.tap(find.byKey(const ValueKey('zi-close')));
    await tester.pumpAndSettle();
    expect(find.byType(ZiChatSheet), findsNothing);
    expect(audio.stops, greaterThan(before));
  });

  testWidgets('back in a conversation starts a new chat', (tester) async {
    turns.script([started, const TextDelta(text: 'x'), done]);
    await open(tester);
    await type(tester, 'one');
    await tester.tap(find.byKey(const ValueKey('zi-back')));
    await tester.pumpAndSettle();
    expect(cubit.state.items, isEmpty);
    expect(find.text('How can I help you?'), findsOneWidget);
  });

  testWidgets('without stt there is no mic, and the orb opens typing', (tester) async {
    final boot = bootstrapJson()..['services'] = ['llm'];
    await open(tester, boot: boot);
    expect(find.text('Tap to speak'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('zi-orb')));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
    expect(find.byKey(const ValueKey('zi-mic')), findsNothing);
  });

  testWidgets('with stt the orb listens, and stop sends the recording', (tester) async {
    turns.script([started, done]);
    await open(tester);
    await tester.tap(find.byKey(const ValueKey('zi-orb')));
    await tester.pumpAndSettle();
    expect(recorder.starts, 1);
    expect(find.text('Listening…'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('zi-stop')));
    await tester.pumpAndSettle();
    final input = turns.starts.single.toJson();
    expect((input['input']! as Map)['type'], 'audio');
    expect((input['input']! as Map)['format'], 'm4a');
    expect(input['voice_reply'], isTrue);
  });

  testWidgets('cancel while listening sends nothing', (tester) async {
    await open(tester);
    await tester.tap(find.byKey(const ValueKey('zi-orb')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('zi-cancel')));
    await tester.pumpAndSettle();
    expect(recorder.cancels, 1);
    expect(turns.starts, isEmpty);
    expect(find.text('How can I help you?'), findsOneWidget);
  });

  testWidgets('a recording over 1 MiB is not sent', (tester) async {
    recorder = FakeRecorder(Uint8List(1024 * 1024 + 1));
    await open(tester);
    await tester.tap(find.byKey(const ValueKey('zi-orb')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('zi-stop')));
    await tester.pumpAndSettle();
    expect(turns.starts, isEmpty);
    expect(find.text('The recording is too long.'), findsOneWidget);
  });

  testWidgets('retry appears only for retryable errors', (tester) async {
    turns
      ..script([failure('invalid_request')])
      ..script([failure('llm_unavailable', retryable: true)]);
    await open(tester);
    await type(tester, 'one');
    expect(find.text('Try again'), findsNothing);
    await type(tester, 'two');
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('the composer stays above the keyboard', (tester) async {
    await open(tester);
    await tester.tap(find.text('Type a message'));
    await tester.pumpAndSettle();
    tester.view.viewInsets = const FakeViewPadding(bottom: 900);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();
    final screenHeight = tester.view.physicalSize.height / tester.view.devicePixelRatio;
    final keyboardTop = screenHeight - 900 / tester.view.devicePixelRatio;
    expect(tester.getBottomLeft(find.byType(TextField)).dy, lessThanOrEqualTo(keyboardTop));
  });
}
