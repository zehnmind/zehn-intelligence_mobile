import 'dart:math';

import '../models/tour.dart';

/// The next [count] departure dates of [tour], at least [minDaysAhead] days
/// after [from]. Dates are local midnights.
List<DateTime> upcomingDepartures(
  Tour tour, {
  required DateTime from,
  int count = 6,
  int minDaysAhead = 2,
}) {
  if (tour.departureWeekdays.isEmpty || count <= 0) return const [];
  final departures = <DateTime>[];
  // Build each date from its parts rather than adding Durations, which would
  // drift by an hour across daylight-saving changes.
  for (var offset = minDaysAhead; departures.length < count; offset++) {
    final day = DateTime(from.year, from.month, from.day + offset);
    if (tour.departureWeekdays.contains(day.weekday)) departures.add(day);
  }
  return departures;
}

/// A confirmed booking. Nothing is sent anywhere; the app only shows it.
class Booking {
  const Booking({
    required this.reference,
    required this.tour,
    required this.departure,
    required this.travelers,
  });

  final String reference;
  final Tour tour;
  final DateTime departure;
  final int travelers;

  int get totalPrice => tour.price * travelers;

  // No 0/O or 1/I, which are easy to confuse when read aloud.
  static const _referenceAlphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

  /// A booking reference like "TX-7KQ4M2".
  static String newReference([Random? random]) {
    final rng = random ?? Random();
    final code = List.generate(
      6,
      (_) => _referenceAlphabet[rng.nextInt(_referenceAlphabet.length)],
    ).join();
    return 'TX-$code';
  }
}
