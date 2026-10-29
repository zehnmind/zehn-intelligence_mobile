import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../models/destination.dart';
import '../models/tour.dart';

/// Trip length buckets offered by the duration filter.
enum DurationRange {
  any('Any length', 1, null),
  short('1–3 days', 1, 3),
  medium('4–6 days', 4, 6),
  long('7+ days', 7, null);

  const DurationRange(this.label, this.minDays, this.maxDays);

  final String label;
  final int minDays;

  /// Inclusive upper bound, or null for no limit.
  final int? maxDays;

  bool includes(int days) =>
      days >= minDays && (maxDays == null || days <= maxDays!);
}

/// Search text plus filters. Every set criterion must match (they combine
/// with AND); a null criterion matches everything.
@immutable
class TourFilter {
  const TourFilter({
    this.query = '',
    this.destination,
    this.maxPrice,
    this.minRating,
    this.duration = DurationRange.any,
  });

  final String query;
  final Destination? destination;

  /// Inclusive upper price per person in USD.
  final int? maxPrice;

  /// Inclusive lower rating.
  final double? minRating;
  final DurationRange duration;

  /// Number of filters set, not counting the search text.
  int get activeFilterCount => [
    destination != null,
    maxPrice != null,
    minRating != null,
    duration != DurationRange.any,
  ].where((isSet) => isSet).length;

  bool get hasActiveFilters => activeFilterCount > 0;

  bool get hasQuery => query.trim().isNotEmpty;

  /// Nullable fields take a getter so they can be cleared:
  /// `filter.copyWith(destination: () => null)`.
  TourFilter copyWith({
    String? query,
    ValueGetter<Destination?>? destination,
    ValueGetter<int?>? maxPrice,
    ValueGetter<double?>? minRating,
    DurationRange? duration,
  }) {
    return TourFilter(
      query: query ?? this.query,
      destination: destination != null ? destination() : this.destination,
      maxPrice: maxPrice != null ? maxPrice() : this.maxPrice,
      minRating: minRating != null ? minRating() : this.minRating,
      duration: duration ?? this.duration,
    );
  }

  /// Same search text, all filters cleared.
  TourFilter withoutFilters() => TourFilter(query: query);

  bool matches(Tour tour) {
    if (destination != null && tour.destination != destination) return false;
    if (maxPrice != null && tour.price > maxPrice!) return false;
    if (minRating != null && tour.rating < minRating!) return false;
    if (!duration.includes(tour.durationDays)) return false;
    return _matchesQuery(tour);
  }

  List<Tour> apply(Iterable<Tour> tours) => tours.where(matches).toList();

  /// Every word of the query must appear in the tour's title, location,
  /// destination or category, ignoring case and common diacritics.
  bool _matchesQuery(Tour tour) {
    final words = normalizeForSearch(query)
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty);
    if (words.isEmpty) return true;
    final haystack = normalizeForSearch(
      [
        tour.title,
        tour.location,
        tour.destination.label,
        ...tour.destination.aliases,
        tour.category.label,
      ].join(' '),
    );
    return words.every(haystack.contains);
  }

  @override
  bool operator ==(Object other) =>
      other is TourFilter &&
      other.query == query &&
      other.destination == destination &&
      other.maxPrice == maxPrice &&
      other.minRating == minRating &&
      other.duration == duration;

  @override
  int get hashCode =>
      Object.hash(query, destination, maxPrice, minRating, duration);
}

const _diacriticFolds = {
  'ç': 'c',
  'ğ': 'g',
  'ı': 'i',
  'ö': 'o',
  'ş': 's',
  'ü': 'u',
  'é': 'e',
  'è': 'e',
  'á': 'a',
  'à': 'a',
  'ó': 'o',
  'í': 'i',
  '̇': '', // combining dot left by lowercasing Turkish "İ"
};

/// Lowercases [input] and folds the diacritics used in tour names, so that
/// "goreme" finds "Göreme".
String normalizeForSearch(String input) {
  final buffer = StringBuffer();
  for (final rune in input.toLowerCase().runes) {
    final char = String.fromCharCode(rune);
    buffer.write(_diacriticFolds[char] ?? char);
  }
  return buffer.toString();
}

/// Bounds for the max-price slider: the cheapest price rounded down and the
/// most expensive rounded up to a multiple of [step]. Always at least one
/// [step] apart.
({int min, int max}) priceBounds(Iterable<Tour> tours, {int step = 100}) {
  if (tours.isEmpty) return (min: 0, max: step * 50);
  final prices = tours.map((tour) => tour.price);
  final lowest = (prices.reduce(math.min) ~/ step) * step;
  final highest = ((prices.reduce(math.max) + step - 1) ~/ step) * step;
  return (min: lowest, max: math.max(highest, lowest + step));
}
