/// The value kinds a component prop or tool argument may take.
///
/// Deliberately narrow. There is no `url`, no `html` and no free-form
/// `richText` kind: a string the model composes is an injection surface, so
/// every string is either chosen from a list, shaped by a pattern, an id the
/// app handed out, or free text that never leaves the device.
enum PropType { string, integer, number, boolean }

/// Schema for a single prop or tool argument.
///
/// One definition drives three things: runtime validation, the schema the
/// model is shown, and the generated documentation. They cannot drift because
/// they come from the same object.
///
/// Prefer the named constructors, which make the safe choice the easy one:
///
/// ```dart
/// 'query': PropSchema.localText(maxLength: 80, description: 'What to find.'),
/// 'category': PropSchema.choiceFrom(() => categories.slugs, description: '…'),
/// 'cardId': PropSchema.entityId('card', required: true, description: '…'),
/// 'time': PropSchema.pattern(r'^([01]\d|2[0-3]):[0-5]\d$', description: '…'),
/// ```
class PropSchema {
  const PropSchema({
    required this.type,
    required this.description,
    this.isRequired = false,
    this.maxLength,
    this.minimum,
    this.maximum,
    this.allowedValues,
    this.choices,
    this.allowlistKey,
    this.pattern,
    this.localOnly = false,
  });

  /// Free text that is matched or stored on this device and never becomes
  /// part of a network request — a search over data the app already holds, a
  /// note kept in local storage. [maxLength] is required.
  const PropSchema.localText({
    required String description,
    required int maxLength,
    bool required = false,
  }) : this(
         type: PropType.string,
         description: description,
         isRequired: required,
         maxLength: maxLength,
         localOnly: true,
       );

  /// One of a fixed list known when the app is built.
  const PropSchema.choice(
    List<String> values, {
    required String description,
    bool required = false,
  }) : this(
         type: PropType.string,
         description: description,
         isRequired: required,
         allowedValues: values,
       );

  /// One of a list that is only known at run time — category slugs loaded
  /// from the server, zone codes. Read again every turn.
  const PropSchema.choiceFrom(
    Iterable<String> Function() values, {
    required String description,
    bool required = false,
  }) : this(
         type: PropType.string,
         description: description,
         isRequired: required,
         choices: values,
       );

  /// An opaque id the app handed out earlier in the conversation — never one
  /// the model made up. [kind] names an entity kind or allowlist key.
  const PropSchema.entityId(
    String kind, {
    required String description,
    bool required = false,
  }) : this(
         type: PropType.string,
         description: description,
         isRequired: required,
         allowlistKey: kind,
       );

  /// A value with a fixed shape, like a `HH:MM` time, that the app parses
  /// into a real value before anything is sent.
  const PropSchema.pattern(
    String pattern, {
    required String description,
    bool required = false,
    int? maxLength,
  }) : this(
         type: PropType.string,
         description: description,
         isRequired: required,
         pattern: pattern,
         maxLength: maxLength,
       );

  const PropSchema.integer({
    required String description,
    bool required = false,
    int? min,
    int? max,
  }) : this(
         type: PropType.integer,
         description: description,
         isRequired: required,
         minimum: min,
         maximum: max,
       );

  const PropSchema.number({
    required String description,
    bool required = false,
    num? min,
    num? max,
  }) : this(
         type: PropType.number,
         description: description,
         isRequired: required,
         minimum: min,
         maximum: max,
       );

  const PropSchema.boolean({required String description, bool required = false})
    : this(
        type: PropType.boolean,
        description: description,
        isRequired: required,
      );

  final PropType type;
  final String description;
  final bool isRequired;

  /// Hard cap for [PropType.string]. Enforced before the value is used.
  final int? maxLength;

  /// Inclusive bounds for numeric kinds.
  final num? minimum;
  final num? maximum;

  /// A fixed enum, known at compile time.
  final List<String>? allowedValues;

  /// An enum read at run time, every turn.
  final Iterable<String> Function()? choices;

  /// Names a runtime allowlist (see [AgentAllowlists]) that this value must be
  /// a member of. Used for opaque ids, which are never composed by the model —
  /// only ever echoed back from a previous read.
  final String? allowlistKey;

  /// An anchored regular expression a [PropType.string] must match — for a
  /// value with a fixed shape, like a `HH:MM` time. Such a value is parsed by
  /// the app into a real one before anything is sent, so the model's text
  /// never reaches the network as written.
  final String? pattern;

  /// Marks a string that is deliberately free-form because it never becomes
  /// part of a network request — it stays on this device, matched against
  /// data the app already holds or written to local storage and read back.
  ///
  /// Note what this does *not* exempt: such a value is still echoed into a
  /// later prompt, so it is a persistence vector for prompt injection, and it
  /// must be length-capped.
  final bool localOnly;

  /// A string the model may fill with anything: no list, no pattern, no id.
  /// Only acceptable when [localOnly] and capped — see [problems].
  bool get isFreeText =>
      type == PropType.string &&
      allowedValues == null &&
      choices == null &&
      allowlistKey == null &&
      pattern == null;

  /// What is wrong with this schema as a declaration, independent of any
  /// value. Checked when a tool is registered, so an unsafe argument fails at
  /// start-up rather than in production.
  List<String> problems() => [
    if (isFreeText && !localOnly)
      'is free text that could reach the network — use a choice, an entity '
          'id, a pattern, or PropSchema.localText if it never leaves the device',
    if (isFreeText && maxLength == null) 'is free text without a maxLength',
    if (type != PropType.string &&
        (maxLength != null ||
            allowedValues != null ||
            choices != null ||
            allowlistKey != null ||
            pattern != null ||
            localOnly))
      'has string-only constraints on a ${type.name}',
    if (type == PropType.string && (minimum != null || maximum != null))
      'has numeric bounds on a string',
    if (description.trim().isEmpty) 'has no description',
  ];

  /// The values currently allowed for a string, when there is a list.
  Iterable<String>? _enumValues(AgentAllowlists? allowlists) {
    if (allowlistKey != null) {
      return allowlists?.valuesFor(allowlistKey!) ?? const <String>{};
    }
    if (choices != null) return choices!();
    return allowedValues;
  }

  /// Returns `null` when [value] is acceptable, otherwise the reason it is not.
  String? validate(Object? value, {AgentAllowlists? allowlists}) {
    if (value == null) {
      return isRequired ? 'is required' : null;
    }

    switch (type) {
      case PropType.string:
        if (value is! String) return 'must be a string';
        if (value.isEmpty && isRequired) return 'must not be empty';
        if (maxLength != null && value.length > maxLength!) {
          return 'must be at most $maxLength characters (was ${value.length})';
        }
        if (allowedValues != null && !allowedValues!.contains(value)) {
          return 'must be one of ${allowedValues!.join(', ')}';
        }
        if (choices != null) {
          final allowed = choices!();
          if (!allowed.contains(value)) {
            return 'must be one of ${allowed.join(', ')}';
          }
        }
        if (pattern != null && !RegExp(pattern!).hasMatch(value)) {
          return 'must match $pattern';
        }
        if (allowlistKey != null) {
          final allowed = allowlists?.valuesFor(allowlistKey!);
          if (allowed == null || !allowed.contains(value)) {
            return 'is not a known id for "$allowlistKey"';
          }
        }
      case PropType.integer:
        if (value is! int) return 'must be an integer';
        return _checkRange(value);
      case PropType.number:
        if (value is! num) return 'must be a number';
        return _checkRange(value);
      case PropType.boolean:
        if (value is! bool) return 'must be a boolean';
    }
    return null;
  }

  String? _checkRange(num value) {
    if (minimum != null && value < minimum!) return 'must be >= $minimum';
    if (maximum != null && value > maximum!) return 'must be <= $maximum';
    return null;
  }

  /// True when this value can only come from a list, and the list is empty
  /// right now — nothing valid could be put in it this turn.
  bool hasNoValidValue({AgentAllowlists? allowlists}) {
    if (allowlistKey == null && choices == null) return false;
    return _enumValues(allowlists)?.isEmpty ?? true;
  }

  /// The JSON-schema fragment shown to the model for this prop.
  ///
  /// [allowlists] is threaded through so that runtime enums (category slugs,
  /// reservation ids) are materialised as a real `enum` the model can only
  /// pick from, rather than a free string it could compose.
  Map<String, Object?> toJsonSchema({AgentAllowlists? allowlists}) {
    final schema = <String, Object?>{
      'type': switch (type) {
        PropType.string => 'string',
        PropType.integer => 'integer',
        PropType.number => 'number',
        PropType.boolean => 'boolean',
      },
      'description': description,
    };
    if (maxLength != null) schema['maxLength'] = maxLength;
    if (minimum != null) schema['minimum'] = minimum;
    if (maximum != null) schema['maximum'] = maximum;
    if (allowedValues != null) schema['enum'] = allowedValues;
    if (choices != null) schema['enum'] = choices!().toList();
    if (pattern != null) schema['pattern'] = pattern;
    if (allowlistKey != null) {
      schema['enum'] =
          allowlists?.valuesFor(allowlistKey!).toList() ?? const <String>[];
    }
    return schema;
  }
}

/// Validates a whole `{name: value}` map against a schema map.
///
/// Unknown keys are rejected, which is the object-level equivalent of
/// `additionalProperties: false`.
class SchemaValidation {
  const SchemaValidation(this.errors);

  final Map<String, String> errors;

  bool get isValid => errors.isEmpty;

  String get summary =>
      errors.entries.map((e) => '${e.key} ${e.value}').join('; ');

  static SchemaValidation run(
    Map<String, PropSchema> schema,
    Map<String, Object?> values, {
    AgentAllowlists? allowlists,
  }) {
    final errors = <String, String>{};

    for (final key in values.keys) {
      if (!schema.containsKey(key)) {
        errors[key] = 'is not a recognised field';
      }
    }

    for (final entry in schema.entries) {
      if (errors.containsKey(entry.key)) continue;
      final reason = entry.value.validate(
        values[entry.key],
        allowlists: allowlists,
      );
      if (reason != null) errors[entry.key] = reason;
    }

    return SchemaValidation(errors);
  }
}

/// Runtime-resolved id sets.
///
/// The model never composes an id. It may only repeat one that a previous read
/// put in here, so a hallucinated id fails validation instead of reaching the
/// network.
abstract interface class AgentAllowlists {
  /// Ids currently valid for [key]. Unknown keys return an empty set.
  Set<String> valuesFor(String key);
}

/// Ids the app keeps current by itself — the signed-in user's cards, the
/// reservations in its own state — vouched for under one [key].
///
/// Give it to a pack (`AgentPack(allowlists: [...])`) so the model can name
/// one of them without a read first: "freeze my Visa" then needs no
/// `cards.list`. [ids] is read on every check, so it follows the app's state;
/// return nothing when the user is signed out.
class LiveAllowlist implements AgentAllowlists {
  const LiveAllowlist(this.key, this.ids);

  /// The allowlist key — an entity kind's name, e.g. `card`.
  final String key;
  final Iterable<String> Function() ids;

  @override
  Set<String> valuesFor(String key) =>
      key == this.key ? ids().toSet() : const <String>{};
}

/// Joins several allowlist sources into one.
class CompositeAllowlists implements AgentAllowlists {
  const CompositeAllowlists(this._sources);

  final List<AgentAllowlists> _sources;

  @override
  Set<String> valuesFor(String key) => {
    for (final source in _sources) ...source.valuesFor(key),
  };
}
