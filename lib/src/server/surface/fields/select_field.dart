import 'package:flutter/material.dart';

import '../form_draft.dart';
import '../form_words.dart';
import '../surface.dart';
import '../values.dart';
import 'field_frame.dart';

/// One or several of a fixed list of options, drawn as a dropdown (a list in a bottom sheet), as rows in the
/// card, or as chips.
class ZiSelectFieldBlock extends StatefulWidget {
  const ZiSelectFieldBlock({super.key, required this.spec, required this.values, required this.theme, this.form});

  final Map<String, Object?> spec;
  final ZiValues values;
  final ZiTheme theme;
  final ZiFormScope? form;

  @override
  State<ZiSelectFieldBlock> createState() => _ZiSelectFieldBlockState();
}

class _ZiSelectFieldBlockState extends State<ZiSelectFieldBlock> {
  /// The open dropdown sheet's route and the navigator holding it; null when no sheet is open.
  ({NavigatorState navigator, ModalRoute<Object?> route})? _sheet;

  Map<String, Object?> get spec => widget.spec;
  ZiValues get values => widget.values;
  ZiTheme get theme => widget.theme;

  @override
  void didUpdateWidget(ZiSelectFieldBlock old) {
    super.didUpdateWidget(old);
    if (widget.form?.status != ZiFormStatus.pending) _closeSheet();
  }

  @override
  void dispose() {
    _closeSheet();
    super.dispose();
  }

  /// Closes this sheet's route after this frame (the tree cannot be changed while it is being built or taken
  /// apart), and no other: one the person already closed is no longer active.
  void _closeSheet() {
    final sheet = _sheet;
    if (sheet == null) return;
    _sheet = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (sheet.navigator.mounted && sheet.route.isActive) sheet.navigator.removeRoute(sheet.route);
    });
  }

  @override
  Widget build(BuildContext context) {
    final form = widget.form;
    final t = theme;
    final field = spec['field'] as String;
    final multiple = spec['multiple'] == true;
    final look = spec['look'];
    final placeholder = values.text(spec['placeholder'], null);
    final options = [
      for (final o in spec['options'] is List ? spec['options'] as List : const [])
        if (o is Map && o['value'] is String) (value: o['value'] as String, label: values.text(o['label'], null)),
    ];
    List<String> picked(Object? held) => [
      for (final o in options)
        if (held is List ? held.contains(o.value) : held == o.value) o.value,
    ];
    String shown(List<String> picks) => [
      for (final o in options)
        if (picks.contains(o.value)) o.label,
    ].join(', ');

    if (form == null || form.readOnly) {
      final held = form == null ? null : values.lookup('/form/$field', null);
      return ZiFieldReadOnly(label: values.text(spec['label'], null), value: shown(picked(held)), theme: t);
    }

    final draft = form.draft;
    final open = form.status == ZiFormStatus.pending;
    final onSurface = t.color('on_surface', Colors.white);
    final accent = t.color('accent', Colors.orange);

    // A tap on a picked option clears it (or takes it out of several); several stay in the options' order.
    void toggle(String value) {
      final now = picked(draft.raw[field]);
      final next = multiple
          ? [
              for (final o in options)
                if (o.value == value ? !now.contains(value) : now.contains(o.value)) o.value,
            ]
          : (now.contains(value) ? <String>[] : [value]);
      draft.set(field, next.isEmpty ? null : (multiple ? next : next.first));
      draft.touch(field);
    }

    Widget rows(BuildContext sheet) {
      final now = picked(draft.raw[field]);
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final o in options)
            _row(
              o.label,
              now.contains(o.value),
              multiple,
              ValueKey('zi-option-${o.value}'),
              open
                  ? () {
                      // The status now, not the one the sheet was opened with.
                      if (widget.form?.status != ZiFormStatus.pending) return;
                      toggle(o.value);
                      if (!multiple && look != 'list' && ModalRoute.of(sheet)?.isCurrent == true) {
                        Navigator.of(sheet).pop();
                      }
                    }
                  : null,
              onSurface,
              accent,
            ),
        ],
      );
    }

    final Widget control;
    // What the dropdown shows, read out beside the label; rows and chips each say whether they are picked.
    String? showing;
    if (look == 'list') {
      control = ListenableBuilder(listenable: draft, builder: (c, _) => rows(c));
    } else if (look == 'chips') {
      control = ListenableBuilder(
        listenable: draft,
        builder: (_, _) {
          final now = picked(draft.raw[field]);
          // Each chip's tap area reaches 4 px past it, so the rows still look 8 px apart.
          return Wrap(
            spacing: 8,
            children: [
              for (final o in options)
                _chip(
                  o.label,
                  now.contains(o.value),
                  multiple,
                  ValueKey('zi-option-${o.value}'),
                  open ? () => toggle(o.value) : null,
                  t,
                ),
            ],
          );
        },
      );
    } else {
      final muted = t.color('muted', Colors.white70);
      final text = shown(picked(draft.raw[field]));
      final empty = text.isEmpty;
      showing = empty ? (placeholder.isEmpty ? ziFormWord('choose', values.language) : placeholder) : text;
      control = Material(
        color: t.color('chip', Colors.white10),
        borderRadius: BorderRadius.circular(t.radius('button', 16)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: open
              ? () {
                  // Else a text field that had focus gets it back when the sheet closes, and the keyboard reopens.
                  FocusManager.instance.primaryFocus?.unfocus();
                  showModalBottomSheet<void>(
                    context: context,
                    backgroundColor: t.color('surface', Colors.black),
                    isScrollControlled: true,
                    builder: (sheet) {
                      _sheet = (navigator: Navigator.of(sheet), route: ModalRoute.of(sheet)!);
                      return SafeArea(
                        child: SingleChildScrollView(
                          child: ListenableBuilder(listenable: draft, builder: (c, _) => rows(c)),
                        ),
                      );
                    },
                  ).whenComplete(() => _sheet = null);
                }
              : null,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: ExcludeSemantics(
                      child: Text(showing, style: t.text('body', color: empty ? muted : onSurface)),
                    ),
                  ),
                  Icon(Icons.expand_more, color: muted),
                ],
              ),
            ),
          ),
        ),
      );
    }
    return ZiFieldFrame(spec: spec, values: values, theme: t, form: form, value: showing, child: control);
  }

  Widget _row(String label, bool on, bool multiple, Key key, VoidCallback? onTap, Color onSurface, Color accent) {
    final icon = multiple
        ? (on ? Icons.check_box : Icons.check_box_outline_blank)
        : (on ? Icons.radio_button_checked : Icons.radio_button_unchecked);
    // Read out as the checkbox or radio button it looks like.
    return Semantics(
      container: true,
      button: true,
      checked: on,
      inMutuallyExclusiveGroup: !multiple,
      child: InkWell(
        key: key,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              spacing: 12,
              children: [
                Icon(icon, color: on ? accent : onSurface),
                Expanded(
                  child: Text(label, style: theme.text('body', color: onSurface)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _chip(String label, bool on, bool multiple, Key key, VoidCallback? onTap, ZiTheme t) {
    // Several chips are checked, like filter chips; one of them is selected, like a choice chip.
    return Semantics(
      container: true,
      button: true,
      checked: multiple ? on : null,
      selected: multiple ? null : on,
      // 40 px to look at, 48 px to tap: the 4 px above and below take the tap too.
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        excludeFromSemantics: true,
        onTap: onTap,
        child: SizedBox(
          height: 48,
          child: Align(
            widthFactor: 1,
            child: Material(
              color: on ? t.color('accent', Colors.orange) : t.color('chip', Colors.white10),
              borderRadius: BorderRadius.circular(t.radius('chip', 20)),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                key: key,
                onTap: onTap,
                child: Container(
                  height: 40,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  alignment: Alignment.center,
                  child: Text(
                    label,
                    style: t.text(
                      'body',
                      color: on ? t.color('on_accent', Colors.white) : t.color('on_surface', Colors.white),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
