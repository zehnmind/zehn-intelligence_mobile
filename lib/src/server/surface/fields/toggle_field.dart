import 'package:flutter/material.dart';

import '../form_draft.dart';
import '../surface.dart';
import '../values.dart';
import 'field_frame.dart';

/// A true or false field: a `Checkbox` before its label, or a `Switch` after it. The whole row takes the tap.
class ZiToggleFieldBlock extends StatelessWidget {
  const ZiToggleFieldBlock({super.key, required this.spec, required this.values, required this.theme, this.form});

  final Map<String, Object?> spec;
  final ZiValues values;
  final ZiTheme theme;
  final ZiFormScope? form;

  @override
  Widget build(BuildContext context) {
    final form = this.form;
    final t = theme;
    final field = spec['field'] as String;
    final label = values.text(spec['label'], null);
    if (form == null || form.readOnly) {
      final shown = values.lookup('/form/$field', null);
      return ZiFieldReadOnly(label: label, value: shown == true ? '✓' : '—', theme: t);
    }
    final on = form.draft.raw[field] == true;
    final open = form.status == ZiFormStatus.pending;
    void flip([bool? next]) {
      form.draft.set(field, next ?? !on);
      form.draft.touch(field);
    }

    final onChanged = open ? flip : null;
    final text = Expanded(
      child: ExcludeSemantics(
        child: Text(label, style: t.text('body', color: t.color('on_surface', Colors.white))),
      ),
    );
    final accent = t.color('accent', Colors.orange);
    final isSwitch = spec['component'] == 'Switch';
    final control = isSwitch
        ? Switch(
            value: on,
            onChanged: onChanged,
            activeTrackColor: accent,
            inactiveTrackColor: t.color('chip', Colors.white10),
          )
        : Checkbox(
            value: on,
            onChanged: onChanged,
            activeColor: accent,
            checkColor: t.color('on_accent', Colors.white),
          );
    return ZiFieldFrame(
      spec: spec,
      values: values,
      theme: t,
      form: form,
      labelAbove: false,
      child: InkWell(
        onTap: open ? () => flip() : null,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Row(
            children: [
              if (isSwitch) ...[text, control] else ...[control, text],
            ],
          ),
        ),
      ),
    );
  }
}
