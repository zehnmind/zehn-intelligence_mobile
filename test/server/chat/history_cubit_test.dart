import 'package:flutter_test/flutter_test.dart';
import 'package:zehn_intelligence/src/server/api/api_client.dart';
import 'package:zehn_intelligence/src/server/chat/history_cubit.dart';

import '../../support/history_fakes.dart';

void main() {
  late FakeHistory history;
  late ZiHistoryCubit cubit;

  setUp(() {
    history = FakeHistory();
    cubit = ZiHistoryCubit(history);
  });

  tearDown(() => cubit.close());

  test('load shows the first page', () async {
    history.saved = [summary('c1'), summary('c2')];
    final loading = cubit.load();
    expect(cubit.state.loading, isTrue);
    await loading;
    expect(cubit.state.items.map((s) => s.id), ['c1', 'c2']);
    expect(cubit.state.loading, isFalse);
    expect(cubit.state.hasMore, isFalse);
  });

  test('a list that fails keeps its code for the retry', () async {
    history.failWith = const ZiApiException('network_error', retryable: true);
    await cubit.load();
    expect(cubit.state.error, 'network_error');
    history.failWith = null;
    history.saved = [summary('c1')];
    await cubit.load();
    expect(cubit.state.error, isNull);
    expect(cubit.state.items.single.id, 'c1');
  });

  test('more pages come as the list scrolls, without repeats after a delete', () async {
    history.saved = [for (var i = 0; i < 45; i++) summary('c$i')];
    await cubit.load();
    expect(cubit.state.items, hasLength(20));
    expect(cubit.state.hasMore, isTrue);
    // A delete moves every later conversation one place up on the server.
    await cubit.delete('c3');
    await cubit.loadMore();
    await cubit.loadMore();
    await cubit.loadMore();
    final ids = cubit.state.items.map((s) => s.id).toList();
    expect(ids, [for (var i = 0; i < 45; i++) if (i != 3) 'c$i']);
    expect(cubit.state.hasMore, isFalse);
  });

  test('delete takes the row out; one already gone is taken out too', () async {
    history.saved = [summary('c1'), summary('c2'), summary('c3')];
    await cubit.load();
    expect(await cubit.delete('c1'), isTrue);
    history.deleteFails = const ZiApiException('conversation_not_found');
    expect(await cubit.delete('c2'), isTrue);
    expect(cubit.state.items.map((s) => s.id), ['c3']);
    expect(cubit.state.total, 1);
  });

  test('a delete the server refuses keeps the row and says why', () async {
    history.saved = [summary('c1')];
    await cubit.load();
    history.deleteFails = const ZiApiException('turn_in_progress');
    expect(await cubit.delete('c1'), isFalse);
    expect(cubit.state.items.single.id, 'c1');
    expect(cubit.state.notice, 'turn_in_progress');
  });

  test('open reads the conversation; one that fails is a notice', () async {
    history.saved = [summary('c1')];
    await cubit.load();
    final opening = cubit.open('c1');
    expect(cubit.state.opening, 'c1');
    expect((await opening)?.id, 'c1');
    expect(cubit.state.opening, isNull);
    history.failWith = const ZiApiException('conversation_not_found');
    expect(await cubit.open('c1'), isNull);
    expect(cubit.state.notice, 'conversation_not_found');
  });
}
