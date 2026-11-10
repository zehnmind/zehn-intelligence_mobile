import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'formats.dart';
import 'surface.dart';

/// The only things a component's tap may ask for.
const ziAllowedActions = {'open_route', 'ask', 'open_url'};

/// Catalog `zehn.basic.v0`: what this build can draw.
const ziCatalog = {'Box', 'Column', 'Row', 'Image', 'Text', 'Chip', 'Header', 'InfoRow', 'Button', 'Divider'};

const _languages = {'uz', 'ru', 'en'};

/// The icons a template can name (`icon`); listed in `catalog/zehn.basic.json`.
const ziIcons = <String, IconData>{
  'theaters': Icons.theaters_outlined,
  'layers': Icons.layers_outlined,
  'schedule': Icons.schedule,
  'phone': Icons.call_outlined,
  'language': Icons.language,
  'movie': Icons.movie_outlined,
  'ticket': Icons.confirmation_number_outlined,
  'map': Icons.map_outlined,
  'parking': Icons.local_parking,
  'star': Icons.star_outline,
  'info': Icons.info_outline,
  'car': Icons.directions_car_outlined,
  'store': Icons.storefront_outlined,
  'calendar': Icons.calendar_today_outlined,
  'wallet': Icons.account_balance_wallet_outlined,
  'person': Icons.person_outline,
  'restaurant': Icons.restaurant,
  'bus': Icons.directions_bus_outlined,
  'gift': Icons.card_giftcard,
};

/// A tap the template asked for, with its arguments resolved.
class ZiSurfaceAction {
  const ZiSurfaceAction(this.name, this.args);

  /// `open_route`, `ask` or `open_url`.
  final String name;
  final Map<String, Object?> args;
}

/// Draws a [ZiSurface] over [data] with native widgets.
class ZiSurfaceView extends StatelessWidget {
  const ZiSurfaceView({
    super.key,
    required this.surface,
    required this.data,
    required this.theme,
    required this.language,
    required this.onAction,
  });

  final ZiSurface surface;
  final Object? data;
  final ZiTheme theme;
  final String language;
  final void Function(ZiSurfaceAction action) onAction;

  @override
  Widget build(BuildContext context) => _Builder(this).build(surface.root, null, 0) ?? const SizedBox.shrink();
}

class _Builder {
  _Builder(this.v);

  final ZiSurfaceView v;
  ZiTheme get t => v.theme;

  // ---- values --------------------------------------------------------------

  bool _localized(Map<Object?, Object?> m) => m.isNotEmpty && m.keys.every(_languages.contains);

  Object? _pick(Map<Object?, Object?> m) => m[v.language] ?? m['en'] ?? m.values.first;

  Object? _lookup(String path, Object? item) {
    Object? node = path.startsWith('/') ? v.data : item;
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
    if (bar < 0) return '${_lookup(inside, item) ?? ''}';
    return ziFormat(_lookup(inside.substring(0, bar), item), inside.substring(bar + 1), v.language);
  });

  /// A literal, `{"path": …}` (with an optional `format`), a language map,
  /// or a string with `{/a/b}`.
  Object? resolve(Object? value, Object? item) {
    if (value is Map) {
      if (value['path'] is String) {
        final found = _lookup(value['path'] as String, item);
        final format = value['format'];
        return format is String ? ziFormat(found, format, v.language) : found;
      }
      if (_localized(value)) return resolve(_pick(value), item);
      return {for (final e in value.entries) '${e.key}': resolve(e.value, item)};
    }
    if (value is String) return _interpolate(value, item);
    if (value is List) return [for (final x in value) resolve(x, item)];
    return value;
  }

  String text(Object? value, Object? item) => '${resolve(value, item) ?? ''}';

  double? number(Object? value) => value is num ? value.toDouble() : null;

  // ---- actions -------------------------------------------------------------

  VoidCallback? action(Map<String, Object?> spec, Object? item) {
    final a = spec['action'];
    if (a is! Map) return null;
    final name = '${a['name']}';
    final rawArgs = a['args'];
    return () {
      if (!ziAllowedActions.contains(name)) {
        debugPrint('zehn_intelligence: action "$name" is not allowed; ignored');
        return;
      }
      // Entry by entry: the args map itself is never a data binding, so an
      // argument named "path" stays an argument.
      final args = <String, Object?>{
        if (rawArgs is Map)
          for (final e in rawArgs.entries) '${e.key}': resolve(e.value, item),
      };
      v.onAction(ZiSurfaceAction(name, args));
    };
  }

  // ---- components ----------------------------------------------------------

  Widget? build(String id, Object? item, int depth) {
    if (depth > 32) return _error('Nested too deep at "$id"');
    final spec = v.surface.components[id];
    if (spec == null) return _error('No component "$id"');
    if (spec.containsKey('visible')) {
      final shown = resolve(spec['visible'], item);
      if (shown == null || shown == false || shown == '') return null;
    }
    try {
      return _wrap(spec, item, _component(spec, item, depth));
    } on Object catch (e) {
      return _error('"$id": $e');
    }
  }

  Widget _component(Map<String, Object?> s, Object? item, int depth) {
    final type = s['component'] as String;
    final onSurface = t.color('on_surface', Colors.white);
    final muted = t.color('muted', Colors.white70);
    final chip = t.color('chip', Colors.white10);
    switch (type) {
      case 'Box':
        final child = s['child'] is String ? build(s['child'] as String, item, depth + 1) : null;
        return Container(
          padding: EdgeInsets.all(number(s['padding']) ?? 0),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: t.color(s['color'], Colors.transparent),
            borderRadius: BorderRadius.circular(t.radius(s['radius'], 0)),
            border: s['border'] == null ? null : Border.all(color: t.color(s['border'], chip)),
          ),
          child: child,
        );
      case 'Column':
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: _cross(s['align'], CrossAxisAlignment.start),
          spacing: number(s['gap']) ?? 0,
          children: _children(s, item, depth, flexible: true),
        );
      case 'Row':
        final scroll = s['scroll'] == true;
        final row = Row(
          mainAxisSize: scroll ? MainAxisSize.min : MainAxisSize.max,
          crossAxisAlignment: _cross(s['align'], scroll ? CrossAxisAlignment.start : CrossAxisAlignment.center),
          spacing: number(s['gap']) ?? 0,
          children: _children(s, item, depth, flexible: !scroll),
        );
        return scroll
            ? SingleChildScrollView(scrollDirection: Axis.horizontal, clipBehavior: Clip.none, child: row)
            : row;
      case 'Image':
        final src = text(s['src'], item);
        return ClipRRect(
          borderRadius: BorderRadius.circular(t.radius(s['radius'], 0)),
          child: Container(
            width: number(s['width']) ?? double.infinity,
            height: number(s['height']),
            color: t.color('image_bg', Colors.black12),
            child: src.startsWith('https://') || src.startsWith('http://')
                ? Image.network(
                    src,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => Icon(Icons.broken_image_outlined, color: muted),
                  )
                : Icon(Icons.image_outlined, color: muted),
          ),
        );
      case 'Text':
        final maxLines = s['maxLines'] is num ? (s['maxLines'] as num).toInt() : null;
        return Text(
          text(s['text'], item),
          maxLines: maxLines,
          overflow: maxLines == null ? null : TextOverflow.ellipsis,
          style: t.text(s['style'], color: t.color(s['color'], onSurface)),
        );
      case 'Chip':
        final icon = ziIcons[s['icon']];
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: t.color(s['color'], chip),
            borderRadius: BorderRadius.circular(t.radius('chip', 100)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, spacing: 6, children: [
            if (icon != null) Icon(icon, size: 14, color: muted),
            Text(text(s['text'], item), style: t.text('caption', color: muted)),
          ]),
        );
      case 'Header':
        final tap = action(s, item);
        return InkWell(
          onTap: tap,
          child: Row(spacing: 10, children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(color: chip, borderRadius: BorderRadius.circular(10)),
              child: Icon(ziIcons[s['icon']] ?? Icons.label_outline, size: 18, color: muted),
            ),
            Expanded(child: Text(text(s['title'], item), style: t.text('title', color: onSurface))),
            if (tap != null) Icon(Icons.chevron_right, color: muted),
          ]),
        );
      case 'InfoRow':
        final tap = action(s, item);
        return InkWell(
          onTap: tap,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 11),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: t.color('border', chip)))),
            child: Row(spacing: 12, children: [
              Icon(ziIcons[s['icon']] ?? Icons.info_outline, size: 18, color: muted),
              Expanded(child: Text(text(s['text'], item), style: t.text('body', color: onSurface))),
              if (tap != null) Icon(Icons.chevron_right, size: 18, color: muted),
            ]),
          ),
        );
      case 'Button':
        final secondary = s['variant'] == 'secondary';
        final fg = secondary ? onSurface : t.color('on_accent', Colors.white);
        final icon = ziIcons[s['icon']];
        return Material(
          color: secondary ? chip : t.color('accent', Colors.orange),
          borderRadius: BorderRadius.circular(t.radius('button', 16)),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: action(s, item),
            child: SizedBox(
              height: 50,
              child: Row(mainAxisAlignment: MainAxisAlignment.center, spacing: 8, children: [
                if (icon != null) Icon(icon, size: 20, color: fg.withValues(alpha: 0.75)),
                Flexible(
                  child: Text(
                    text(s['label'], item),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.text('title', color: fg),
                  ),
                ),
              ]),
            ),
          ),
        );
      case 'Divider':
        return Container(height: 1, color: t.color('border', chip));
      default:
        return _error('"$type" is not in catalog ${v.surface.catalogId}');
    }
  }

  /// Size and tap for any component; Header, InfoRow and Button handle their own tap.
  Widget _wrap(Map<String, Object?> s, Object? item, Widget w) {
    final type = s['component'];
    if (type != 'Image' && (s['width'] != null || s['height'] != null)) {
      w = SizedBox(width: number(s['width']), height: number(s['height']), child: w);
    }
    if (!const {'Header', 'InfoRow', 'Button'}.contains(type)) {
      final tap = action(s, item);
      if (tap != null) w = GestureDetector(onTap: tap, behavior: HitTestBehavior.opaque, child: w);
    }
    return w;
  }

  List<Widget> _children(Map<String, Object?> s, Object? item, int depth, {required bool flexible}) {
    final c = s['children'];
    final pairs = <(Map<String, Object?>?, Widget)>[];
    if (c is List) {
      for (final id in c) {
        final w = build('$id', item, depth + 1);
        if (w != null) pairs.add((v.surface.components['$id'], w));
      }
    } else if (c is Map && c['componentId'] is String) {
      // A template repeated over a list in the data: paths without "/" read the item.
      final items = c['path'] is String ? _lookup(c['path'] as String, item) : null;
      final templateId = c['componentId'] as String;
      for (final element in items is List ? items : const <Object?>[]) {
        final w = build(templateId, element, depth + 1);
        if (w != null) pairs.add((v.surface.components[templateId], w));
      }
    }
    return [
      for (final (spec, w) in pairs)
        flexible && spec?['flex'] is num ? Expanded(flex: (spec!['flex'] as num).toInt(), child: w) : w,
    ];
  }

  CrossAxisAlignment _cross(Object? value, CrossAxisAlignment fallback) => switch (value) {
    'center' => CrossAxisAlignment.center,
    'end' => CrossAxisAlignment.end,
    'stretch' => CrossAxisAlignment.stretch,
    'start' => CrossAxisAlignment.start,
    _ => fallback,
  };

  /// A red note in debug builds; nothing in release.
  Widget _error(String message) {
    if (!kDebugMode) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0x22FF5252),
        border: Border.all(color: const Color(0xFFFF5252)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text('⚠ $message', style: const TextStyle(color: Color(0xFFFF8A80), fontSize: 12)),
    );
  }
}
