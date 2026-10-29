import 'dart:collection';

import 'package:flutter/foundation.dart';

/// The ids of the tours the user saved, kept in the order they were added.
class FavoritesController extends ChangeNotifier {
  FavoritesController([Iterable<String> initialIds = const []])
    : _ids = LinkedHashSet.of(initialIds);

  final LinkedHashSet<String> _ids;

  /// Saved tour ids, oldest first.
  Set<String> get ids => UnmodifiableSetView(_ids);

  int get count => _ids.length;

  bool isFavorite(String tourId) => _ids.contains(tourId);

  void toggle(String tourId) {
    if (!_ids.remove(tourId)) _ids.add(tourId);
    notifyListeners();
  }

  void add(String tourId) {
    if (_ids.add(tourId)) notifyListeners();
  }

  void remove(String tourId) {
    if (_ids.remove(tourId)) notifyListeners();
  }
}
