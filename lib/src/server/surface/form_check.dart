import 'form_words.dart';
import 'surface.dart';
import 'values.dart';

/// The blocks a form reads a value from. Each is a leaf.
const ziFieldBlocks = {
  'TextField',
  'Checkbox',
  'Switch',
  'Select',
  'DateField',
};

const _defaultMaxLength = 500;

/// The first rule a value breaks.
class ZiCheckFailure {
  const ZiCheckFailure(this.rule, {this.min, this.max, this.message});

  /// `required` · `length` · `range` · `items` · `number` · `email` · `phone` · `date` · `option`.
  final String rule;
  final num? min;
  final num? max;

  /// The failing check's own `message`; null uses the words.
  final Object? message;

  /// The key of the words to show: `length_min` or `length_max` when only one bound is set, else the rule.
  String get word {
    if (rule != 'length' && rule != 'range' && rule != 'items') return rule;
    if (min != null && max == null) return '${rule}_min';
    if (max != null && min == null) return '${rule}_max';
    return rule;
  }
}

typedef _Entry = ({
  Map<String, Object?> spec,
  List<Map<String, Object?>> above,
});

/// Each field block with the blocks above it, in the order they are drawn.
List<_Entry> _walk(ZiSurface surface) {
  final seen = <String>{};
  final found = <_Entry>[];
  void visit(String id, List<Map<String, Object?>> above) {
    final spec = surface.components[id];
    if (spec == null || !seen.add(id)) return;
    if (ziFieldBlocks.contains(spec['component'])) {
      if (spec['field'] is String) found.add((spec: spec, above: above));
      return;
    }
    final inside = [...above, spec];
    if (spec['child'] is String) visit(spec['child'] as String, inside);
    final children = spec['children'];
    if (children is List) {
      for (final child in children) {
        if (child is String) visit(child, inside);
      }
    }
  }

  visit(surface.root, const []);
  return found;
}

/// The field blocks in the order they are drawn (root first; `child`, then `children` as listed),
/// each once. A block without a string `field` is left out; a repeated block is not followed.
List<Map<String, Object?>> ziFormFields(ZiSurface surface) => [
  for (final e in _walk(surface)) e.spec,
];

/// What a field sends for what it holds, or null for no value.
Object? ziFieldValue(Map<String, Object?> spec, Object? raw) {
  switch (spec['component']) {
    case 'Checkbox' || 'Switch':
      return raw is bool ? raw : null;
    case 'Select':
      if (spec['multiple'] == true) {
        if (raw is! List) return null;
        final picked = [
          for (final x in raw)
            if (x is String && x.isNotEmpty) x,
        ];
        if (picked.isEmpty) return null;
        // Options keep their own order whatever order they were picked in; unknown values go last.
        final order = _optionValues(spec);
        int rank(String v) =>
            order.contains(v) ? order.indexOf(v) : order.length;
        return picked.toSet().toList()
          ..sort((a, b) => rank(a).compareTo(rank(b)));
      }
      return raw is String && raw.isNotEmpty ? raw : null;
    default:
      final text = _text(raw);
      if (text.isEmpty) return null;
      return spec['input'] == 'number' && _numberText.hasMatch(text)
          ? _number(text)
          : text;
  }
}

String _text(Object? raw) => raw is String ? raw.trim() : '';

List<String> _optionValues(Map<String, Object?> spec) {
  final options = spec['options'];
  return [
    if (options is List)
      for (final o in options)
        if (o is Map && o['value'] is String) o['value'] as String,
  ];
}

final _numberText = RegExp(r'^-?\d+([.,]\d+)?$');
final _emailText = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
final _phoneStrip = RegExp(r'[\s+\-()]');
final _phoneDigits = RegExp(r'^\d{7,15}$');
final _dayText = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');

/// An integer when there is no fraction, else a double.
num _number(String text) {
  final d = double.parse(text.replaceFirst(',', '.'));
  return d == d.truncateToDouble() && d.abs() < 9007199254740992
      ? d.toInt()
      : d;
}

/// What the form sends for [raw] (by field key), and the keys it hides. A field is hidden when its own
/// `visible`, or a block above it, does not show against what the form sends; hidden fields are left out of
/// that, so this repeats until nothing more is hidden. The server sees only what is sent, so both agree.
({Map<String, Object?> values, Set<String> hidden}) ziFormValues(
  ZiSurface surface,
  Map<String, Object?> raw,
) {
  final entries = _walk(surface);
  Map<String, Object?> sent(Set<String> hidden) {
    final values = <String, Object?>{};
    for (final e in entries) {
      final key = e.spec['field'] as String;
      if (hidden.contains(key)) continue;
      final value = ziFieldValue(e.spec, raw[key]);
      if (value != null) values[key] = value;
    }
    return values;
  }

  var hidden = <String>{};
  for (var i = 0; i <= entries.length; i++) {
    final values = ZiValues({'form': sent(hidden)}, 'en');
    final next = {
      ...hidden,
      for (final e in entries)
        if (![...e.above, e.spec].every((b) => values.shown(b, null)))
          e.spec['field'] as String,
    };
    if (next.length == hidden.length) break;
    hidden = next;
  }
  return (values: sent(hidden), hidden: hidden);
}

/// The first rule [raw] breaks, in the order of the shared checking rules; null when it passes.
/// The `type` and `unknown_field` rules are the server's.
ZiCheckFailure? ziCheckField(
  Map<String, Object?> spec,
  Object? raw, {
  required DateTime today,
}) {
  final component = spec['component'];
  final value = ziFieldValue(spec, raw);
  final checks = spec['checks'] is List
      ? (spec['checks'] as List).whereType<Map<Object?, Object?>>()
      : const <Map<Object?, Object?>>[];
  Map<Object?, Object?>? checkOf(String rule) {
    for (final c in checks) {
      if (c['rule'] == rule) return c;
    }
    return null;
  }

  if (value != null) {
    if (component == 'TextField') {
      final text = _text(raw);
      switch (spec['input']) {
        case 'number' when !_numberText.hasMatch(text):
          return const ZiCheckFailure('number');
        case 'email' when !_emailText.hasMatch(text):
          return const ZiCheckFailure('email');
        case 'phone'
            when !_phoneDigits.hasMatch(text.replaceAll(_phoneStrip, '')):
          return const ZiCheckFailure('phone');
      }
    } else if (component == 'DateField') {
      final day = value == 'today' ? null : ziDateOf(value, today: today);
      final min = ziDateOf(spec['min'], today: today);
      final max = ziDateOf(spec['max'], today: today);
      if (day == null ||
          (min != null && day.isBefore(min)) ||
          (max != null && day.isAfter(max))) {
        return const ZiCheckFailure('date');
      }
    } else if (component == 'Select') {
      final options = _optionValues(spec);
      if ((value is List ? value : [value]).any((v) => !options.contains(v))) {
        return const ZiCheckFailure('option');
      }
    }
  }

  final required = checkOf('required');
  if (required != null &&
      (value == null ||
          ((component == 'Checkbox' || component == 'Switch') &&
              value != true))) {
    return ZiCheckFailure('required', message: required['message']);
  }
  if (value == null) return null;

  ZiCheckFailure? outside(String rule, num size) {
    final check = checkOf(rule);
    if (check == null) return null;
    final min = check['min'] is num ? check['min'] as num : null;
    final max = check['max'] is num ? check['max'] as num : null;
    if ((min != null && size < min) || (max != null && size > max)) {
      return ZiCheckFailure(
        rule,
        min: min,
        max: max,
        message: check['message'],
      );
    }
    return null;
  }

  if (component == 'TextField') {
    // UTF-16 code units, which is what `String.length` counts.
    final length = _text(raw).length;
    final failure = outside('length', length);
    if (failure != null) return failure;
    final maxLength = spec['maxLength'] is num
        ? spec['maxLength'] as num
        : _defaultMaxLength;
    if (length > maxLength) return ZiCheckFailure('length', max: maxLength);
    if (value is num) return outside('range', value);
  } else if (value is List) {
    return outside('items', value.length);
  }
  return null;
}

/// The failure's own `message` when it has one, else the words for its rule.
String ziCheckMessage(ZiCheckFailure failure, ZiValues values) {
  if (failure.message != null) {
    final own = values.text(failure.message, null);
    if (own.isNotEmpty) return own;
  }
  return ziFormWord(
    failure.word,
    values.language,
    min: failure.min,
    max: failure.max,
  );
}

/// `YYYY-MM-DD`.
String ziDateText(DateTime day) =>
    '${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';

/// A real `YYYY-MM-DD` day, or [today]'s day for `"today"`; null for anything else.
DateTime? ziDateOf(Object? value, {required DateTime today}) {
  if (value == 'today') return DateTime(today.year, today.month, today.day);
  final m = value is String ? _dayText.firstMatch(value) : null;
  if (m == null) return null;
  final (y, mo, d) = (int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
  final day = DateTime(y, mo, d);
  return day.year == y && day.month == mo && day.day == d ? day : null;
}
