import 'package:flutter_test/flutter_test.dart';
import 'package:tour_explorer/utils/formatters.dart';

void main() {
  test('prices use thousands separators', () {
    expect(formatPrice(150), '\$150');
    expect(formatPrice(1290), '\$1,290');
    expect(formatPrice(1234567), '\$1,234,567');
  });

  test('compact counts', () {
    expect(formatCompactCount(512), '512');
    expect(formatCompactCount(1284), '1.3k');
    expect(formatCompactCount(2000), '2k');
  });

  test('plurals', () {
    expect(formatDuration(1), '1 day');
    expect(formatDuration(4), '4 days');
    expect(formatTourCount(1), '1 tour');
    expect(formatTravelers(2), '2 travelers');
  });

  test('dates and weekdays', () {
    expect(formatShortDate(DateTime(2026, 11, 2)), 'Mon, 2 Nov');
    expect(formatWeekdays(const [6, 1, 4]), 'Mon, Thu, Sat');
    expect(formatWeekdays(const [1, 2, 3, 4, 5, 6, 7]), 'Daily');
  });
}
