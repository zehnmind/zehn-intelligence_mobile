import '../api/api_client.dart';
import '../auth/token_source.dart';
import 'chat_state.dart';

/// One of the user's conversations in the history list (`GET /v1/conversations`).
class ZiConversationSummary {
  const ZiConversationSummary({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.lastTurnAt,
    this.canContinue = false,
  });

  /// Null without a `conversation_id`.
  static ZiConversationSummary? tryParse(Object? json) {
    if (json is! Map || json['conversation_id'] is! String) return null;
    return ZiConversationSummary.fromJson(json);
  }

  factory ZiConversationSummary.fromJson(Map<dynamic, dynamic> json) {
    final created = _date(json['created_at']);
    final last = _date(json['last_turn_at']) ?? created;
    final epoch = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    return ZiConversationSummary(
      id: json['conversation_id'] is String ? json['conversation_id'] as String : '',
      title: json['title'] is String ? json['title'] as String : '',
      createdAt: created ?? last ?? epoch,
      lastTurnAt: last ?? epoch,
      canContinue: json['can_continue'] == true,
    );
  }

  final String id;

  /// The first question, at most 80 characters.
  final String title;
  final DateTime createdAt;
  final DateTime lastTurnAt;

  /// False: it started on another spec version, or it is full. It reads,
  /// but the next question starts a new conversation.
  final bool canContinue;
}

class ZiConversationPage {
  const ZiConversationPage({required this.items, required this.total});

  factory ZiConversationPage.fromJson(Object? json) {
    final map = json is Map ? json : const {};
    final items = map['items'] is List ? map['items'] as List : const [];
    final total = map['total'];
    return ZiConversationPage(
      items: [for (final item in items) ?ZiConversationSummary.tryParse(item)],
      total: total is int ? total : 0,
    );
  }

  final List<ZiConversationSummary> items;

  /// Every conversation the user has, on every page.
  final int total;
}

/// A conversation as the chat showed it (`GET /v1/conversations/{id}`).
class ZiConversation {
  const ZiConversation({required this.summary, required this.items});

  factory ZiConversation.fromJson(Object? json) {
    final map = json is Map ? json : const {};
    final messages = map['messages'] is List ? map['messages'] as List : const [];
    final items = <ZiChatItem>[];
    for (final (i, message) in messages.indexed) {
      if (message is Map) {
        if (_item(message, 'h$i') case final item?) items.add(item);
      }
    }
    return ZiConversation(summary: ZiConversationSummary.fromJson(map), items: items);
  }

  final ZiConversationSummary summary;
  final List<ZiChatItem> items;

  String get id => summary.id;
  bool get canContinue => summary.canContinue;
  DateTime get createdAt => summary.createdAt;

  /// The user's text, the assistant's text, an `inline` card, or a confirm
  /// card with what became of it. A `sheet` or `route` was opened, not shown
  /// in the chat, so it is left out (and never opened again).
  static ZiChatItem? _item(Map<dynamic, dynamic> m, String id) {
    final text = m['text'] is String ? (m['text'] as String).trim() : '';
    switch ((m['role'], m['type'])) {
      case ('user', 'text'):
        return text.isEmpty ? null : ZiUserItem(text, spoken: m['spoken'] == true);
      case ('assistant', 'text'):
        return text.isEmpty ? null : ZiAssistantItem(id, text);
      case ('assistant', 'component'):
        final component = m['component'];
        if (component is! String || (m['kind'] ?? 'inline') != 'inline') return null;
        return ZiComponentItem(id, component, ZiComponentKind.inline, _map(m['props']) ?? const {},
            surface: _map(m['surface']), route: m['route'] is String ? m['route'] as String : null);
      case ('assistant', 'confirm'):
        final action = m['action_id'];
        final tool = m['tool'];
        if (action is! String || tool is! String) return null;
        return ZiConfirmItem(
          actionId: action,
          tool: tool,
          method: '',
          surface: _map(m['surface']),
          data: _map(m['props']) ?? const {},
          label: m['confirm_label'] is String ? m['confirm_label'] as String : null,
          status: ZiConfirmStatus.values.asNameMap()[m['status']] ?? ZiConfirmStatus.pending,
        );
    }
    return null;
  }
}

/// The user's history on the console: per install, or per app user token
/// when the app gives one.
class ZiHistory {
  ZiHistory({required ZiApiClient api, required ZiTokenSource Function() tokens}) : _api = api, _tokens = tokens;

  static const pageSize = 20;

  final ZiApiClient _api;
  final ZiTokenSource Function() _tokens;

  /// The latest active first.
  Future<ZiConversationPage> list({int page = 1}) async => ZiConversationPage.fromJson(await _call(
        (token) => _api.getJson('/v1/conversations', query: {'page': '$page', 'size': '$pageSize'}, userToken: token)));

  Future<ZiConversation> read(String id) async =>
      ZiConversation.fromJson(await _call((token) => _api.getJson('/v1/conversations/${Uri.encodeComponent(id)}', userToken: token)));

  /// `409 turn_in_progress` while a turn is still open in it.
  Future<void> delete(String id) =>
      _call((token) => _api.deleteJson('/v1/conversations/${Uri.encodeComponent(id)}', userToken: token));

  Future<Object?> _call(Future<Object?> Function(String? token) call) async {
    final tokens = _tokens();
    try {
      return await call(await tokens.token());
    } on ZiApiException catch (e) {
      final fresh = e.code == 'user_token_expired' || e.code == 'user_token_required' ? await tokens.refresh() : null;
      if (fresh == null) rethrow;
      return call(fresh);
    }
  }
}

DateTime? _date(Object? v) => v is String ? DateTime.tryParse(v) : null;

Map<String, Object?>? _map(Object? v) => v is Map ? v.cast<String, Object?>() : null;
