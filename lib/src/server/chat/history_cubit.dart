import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../api/api_client.dart';
import 'history.dart';

class ZiHistoryState extends Equatable {
  const ZiHistoryState({
    this.items = const [],
    this.total = 0,
    this.loading = false,
    this.error,
    this.notice,
    this.opening,
  });

  /// Latest active first, as many pages as were loaded.
  final List<ZiConversationSummary> items;
  final int total;

  /// A page is on its way.
  final bool loading;

  /// The list could not be loaded at all: an error code, for the retry.
  final String? error;

  /// A delete or an open failed: its error code.
  final String? notice;

  /// The conversation being read.
  final String? opening;

  bool get hasMore => items.length < total;

  ZiHistoryState copyWith({
    List<ZiConversationSummary>? items,
    int? total,
    bool? loading,
    String? error,
    String? notice,
    String? opening,
  }) => ZiHistoryState(
    items: items ?? this.items,
    total: total ?? this.total,
    loading: loading ?? this.loading,
    error: error,
    notice: notice,
    opening: opening,
  );

  @override
  List<Object?> get props => [items, total, loading, error, notice, opening];
}

/// The history screen: the user's conversations, page by page, to open or
/// delete.
class ZiHistoryCubit extends Cubit<ZiHistoryState> {
  ZiHistoryCubit(this._history) : super(const ZiHistoryState());

  final ZiHistory _history;

  /// The first page, again.
  Future<void> load() async {
    _emit(const ZiHistoryState(loading: true));
    try {
      final page = await _history.list();
      _emit(ZiHistoryState(items: page.items, total: page.total));
    } on Object catch (e) {
      _emit(ZiHistoryState(error: _code(e)));
    }
  }

  /// The next page. After a delete the server's pages have moved up, so the
  /// page is counted from what is shown, and what is already shown is skipped.
  Future<void> loadMore() async {
    if (state.loading || !state.hasMore || state.error != null) return;
    _emit(state.copyWith(loading: true));
    try {
      final page = await _history.list(page: state.items.length ~/ ZiHistory.pageSize + 1);
      final shown = {for (final s in state.items) s.id};
      final fresh = [for (final s in page.items) if (!shown.contains(s.id)) s];
      // A page with nothing new: the list is all here.
      final total = fresh.isEmpty ? state.items.length : page.total;
      _emit(state.copyWith(items: [...state.items, ...fresh], total: total, loading: false));
    } on Object catch (e) {
      _emit(state.copyWith(loading: false, notice: _code(e)));
    }
  }

  /// True when the conversation is gone (already gone counts).
  Future<bool> delete(String id) async {
    try {
      await _history.delete(id);
    } on ZiApiException catch (e) {
      if (e.code != 'conversation_not_found') {
        _emit(state.copyWith(notice: e.code));
        return false;
      }
    } on Object catch (e) {
      _emit(state.copyWith(notice: _code(e)));
      return false;
    }
    final items = [for (final s in state.items) if (s.id != id) s];
    final removed = state.items.length - items.length;
    _emit(state.copyWith(items: items, total: state.total - removed));
    return true;
  }

  /// The conversation to show, or null (the reason is the notice).
  Future<ZiConversation?> open(String id) async {
    if (state.opening != null) return null;
    _emit(state.copyWith(opening: id));
    try {
      final conversation = await _history.read(id);
      _emit(state.copyWith());
      return conversation;
    } on Object catch (e) {
      _emit(state.copyWith(notice: _code(e)));
      return null;
    }
  }

  static String _code(Object e) => e is ZiApiException ? e.code : 'internal_error';

  void _emit(ZiHistoryState next) {
    if (!isClosed) emit(next);
  }
}
