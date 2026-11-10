import 'package:zehn_intelligence/src/server/api/api_client.dart';
import 'package:zehn_intelligence/src/server/auth/token_source.dart';
import 'package:zehn_intelligence/src/server/chat/chat_state.dart';
import 'package:zehn_intelligence/src/server/chat/history.dart';

import 'test_info.dart';

ZiConversationSummary summary(String id, {String? title, bool canContinue = true}) => ZiConversationSummary(
  id: id,
  title: title ?? 'Question $id',
  createdAt: DateTime(2026, 11, 6, 9, 12),
  lastTurnAt: DateTime(2026, 11, 6, 9, 14),
  canContinue: canContinue,
);

/// A server's history in memory: pages of [ZiHistory.pageSize], latest first.
class FakeHistory extends ZiHistory {
  FakeHistory()
    : super(api: ZiApiClient(baseUrl: Uri.parse('http://unused.invalid'), info: info), tokens: () => const AnonymousTokenSource());

  List<ZiConversationSummary> saved = [];

  /// What [read] shows for a conversation; two lines by default.
  Map<String, List<ZiChatItem>> transcripts = {};
  ZiApiException? failWith;
  ZiApiException? deleteFails;
  final List<int> pages = [];

  @override
  Future<ZiConversationPage> list({int page = 1}) async {
    pages.add(page);
    final fail = failWith;
    if (fail != null) throw fail;
    final start = (page - 1) * ZiHistory.pageSize;
    return ZiConversationPage(items: saved.skip(start).take(ZiHistory.pageSize).toList(), total: saved.length);
  }

  @override
  Future<ZiConversation> read(String id) async {
    final fail = failWith;
    if (fail != null) throw fail;
    final s = saved.firstWhere((c) => c.id == id);
    return ZiConversation(
      summary: s,
      items: transcripts[id] ?? [ZiUserItem(s.title), ZiAssistantItem('h1', 'Answer to ${s.title}')],
    );
  }

  @override
  Future<void> delete(String id) async {
    final fail = deleteFails;
    if (fail != null) throw fail;
    saved.removeWhere((c) => c.id == id);
  }
}
