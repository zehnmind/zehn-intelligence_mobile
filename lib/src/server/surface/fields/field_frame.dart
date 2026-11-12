import 'package:flutter/material.dart';

import '../form_check.dart';
import '../form_draft.dart';
import '../surface.dart';
import '../values.dart';

/// Around every field: the label above it, the hint or the error under it, its name for a
/// screen reader, and "scroll here" when a failed Send names this field.
class ZiFieldFrame extends StatefulWidget {
  const ZiFieldFrame({
    super.key,
    required this.spec,
    required this.values,
    required this.theme,
    required this.form,
    required this.child,
    this.focus,
    this.labelAbove = true,
  });

  final Map<String, Object?> spec;
  final ZiValues values;
  final ZiTheme theme;
  final ZiFormScope form;
  final Widget child;

  /// Asked for focus when a failed Send names this field.
  final FocusNode? focus;

  /// False for a block that draws its label beside its control.
  final bool labelAbove;

  @override
  State<ZiFieldFrame> createState() => _ZiFieldFrameState();
}

class _ZiFieldFrameState extends State<ZiFieldFrame> {
  late int _tick;

  String get _field => widget.spec['field'] as String;

  @override
  void initState() {
    super.initState();
    _tick = widget.form.draft.focusTick;
  }

  @override
  void didUpdateWidget(ZiFieldFrame old) {
    super.didUpdateWidget(old);
    final draft = widget.form.draft;
    // Only a request made since this frame last looked counts; the card is drawn again on every keystroke.
    if (draft.focusTick == _tick) return;
    _tick = draft.focusTick;
    if (draft.focusField != _field) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Scrollable.ensureVisible(context, alignment: 0.1, duration: const Duration(milliseconds: 200));
      widget.focus?.requestFocus();
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.theme;
    final muted = t.text('caption', color: t.color('muted', Colors.white70));
    final label = widget.values.text(widget.spec['label'], null);
    final hint = widget.values.text(widget.spec['hint'], null);
    final failure = widget.form.draft.errorOf(_field);
    final error = failure == null ? null : ziCheckMessage(failure, widget.values);
    final under = error ?? (hint.isEmpty ? null : hint);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 6,
      children: [
        if (widget.labelAbove && label.isNotEmpty) ExcludeSemantics(child: Text(label, style: muted)),
        Semantics(container: true, label: label, hint: under, child: widget.child),
        if (error != null)
          Semantics(
            liveRegion: true,
            child: Text(
              error,
              key: ValueKey('zi-error-$_field'),
              style: t.text('caption', color: t.color('error', const Color(0xFFD64545))),
            ),
          )
        else if (hint.isNotEmpty)
          Text(hint, style: muted),
      ],
    );
  }
}

/// A field that takes no input: its label, and its value as text ("—" when empty).
class ZiFieldReadOnly extends StatelessWidget {
  const ZiFieldReadOnly({super.key, required this.label, required this.value, required this.theme});

  final String label;
  final String value;
  final ZiTheme theme;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 4,
      children: [
        if (label.isNotEmpty) Text(label, style: theme.text('caption', color: theme.color('muted', Colors.white70))),
        Text(value.isEmpty ? '—' : value, style: theme.text('body', color: theme.color('on_surface', Colors.white))),
      ],
    );
  }
}
