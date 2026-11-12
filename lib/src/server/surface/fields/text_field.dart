import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../form_draft.dart';
import '../surface.dart';
import '../values.dart';
import 'field_frame.dart';

/// A box to type into. Its text, cursor and focus live in this [State], which the card finds again by key
/// when it is drawn anew on every keystroke.
class ZiTextFieldBlock extends StatefulWidget {
  const ZiTextFieldBlock({
    super.key,
    required this.spec,
    required this.values,
    required this.theme,
    this.form,
    this.last = false,
  });

  final Map<String, Object?> spec;
  final ZiValues values;
  final ZiTheme theme;
  final ZiFormScope? form;

  /// The last text field shown, so its key is Done.
  final bool last;

  @override
  State<ZiTextFieldBlock> createState() => _ZiTextFieldBlockState();
}

class _ZiTextFieldBlockState extends State<ZiTextFieldBlock> {
  late final TextEditingController _controller = TextEditingController(text: _held(widget.form?.draft.raw[_field]));
  final FocusNode _focus = FocusNode();

  String get _field => widget.spec['field'] as String;

  static String _held(Object? raw) => raw is String ? raw : '';

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) widget.form?.draft.touch(_field);
    });
  }

  @override
  void dispose() {
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final form = widget.form;
    final spec = widget.spec;
    final t = widget.theme;
    final label = widget.values.text(spec['label'], null);
    if (form == null || form.readOnly) {
      final shown = widget.values.lookup('/form/$_field', null);
      return ZiFieldReadOnly(label: label, value: shown == null ? '' : '$shown', theme: t);
    }
    final input = spec['input'];
    final multiline = input == 'multiline';
    final maxLength = spec['maxLength'] is num ? (spec['maxLength'] as num).toInt() : 500;
    final failure = form.draft.errorOf(_field);
    final body = t.text('body', color: t.color('on_surface', Colors.white));
    final muted = t.color('muted', Colors.white70);
    final radius = BorderRadius.circular(t.radius('button', 16));
    OutlineInputBorder border(Color color, double width) => OutlineInputBorder(
      borderRadius: radius,
      borderSide: BorderSide(color: color, width: width),
    );
    final rest = failure == null
        ? OutlineInputBorder(borderRadius: radius, borderSide: BorderSide.none)
        : border(t.color('error', const Color(0xFFD64545)), 1);
    return ZiFieldFrame(
      spec: spec,
      values: widget.values,
      theme: t,
      form: form,
      focus: _focus,
      child: TextField(
        controller: _controller,
        focusNode: _focus,
        enabled: form.status == ZiFormStatus.pending,
        keyboardType: switch (input) {
          'multiline' => TextInputType.multiline,
          'number' => const TextInputType.numberWithOptions(decimal: true, signed: true),
          'email' => TextInputType.emailAddress,
          'phone' => TextInputType.phone,
          _ => TextInputType.text,
        },
        textInputAction: multiline
            ? TextInputAction.newline
            : (widget.last ? TextInputAction.done : TextInputAction.next),
        minLines: multiline ? 3 : 1,
        maxLines: multiline ? 6 : 1,
        inputFormatters: [LengthLimitingTextInputFormatter(maxLength)],
        scrollPadding: const EdgeInsets.fromLTRB(20, 20, 20, 96),
        style: body,
        onChanged: (text) => form.draft.set(_field, text),
        decoration: InputDecoration(
          filled: true,
          fillColor: t.color('chip', Colors.white10),
          counterText: '',
          hintText: widget.values.text(spec['placeholder'], null),
          hintStyle: body.copyWith(color: muted),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          constraints: const BoxConstraints(minHeight: 48),
          border: rest,
          enabledBorder: rest,
          disabledBorder: rest,
          focusedBorder: border(t.color('accent', Colors.orange), 1.5),
        ),
      ),
    );
  }
}
