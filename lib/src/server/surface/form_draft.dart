import 'dart:collection';

import 'package:flutter/foundation.dart';

import 'form_check.dart';
import 'surface.dart';

enum ZiFormStatus { pending, sending, submitted, dismissed }

/// What a person has typed into one form, which fields they left, and what failed.
class ZiFormDraft extends ChangeNotifier {
  ZiFormDraft(this.surface, {Map<String, Object?> prefill = const {}, DateTime Function()? today})
    : today = _dayOf((today ?? DateTime.now)()),
      _fields = {for (final spec in ziFormFields(surface)) spec['field'] as String: spec} {
    for (final entry in _fields.entries) {
      final spec = entry.value;
      final held = _start(spec, prefill[entry.key], this.today) ?? _start(spec, spec['value'], this.today);
      if (held != null) {
        _raw[entry.key] = held;
      } else if (spec['component'] == 'Checkbox' || spec['component'] == 'Switch') {
        _raw[entry.key] = false;
      }
    }
  }

  /// Parsed once, for the life of the form.
  final ZiSurface surface;

  /// The phone's day (date only), fixed when the form is opened.
  final DateTime today;

  final Map<String, Map<String, Object?>> _fields;
  final Map<String, Object?> _raw = {};
  final Set<String> _touched = {};
  final Map<String, ZiCheckFailure> _server = {};
  bool _tried = false;
  bool _notSent = false;
  String? _focusField;
  int _focusTick = 0;
  ({Map<String, Object?> values, Set<String> hidden})? _formed;

  /// By field key, as held: a TextField's text, a bool, an option value or a list of them, `YYYY-MM-DD`.
  Map<String, Object?> get raw => UnmodifiableMapView(_raw);

  /// What `/form` reads and what is sent.
  Map<String, Object?> get values => _form.values;

  Set<String> get hidden => _form.hidden;

  /// The last send failed.
  bool get notSent => _notSent;

  /// The field a failed Send asks to show.
  String? get focusField => _focusField;

  /// Grows with each such request.
  int get focusTick => _focusTick;

  ({Map<String, Object?> values, Set<String> hidden}) get _form => _formed ??= ziFormValues(surface, _raw);

  /// Sets what [field] holds; null removes it. The field's server error is forgotten.
  void set(String field, Object? value) {
    if (value == null) {
      _raw.remove(field);
    } else {
      _raw[field] = value;
    }
    _server.remove(field);
    _formed = null;
    notifyListeners();
  }

  /// [field] was left; its error may show from now on.
  void touch(String field) {
    if (_touched.add(field)) notifyListeners();
  }

  /// A server error first; then, once the field was left or a send was tried, what its own checks say.
  ZiCheckFailure? errorOf(String field) {
    final spec = _fields[field];
    if (spec == null || hidden.contains(field)) return null;
    final server = _server[field];
    if (server != null) return server;
    if (!_touched.contains(field) && !_tried) return null;
    return ziCheckField(spec, _raw[field], today: today);
  }

  /// A send is tried. False, with [focusField] set to the first visible field that fails.
  bool check() {
    _tried = true;
    for (final entry in _fields.entries) {
      if (hidden.contains(entry.key) || ziCheckField(entry.value, _raw[entry.key], today: today) == null) continue;
      _focusField = entry.key;
      _focusTick++;
      notifyListeners();
      return false;
    }
    notifyListeners();
    return true;
  }

  /// Shows what the server refused, by field, and asks to show the first such field in drawn order. A rule the phone
  /// cannot report, or one for a field that is not shown or has nothing to say it with, is not kept: the form says
  /// Not sent instead.
  void serverErrors(Map<String, String> ruleByField) {
    _server.clear();
    for (final entry in ruleByField.entries) {
      final spec = _fields[entry.key];
      final failure = spec == null || hidden.contains(entry.key) || !ziCheckRules.contains(entry.value)
          ? null
          : _failure(spec, entry.value, _raw[entry.key], today);
      if (failure == null) {
        _notSent = true;
      } else {
        _server[entry.key] = failure;
      }
    }
    final shown = _fields.keys.where(_server.containsKey);
    if (shown.isNotEmpty) {
      _focusField = shown.first;
      _focusTick++;
    }
    notifyListeners();
  }

  void markNotSent(bool value) {
    if (_notSent == value) return;
    _notSent = value;
    notifyListeners();
  }
}

DateTime _dayOf(DateTime t) => DateTime(t.year, t.month, t.day);

/// The failure to show for [rule] on [spec], or null when it cannot be said. What the field holds now is
/// believed first; else the field's own check of the rule, when it has bounds to name (or needs none); else,
/// for `length`, the limit every text field is held to.
ZiCheckFailure? _failure(Map<String, Object?> spec, String rule, Object? raw, DateTime today) {
  final own = ziCheckField(spec, raw, today: today);
  if (own != null && own.rule == rule) return own;
  final checks = spec['checks'];
  if (checks is List) {
    for (final c in checks) {
      if (c is Map && c['rule'] == rule) {
        final min = c['min'] is num ? c['min'] as num : null;
        final max = c['max'] is num ? c['max'] as num : null;
        if (min != null || max != null || !const {'length', 'range', 'items'}.contains(rule)) {
          return ZiCheckFailure(rule, min: min, max: max, message: c['message']);
        }
      }
    }
  }
  if (rule == 'length') return ZiCheckFailure(rule, max: spec['maxLength'] is num ? spec['maxLength'] as num : 500);
  return const {'range', 'items'}.contains(rule) ? null : ZiCheckFailure(rule);
}

/// What [spec] starts out holding for [given], or null when [given] is not of the type the field takes.
Object? _start(Map<String, Object?> spec, Object? given, DateTime today) {
  switch (spec['component']) {
    case 'Checkbox' || 'Switch':
      return given is bool ? given : null;
    case 'TextField':
      if (spec['input'] == 'number') {
        final number = ziFieldValue(spec, given);
        if (given is num) return number is num ? '$number' : null;
        return given is String && number is num ? given : null;
      }
      return given is String ? given : null;
    case 'Select':
      final options = [
        for (final o in spec['options'] is List ? spec['options'] as List : const [])
          if (o is Map && o['value'] is String) o['value'] as String,
      ];
      if (spec['multiple'] == true) {
        final picked = [
          if (given is List)
            for (final v in given)
              if (options.contains(v)) v as String,
        ];
        return picked.isEmpty ? null : picked;
      }
      return given is String && options.contains(given) ? given : null;
    case 'DateField':
      final day = ziDateOf(given, today: today);
      return day == null ? null : ziDateText(day);
  }
  return null;
}

/// What the view needs to draw a form.
class ZiFormScope {
  const ZiFormScope({
    required this.formId,
    required this.draft,
    this.status = ZiFormStatus.pending,
    this.busy = false,
    required this.onSubmit,
  });

  final String formId;
  final ZiFormDraft draft;
  final ZiFormStatus status;

  /// The chat is running a turn: Send takes no tap.
  final bool busy;
  final VoidCallback onSubmit;

  bool get readOnly => status == ZiFormStatus.submitted || status == ZiFormStatus.dismissed;
}
