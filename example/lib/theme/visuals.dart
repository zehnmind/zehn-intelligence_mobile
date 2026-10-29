import 'package:flutter/material.dart';

import '../models/destination.dart';
import '../models/tour_category.dart';

extension TourCategoryVisuals on TourCategory {
  IconData get icon => switch (this) {
    TourCategory.beach => Icons.beach_access_rounded,
    TourCategory.culture => Icons.account_balance_rounded,
    TourCategory.adventure => Icons.hiking_rounded,
    TourCategory.city => Icons.location_city_rounded,
    TourCategory.nature => Icons.forest_rounded,
  };
}

extension DestinationVisuals on Destination {
  /// Colors of the placeholder shown when a photo can't be loaded.
  List<Color> get gradient => switch (this) {
    Destination.turkey => const [Color(0xFFB83227), Color(0xFFE67E22)],
    Destination.uae => const [Color(0xFF9C6B1E), Color(0xFFE0B354)],
    Destination.thailand => const [Color(0xFF1F7A4D), Color(0xFF38B2AC)],
    Destination.maldives => const [Color(0xFF0987A0), Color(0xFF4FD1C5)],
    Destination.georgia => const [Color(0xFF553C9A), Color(0xFF9F7AEA)],
    Destination.uzbekistan => const [Color(0xFF1E4E8C), Color(0xFF3FA7D6)],
  };
}
