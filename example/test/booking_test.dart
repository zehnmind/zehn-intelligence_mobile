import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:tour_explorer/logic/booking.dart';

import 'helpers.dart';

void main() {
  group('upcomingDepartures', () {
    // 26 October 2026 is a Monday.
    final monday = DateTime(2026, 10, 26);

    test('lists the next departures on the tour weekdays', () {
      final tour = makeTour(
        id: 't',
        departureWeekdays: const [DateTime.monday, DateTime.thursday],
      );
      expect(upcomingDepartures(tour, from: monday, count: 3), [
        DateTime(2026, 10, 29),
        DateTime(2026, 11, 2),
        DateTime(2026, 11, 5),
      ]);
    });

    test('skips the next few days', () {
      final tour = makeTour(
        id: 't',
        departureWeekdays: const [DateTime.monday],
      );
      expect(
        upcomingDepartures(tour, from: monday, count: 1).single,
        DateTime(2026, 11, 2),
      );
      expect(
        upcomingDepartures(
          tour,
          from: monday,
          count: 1,
          minDaysAhead: 0,
        ).single,
        monday,
      );
    });

    test('rolls over into the next year', () {
      final daily = makeTour(
        id: 't',
        departureWeekdays: const [1, 2, 3, 4, 5, 6, 7],
      );
      expect(
        upcomingDepartures(daily, from: DateTime(2026, 12, 30), count: 3),
        [DateTime(2027, 1, 1), DateTime(2027, 1, 2), DateTime(2027, 1, 3)],
      );
    });

    test('ignores the time of day', () {
      final tour = makeTour(
        id: 't',
        departureWeekdays: const [DateTime.monday],
      );
      expect(
        upcomingDepartures(
          tour,
          from: DateTime(2026, 10, 26, 23, 59),
          count: 1,
        ).single,
        DateTime(2026, 11, 2),
      );
    });

    test('returns nothing for a tour without departure days', () {
      final tour = makeTour(id: 't', departureWeekdays: const []);
      expect(upcomingDepartures(tour, from: monday), isEmpty);
    });
  });

  group('Booking', () {
    test('total is the price per person times travelers', () {
      final booking = Booking(
        reference: 'TX-AAAAAA',
        tour: makeTour(id: 't', price: 890),
        departure: DateTime(2026, 11, 2),
        travelers: 3,
      );
      expect(booking.totalPrice, 2670);
    });

    test('references are short, readable and random', () {
      final reference = Booking.newReference();
      expect(reference, matches(RegExp(r'^TX-[A-HJ-NP-Z2-9]{6}$')));
      expect(Booking.newReference(Random(7)), Booking.newReference(Random(7)));
    });
  });
}
