import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'fields/text_field.dart';
import 'form_check.dart';
import 'form_draft.dart';
import 'form_words.dart';
import 'surface.dart';
import 'values.dart';

/// The only things a component's tap may ask for.
const ziAllowedActions = {'open_route', 'ask', 'open_url', 'submit'};

/// Catalog `zehn.basic.v0`: what this build can draw.
const ziCatalog = {'Box', 'Column', 'Row', 'Image', 'Text', 'Icon', 'Chip', 'Header', 'InfoRow', 'Button', 'Divider', 'Stack', 'Wrap', 'Progress', 'Avatar', 'TextField'};

/// Whether this build has a widget for every block of [surface]'s template.
bool ziDraws(ZiSurface surface) => surface.components.values.every((spec) => ziCatalog.contains(spec['component']));

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
  'forward': Icons.chevron_right,
};

/// Draws one of the app's own icons: its [size] and [color] come from the template.
typedef ZiIconBuilder = Widget Function(BuildContext context, double size, Color color);

/// The app's own icons by name (`ZehnIntelligence.registerIcon`). A name here beats a built-in
/// of the same name, so an app can give `forward` its own chevron.
final Map<String, ZiIconBuilder> ziCustomIcons = {};

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
    this.form,
  });

  final ZiSurface surface;
  final Object? data;
  final ZiTheme theme;
  final String language;
  final void Function(ZiSurfaceAction action) onAction;

  /// Set when the card is a form: blocks read what is typed from `/form`, and Send asks the form.
  final ZiFormScope? form;

  @override
  Widget build(BuildContext context) {
    final form = this.form;
    if (form == null) return _Builder(this, data).build(surface.root, null, 0) ?? const SizedBox.shrink();
    return ListenableBuilder(
      listenable: form.draft,
      builder: (context, _) {
        final base = data is Map<String, Object?> ? data as Map<String, Object?> : const <String, Object?>{};
        return _Builder(this, {...base, 'form': form.draft.values}).build(surface.root, null, 0) ??
            const SizedBox.shrink();
      },
    );
  }
}

class _Builder {
  _Builder(this.v, Object? data) : values = ZiValues(data, v.language);

  final ZiSurfaceView v;
  ZiTheme get t => v.theme;

  // ---- values --------------------------------------------------------------

  final ZiValues values;

  Object? resolve(Object? value, Object? item) => values.resolve(value, item);

  String text(Object? value, Object? item) => values.text(value, item);

  double? number(Object? value) => value is num ? value.toDouble() : null;

  /// Space around or inside a block: one number for every side, or
  /// `{"x": 16, "y": 8, "top": 4, "right": …, "bottom": …, "left": …}` (a side beats x / y).
  EdgeInsets insets(Object? value) {
    if (value is num) return EdgeInsets.all(_space(value));
    if (value is! Map) return EdgeInsets.zero;
    double side(String key, String axis) => _space(value[key] ?? value[axis]);
    return EdgeInsets.fromLTRB(side('left', 'x'), side('top', 'y'), side('right', 'x'), side('bottom', 'y'));
  }

  double _space(Object? value) => value is num ? value.toDouble().clamp(0.0, 1000.0) : 0;

  AlignmentGeometry? _alignment(Object? value) => switch (value) {
    'center' => AlignmentDirectional.center,
    'top' => AlignmentDirectional.topCenter,
    'bottom' => AlignmentDirectional.bottomCenter,
    'start' => AlignmentDirectional.centerStart,
    'end' => AlignmentDirectional.centerEnd,
    'top_start' => AlignmentDirectional.topStart,
    'top_end' => AlignmentDirectional.topEnd,
    'bottom_start' => AlignmentDirectional.bottomStart,
    'bottom_end' => AlignmentDirectional.bottomEnd,
    _ => null,
  };

  MainAxisAlignment _main(Object? value) => switch (value) {
    'center' => MainAxisAlignment.center,
    'end' => MainAxisAlignment.end,
    'space_between' => MainAxisAlignment.spaceBetween,
    'space_around' => MainAxisAlignment.spaceAround,
    'space_evenly' => MainAxisAlignment.spaceEvenly,
    _ => MainAxisAlignment.start,
  };

  TextAlign? _textAlign(Object? value) => switch (value) {
    'center' => TextAlign.center,
    'end' => TextAlign.end,
    'start' => TextAlign.start,
    _ => null,
  };

  /// `{"x": 0, "y": 4, "blur": 10, "spread": 0, "color": "#08000000"}`: one soft shadow.
  List<BoxShadow>? _shadow(Object? value) {
    if (value is! Map) return null;
    double n(String key) => value[key] is num ? (value[key] as num).toDouble().clamp(-100.0, 100.0) : 0;
    return [
      BoxShadow(
        color: t.color(value['color'], const Color(0x1F000000)),
        offset: Offset(n('x'), n('y')),
        blurRadius: n('blur').clamp(0.0, 100.0),
        spreadRadius: n('spread'),
      ),
    ];
  }

  // ---- icons ---------------------------------------------------------------

  /// An icon of the app's own, else a built-in one; null for a name nobody knows.
  Widget? glyph(Object? name, double size, Color color) {
    final custom = ziCustomIcons[name];
    if (custom != null) return Builder(builder: (context) => custom(context, size, color));
    final data = ziIcons[name];
    return data == null ? null : Icon(data, size: size, color: color);
  }

  // ---- text ----------------------------------------------------------------

  FontWeight _weight(num w) => FontWeight.values[((w.toInt().clamp(100, 900)) ~/ 100 - 1).clamp(0, 8)];

  /// The block's text style (`style`), with its own `size`, `weight`, `lineHeight`, `letterSpacing`
  /// and `font` on top.
  TextStyle _textStyle(Map<String, Object?> s, Color color) => t.text(
    s['style'],
    color: color,
    size: number(s['size']),
    weight: s['weight'] is num ? (s['weight'] as num).toInt() : null,
    lineHeight: number(s['lineHeight']),
    letterSpacing: number(s['letterSpacing']),
    font: s['font'] is String ? s['font'] as String : null,
  );

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
      if (name == 'submit') {
        v.form?.onSubmit();
        return;
      }
      v.onAction(ZiSurfaceAction(name, args));
    };
  }

  // ---- components ----------------------------------------------------------

  Widget? build(String id, Object? item, int depth) {
    if (depth > 32) return _error('Nested too deep at "$id"');
    final spec = v.surface.components[id];
    if (spec == null) return _error('No component "$id"');
    if (!values.shown(spec, item)) return null;
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
          padding: insets(s['padding']),
          alignment: _alignment(s['alignment']),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: t.color(s['color'], Colors.transparent),
            borderRadius: BorderRadius.circular(t.radius(s['radius'], 0)),
            border: s['border'] == null ? null : Border.all(color: t.color(s['border'], chip)),
            boxShadow: _shadow(s['shadow']),
          ),
          child: child,
        );
      case 'Column':
        return Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: _main(s['justify']),
          crossAxisAlignment: _cross(s['align'], CrossAxisAlignment.start),
          spacing: number(s['gap']) ?? 0,
          children: _children(s, item, depth, flexible: true),
        );
      case 'Row':
        final scroll = s['scroll'] == true;
        final row = Row(
          mainAxisSize: scroll ? MainAxisSize.min : MainAxisSize.max,
          mainAxisAlignment: _main(s['justify']),
          crossAxisAlignment: _cross(s['align'], scroll ? CrossAxisAlignment.start : CrossAxisAlignment.center),
          spacing: number(s['gap']) ?? 0,
          children: _children(s, item, depth, flexible: !scroll),
        );
        // A sideways list pads its own content (the padding scrolls with it), not its frame.
        return scroll
            ? SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                clipBehavior: Clip.none,
                padding: insets(s['padding']),
                child: row,
              )
            : row;
      case 'Image':
        final src = text(s['src'], item);
        final fit = switch (s['fit']) {
          'fill' => BoxFit.fill,
          'contain' => BoxFit.contain,
          _ => BoxFit.cover,
        };
        return ClipRRect(
          borderRadius: BorderRadius.circular(t.radius(s['radius'], 0)),
          child: Container(
            width: number(s['width']) ?? double.infinity,
            height: number(s['height']),
            color: t.color('image_bg', Colors.black12),
            child: src.startsWith('https://') || src.startsWith('http://')
                ? Image.network(
                    src,
                    fit: fit,
                    errorBuilder: (_, _, _) => Icon(Icons.broken_image_outlined, color: muted),
                  )
                : Icon(Icons.image_outlined, color: muted),
          ),
        );
      case 'Text':
        final maxLines = s['maxLines'] is num ? (s['maxLines'] as num).toInt() : null;
        final style = _textStyle(s, t.color(s['color'], onSurface));
        final spans = resolve(s['spans'], item);
        final align = _textAlign(s['textAlign']);
        final overflow = maxLines == null ? null : TextOverflow.ellipsis;
        if (spans is List) {
          return Text.rich(
            TextSpan(children: [
              for (final span in spans)
                if (span is Map)
                  TextSpan(
                    text: '${span['text'] ?? ''}',
                    style: span['color'] == null && span['weight'] == null
                        ? null
                        : TextStyle(
                            color: span['color'] == null ? null : t.color(span['color'], onSurface),
                            fontWeight: span['weight'] is num ? _weight(span['weight'] as num) : null,
                          ),
                  ),
            ]),
            maxLines: maxLines,
            overflow: overflow,
            textAlign: align,
            style: style,
          );
        }
        return Text(text(s['text'], item), maxLines: maxLines, overflow: overflow, textAlign: align, style: style);
      case 'Icon':
        final size = (number(s['size']) ?? 24).clamp(8.0, 96.0);
        return glyph(s['name'], size, t.color(s['color'], muted)) ?? SizedBox(width: size, height: size);
      case 'Chip':
        final icon = glyph(s['icon'], 14, muted);
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: t.color(s['color'], chip),
            borderRadius: BorderRadius.circular(t.radius('chip', 100)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, spacing: 6, children: [
            ?icon,
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
              child: glyph(s['icon'], 18, muted) ?? Icon(Icons.label_outline, size: 18, color: muted),
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
              glyph(s['icon'], 18, muted) ?? Icon(Icons.info_outline, size: 18, color: muted),
              Expanded(child: Text(text(s['text'], item), style: t.text('body', color: onSurface))),
              if (tap != null) Icon(Icons.chevron_right, size: 18, color: muted),
            ]),
          ),
        );
      case 'Button':
        return _button(s, item);
      case 'Divider':
        return Container(height: 1, color: t.color('border', chip));
      case 'Stack':
        // A block with a position is laid over the others; the first block is always a plain one,
        // so the stack always has a size.
        final pairs = _built(s, item, depth);
        return Stack(
          clipBehavior: Clip.none,
          alignment: _alignment(s['alignment']) ?? AlignmentDirectional.topStart,
          children: [
            for (final (i, (spec, w, key)) in pairs.indexed)
              if (_alignment(spec?['position']) case final place? when i > 0)
                Positioned.fill(key: key, child: Align(alignment: place, child: w))
              else
                _keyed(key, w),
          ],
        );
      case 'Wrap':
        final gap = number(s['gap']) ?? 0;
        return Wrap(
          spacing: gap,
          runSpacing: number(s['runGap']) ?? gap,
          alignment: switch (s['align']) {
            'center' => WrapAlignment.center,
            'end' => WrapAlignment.end,
            _ => WrapAlignment.start,
          },
          children: _children(s, item, depth, flexible: false),
        );
      case 'Progress':
        final value = resolve(s['value'], item);
        final fraction = value is num && !value.isNaN ? value.toDouble().clamp(0.0, 1.0) : 0.0;
        final height = (number(s['height']) ?? 6).clamp(2.0, 40.0);
        // Full width where the parent bounds it; a Row child with no width or flex gets 120.
        return LayoutBuilder(
          builder: (context, constraints) => ClipRRect(
            borderRadius: BorderRadius.circular(height / 2),
            child: Container(
              width: constraints.hasBoundedWidth ? double.infinity : 120,
              height: height,
              color: t.color(s['track'], chip),
              alignment: AlignmentDirectional.centerStart,
              child: FractionallySizedBox(
                widthFactor: fraction,
                heightFactor: 1,
                child: ColoredBox(color: t.color(s['color'], t.color('accent', Colors.orange))),
              ),
            ),
          ),
        );
      case 'TextField':
        final form = v.form;
        final shown = form == null ? const <String>{} : form.draft.hidden;
        final lastField = ziFormFields(v.surface).lastWhere(
          (f) => f['component'] == 'TextField' && !shown.contains(f['field']),
          orElse: () => s,
        )['field'];
        return ZiTextFieldBlock(
          key: form == null ? null : ValueKey('zi-field-${form.formId}-${s['id']}'),
          spec: s,
          values: values,
          theme: t,
          form: form,
          last: lastField == s['field'],
        );
      case 'Avatar':
        final size = (number(s['size']) ?? 40).clamp(16.0, 160.0);
        final src = text(s['src'], item);
        final initials = Container(
          alignment: Alignment.center,
          color: t.color(s['color'], chip),
          child: Text(
            text(s['text'], item).trim().characters.take(2).toString().toUpperCase(),
            style: t.text('body', color: onSurface, size: size * 0.4, weight: 500),
          ),
        );
        return ClipOval(
          child: SizedBox(
            width: size,
            height: size,
            child: src.startsWith('https://') || src.startsWith('http://')
                ? ColoredBox(
                    color: t.color('image_bg', Colors.black12),
                    child: Image.network(
                      src,
                      width: size,
                      height: size,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => initials,
                    ),
                  )
                : initials,
          ),
        );
      default:
        return _error('"$type" is not in catalog ${v.surface.catalogId}');
    }
  }

  Widget _button(Map<String, Object?> s, Object? item) {
    final submit = s['action'] is Map && (s['action'] as Map)['name'] == 'submit';
    final form = v.form;
    final muted = t.color('muted', Colors.white70);
    if (submit && form == null) return const SizedBox.shrink();
    if (submit && form!.readOnly) {
      final word = form.status == ZiFormStatus.submitted ? 'sent' : 'not_answered';
      return Text(
        ziFormWord(word, v.language),
        key: const ValueKey('zi-form-status'),
        style: t.text('caption', color: muted),
      );
    }
    final sending = submit && form!.status == ZiFormStatus.sending;
    final busy = submit && form!.busy;
    final secondary = s['variant'] == 'secondary';
    final fg = secondary ? t.color('on_surface', Colors.white) : t.color('on_accent', Colors.white);
    final fill = secondary ? t.color('chip', Colors.white10) : t.color('accent', Colors.orange);
    final tap = sending || busy ? null : action(s, item);
    final icon = glyph(s['icon'], 20, fg.withValues(alpha: 0.75));
    final button = Semantics(
      button: true,
      enabled: tap != null,
      child: Material(
        key: submit ? const ValueKey('zi-form-send') : null,
        color: busy ? fill.withValues(alpha: 0.4) : fill,
        borderRadius: BorderRadius.circular(t.radius('button', 16)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: tap,
          child: SizedBox(
            height: 50,
            child: Row(mainAxisAlignment: MainAxisAlignment.center, spacing: 8, children: [
              if (sending)
                SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: fg))
              else ...[
                ?icon,
                Flexible(
                  child: Text(
                    text(s['label'], item),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.text('title', color: fg),
                  ),
                ),
              ],
            ]),
          ),
        ),
      ),
    );
    if (!submit || !form!.draft.notSent || sending) return button;
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 6, children: [
      button,
      Text(
        ziFormWord('not_sent', v.language),
        key: const ValueKey('zi-form-not-sent'),
        style: t.text('caption', color: t.color('error', const Color(0xFFD64545))),
      ),
    ]);
  }

  /// Padding, size and tap for any component; Header, InfoRow and Button handle their own tap.
  /// Padding is inside the size (as CSS border-box): a Box and a sideways Row pad themselves.
  Widget _wrap(Map<String, Object?> s, Object? item, Widget w) {
    final type = s['component'];
    final padding = insets(s['padding']);
    if (type != 'Box' && !(type == 'Row' && s['scroll'] == true) && padding != EdgeInsets.zero) {
      w = Padding(padding: padding, child: w);
    }
    // A Progress holds its own height to 2..40.
    if (type != 'Image' && (s['width'] != null || s['height'] != null)) {
      w = SizedBox(width: number(s['width']), height: type == 'Progress' ? null : number(s['height']), child: w);
    }
    if (!const {'Header', 'InfoRow', 'Button'}.contains(type)) {
      final tap = action(s, item);
      if (tap != null) w = GestureDetector(onTap: tap, behavior: HitTestBehavior.opaque, child: w);
    }
    return w;
  }

  List<Widget> _children(Map<String, Object?> s, Object? item, int depth, {required bool flexible}) => [
    for (final (spec, w, key) in _built(s, item, depth))
      flexible && spec?['flex'] is num
          ? Expanded(key: key, flex: (spec!['flex'] as num).toInt(), child: w)
          : _keyed(key, w),
  ];

  Widget _keyed(Key? key, Widget w) => key == null ? w : KeyedSubtree(key: key, child: w);

  /// Each drawn child with its spec; a child that is not shown is left out. In a form, a child named by id has a
  /// key to go on the outermost widget its parent makes for it, so a field keeps its text and focus when a sibling
  /// before it appears or goes. A repeated child has none: its id is built many times.
  List<(Map<String, Object?>?, Widget, Key?)> _built(Map<String, Object?> s, Object? item, int depth) {
    final c = s['children'];
    final pairs = <(Map<String, Object?>?, Widget, Key?)>[];
    if (c is List) {
      for (final id in c) {
        final w = build('$id', item, depth + 1);
        if (w != null) pairs.add((v.surface.components['$id'], w, v.form == null ? null : ValueKey('zi-block-$id')));
      }
    } else if (c is Map && c['componentId'] is String) {
      // A template repeated over a list in the data: paths without "/" read the item.
      final items = c['path'] is String ? values.lookup(c['path'] as String, item) : null;
      final templateId = c['componentId'] as String;
      // `separator`: a block drawn between two repeats (a divider), never before the first or after the last.
      final separatorId = c['separator'] is String ? c['separator'] as String : null;
      for (final element in items is List ? items : const <Object?>[]) {
        final w = build(templateId, element, depth + 1);
        if (w == null) continue;
        final between = pairs.isEmpty || separatorId == null ? null : build(separatorId, item, depth + 1);
        if (between != null) pairs.add((v.surface.components[separatorId], between, null));
        pairs.add((v.surface.components[templateId], w, null));
      }
    }
    return pairs;
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
