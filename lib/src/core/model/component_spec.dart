/// Hard cap on the components in one reply.
///
/// Enforced at parse time as well as at render time: a 10,000-item list is a
/// denial of service on a phone.
const int kAgentMaxChildren = 10;

/// The id of the built-in prose component.
const String kAgentTextComponent = 'text';

/// The single wire format for everything the agent renders.
///
/// The model emits the smallest possible shape — a component id and, for a
/// card, the id of the entity it shows:
///
///     {"component": "product_card", "id": "8837…"}
///
/// Everything else — the title, the photo, where a tap goes — comes from the
/// app's own data for that entity, never from the model. That is the point: a
/// card cannot show a wrong name or a made-up price, because the model never
/// writes either.
///
/// [fallbackText] is filled in by the app from the resolved entity before
/// anything is shown or saved, so a component is never persisted without one.
/// An old build meeting a component type it has never heard of renders that
/// sentence instead of a blank rectangle.
class ComponentSpec {
  const ComponentSpec({
    required this.type,
    this.fallbackText = '',
    this.props = const {},
  });

  /// Registry key, e.g. `product_card`.
  final String type;
  final Map<String, Object?> props;
  final String fallbackText;

  /// Tolerant parse. Returns `null` for anything structurally unusable.
  static ComponentSpec? fromJson(Object? json) {
    if (json is! Map) return null;

    // `component` is the id the model is taught; `type` is what saved
    // transcripts use. Either names the registry entry.
    final type = json['component'] ?? json['type'];
    if (type is! String || type.isEmpty) return null;

    final rawFallback = json['fallbackText'];
    final fallbackText = rawFallback is String ? rawFallback : '';

    return ComponentSpec(
      type: type,
      fallbackText: fallbackText,
      props: _propsOf(json),
    );
  }

  /// Keys that belong to the component itself rather than to its props.
  ///
  /// `action` and `children` are no longer part of the format — a tap is
  /// declared by the app's component, never by the model — but they stay
  /// reserved so that older transcripts, or a model that still writes them,
  /// have them ignored rather than treated as props.
  static const Set<String> _reserved = {
    'type',
    'component',
    'props',
    'fallbackText',
    'action',
    'children',
  };

  /// Reads props from `props`, falling back to any non-reserved key sitting at
  /// the top level.
  ///
  /// Models inline props rather than nesting them under `props` often enough
  /// that treating it as malformed would mean routinely rendering fallback
  /// text for output that is otherwise perfectly good. Nothing is loosened by
  /// accepting it: whatever is collected here is still validated against the
  /// component's prop schema, and an unrecognised key is still rejected.
  static Map<String, Object?> _propsOf(Map<Object?, Object?> json) {
    final declared = json['props'];
    if (declared is Map && declared.isNotEmpty) {
      return Map<String, Object?>.from(declared);
    }

    final hoisted = <String, Object?>{};
    for (final entry in json.entries) {
      final key = entry.key;
      if (key is String && !_reserved.contains(key)) hoisted[key] = entry.value;
    }
    return hoisted;
  }

  Map<String, Object?> toJson() => {
    'type': type,
    'fallbackText': fallbackText,
    if (props.isNotEmpty) 'props': props,
  };

  /// Reads a string prop, or `null` when absent or of the wrong type.
  String? stringProp(String key) {
    final value = props[key];
    return value is String && value.isNotEmpty ? value : null;
  }

  @override
  String toString() => 'ComponentSpec($type)';
}
