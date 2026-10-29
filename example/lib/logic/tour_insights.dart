import 'dart:math';

import '../models/destination.dart';
import '../models/tour.dart';
import '../models/tour_category.dart';

/// Highest rated first; more reviews break ties.
int compareByPopularity(Tour a, Tour b) {
  final byRating = b.rating.compareTo(a.rating);
  return byRating != 0 ? byRating : b.reviewCount.compareTo(a.reviewCount);
}

/// The most popular tours, optionally limited to one [category].
List<Tour> popularTours(
  Iterable<Tour> tours, {
  TourCategory? category,
  int limit = 6,
}) {
  final matching = [
    for (final tour in tours)
      if (category == null || tour.category == category) tour,
  ]..sort(compareByPopularity);
  return matching.take(limit).toList();
}

class DestinationSummary {
  const DestinationSummary({
    required this.destination,
    required this.tourCount,
    required this.lowestPrice,
    required this.coverImageUrl,
  });

  final Destination destination;
  final int tourCount;
  final int lowestPrice;

  /// The image of the destination's most popular tour.
  final String coverImageUrl;
}

/// One summary per destination that has tours, in [Destination] order.
List<DestinationSummary> summarizeDestinations(Iterable<Tour> tours) {
  final summaries = <DestinationSummary>[];
  for (final destination in Destination.values) {
    final matching = [
      for (final tour in tours)
        if (tour.destination == destination) tour,
    ]..sort(compareByPopularity);
    if (matching.isEmpty) continue;
    summaries.add(
      DestinationSummary(
        destination: destination,
        tourCount: matching.length,
        lowestPrice: matching.map((tour) => tour.price).reduce(min),
        coverImageUrl: matching.first.imageUrl,
      ),
    );
  }
  return summaries;
}
