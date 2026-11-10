/// Value formats a template can name: `{/start|time}` in a string, or
/// `{"path": "/price", "format": "money:UZS"}`. Listed in
/// `catalog/zehn.basic.json`; `money` takes a currency code after `:`.
const ziFormats = {'time', 'date', 'datetime', 'number', 'money', 'duration'};

/// Never breaks a line: inside a number, and between it and its currency.
const _nb = ' ';

const _months = {
  'uz': ['yanvar', 'fevral', 'mart', 'aprel', 'may', 'iyun', 'iyul', 'avgust', 'sentabr', 'oktabr', 'noyabr', 'dekabr'],
  'ru': ['января', 'февраля', 'марта', 'апреля', 'мая', 'июня', 'июля', 'августа', 'сентября', 'октября', 'ноября', 'декабря'],
  'en': ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'],
};

const _hoursMinutes = {
  'uz': ('soat', 'daqiqa'),
  'ru': ('ч', 'мин'),
  'en': ('h', 'min'),
};

final _clock = RegExp(r'^(\d{2}):(\d{2})(:\d{2}(\.\d+)?)?$');

/// [value] drawn as [format] in [language]. A value that doesn't parse,
/// or a format this SDK doesn't know, comes back as it was.
String ziFormat(Object? value, String format, String language) {
  final raw = '${value ?? ''}';
  final lang = _months.containsKey(language) ? language : 'en';
  final colon = format.indexOf(':');
  final name = colon < 0 ? format : format.substring(0, colon);
  final arg = colon < 0 ? '' : format.substring(colon + 1);
  final out = switch (name) {
    'time' => _time(raw),
    'date' => _when(raw, (t) => _date(t, lang)),
    'datetime' => _when(raw, (t) => '${_date(t, lang)}, ${_hm(t)}'),
    'number' => _number(value, lang),
    'money' => _money(value, lang, arg),
    'duration' => _duration(value, lang),
    _ => null,
  };
  return out ?? raw;
}

/// With a zone: the phone's local time. Without one: as written.
String? _when(String raw, String Function(DateTime t) draw) {
  final t = DateTime.tryParse(raw);
  if (t == null) return null;
  return draw(t.isUtc ? t.toLocal() : t);
}

String? _time(String raw) {
  final clock = _clock.firstMatch(raw);
  if (clock != null) return '${clock[1]}:${clock[2]}';
  return _when(raw, _hm);
}

String _hm(DateTime t) => '${_two(t.hour)}:${_two(t.minute)}';

String _two(int n) => n.toString().padLeft(2, '0');

String _date(DateTime t, String lang) {
  final month = _months[lang]![t.month - 1];
  return switch (lang) {
    'uz' => '${t.day}-$month',
    'ru' => '${t.day} $month',
    _ => '$month ${t.day}',
  };
}

num? _numeric(Object? value) => switch (value) {
  num() => value,
  String() => num.tryParse(value.trim()),
  _ => null,
};

String? _number(Object? value, String lang) {
  final n = _numeric(value);
  if (n == null || !n.isFinite) return null;
  final whole = n == n.truncate();
  final text = whole ? n.toInt().toString() : n.toString();
  if (text.contains('e')) return null;
  final negative = text.startsWith('-');
  final digits = negative ? text.substring(1) : text;
  final dot = digits.indexOf('.');
  final integer = dot < 0 ? digits : digits.substring(0, dot);
  final fraction = dot < 0 ? '' : digits.substring(dot + 1);
  final english = lang == 'en';
  final group = english ? ',' : _nb;
  final grouped = StringBuffer();
  for (var i = 0; i < integer.length; i++) {
    if (i > 0 && (integer.length - i) % 3 == 0) grouped.write(group);
    grouped.write(integer[i]);
  }
  final decimal = fraction.isEmpty ? '' : '${english ? '.' : ','}$fraction';
  return '${negative ? '-' : ''}$grouped$decimal';
}

String? _money(Object? value, String lang, String code) {
  final n = _number(value, lang);
  return n == null || code.isEmpty ? n : '$n$_nb$code';
}

String? _duration(Object? value, String lang) {
  final n = _numeric(value);
  if (n == null || !n.isFinite || n < 0) return null;
  final minutes = n.round();
  final (h, m) = _hoursMinutes[lang]!;
  final hours = minutes ~/ 60;
  final rest = minutes % 60;
  if (hours == 0) return '$rest $m';
  return rest == 0 ? '$hours $h' : '$hours $h $rest $m';
}

