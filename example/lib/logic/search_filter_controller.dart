import 'package:flutter/foundation.dart';

import '../models/destination.dart';
import 'tour_filter.dart';

/// The search screen's query and filters. Shared so the home screen can open
/// the search pre-filtered to a destination.
class SearchFilterController extends ChangeNotifier {
  TourFilter _filter = const TourFilter();

  TourFilter get filter => _filter;

  void update(TourFilter filter) {
    if (filter == _filter) return;
    _filter = filter;
    notifyListeners();
  }

  void setQuery(String query) => update(_filter.copyWith(query: query));

  void setDestination(Destination? destination) =>
      update(_filter.copyWith(destination: () => destination));

  void clearFilters() => update(_filter.withoutFilters());

  void reset() => update(const TourFilter());
}
