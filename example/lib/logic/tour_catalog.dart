import 'package:flutter/foundation.dart';

import '../data/tour_repository.dart';
import '../models/tour.dart';

enum CatalogStatus { loading, ready, error }

/// Loads the tours once and looks them up by id.
class TourCatalog extends ChangeNotifier {
  TourCatalog(this._repository);

  final TourRepository _repository;

  CatalogStatus _status = CatalogStatus.loading;
  List<Tour> _tours = const [];
  Map<String, Tour> _byId = const {};
  bool _disposed = false;

  CatalogStatus get status => _status;
  List<Tour> get tours => _tours;

  Tour? tourById(String id) => _byId[id];

  Future<void> load() async {
    _status = CatalogStatus.loading;
    notifyListeners();
    try {
      final tours = await _repository.fetchTours();
      _tours = List.unmodifiable(tours);
      _byId = {for (final tour in tours) tour.id: tour};
      _status = CatalogStatus.ready;
    } catch (error, stackTrace) {
      debugPrint('Loading tours failed: $error\n$stackTrace');
      _status = CatalogStatus.error;
    }
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
