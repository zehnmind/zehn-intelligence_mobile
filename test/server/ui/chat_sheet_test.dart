import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zehn_intelligence/src/server/api/turn_events.dart';
import 'package:zehn_intelligence/src/server/chat/chat_cubit.dart';
import 'package:zehn_intelligence/src/server/chat/chat_settings.dart';
import 'package:zehn_intelligence/src/server/ui/chat_sheet.dart';
import 'package:zehn_intelligence/src/server/ui/voice.dart';
import 'package:zehn_intelligence/zehn_intelligence.dart' show ZiComponentController;

import '../../support/chat_fakes.dart';

typedef ComponentBuilder = Widget Function(BuildContext, Map<String, Object?>, ZiComponentController);

const voice = ZiChatSettings(services: {'llm', 'stt', 'tts'});

/// A confirm template, read with the card's props.
const reserveCard = <String, Object?>{
  'createSurface': {
    'surfaceId': 'zi_confirm',
    'catalogId': 'zehn.basic.v0',
    'root': 'root',
    'components': [
      {'id': 'root', 'component': 'Text', 'text': 'Reserve zone {/zone}?'},
    ],
  },
};

/// A card template as the server sends it in `mount_component.surface`.
const cinemaCard = <String, Object?>{
  'createSurface': {
    'surfaceId': 'cinema_details',
    'catalogId': 'zehn.basic.v0',
    'root': 'root',
    'components': [
      {'id': 'root', 'component': 'Text', 'text': {'path': '/name'}},
    ],
  },
};

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

  Widget sheetLauncher(ValueListenable<ZiChatSettings> settings, Map<String, ComponentBuilder> builders) => Builder(
    builder: (context) => TextButton(
      onPressed: () => ZiChatSheet.show(
        context,
        cubit: cubit,
        settings: settings,
        language: () => 'en',
        builders: builders,
        openRoute: routes.add,
        recorderFactory: () => recorder,
      ),
      child: const Text('open'),
    ),
  );

  Future<ValueNotifier<ZiChatSettings>> open(
    WidgetTester tester, {
    ZiChatSettings settings = voice,
    Map<String, ComponentBuilder> builders = const {},
  }) async {
    phone(tester);
    final notifier = ValueNotifier(settings);
    addTearDown(notifier.dispose);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Center(child: sheetLauncher(notifier, builders)))));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return notifier;
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

  testWidgets('chat settings override the welcome text', (tester) async {
    await open(tester, settings: const ZiChatSettings(
      welcomeTitle: 'Welcome to the mall',
      welcomeSubtitle: 'Find stores, restaurants and offers.',
    ));
    expect(find.text('Welcome to the mall'), findsOneWidget);
    expect(find.text('Find stores, restaurants and offers.'), findsOneWidget);
  });

  testWidgets('settings that arrive while the chat is open are used at once', (tester) async {
    final settings = await open(tester, settings: const ZiChatSettings());
    expect(find.text('Tap to speak'), findsNothing);
    settings.value = const ZiChatSettings(services: {'stt'}, welcomeTitle: 'Welcome to the mall');
    await tester.pumpAndSettle();
    expect(find.text('Welcome to the mall'), findsOneWidget);
    expect(find.text('Tap to speak'), findsOneWidget);
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

  testWidgets('an inline card is drawn from the template in the event', (tester) async {
    turns.script([
      started,
      const MountComponent(callId: 'm1', component: 'cinema_details', kind: 'inline', props: {'name': 'Cinematica'}, surface: cinemaCard),
      done,
    ]);
    await open(tester);
    await type(tester, 'kino');
    expect(find.text('Cinematica'), findsOneWidget);
  });

  testWidgets('a card with no template and no builder draws nothing', (tester) async {
    turns.script([
      started,
      const MountComponent(callId: 'm1', component: 'cinema_details', kind: 'inline', props: {'name': 'Cinematica'}),
      const TextDelta(text: 'after'),
      done,
    ]);
    await open(tester);
    await type(tester, 'kino');
    expect(find.text('Cinematica'), findsNothing);
    expect(find.textContaining('after', findRichText: true), findsOneWidget);
  });

  testWidgets('in-app builder wins over the template', (tester) async {
    turns.script([
      started,
      const MountComponent(callId: 'm1', component: 'cinema_details', kind: 'inline', props: {'name': 'Cinematica'}, surface: cinemaCard),
      done,
    ]);
    await open(tester, builders: {'cinema_details': (c, data, ctl) => Text('from app ${data['name']}')});
    await type(tester, 'kino');
    expect(find.text('from app Cinematica'), findsOneWidget);
  });

  testWidgets('route component closes the sheet and opens the route exactly as sent', (tester) async {
    turns.script([
      started,
      // The server fills the route; the SDK never changes it.
      const MountComponent(callId: 'm1', component: 'venue_page', kind: 'route', props: {'id': 'a1'}, route: '/venues/{id}'),
      done,
    ]);
    await open(tester);
    await type(tester, 'kino');
    expect(routes, ['/venues/{id}']);
    expect(find.byType(ZiChatSheet), findsNothing);
  });

  testWidgets('two route components in one turn close only the chat', (tester) async {
    phone(tester);
    final settings = ValueNotifier(voice);
    addTearDown(settings.dispose);
    turns.script([
      started,
      const MountComponent(callId: 'm1', component: 'cinema_page', kind: 'route', props: {'id': 1}, route: '/explore/cinema/1'),
      const MountComponent(callId: 'm2', component: 'loyalty_page', kind: 'route', props: {}, route: '/loyalty'),
      done,
    ]);
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (context) => Scaffold(body: Column(children: [const Text('page b'), sheetLauncher(settings, const {})])),
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
    await open(tester, settings: const ZiChatSettings(services: {'llm'}));
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

  ConfirmEvent reserve({String method = 'POST', Map<String, Object?>? surface = reserveCard, String? label = 'Reserve'}) => ConfirmEvent(
    callId: 'c2',
    actionId: 'a1',
    tool: 'parking.reserve',
    method: method,
    surface: surface,
    props: const {'zone': 'B1'},
    confirmLabel: label,
    expiresIn: const Duration(minutes: 10),
    turnId: 't1',
  );

  testWidgets('a confirm card draws its template with Cancel and the server\'s Confirm word', (tester) async {
    turns.script([started, reserve(), done]);
    await open(tester);
    await type(tester, 'reserve');
    expect(find.text('Reserve zone B1?'), findsOneWidget);
    expect(find.text('Reserve'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    turns.script([const TextDelta(text: 'Done, place reserved.'), done]);
    await tester.tap(find.byKey(const ValueKey('zi-confirm')));
    await tester.pumpAndSettle();
    expect((turns.starts.last.toJson()['input']! as Map)['decision'], 'confirm');
    expect(find.text('Confirmed'), findsOneWidget);
    expect(find.byKey(const ValueKey('zi-confirm')), findsNothing);
    expect(find.textContaining('place reserved', findRichText: true), findsOneWidget);
  });

  testWidgets('Cancel sends the cancel decision', (tester) async {
    turns.script([started, reserve(), done]);
    await open(tester);
    await type(tester, 'reserve');
    turns.script([done]);
    await tester.tap(find.byKey(const ValueKey('zi-decline')));
    await tester.pumpAndSettle();
    expect((turns.starts.last.toJson()['input']! as Map)['decision'], 'cancel');
    expect(find.text('Cancelled'), findsOneWidget);
  });

  testWidgets('a DELETE confirm is in the warning colour; no label and no template use the SDK words', (tester) async {
    turns.script([started, reserve(method: 'DELETE', surface: null, label: null), done]);
    await open(tester);
    await type(tester, 'cancel my reservation');
    expect(find.text('Confirm this?'), findsOneWidget);
    expect(find.text('Confirm'), findsOneWidget);
    final box = tester.widget<Container>(
      find.descendant(of: find.byKey(const ValueKey('zi-confirm')), matching: find.byType(Container)).first,
    );
    expect((box.decoration! as BoxDecoration).color, const Color(0xFFD64545));
    // The card's expiry timer belongs to the chat, which outlives this sheet.
    cubit.reset();
  });

  testWidgets('the sheet fills the height below the status bar', (tester) async {
    tester.view.padding = const FakeViewPadding(top: 62 * 3, bottom: 34 * 3);
    tester.view.viewPadding = const FakeViewPadding(top: 62 * 3, bottom: 34 * 3);
    addTearDown(tester.view.resetPadding);
    addTearDown(tester.view.resetViewPadding);
    await open(tester);
    final sheet = tester.getRect(find.byType(ZiChatSheet));
    expect(sheet.top, 62);
    expect(sheet.bottom, 874);
    // The composer area keeps clear of the home indicator.
    expect(tester.getBottomLeft(find.text('Type a message')).dy, lessThanOrEqualTo(874 - 34));
  });
}
