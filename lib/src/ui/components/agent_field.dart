import '../../core/cards/card_check.dart';
import '../../core/cards/card_values.dart';
import '../../core/entities/entity_store.dart';

/// The fields a coded card exposes to dashboard cards, as the registry, the
/// renderer and the manifest use them.
abstract interface class AgentCardData {
  /// Names and types, for the check.
  List<CardFieldSchema> get schema;

  /// Names, types, examples and units, for the manifest and the console's
  /// preview.
  List<Map<String, Object?>> get manifest;

  /// Every field's value for the entity [id], in [languageCode]; null when
  /// the app no longer has it.
  Map<String, CardValue?>? valuesFor(
    String id,
    String languageCode,
    EntityStore entities,
  );
}

/// One field a coded card exposes to dashboard cards: a named, typed getter
/// over the app's own object.
///
/// Only declared fields can ever be shown, so leave out what must stay on
/// the phone: QR data, card numbers, payment details. An `image` is drawn by
/// the app's own image builder, and its URL never reaches the model.
class AgentField<T> {
  AgentField._(
    this.name,
    this.type,
    this._read, {
    this.example,
    this.unit = const {},
    this.fields = const [],
  });

  /// Words, in the reader's language.
  factory AgentField.text(
    String name,
    String? Function(T entity, String languageCode) get, {
    String? example,
  }) => AgentField._(name, CardFieldType.text, (entity, language) {
    final text = get(entity, language);
    return text == null ? null : CardTextValue(text);
  }, example: example);

  /// Grouped by threes when shown.
  factory AgentField.number(
    String name,
    num? Function(T entity) get, {
    num? example,
  }) => AgentField._(name, CardFieldType.number, (entity, _) {
    final number = get(entity);
    return number == null ? null : CardNumberValue(number);
  }, example: example);

  /// An amount, shown with its [unit] in the reader's language (else
  /// English, else any).
  factory AgentField.money(
    String name,
    num? Function(T entity) get, {
    Map<String, String> unit = const {},
    num? example,
  }) => AgentField._(
    name,
    CardFieldType.money,
    (entity, language) {
      final amount = get(entity);
      if (amount == null) return null;
      return CardMoneyValue(
        amount,
        unit: unit[language] ?? unit['en'] ?? unit.values.firstOrNull ?? '',
      );
    },
    example: example,
    unit: unit,
  );

  /// A wall-clock time: shown as given, never converted to another zone.
  factory AgentField.date(
    String name,
    DateTime? Function(T entity) get, {
    DateTime? example,
  }) => AgentField._(name, CardFieldType.date, (entity, _) {
    final date = get(entity);
    return date == null ? null : CardDateValue(date);
  }, example: example);

  /// An https picture.
  factory AgentField.image(String name, String? Function(T entity) get) =>
      AgentField._(name, CardFieldType.image, (entity, _) {
        final url = get(entity);
        return url == null ? null : CardImageValue(url);
      });

  /// True or false, for a card's `when` and a list's `only`.
  factory AgentField.flag(
    String name,
    bool? Function(T entity) get, {
    bool? example,
  }) => AgentField._(name, CardFieldType.flag, (entity, _) {
    final flag = get(entity);
    return flag == null ? null : CardFlagValue(flag);
  }, example: example);

  /// Items with fields of their own, one row each: one level only. Name
  /// the item type on the list, so its fields' getters know it:
  ///
  /// ```dart
  /// AgentField.list('tickets', (e) => e.tickets, <AgentField<Ticket>>[
  ///   AgentField.text('type', (t, lang) => t.name(lang)),
  ///   AgentField.money('price', (t) => t.price, unit: {'en': 'UZS'}),
  /// ])
  /// ```
  static AgentField<E> list<E, S>(
    String name,
    Iterable<S>? Function(E entity) get,
    List<AgentField<S>> fields,
  ) => AgentField<E>._(name, CardFieldType.list, (entity, language) {
    final items = get(entity);
    if (items == null) return null;
    return CardListValue([
      for (final item in items)
        {for (final field in fields) field.name: field.valueOf(item, language)},
    ]);
  }, fields: fields);

  final String name;
  final CardFieldType type;
  final CardValue? Function(T entity, String languageCode) _read;

  /// What the console's preview shows.
  final Object? example;

  /// A money field's unit, per language.
  final Map<String, String> unit;

  /// A list's item fields.
  final List<AgentField<Object?>> fields;

  /// The value for [entity]. A getter that throws leaves the field empty
  /// rather than the card broken.
  CardValue? valueOf(T entity, String languageCode) {
    try {
      return _read(entity, languageCode);
    } catch (_) {
      return null;
    }
  }

  CardFieldSchema get schema => CardFieldSchema(
    name,
    type,
    fields: [for (final field in fields) field.schema],
  );

  Map<String, Object?> get manifest => {
    'name': name,
    'type': type.name,
    if (example case final example?) 'example': _json(example),
    if (unit.isNotEmpty) 'unit': unit,
    if (fields.isNotEmpty)
      'fields': [for (final field in fields) field.manifest],
  };

  static Object? _json(Object value) => switch (value) {
    DateTime(
      :final year,
      :final month,
      :final day,
      :final hour,
      :final minute,
      :final second,
    ) =>
      '${'$year'.padLeft(4, '0')}-${_two(month)}-${_two(day)}'
          'T${_two(hour)}:${_two(minute)}:${_two(second)}',
    _ => value,
  };

  static String _two(int n) => '$n'.padLeft(2, '0');
}

/// The fields a coded card exposes, with how to find its object by id.
///
/// ```dart
/// AgentComponent.custom(
///   contract: …, build: …,
///   fields: AgentFields<Event>(find: cache.eventById, [
///     AgentField.text('title', (e, lang) => e.title(lang)),
///     AgentField.image('photo', (e) => e.photoUrl),
///   ]),
/// )
/// ```
class AgentFields<T> implements AgentCardData {
  AgentFields(this.fields, {required T? Function(String id) find})
    : _find = find,
      _findIn = null;

  /// For a card that finds its object in the agent's [EntityStore].
  AgentFields.inStore(
    this.fields,
    T? Function(String id, EntityStore entities) find,
  ) : _find = null,
      _findIn = find;

  final List<AgentField<T>> fields;
  final T? Function(String id)? _find;
  final T? Function(String id, EntityStore entities)? _findIn;

  @override
  List<CardFieldSchema> get schema => [for (final f in fields) f.schema];

  @override
  List<Map<String, Object?>> get manifest => [
    for (final f in fields) f.manifest,
  ];

  @override
  Map<String, CardValue?>? valuesFor(
    String id,
    String languageCode,
    EntityStore entities,
  ) {
    final entity = _find != null ? _find(id) : _findIn?.call(id, entities);
    if (entity == null) return null;
    return {for (final f in fields) f.name: f.valueOf(entity, languageCode)};
  }
}
