import 'package:flutter/painting.dart';

/// A console-made template: an A2UI-shaped `createSurface` message (flat
/// components with ids, a root). Nothing in it is executed.
class ZiSurface {
  ZiSurface._(this.id, this.catalogId, this.root, this.components);

  /// Throws [FormatException] when the shape is wrong.
  factory ZiSurface.parse(Object? json) {
    if (json is! Map || json['createSurface'] is! Map) {
      throw const FormatException('Expected {"createSurface": {...}}');
    }
    final s = (json['createSurface'] as Map).cast<String, Object?>();
    final list = s['components'];
    if (list is! List) throw const FormatException('createSurface.components must be a list');
    final byId = <String, Map<String, Object?>>{};
    for (final c in list) {
      if (c is! Map || c['id'] is! String || c['component'] is! String) {
        throw FormatException('Every component needs a string "id" and "component": $c');
      }
      final id = c['id'] as String;
      if (byId.containsKey(id)) throw FormatException('Duplicate component id "$id"');
      byId[id] = c.cast<String, Object?>();
    }
    final root = s['root'] is String ? s['root'] as String : 'root';
    if (!byId.containsKey(root)) throw FormatException('No root component "$root"');
    return ZiSurface._(
      s['surfaceId'] is String ? s['surfaceId'] as String : '?',
      s['catalogId'] is String ? s['catalogId'] as String : '?',
      root,
      byId,
    );
  }

  final String id;
  final String catalogId;
  final String root;
  final Map<String, Map<String, Object?>> components;
}

/// Theme tokens from the console (colors, text styles, radii, font family).
/// The font must be one the app already ships.
class ZiTheme {
  const ZiTheme(this.json);

  final Map<String, Object?> json;

  String? get font => json['font'] is String ? json['font'] as String : null;

  Color color(Object? token, Color fallback) {
    if (token is! String) return fallback;
    final colors = json['colors'];
    final value = (colors is Map ? colors[token] : null) ?? token;
    return parseColor(value is String ? value : null) ?? fallback;
  }

  TextStyle text(Object? token, {Color? color}) {
    final styles = json['text'];
    final picked = styles is Map ? (styles[token ?? 'body'] ?? styles['body']) : null;
    final s = picked is Map ? picked : const <String, Object?>{};
    final weight = s['weight'] is num ? (s['weight'] as num).toInt() : 400;
    return TextStyle(
      fontFamily: font,
      fontSize: s['size'] is num ? (s['size'] as num).toDouble() : 15,
      fontWeight: FontWeight.values[(weight ~/ 100 - 1).clamp(0, 8)],
      height: s['height'] is num ? (s['height'] as num).toDouble() : null,
      color: color,
    );
  }

  double radius(Object? token, double fallback) {
    if (token is num) return token.toDouble();
    final r = json['radius'];
    final value = r is Map ? r[token] : null;
    return value is num ? value.toDouble() : fallback;
  }
}

/// `#RRGGBB` or `#AARRGGBB`; null otherwise.
Color? parseColor(String? hex) {
  if (hex == null || !hex.startsWith('#')) return null;
  var h = hex.substring(1);
  if (h.length == 6) h = 'FF$h';
  if (h.length != 8) return null;
  final v = int.tryParse(h, radix: 16);
  return v == null ? null : Color(v);
}
