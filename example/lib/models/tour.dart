import 'package:flutter/foundation.dart';

import 'destination.dart';
import 'tour_category.dart';

@immutable
class Tour {
  const Tour({
    required this.id,
    required this.title,
    required this.destination,
    required this.location,
    required this.category,
    required this.price,
    required this.durationDays,
    required this.rating,
    required this.reviewCount,
    required this.imageUrl,
    required this.description,
    required this.highlights,
    required this.included,
    required this.maxGroupSize,
    required this.languages,
    required this.departureWeekdays,
  });

  /// Stable identifier. Favorites and navigation refer to tours by this id.
  final String id;
  final String title;
  final Destination destination;

  /// City or region within the destination, e.g. "Göreme, Cappadocia".
  final String location;
  final TourCategory category;

  /// Price per person in whole US dollars.
  final int price;
  final int durationDays;

  /// Average review score from 0 to 5.
  final double rating;
  final int reviewCount;
  final String imageUrl;
  final String description;
  final List<String> highlights;
  final List<String> included;
  final int maxGroupSize;
  final List<String> languages;

  /// Weekdays the tour departs on, using [DateTime.monday]..[DateTime.sunday].
  final List<int> departureWeekdays;

  @override
  bool operator ==(Object other) => other is Tour && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'Tour($id)';
}
