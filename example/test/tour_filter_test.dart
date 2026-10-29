import 'package:flutter_test/flutter_test.dart';
import 'package:tour_explorer/logic/tour_filter.dart';
import 'package:tour_explorer/models/destination.dart';
import 'package:tour_explorer/models/tour.dart';
import 'package:tour_explorer/models/tour_category.dart';

import 'helpers.dart';

void main() {
  final istanbul = makeTour(
    id: 'ist',
    title: 'Istanbul Food Walk',
    location: 'Istanbul',
    price: 300,
    durationDays: 1,
    rating: 4.8,
  );
  final balloons = makeTour(
    id: 'goreme',
    title: 'Balloon Flight',
    location: 'Göreme, Cappadocia',
    category: TourCategory.adventure,
    price: 900,
    durationDays: 4,
    rating: 4.9,
  );
  final safari = makeTour(
    id: 'safari',
    title: 'Desert Safari',
    destination: Destination.uae,
    location: 'Dubai',
    category: TourCategory.adventure,
    price: 250,
    durationDays: 2,
    rating: 4.6,
  );
  final villa = makeTour(
    id: 'villa',
    title: 'Overwater Villa',
    destination: Destination.maldives,
    location: 'South Malé Atoll',
    category: TourCategory.beach,
    price: 3000,
    durationDays: 7,
    rating: 4.9,
  );
  final tbilisi = makeTour(
    id: 'tbilisi',
    title: 'Old Town & Wine',
    destination: Destination.georgia,
    location: 'Tbilisi',
    price: 450,
    durationDays: 4,
    rating: 4.4,
  );
  final silkRoad = makeTour(
    id: 'silk',
    title: 'Silk Road Classic',
    destination: Destination.uzbekistan,
    location: 'Samarkand',
    category: TourCategory.culture,
    price: 1200,
    durationDays: 8,
    rating: 4.7,
  );
  final tours = [istanbul, balloons, safari, villa, tbilisi, silkRoad];

  List<String> ids(TourFilter filter) =>
      filter.apply(tours).map((tour) => tour.id).toList();

  group('search text', () {
    test('an empty filter returns every tour in order', () {
      expect(const TourFilter().apply(tours), tours);
    });

    test('a blank query matches everything', () {
      expect(ids(const TourFilter(query: '   ')), hasLength(tours.length));
    });

    test('matches titles regardless of case', () {
      expect(ids(const TourFilter(query: 'BALLOON')), ['goreme']);
    });

    test('matches the destination name and its aliases', () {
      expect(ids(const TourFilter(query: 'maldives')), ['villa']);
      expect(ids(const TourFilter(query: 'emirates')), ['safari']);
      expect(ids(const TourFilter(query: 'Türkiye')), ['ist', 'goreme']);
    });

    test('matches the location and ignores diacritics', () {
      expect(ids(const TourFilter(query: 'goreme')), ['goreme']);
      expect(ids(const TourFilter(query: 'samarkand')), ['silk']);
    });

    test('requires every word to match', () {
      expect(ids(const TourFilter(query: 'turkey adventure')), ['goreme']);
      expect(ids(const TourFilter(query: 'dubai villa')), isEmpty);
    });
  });

  group('filters', () {
    test('destination keeps only that country', () {
      expect(ids(const TourFilter(destination: Destination.georgia)), [
        'tbilisi',
      ]);
    });

    test('max price is inclusive', () {
      expect(ids(const TourFilter(maxPrice: 300)), ['ist', 'safari']);
    });

    test('min rating is inclusive', () {
      expect(ids(const TourFilter(minRating: 4.9)), ['goreme', 'villa']);
    });

    test('duration buckets', () {
      expect(ids(const TourFilter(duration: DurationRange.short)), [
        'ist',
        'safari',
      ]);
      expect(ids(const TourFilter(duration: DurationRange.medium)), [
        'goreme',
        'tbilisi',
      ]);
      expect(ids(const TourFilter(duration: DurationRange.long)), [
        'villa',
        'silk',
      ]);
    });

    test('duration bucket edges', () {
      expect(DurationRange.short.includes(3), isTrue);
      expect(DurationRange.short.includes(4), isFalse);
      expect(DurationRange.medium.includes(4), isTrue);
      expect(DurationRange.medium.includes(6), isTrue);
      expect(DurationRange.long.includes(7), isTrue);
      expect(DurationRange.long.includes(30), isTrue);
      expect(DurationRange.any.includes(1), isTrue);
    });

    test('filters combine with AND', () {
      const turkeyUnder500 = TourFilter(
        destination: Destination.turkey,
        maxPrice: 500,
      );
      expect(ids(turkeyUnder500), ['ist']);
      expect(ids(turkeyUnder500.copyWith(minRating: () => 4.9)), isEmpty);
      expect(
        ids(
          const TourFilter(
            query: 'adventure',
            maxPrice: 1000,
            minRating: 4.8,
            duration: DurationRange.medium,
          ),
        ),
        ['goreme'],
      );
    });

    test('search text combines with filters', () {
      expect(ids(const TourFilter(query: 'safari', maxPrice: 200)), isEmpty);
      expect(ids(const TourFilter(query: 'safari', maxPrice: 250)), ['safari']);
    });
  });

  group('state helpers', () {
    test('counts active filters but not the query', () {
      expect(const TourFilter(query: 'x').activeFilterCount, 0);
      expect(const TourFilter(query: 'x').hasActiveFilters, isFalse);
      const filter = TourFilter(
        destination: Destination.uae,
        maxPrice: 100,
        minRating: 4.5,
        duration: DurationRange.long,
      );
      expect(filter.activeFilterCount, 4);
    });

    test('withoutFilters keeps the search text', () {
      const filter = TourFilter(
        query: 'wine',
        destination: Destination.georgia,
        maxPrice: 400,
        minRating: 4.5,
        duration: DurationRange.short,
      );
      expect(filter.withoutFilters(), const TourFilter(query: 'wine'));
    });

    test('copyWith can clear nullable fields and keeps the rest', () {
      const filter = TourFilter(destination: Destination.uae, maxPrice: 300);
      final cleared = filter.copyWith(destination: () => null);
      expect(cleared.destination, isNull);
      expect(cleared.maxPrice, 300);
      expect(filter.copyWith(), filter);
    });

    test('equal filters are equal', () {
      expect(
        const TourFilter(query: 'a', minRating: 4.5),
        const TourFilter(query: 'a', minRating: 4.5),
      );
      expect(
        const TourFilter(query: 'a').hashCode,
        const TourFilter(query: 'a').hashCode,
      );
      expect(const TourFilter(query: 'a'), isNot(const TourFilter()));
    });
  });

  group('priceBounds', () {
    test('rounds to the step', () {
      final bounds = priceBounds([
        makeTour(id: 'a', price: 150),
        makeTour(id: 'b', price: 4290),
      ]);
      expect(bounds, (min: 100, max: 4300));
    });

    test('keeps the range at least one step wide', () {
      expect(priceBounds([makeTour(id: 'a', price: 100)]), (
        min: 100,
        max: 200,
      ));
    });

    test('has a default range without tours', () {
      expect(priceBounds(const <Tour>[]), (min: 0, max: 5000));
    });
  });
}
