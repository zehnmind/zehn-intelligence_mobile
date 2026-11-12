import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zehn_intelligence/src/server/api/turn_events.dart';
import 'package:zehn_intelligence/src/server/chat/chat_cubit.dart';
import 'package:zehn_intelligence/src/server/api/api_client.dart';
import 'package:zehn_intelligence/src/server/chat/chat_settings.dart';
import 'package:zehn_intelligence/src/server/chat/chat_state.dart';
import 'package:zehn_intelligence/src/server/chat/history.dart';
import 'package:zehn_intelligence/src/server/surface/surface_view.dart';
import 'package:zehn_intelligence/src/server/ui/chat_sheet.dart';
import 'package:zehn_intelligence/src/server/ui/voice.dart';
import 'package:zehn_intelligence/zehn_intelligence.dart' show ZiComponentController;

import '../../support/chat_fakes.dart';
import '../../support/form_cards.dart';
import '../../support/history_fakes.dart';

typedef ComponentBuilder = Widget Function(BuildContext, Map<String, Object?>, ZiComponentController);

const voice = ZiChatSettings();

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

  Widget sheetLauncher(ValueListenable<ZiChatSettings> settings, Map<String, ComponentBuilder> builders, ZiHistory? history) => Builder(
    builder: (context) => TextButton(
      onPressed: () => ZiChatSheet.show(
        context,
        cubit: cubit,
        settings: settings,
        language: () => 'en',
        builders: builders,
        openRoute: routes.add,
        recorderFactory: () => recorder,
        history: history,
      ),
      child: const Text('open'),
    ),
  );

  Future<ValueNotifier<ZiChatSettings>> open(
    WidgetTester tester, {
    ZiChatSettings settings = voice,
    Map<String, ComponentBuilder> builders = const {},
    ZiHistory? history,
  }) async {
    phone(tester);
    final notifier = ValueNotifier(settings);
    addTearDown(notifier.dispose);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Center(child: sheetLauncher(notifier, builders, history)))));
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
    expect(find.text('Welcome to the mall'), findsNothing);
    settings.value = const ZiChatSettings(welcomeTitle: 'Welcome to the mall');
    await tester.pumpAndSettle();
    expect(find.text('Welcome to the mall'), findsOneWidget);
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
              builder: (context) => Scaffold(body: Column(children: [const Text('page b'), sheetLauncher(settings, const {}, null)])),
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

  testWidgets('the mic is always there: the config names no services', (tester) async {
    await open(tester, settings: const ZiChatSettings());
    expect(find.text('Tap to speak'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('zi-orb')));
    await tester.pumpAndSettle();
    expect(recorder.starts, 1);
    await tester.tap(find.byKey(const ValueKey('zi-cancel')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Type a message'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('zi-mic')), findsOneWidget);
  });

  testWidgets('the orb listens, and stop sends the recording', (tester) async {
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

  testWidgets('a confirm card is one frame: the template and its buttons inside, in the theme', (tester) async {
    turns.script([started, reserve(), done]);
    await open(tester, settings: const ZiChatSettings(theme: {
      'colors': {
        'surface': '#F7F7F7',
        'border': '#DDDDDD',
        'chip': '#EEEEEE',
        'on_surface': '#111111',
        'accent': '#FF6600',
        'on_accent': '#FFFFFF',
      },
      'radius': {'card': 24},
    }));
    await type(tester, 'reserve');
    final card = find.byKey(const ValueKey('zi-confirm-card'));
    final frame = tester.widget<Container>(card);
    final look = frame.decoration! as BoxDecoration;
    expect(look.color, const Color(0xFFF7F7F7));
    expect(look.border, Border.all(color: const Color(0xFFDDDDDD)));
    expect(look.borderRadius, BorderRadius.circular(24));
    expect(frame.padding, const EdgeInsets.all(16));
    for (final inside in [find.text('Reserve zone B1?'), find.byKey(const ValueKey('zi-decline')), find.byKey(const ValueKey('zi-confirm'))]) {
      expect(find.descendant(of: card, matching: inside), findsOneWidget);
    }
    Container fill(String key) => tester.widget<Container>(
      find.descendant(of: find.byKey(ValueKey(key)), matching: find.byType(Container)).first,
    );
    expect((fill('zi-decline').decoration! as BoxDecoration).color, const Color(0xFFEEEEEE));
    expect(tester.widget<Text>(find.text('Cancel')).style?.color, const Color(0xFF111111));
    expect((fill('zi-confirm').decoration! as BoxDecoration).color, const Color(0xFFFF6600));
    final cancel = tester.getRect(find.byKey(const ValueKey('zi-decline')));
    final confirm = tester.getRect(find.byKey(const ValueKey('zi-confirm')));
    expect(cancel.height, 44);
    expect(cancel.width, confirm.width);
    expect(confirm.left - cancel.right, 8);
    expect(confirm.top - tester.getRect(find.text('Reserve zone B1?')).bottom, 16);
    turns.script([done]);
    await tester.tap(find.byKey(const ValueKey('zi-confirm')));
    await tester.pumpAndSettle();
    expect(find.descendant(of: card, matching: find.text('Confirmed')), findsOneWidget);
  });

  testWidgets('a spoken answer has one speaker, under its last part: tap plays it again, tap again stops', (tester) async {
    AudioClip clip(int seq) => AudioClip(format: 'mp3', text: '', data: 'c$seq', turnId: 't1', seq: seq);
    turns.script([
      started,
      const TextDelta(text: 'Part one', turnId: 't1'),
      const MountComponent(callId: 'c1', component: 'cinema', kind: 'inline', props: {'name': 'Cinematica'}, surface: cinemaCard, turnId: 't1'),
      const TextDelta(text: 'Part two', turnId: 't1'),
      clip(1),
      clip(2),
      done,
    ]);
    await open(tester);
    await type(tester, 'cinema');
    final speaker = find.byKey(const ValueKey('zi-speak-t1'));
    expect(speaker, findsOneWidget);
    expect(tester.getRect(speaker).top, greaterThanOrEqualTo(tester.getRect(find.textContaining('Part two', findRichText: true)).bottom));
    // The chat (and its playback listener) was made in setUp, outside the
    // test's fake clock: the end of playback is delivered in real time.
    await tester.runAsync(() async {
      audio.finish();
      await pumpEventQueue();
    });
    await tester.pumpAndSettle();
    expect(find.descendant(of: speaker, matching: find.byIcon(Icons.volume_up_outlined)), findsOneWidget);
    audio.clips.clear();
    await tester.tap(speaker);
    await tester.pumpAndSettle();
    expect(audio.clips, [(1, 'c1', 'mp3'), (2, 'c2', 'mp3')]);
    expect(find.descendant(of: speaker, matching: find.byIcon(Icons.stop_rounded)), findsOneWidget);
    final stops = audio.stops;
    await tester.tap(speaker);
    await tester.pumpAndSettle();
    expect(audio.stops, stops + 1);
    expect(find.descendant(of: speaker, matching: find.byIcon(Icons.volume_up_outlined)), findsOneWidget);
  });

  testWidgets("a long answer's speaker stays in view above the follow-up chips", (tester) async {
    // Events come over several frames, as from the server.
    final leg = StreamController<TurnEvent>();
    turns.legs.add(leg.stream);
    await open(tester);
    await type(tester, 'long');
    leg
      ..add(started)
      ..add(TextDelta(text: List.filled(30, 'A line of the answer.').join('\n\n'), turnId: 't1'));
    await tester.pumpAndSettle();
    leg.add(const AudioClip(format: 'mp3', text: '', data: 'c1', turnId: 't1', seq: 1));
    await tester.pumpAndSettle();
    leg
      ..add(const SuggestionsEvent(items: ['Tell me more'], turnId: 't1'))
      ..add(done);
    await leg.close();
    await tester.pumpAndSettle();
    final speaker = tester.getRect(find.byKey(const ValueKey('zi-speak-t1')));
    expect(speaker.bottom, lessThanOrEqualTo(tester.getRect(find.text('Tell me more')).top));
  });

  testWidgets('an answer with no speech held has no speaker', (tester) async {
    turns.script([started, const TextDelta(text: 'Quiet answer', turnId: 't1'), done]);
    await open(tester);
    await type(tester, 'hi');
    expect(find.textContaining('Quiet answer', findRichText: true), findsOneWidget);
    expect(find.byKey(const ValueKey('zi-speak-t1')), findsNothing);
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
  group('history', () {
    late FakeHistory history;

    setUp(() => history = FakeHistory());

    Future<void> openHistory(WidgetTester tester) async {
      await open(tester, history: history);
      await tester.tap(find.byKey(const ValueKey('zi-history')));
      await tester.pumpAndSettle();
    }

    testWidgets('without a history the landing has no history button', (tester) async {
      await open(tester);
      expect(find.byKey(const ValueKey('zi-history')), findsNothing);
    });

    testWidgets('the history button lists the conversations, latest first, with their times', (tester) async {
      history.saved = [summary('c1', title: 'Where is the cinema?'), summary('c2', title: 'Parking for 2 hours')];
      await openHistory(tester);
      expect(find.text('Chat history'), findsOneWidget);
      expect(tester.getTopLeft(find.text('Where is the cinema?')).dy,
          lessThan(tester.getTopLeft(find.text('Parking for 2 hours')).dy));
      expect(find.text('09:14, 06.11.2026'), findsNWidgets(2));
      expect(find.text('How can I help you?'), findsNothing);
    });

    testWidgets('a conversation opens as it was, from when it started, and the next question goes on in it', (tester) async {
      history.saved = [summary('c1', title: 'Where is the cinema?')];
      await openHistory(tester);
      await tester.tap(find.text('Where is the cinema?'));
      await tester.pumpAndSettle();
      expect(find.text('Where is the cinema?'), findsOneWidget);
      expect(find.byType(MarkdownBody), findsOneWidget);
      expect(find.text('Chat'), findsOneWidget);
      expect(find.text('09:12, 06.11.2026'), findsOneWidget);
      turns.script([const TurnStarted(conversationId: 'c1', conversationNew: false, turnId: 't2'), const TextDelta(text: 'Yes'), done]);
      await type(tester, 'Is it open now?');
      expect(turns.starts.single.conversationId, 'c1');
    });

    testWidgets("one that can't go on is read-only: a note and New chat instead of the input", (tester) async {
      history.saved = [summary('c1', title: 'Where is the cinema?', canContinue: false)];
      await openHistory(tester);
      await tester.tap(find.text('Where is the cinema?'));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
      expect(find.text('This chat can’t be continued.'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('zi-new-chat')));
      await tester.pumpAndSettle();
      expect(find.text('How can I help you?'), findsOneWidget);
      expect(cubit.state, isNot(predicate<ZiChatState>((s) => s.readOnly)));
    });

    testWidgets('back from the history is the landing', (tester) async {
      await openHistory(tester);
      await tester.tap(find.byKey(const ValueKey('zi-back')));
      await tester.pumpAndSettle();
      expect(find.text('How can I help you?'), findsOneWidget);
      expect(find.text('Chat history'), findsNothing);
    });

    testWidgets('an empty history says so', (tester) async {
      await openHistory(tester);
      expect(find.text('No chats yet'), findsOneWidget);
    });

    testWidgets('a list that fails offers a retry', (tester) async {
      history.failWith = const ZiApiException('network_error', retryable: true);
      await openHistory(tester);
      expect(find.text('No connection. Please try again.'), findsOneWidget);
      history
        ..failWith = null
        ..saved = [summary('c1', title: 'Where is the cinema?')];
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.text('Where is the cinema?'), findsOneWidget);
    });

    testWidgets('swiping a conversation away deletes it', (tester) async {
      history.saved = [summary('c1', title: 'Where is the cinema?'), summary('c2', title: 'Parking for 2 hours')];
      await openHistory(tester);
      await tester.drag(find.text('Where is the cinema?'), const Offset(-400, 0));
      await tester.pumpAndSettle();
      expect(find.text('Where is the cinema?'), findsNothing);
      expect(history.saved.map((s) => s.id), ['c2']);
    });

    testWidgets('a delete the server refuses keeps the row and says so', (tester) async {
      history
        ..saved = [summary('c1', title: 'Where is the cinema?')]
        ..deleteFails = const ZiApiException('turn_in_progress');
      await openHistory(tester);
      await tester.drag(find.text('Where is the cinema?'), const Offset(-400, 0));
      await tester.pumpAndSettle();
      expect(find.text('Where is the cinema?'), findsOneWidget);
      expect(find.text('Something went wrong.'), findsOneWidget);
    });
  });

  group('forms', () {
    FormEvent book({Map<String, Object?> prefill = const {}, Map<String, Object?> surface = bookCard}) => FormEvent(
        callId: 'c3', formId: 'f1', component: 'book_table', tool: 'bookings.create', surface: surface,
        props: {'form': prefill}, turnId: 't1');
    Finder box(String id) => find.descendant(of: find.byKey(ValueKey('zi-field-f1-$id')), matching: find.byType(EditableText));
    Finder nameBox() => box('name');
    Finder chatList() => find.descendant(of: find.byType(ListView), matching: find.byType(Scrollable)).first;
    final longAnswer = TextDelta(text: List.filled(60, 'A long answer.').join('\n\n'));
    Future<void> showForm(WidgetTester tester, {Map<String, Object?> prefill = const {}}) async {
      turns.script([started, book(prefill: prefill), done]);
      await open(tester);
      await type(tester, 'book a table');
    }

    testWidgets('a form card is drawn from the event with what is prefilled', (tester) async {
      await showForm(tester, prefill: {'name': 'Ali'});
      expect(find.text('Your name'), findsOneWidget);
      expect(tester.widget<EditableText>(nameBox()).controller.text, 'Ali');
    });

    testWidgets('Send sends the values; the card turns into label and value lines and says Sent', (tester) async {
      await showForm(tester, prefill: {'name': 'Ali'});
      turns.script([started, const TextDelta(text: 'Booking…'), done]);
      await tester.tap(find.byKey(const ValueKey('zi-form-send')));
      await tester.pumpAndSettle();
      expect((turns.starts.last.input['values']! as Map)['name'], 'Ali');
      expect(nameBox(), findsNothing);
      expect(find.text('Ali'), findsOneWidget);
      expect(find.text('Sent'), findsOneWidget);
    });

    testWidgets('a failing field keeps the form open with its error under it', (tester) async {
      await showForm(tester);
      await tester.tap(find.byKey(const ValueKey('zi-form-send')));
      await tester.pumpAndSettle();
      expect(turns.starts, hasLength(1));
      expect(find.text('Fill this in'), findsOneWidget);
    });

    testWidgets('typing in the chat\'s own input keeps the form\'s parsed template and what is typed', (tester) async {
      await showForm(tester);
      await tester.enterText(nameBox(), 'Ali');
      final before = tester.widget<ZiSurfaceView>(find.byType(ZiSurfaceView)).surface;
      await tester.enterText(find.byType(TextField).last, 'one more thing');
      await tester.pump();
      expect(identical(tester.widget<ZiSurfaceView>(find.byType(ZiSurfaceView)).surface, before), isTrue);
      expect(tester.widget<EditableText>(nameBox()).controller.text, 'Ali');
    });

    testWidgets('a result card is parsed once too', (tester) async {
      turns.script([started,
        const MountComponent(callId: 'm1', component: 'cinema_details', kind: 'inline', props: {'name': 'Cinematica'}, surface: cinemaCard),
        done]);
      await open(tester);
      await type(tester, 'kino');
      final before = tester.widget<ZiSurfaceView>(find.byType(ZiSurfaceView)).surface;
      await tester.enterText(find.byType(TextField), 'x');
      await tester.pump();
      expect(identical(tester.widget<ZiSurfaceView>(find.byType(ZiSurfaceView)).surface, before), isTrue);
    });

    testWidgets('typing in a field does not move the chat', (tester) async {
      turns.script([started, book(), longAnswer, done]);
      await open(tester);
      await type(tester, 'book a table');
      await tester.scrollUntilVisible(nameBox(), -200, scrollable: chatList());
      final position = tester.state<ScrollableState>(chatList()).position;
      final at = position.pixels;
      await tester.enterText(nameBox(), 'Ali');
      await tester.pump();
      expect(position.pixels, at);
    });

    testWidgets('what is typed survives the field scrolling out of the list, and the chat closing', (tester) async {
      turns.script([started, book(), longAnswer, done]);
      await open(tester);
      await type(tester, 'book a table');
      await tester.scrollUntilVisible(nameBox(), -200, scrollable: chatList());
      await tester.enterText(nameBox(), 'Ali');
      FocusManager.instance.primaryFocus?.unfocus(); // a focused field is kept alive; an idle one is not
      await tester.pump();
      await tester.drag(chatList(), const Offset(0, -5000));
      await tester.pumpAndSettle();
      expect(nameBox(), findsNothing);
      await tester.scrollUntilVisible(nameBox(), -200, scrollable: chatList());
      expect(tester.widget<EditableText>(nameBox()).controller.text, 'Ali');
      Navigator.of(tester.element(find.byType(ZiChatSheet))).pop();
      await tester.pumpAndSettle();
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(nameBox(), 200, scrollable: chatList());
      expect(tester.widget<EditableText>(nameBox()).controller.text, 'Ali');
    });

    testWidgets('the field being typed in stays above the keyboard', (tester) async {
      turns.script([started, longAnswer, book(), done]); // the form is the last thing, at the foot of the chat
      await open(tester);
      await type(tester, 'book a table');
      await tester.tap(box('phone'));
      tester.view.viewInsets = const FakeViewPadding(bottom: 900);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      final keyboardTop = (tester.view.physicalSize.height - 900) / tester.view.devicePixelRatio;
      expect(tester.getBottomLeft(box('phone')).dy, lessThanOrEqualTo(keyboardTop));
    });

    testWidgets('a failed Send above the list brings the first failing field into view with its label and error', (tester) async {
      const tallCard = <String, Object?>{'createSurface': {'root': 'root', 'components': [
        {'id': 'root', 'component': 'Column', 'gap': 12, 'children': ['name', 'phone', 'email', 'city', 'guests', 'notes', 'send']},
        {'id': 'name', 'component': 'TextField', 'field': 'name', 'label': 'Your name', 'checks': [{'rule': 'required'}]},
        {'id': 'phone', 'component': 'TextField', 'field': 'phone', 'label': 'Phone', 'input': 'phone'},
        {'id': 'email', 'component': 'TextField', 'field': 'email', 'label': 'Email', 'input': 'email'},
        {'id': 'city', 'component': 'TextField', 'field': 'city', 'label': 'City'},
        {'id': 'guests', 'component': 'TextField', 'field': 'guests', 'label': 'Guests', 'input': 'number'},
        {'id': 'notes', 'component': 'TextField', 'field': 'notes', 'label': 'Notes', 'input': 'multiline'},
        {'id': 'send', 'component': 'Button', 'label': 'Book', 'action': {'name': 'submit'}}]}};
      turns.script([started, book(surface: tallCard), done]);
      await open(tester);
      await type(tester, 'book a table');
      tester.view.viewInsets = const FakeViewPadding(bottom: 900);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      final position = tester.state<ScrollableState>(chatList()).position;
      position.jumpTo(position.maxScrollExtent);
      await tester.pumpAndSettle();
      final list = tester.getRect(chatList());
      expect(tester.getRect(find.text('Your name')).top, lessThan(list.top)); // the form is taller than the list
      await tester.tap(find.byKey(const ValueKey('zi-form-send')));
      await tester.pumpAndSettle();
      expect(turns.starts, hasLength(1));
      for (final part in [find.text('Your name'), nameBox(), find.byKey(const ValueKey('zi-error-name'))]) {
        final rect = tester.getRect(part);
        expect(rect.top, greaterThanOrEqualTo(list.top));
        expect(rect.bottom, lessThanOrEqualTo(list.bottom));
      }
    });

    testWidgets('back to a new chat, then the conversation from the history, shows what was typed into its form', (tester) async {
      final history = FakeHistory()
        ..saved = [summary('c1', title: 'Table for two')]
        ..transcripts['c1'] = const [
          ZiUserItem('book a table'),
          ZiFormItem(formId: 'f1', callId: 'c3', component: 'book_table', tool: 'bookings.create', surface: bookCard, data: {'form': {}}),
        ];
      turns.script([started, book(), done]);
      await open(tester, history: history);
      await type(tester, 'book a table');
      await tester.enterText(nameBox(), 'Vali');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('zi-back')));
      await tester.pumpAndSettle();
      expect(find.text('How can I help you?'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('zi-history')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Table for two'));
      await tester.pumpAndSettle();
      expect(tester.widget<EditableText>(nameBox()).controller.text, 'Vali');
    });

    testWidgets('no follow-up chips while a form waits for the person; they come back once it is answered', (tester) async {
      turns.script([started, book(prefill: {'name': 'Ali'}), const SuggestionsEvent(items: ['Tell me more'], turnId: 't1'), done]);
      await open(tester);
      await type(tester, 'book a table');
      expect(cubit.state.suggestions, ['Tell me more']);
      expect(find.text('Tell me more'), findsNothing);
      turns.script([started, const SuggestionsEvent(items: ['Tell me more'], turnId: 't2'), done]);
      await tester.tap(find.byKey(const ValueKey('zi-form-send')));
      await tester.pumpAndSettle();
      expect(find.text('Sent'), findsOneWidget);
      expect(find.text('Tell me more'), findsOneWidget);
    });

    testWidgets('a form with a block this build cannot draw shows the update line and no fields', (tester) async {
      turns.script([started, book(surface: const {'createSurface': {'root': 'root', 'components': [
        {'id': 'root', 'component': 'Column', 'children': ['name', 'stars']},
        {'id': 'name', 'component': 'TextField', 'field': 'name', 'label': 'Your name'},
        {'id': 'stars', 'component': 'Slider', 'field': 'stars', 'label': 'Stars'}]}}), done]);
      await open(tester);
      await type(tester, 'rate');
      expect(tester.widget<Text>(find.byKey(const ValueKey('zi-form-update'))).data, 'Update the app to answer this.');
      expect(find.text('Your name'), findsNothing);
    });

    testWidgets('no "Thinking…" while a form waits for the person; it shows while the answers are being sent', (tester) async {
      final showing = StreamController<TurnEvent>();
      turns.legs.add(showing.stream);
      await open(tester);
      await type(tester, 'book a table');
      showing..add(started)..add(book(prefill: {'name': 'Ali'}));
      await tester.pump(Duration.zero); // delivers the events, then draws the frame they ask for
      expect(find.byKey(const ValueKey('zi-form-send')), findsOneWidget);
      expect(find.text('Thinking…'), findsNothing); // the turn still runs, but the next move is the person's
      showing.add(done);
      await showing.close();
      await tester.pumpAndSettle();
      final sending = StreamController<TurnEvent>();
      addTearDown(sending.close);
      turns.legs.add(sending.stream);
      await tester.tap(find.byKey(const ValueKey('zi-form-send')));
      await tester.pump();
      expect(find.text('Thinking…'), findsOneWidget);
    });
  });
}
