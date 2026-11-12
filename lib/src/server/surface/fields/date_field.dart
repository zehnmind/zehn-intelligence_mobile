import 'package:flutter/material.dart';

import '../form_check.dart';
import '../form_draft.dart';
import '../form_words.dart';
import '../formats.dart';
import '../surface.dart';
import '../values.dart';
import 'field_frame.dart';

/// A day picked from a calendar, held as `YYYY-MM-DD`.
class ZiDateFieldBlock extends StatefulWidget {
  const ZiDateFieldBlock({super.key, required this.spec, required this.values, required this.theme, this.form});

  final Map<String, Object?> spec;
  final ZiValues values;
  final ZiTheme theme;
  final ZiFormScope? form;

  @override
  State<ZiDateFieldBlock> createState() => _ZiDateFieldBlockState();
}

class _ZiDateFieldBlockState extends State<ZiDateFieldBlock> {
  /// The open calendar's route and the navigator holding it; null when no calendar is open.
  ({NavigatorState navigator, Route<DateTime> route})? _calendar;

  @override
  void didUpdateWidget(ZiDateFieldBlock old) {
    super.didUpdateWidget(old);
    if (widget.form?.status != ZiFormStatus.pending) _closeCalendar();
  }

  @override
  void dispose() {
    _closeCalendar();
    super.dispose();
  }

  /// Closes this calendar's route after this frame (the tree cannot be changed while it is being built or taken
  /// apart), and no other: one the person already closed is no longer active.
  void _closeCalendar() {
    final calendar = _calendar;
    if (calendar == null) return;
    _calendar = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (calendar.navigator.mounted && calendar.route.isActive) calendar.navigator.removeRoute(calendar.route);
    });
  }

  /// The first and last day the calendar offers, from the field's bounds.
  ({DateTime first, DateTime last}) _range(DateTime today) {
    final min = ziDateOf(widget.spec['min'], today: today);
    final max = ziDateOf(widget.spec['max'], today: today);
    final first = min ?? DateTime(1900);
    // A max before the first day is ignored; so is a first day past the default end.
    var last = max != null && !max.isBefore(first) ? max : DateTime(2100);
    if (last.isBefore(first)) last = first;
    return (first: first, last: last);
  }

  Future<void> _open(ZiFormDraft draft, String field, ({DateTime first, DateTime last}) range) async {
    final (:first, :last) = range;
    // The held day, else today, moved inside the bounds.
    final held = ziDateOf(draft.raw[field], today: draft.today) ?? draft.today;
    final initial = held.isBefore(first) ? first : (held.isAfter(last) ? last : held);

    final navigator = Navigator.of(context);
    final route = DialogRoute<DateTime>(
      context: context,
      builder: (_) => DatePickerDialog(firstDate: first, lastDate: last, initialDate: initial),
    );
    _calendar = (navigator: navigator, route: route);
    final picked = await navigator.push(route);
    if (_calendar?.route == route) _calendar = null;
    // The form may have been locked, or the card gone, while the calendar was open.
    if (picked == null || !mounted || widget.form?.status != ZiFormStatus.pending) return;
    draft.set(field, ziDateText(picked));
    draft.touch(field);
  }

  @override
  Widget build(BuildContext context) {
    final form = widget.form;
    final values = widget.values;
    final t = widget.theme;
    final spec = widget.spec;
    final field = spec['field'] as String;
    String shown(Object? held) => held == null ? '' : ziFormat(held, 'date', values.language);

    if (form == null || form.readOnly) {
      final held = form == null ? null : values.lookup('/form/$field', null);
      return ZiFieldReadOnly(label: values.text(spec['label'], null), value: shown(held), theme: t);
    }

    final draft = form.draft;
    final open = form.status == ZiFormStatus.pending;
    final onSurface = t.color('on_surface', Colors.white);
    final muted = t.color('muted', Colors.white70);
    final range = _range(draft.today);
    final control = ListenableBuilder(
      listenable: draft,
      builder: (_, _) {
        final text = shown(draft.raw[field]);
        final empty = text.isEmpty;
        return Material(
          color: t.color('chip', Colors.white10),
          borderRadius: BorderRadius.circular(t.radius('button', 16)),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: open ? () => _open(draft, field, range) : null,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Expanded(
                      child: ExcludeSemantics(
                        child: Text(
                          empty ? ziFormWord('choose', values.language) : text,
                          style: t.text('body', color: empty ? muted : onSurface),
                        ),
                      ),
                    ),
                    Icon(Icons.calendar_today_outlined, color: muted),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
    return ZiFieldFrame(spec: spec, values: values, theme: t, form: form, child: control);
  }
}
