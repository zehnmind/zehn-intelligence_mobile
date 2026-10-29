const _weekdayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _monthNames = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// 1284 -> "1,284".
String formatThousands(int value) {
  final digits = value.abs().toString();
  final buffer = StringBuffer(value < 0 ? '-' : '');
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }
  return buffer.toString();
}

/// 1290 -> "$1,290".
String formatPrice(int usd) => '\$${formatThousands(usd)}';

/// 1284 -> "1.3k", 512 -> "512".
String formatCompactCount(int count) {
  if (count < 1000) return '$count';
  final thousands = (count / 1000).toStringAsFixed(1);
  return '${thousands.endsWith('.0') ? thousands.substring(0, thousands.length - 2) : thousands}k';
}

String formatDuration(int days) => days == 1 ? '1 day' : '$days days';

String formatTourCount(int count) => count == 1 ? '1 tour' : '$count tours';

String formatTravelers(int count) =>
    count == 1 ? '1 traveler' : '$count travelers';

/// "Mon, 3 Nov".
String formatShortDate(DateTime date) =>
    '${_weekdayNames[date.weekday - 1]}, ${date.day} ${_monthNames[date.month - 1]}';

/// "Mon, Thu, Sat", or "Daily" when the tour runs every day.
String formatWeekdays(Iterable<int> weekdays) {
  final sorted = weekdays.toSet().toList()..sort();
  if (sorted.length == 7) return 'Daily';
  return sorted.map((day) => _weekdayNames[day - 1]).join(', ');
}
