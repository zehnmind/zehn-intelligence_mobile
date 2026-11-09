import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:zehn_intelligence/src/server/api/turn_client.dart';
import 'package:zehn_intelligence/src/server/api/turn_events.dart';
import 'package:zehn_intelligence/src/server/chat/chat_cubit.dart';
import 'package:zehn_intelligence/src/server/chat/chat_state.dart';

import '../../support/chat_fakes.dart';

class ThrowingRunner extends FakeRunner {
  @override
  Future<List<ToolCallResult>> runAll(List<ClientApiRequest> calls) async => throw StateError('bug');
}

void main() {
  late FakeTurns turns;
  late FakeRunner runner;
  late FakeAudio audio;
  late String language;
  late ZiChatCubit cubit;

  setUp(() {
    turns = FakeTurns();
    runner = FakeRunner();
    audio = FakeAudio();
    language = 'uz';
    cubit = ZiChatCubit(
      turns: turns,
      tools: runner,
      audio: audio,
      language: () => language,
      starterSuggestions: () async => ['Kino', 'Parking'],
    );
  });

  tearDown(() => cubit.close());

  const started = TurnStarted(conversationId: 'c1', conversationNew: true, turnId: 't1');
  const done = TurnDone(outcome: 'answered', turnId: 't1');

  test('text deltas build one assistant message', () async {
    turns.script([started, const TextDelta(text: 'Sa'), const TextDelta(text: 'lom'), done]);
    await cubit.sendText('  hi  ');
    expect(cubit.state.items, [const ZiUserItem('hi'), const ZiAssistantItem('a1', 'Salom')]);
    expect(cubit.state.busy, isFalse);
    expect(cubit.state.conversationId, 'c1');
  });

  test('conversation id is kept for the next turn', () async {
    turns
      ..script([started, done])
      ..script([done]);
    await cubit.sendText('one');
    await cubit.sendText('two');
    expect(turns.starts[0].conversationId, isNull);
    expect(turns.starts[1].conversationId, 'c1');
  });

  test('text over 4000 characters is cut', () async {
    turns.script([done]);
    await cubit.sendText('a' * 4100);
    expect((turns.starts.single.toJson()['input']! as Map)['text'], hasLength(4000));
  });

  test('paused turn runs tools and posts their results', () async {
    final deadline = DateTime.utc(2030);
    turns
      ..script([
        started,
        const ClientApiRequest(callId: 'c_1', tool: 'cinemas.list', args: {}),
        const ClientApiRequest(callId: 'c_2', tool: 'stores.list', args: {'page': 1}),
        TurnPaused(callIds: const ['c_1', 'c_2'], deadline: deadline, maxResultBytes: 32768, turnId: 't1'),
      ])
      ..script([const TextDelta(text: 'Found'), done]);
    await cubit.sendText('kino');
    expect(runner.rounds.single.map((c) => c.callId), ['c_1', 'c_2']);
    final (turnId, results, sentDeadline) = turns.results.single;
    expect(turnId, 't1');
    expect(results.map((r) => r.callId), ['c_1', 'c_2']);
    expect(sentDeadline, deadline);
    expect((cubit.state.items.last as ZiAssistantItem).text, 'Found');
  });

  test('inline component goes to items, route goes to opens', () async {
    final opened = <ZiComponentItem>[];
    final sub = cubit.opens.listen(opened.add);
    turns.script([
      started,
      const TextDelta(text: 'Here:'),
      const MountComponent(callId: 'm1', component: 'cinema_details', kind: 'inline', props: {'id': 1}, surface: {'root': 'r'}),
      const MountComponent(callId: 'm2', component: 'loyalty_page', kind: 'route', props: {}, route: '/loyalty'),
      const TextDelta(text: 'Anything else?'),
      done,
    ]);
    await cubit.sendText('kino');
    await Future<void>.delayed(Duration.zero);
    expect(cubit.state.items, [
      const ZiUserItem('kino'),
      const ZiAssistantItem('a1', 'Here:'),
      const ZiComponentItem('m1', 'cinema_details', ZiComponentKind.inline, {'id': 1}, surface: {'root': 'r'}),
      const ZiAssistantItem('a2', 'Anything else?'),
    ]);
    expect(opened.single.component, 'loyalty_page');
    expect(opened.single.kind, ZiComponentKind.route);
    expect(opened.single.route, '/loyalty');
    await sub.cancel();
  });

  test('conversation_spec_changed resends once with a null conversation id', () async {
    turns
      ..script([started, done])
      ..script([failure('conversation_spec_changed')])
      ..script([const TurnStarted(conversationId: 'c2', conversationNew: true), done]);
    await cubit.sendText('one');
    await cubit.sendText('two');
    expect(turns.starts.map((s) => s.conversationId), [null, 'c1', null]);
    expect(cubit.state.conversationId, 'c2');
    expect(cubit.state.items.whereType<ZiErrorItem>(), isEmpty);
  });

  test('a second conversation error is shown', () async {
    turns
      ..script([failure('conversation_full')])
      ..script([failure('conversation_full')]);
    await cubit.sendText('one');
    expect(turns.starts, hasLength(2));
    expect(cubit.state.items.last, const ZiErrorItem('conversation_full'));
  });

  test('retryable error shows retry, retry resends the last input', () async {
    turns
      ..script([failure('llm_unavailable', retryable: true)])
      ..script([const TextDelta(text: 'ok'), done]);
    await cubit.sendText('hello');
    expect(cubit.state.items.last, const ZiErrorItem('llm_unavailable', retryable: true));
    await cubit.retry();
    expect((turns.starts[1].toJson()['input']! as Map)['text'], 'hello');
    expect(cubit.state.items, [const ZiUserItem('hello'), const ZiAssistantItem('a1', 'ok')]);
  });

  test('send while busy is ignored', () async {
    final leg = StreamController<TurnEvent>();
    turns.legs.add(leg.stream);
    unawaited(cubit.sendText('one'));
    await Future<void>.delayed(Duration.zero);
    expect(cubit.state.busy, isTrue);
    await cubit.sendText('two');
    expect(turns.starts, hasLength(1));
    await leg.close();
  });

  test('language is read per turn', () async {
    turns
      ..script([done])
      ..script([done]);
    await cubit.sendText('one');
    language = 'ru';
    await cubit.sendText('two');
    expect(turns.starts.map((s) => s.toJson()['language']), ['uz', 'ru']);
  });

  test('close during stream does not throw', () async {
    final leg = StreamController<TurnEvent>();
    turns.legs.add(leg.stream);
    unawaited(cubit.sendText('one'));
    await Future<void>.delayed(Duration.zero);
    await cubit.close();
    leg.add(const TextDelta(text: 'late'));
    await leg.close();
    await Future<void>.delayed(Duration.zero);
    expect(audio.stops, greaterThanOrEqualTo(1));
  });

  test('audio clips are queued and a new send stops playback', () async {
    turns
      ..script([started, const AudioClip(format: 'mp3', text: 'Hi', data: 'AAA=', seq: 3), done])
      ..script([done]);
    await cubit.sendAudio('BBB=', 'm4a', voiceReply: true);
    expect(audio.clips.single, (3, 'AAA=', 'mp3'));
    expect(turns.starts.single.toJson()['voice_reply'], isTrue);
    final stopsBefore = audio.stops;
    await cubit.sendText('next');
    expect(audio.stops, stopsBefore + 1);
  });

  test('transcript replaces the spoken user bubble', () async {
    turns.script([started, const TranscriptEvent(text: 'kino qayerda'), done]);
    await cubit.sendAudio('BBB=', 'm4a', voiceReply: false);
    expect(cubit.state.items.first, const ZiUserItem('kino qayerda', spoken: true));
  });

  test('starter suggestions load, turn suggestions replace them, a send clears them', () async {
    await cubit.loadStarterSuggestions();
    expect(cubit.state.suggestions, ['Kino', 'Parking']);
    turns
      ..script([started, const SuggestionsEvent(items: ['Cheaper?']), done])
      ..script([done]);
    await cubit.sendText('one');
    expect(cubit.state.suggestions, ['Cheaper?']);
    await cubit.sendText('two');
    expect(cubit.state.suggestions, isEmpty);
  });

  test('reset clears the chat and stops audio', () async {
    turns.script([started, const TextDelta(text: 'x'), done]);
    await cubit.sendText('one');
    cubit.reset();
    expect(cubit.state.items, isEmpty);
    expect(cubit.state.conversationId, isNull);
    expect(audio.stops, greaterThanOrEqualTo(1));
  });

  test('showError adds a local error item', () {
    cubit.showError('payload_too_large');
    expect(cubit.state.items.single, const ZiErrorItem('payload_too_large'));
    expect(cubit.state.busy, isFalse);
  });

  test('a failure inside the turn ends it with a retryable error', () async {
    final broken = ZiChatCubit(turns: turns, tools: ThrowingRunner(), audio: audio, language: () => 'uz');
    turns.script([
      started,
      const ClientApiRequest(callId: 'c_1', tool: 'x', args: {}),
      TurnPaused(callIds: const ['c_1'], deadline: DateTime.utc(2030), maxResultBytes: 32768, turnId: 't1'),
    ]);
    await broken.sendText('one');
    expect(broken.state.busy, isFalse);
    expect(broken.state.items.last, const ZiErrorItem('internal_error', retryable: true));
    await broken.close();
  });

  test('stopAudio stops playback', () async {
    final before = audio.stops;
    await cubit.stopAudio();
    expect(audio.stops, before + 1);
  });

  group('confirm cards', () {
    const card = ConfirmEvent(
      callId: 'c2',
      actionId: 'a1',
      tool: 'parking.reserve',
      method: 'POST',
      surface: {'root': 'r'},
      props: {'zone_id': 12},
      confirmLabel: 'Reserve',
      expiresIn: Duration(minutes: 10),
      turnId: 't1',
    );

    Future<void> showCard([ConfirmEvent event = card]) async {
      turns.script([started, const TextDelta(text: 'Reserve zone B1?'), event, done]);
      await cubit.sendText('reserve');
    }

    ZiConfirmItem item() => cubit.state.items.whereType<ZiConfirmItem>().single;

    test('a confirm event shows a pending card with its template, data and label', () async {
      await showCard();
      expect(item(), const ZiConfirmItem(
        actionId: 'a1',
        tool: 'parking.reserve',
        method: 'POST',
        surface: {'root': 'r'},
        data: {'zone_id': 12},
        label: 'Reserve',
      ));
      expect(cubit.state.busy, isFalse);
    });

    test('Confirm sends an action turn and allows that one write', () async {
      await showCard();
      turns.script([const TextDelta(text: 'Reserved.'), done]);
      await cubit.decide('a1', confirm: true);
      expect(turns.starts.last.toJson(), {
        'conversation_id': 'c1',
        'input': {'type': 'action', 'action_id': 'a1', 'decision': 'confirm'},
        'language': 'uz',
        'utc_offset_minutes': isA<int>(),
        'voice_reply': false,
      });
      expect(item().status, ZiConfirmStatus.confirmed);
      // No bubble for the tap: the card shows the answer.
      expect(cubit.state.items.whereType<ZiUserItem>(), hasLength(1));
      expect(cubit.takeConfirmed('a1'), isTrue);
      expect(cubit.takeConfirmed('a1'), isFalse);
    });

    test('Cancel sends a cancel decision and allows nothing', () async {
      await showCard();
      turns.script([done]);
      await cubit.decide('a1', confirm: false);
      expect((turns.starts.last.toJson()['input']! as Map)['decision'], 'cancel');
      expect(item().status, ZiConfirmStatus.cancelled);
      expect(cubit.takeConfirmed('a1'), isFalse);
    });

    test('a second tap is ignored', () async {
      await showCard();
      turns.script([done]);
      await cubit.decide('a1', confirm: true);
      await cubit.decide('a1', confirm: false);
      expect(turns.starts, hasLength(2));
      expect(item().status, ZiConfirmStatus.confirmed);
    });

    test('a card past expires_in shows expired and sends nothing', () async {
      await showCard(const ConfirmEvent(
        callId: 'c2',
        actionId: 'a1',
        tool: 'parking.reserve',
        method: 'POST',
        props: {},
        expiresIn: Duration(milliseconds: 1),
        turnId: 't1',
      ));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(item().status, ZiConfirmStatus.expired);
      await cubit.decide('a1', confirm: true);
      expect(turns.starts, hasLength(1));
    });

    for (final code in ['action_used', 'action_expired', 'action_not_found']) {
      test('$code marks the card expired, with no error message', () async {
        await showCard();
        turns.script([failure(code)]);
        await cubit.decide('a1', confirm: true);
        expect(item().status, ZiConfirmStatus.expired);
        expect(cubit.state.items.whereType<ZiErrorItem>(), isEmpty);
        expect(cubit.takeConfirmed('a1'), isFalse);
        expect(cubit.state.busy, isFalse);
      });
    }

    test('reset forgets confirmed actions', () async {
      await showCard();
      turns.script([done]);
      await cubit.decide('a1', confirm: true);
      cubit.reset();
      expect(cubit.takeConfirmed('a1'), isFalse);
    });
  });
}
