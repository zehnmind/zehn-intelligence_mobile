import 'package:flutter/widgets.dart';

import 'favorites_controller.dart';
import 'search_filter_controller.dart';
import 'tour_catalog.dart';

/// Makes a [Listenable] available to the widget tree. Widgets that look it up
/// with [watch] rebuild whenever it notifies.
class NotifierScope<T extends Listenable> extends InheritedNotifier<T> {
  const NotifierScope({
    super.key,
    required T super.notifier,
    required super.child,
  });

  /// Returns the nearest [T] and rebuilds [context] when it changes.
  static T watch<T extends Listenable>(BuildContext context) => _notifierOf(
    context.dependOnInheritedWidgetOfExactType<NotifierScope<T>>(),
  );

  /// Returns the nearest [T] without subscribing. Use in callbacks.
  static T read<T extends Listenable>(BuildContext context) =>
      _notifierOf(context.getInheritedWidgetOfExactType<NotifierScope<T>>());

  static T _notifierOf<T extends Listenable>(NotifierScope<T>? scope) {
    assert(scope != null, 'No NotifierScope<$T> above this widget.');
    return scope!.notifier!;
  }
}

/// Shorthands for the app-wide state. These subscribe the calling widget.
extension AppState on BuildContext {
  TourCatalog get catalog => NotifierScope.watch<TourCatalog>(this);
  FavoritesController get favorites =>
      NotifierScope.watch<FavoritesController>(this);
  SearchFilterController get searchFilter =>
      NotifierScope.watch<SearchFilterController>(this);
}
