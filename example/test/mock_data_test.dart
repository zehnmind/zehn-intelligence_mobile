import 'package:flutter_test/flutter_test.dart';
import 'package:tour_explorer/data/mock_tours.dart';
import 'package:tour_explorer/logic/tour_filter.dart';
import 'package:tour_explorer/models/destination.dart';
import 'package:tour_explorer/models/tour_category.dart';

void main() {
  test('has 15 to 20 tours with unique ids', () {
    expect(mockTours.length, inInclusiveRange(15, 20));
    final ids = mockTours.map((tour) => tour.id).toSet();
    expect(ids, hasLength(mockTours.length));
  });

  test('every destination has at least three tours', () {
    for (final destination in Destination.values) {
      final count = mockTours.where((t) => t.destination == destination).length;
      expect(count, greaterThanOrEqualTo(3), reason: destination.label);
    }
  });

  test('every category and duration bucket has tours', () {
    for (final category in TourCategory.values) {
      expect(
        mockTours.any((tour) => tour.category == category),
        isTrue,
        reason: category.label,
      );
    }
    for (final range in DurationRange.values) {
      expect(
        mockTours.any((tour) => range.includes(tour.durationDays)),
        isTrue,
        reason: range.label,
      );
    }
  });

  test('every tour has valid fields', () {
    for (final tour in mockTours) {
      final reason = tour.id;
      expect(tour.title, isNotEmpty, reason: reason);
      expect(tour.price, greaterThan(0), reason: reason);
      expect(tour.durationDays, greaterThan(0), reason: reason);
      expect(tour.rating, inInclusiveRange(0, 5), reason: reason);
      expect(tour.maxGroupSize, greaterThan(0), reason: reason);
      expect(Uri.parse(tour.imageUrl).scheme, 'https', reason: reason);
      expect(tour.highlights, isNotEmpty, reason: reason);
      expect(tour.included, isNotEmpty, reason: reason);
      expect(tour.languages, isNotEmpty, reason: reason);
      expect(tour.departureWeekdays, isNotEmpty, reason: reason);
      for (final day in tour.departureWeekdays) {
        expect(day, inInclusiveRange(DateTime.monday, DateTime.sunday));
      }
    }
  });

  test('search and filters give meaningful results on the real data', () {
    expect(const TourFilter(query: 'samarkand').apply(mockTours).length, 2);
    expect(
      const TourFilter(
        destination: Destination.thailand,
        maxPrice: 600,
      ).apply(mockTours),
      hasLength(3),
    );
    expect(
      const TourFilter(
        minRating: 4.8,
        duration: DurationRange.long,
      ).apply(mockTours),
      hasLength(4),
    );
  });
}
