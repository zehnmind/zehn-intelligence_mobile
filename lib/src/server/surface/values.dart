import 'formats.dart';

const _languages = {'uz', 'ru', 'en'};

/// Reads a template's values against a card's data (DYNAMIC_CARDS §6.2).
class ZiValues {
  const ZiValues(this.data, this.language);

  final Object? data;
  final String language;

  bool _localized(Map<Object?, Object?> m) => m.isNotEmpty && m.keys.every(_languages.contains);

  Object? _pick(Map<Object?, Object?> m) => m[language] ?? m['en'] ?? m.values.first;

  /// `/a/b` reads the card's data, `a/b` reads [item]; a language map is picked.
  Object? lookup(String path, Object? item) {
    Object? node = path.startsWith('/') ? data : item;
    for (final part in path.split('/').where((p) => p.isNotEmpty)) {
      if (node is Map) {
        node = node[part];
      } else if (node is List) {
        final i = int.tryParse(part);
        node = i != null && i >= 0 && i < node.length ? node[i] : null;
      } else {
        return null;
      }
    }
    return node is Map && _localized(node) ? _pick(node) : node;
  }

  /// `{/a/b}`, or `{/a/b|format}` (`formats.dart`).
  String _interpolate(String s, Object? item) => s.replaceAllMapped(RegExp(r'\{([^{}\s]+)\}'), (m) {
    final inside = m[1]!;
    final bar = inside.indexOf('|');
    if (bar < 0) return '${lookup(inside, item) ?? ''}';
    return ziFormat(lookup(inside.substring(0, bar), item), inside.substring(bar + 1), language);
  });

  /// The value at a path is the literal; a list at the path holds it. A string never equals a number.
  bool _equals(Object? found, Object? literal) {
    if (literal is! String && literal is! num && literal is! bool) return false;
    return found is List ? found.contains(literal) : found == literal;
  }

  /// A literal, `{"path": …}` (with an optional `format` or `equals`), a language map,
  /// or a string with `{/a/b}`.
  Object? resolve(Object? value, Object? item) {
    if (value is Map) {
      if (value['path'] is String) {
        final found = lookup(value['path'] as String, item);
        if (value.containsKey('equals')) return _equals(found, value['equals']);
        final format = value['format'];
        return format is String ? ziFormat(found, format, language) : found;
      }
      if (_localized(value)) return resolve(_pick(value), item);
      return {for (final e in value.entries) '${e.key}': resolve(e.value, item)};
    }
    if (value is String) return _interpolate(value, item);
    if (value is List) return [for (final x in value) resolve(x, item)];
    return value;
  }

  String text(Object? value, Object? item) => '${resolve(value, item) ?? ''}';

  /// False when `visible` resolves to null, false or an empty string.
  bool shown(Map<String, Object?> spec, Object? item) {
    if (!spec.containsKey('visible')) return true;
    final visible = resolve(spec['visible'], item);
    return !(visible == null || visible == false || visible == '');
  }
}
