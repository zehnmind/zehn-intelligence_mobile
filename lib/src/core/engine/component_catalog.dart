import '../log.dart';
import '../model/component_spec.dart';
import '../schema/prop_schema.dart';

/// What the model is told about a component, and how its props are checked —
/// everything about a component except how it draws.
///
/// An entity card has a single prop, `id`, validated against an allowlist:
/// the model names the component and the entity, and the app draws the rest
/// from its own data.
class ComponentContract {
  const ComponentContract({
    required this.type,
    required this.use,
    required this.example,
    this.props = const {},
    this.describe,
    this.baseType,
  });

  /// An entity card: `{"component": type, "id": <id of kind>}`.
  ComponentContract.entity({
    required this.type,
    required String kind,
    required this.use,
    required this.describe,
    Map<String, Object?>? example,
    String what = 'id',
  }) : props = {
         'id': PropSchema.entityId(
           kind,
           required: true,
           description: 'The $what, copied exactly from the tool result.',
         ),
       },
       example = example ?? {'component': type, 'id': '<$what from the tool>'},
       baseType = null;

  /// The component id the model names, e.g. `product_card`.
  final String type;

  /// When to use it — shown to the model verbatim.
  final String use;

  /// A complete, valid instance — shown to the model. Models copy examples
  /// far more reliably than they follow schemas.
  final Map<String, Object?> example;

  final Map<String, PropSchema> props;

  /// A plain sentence carrying what the component shows, written by the app
  /// from the entity itself: the text a screen reader, the voice and a saved
  /// transcript use. Null means the entity cannot be resolved, and the
  /// component is dropped rather than rendered empty.
  final String? Function(ComponentSpec spec, String languageCode)? describe;

  /// For a dashboard card: the coded card it stands beside, whose results it
  /// shows by the same id. The model may use either for a result, never
  /// both. Null for every coded card.
  final String? baseType;

  bool get isEntityCard => props.containsKey('id');

  SchemaValidation validate(
    Map<String, Object?> values, {
    AgentAllowlists? allowlists,
  }) => SchemaValidation.run(props, values, allowlists: allowlists);

  Map<String, Object?> toCatalogEntry() => {
    'component': type,
    'use': use,
    'example': example,
    'for': ?baseType,
  };
}

/// The built-in prose component. [example] is the sentence the model is shown;
/// one from the app's own domain works best.
ComponentContract textComponentContract({
  int maxTextLength = 500,
  String example = 'Your order will arrive tomorrow.',
}) => ComponentContract(
  type: kAgentTextComponent,
  use:
      'One or two short sentences. Lead every reply with one that answers '
      'the question directly.',
  example: {'component': 'text', 'text': example},
  props: {
    'text': PropSchema(
      type: PropType.string,
      description: 'Plain prose. No markdown, no links.',
      isRequired: true,
      maxLength: maxTextLength,
    ),
    'tone': const PropSchema(
      type: PropType.string,
      description: 'warning for bad news, success for a completed change.',
      allowedValues: ['neutral', 'success', 'warning'],
    ),
  },
  describe: (spec, _) => spec.stringProp('text'),
);

/// What the engine needs from the components: the catalog shown to the model,
/// and a way to make the model's output safe to show and save.
abstract interface class AgentComponentCatalog {
  List<Map<String, Object?>> catalogEntries();

  List<ComponentSpec> hydrate(
    List<ComponentSpec> specs, {
    required String languageCode,
  });
}

/// Turns raw model output into components that are safe to show and save.
class ComponentHydrator implements AgentComponentCatalog {
  ComponentHydrator({
    required Iterable<ComponentContract> Function() contracts,
    required AgentAllowlists allowlists,
    this.log = silentAgentLog,
  }) : _contracts = contracts,
       _allowlists = allowlists;

  static const int maxComponents = kAgentMaxChildren;
  static const int maxTextLength = 500;

  final Iterable<ComponentContract> Function() _contracts;
  final AgentAllowlists _allowlists;
  final AgentLog log;

  Map<String, ComponentContract> get _byType => {
    for (final contract in _contracts()) contract.type: contract,
  };

  ComponentContract? contractFor(String type) => _byType[type];

  @override
  List<Map<String, Object?>> catalogEntries() => [
    for (final contract in _contracts()) contract.toCatalogEntry(),
  ];

  /// * Unknown component types are dropped, unless they already carry
  ///   fallback text (a transcript from a newer build) — clipped, and with
  ///   nothing else kept.
  /// * Cards keep only their `id`. Anything else the model wrote beside it —
  ///   a title, a price, an `imageUrl` — is discarded unread, because
  ///   rendering never uses it; the app's own data does.
  /// * A card whose entity this conversation never fetched is dropped. There
  ///   is nothing true to show for it.
  /// * Fallback text is written by the app from the entity, so every saved
  ///   component has an accurate one.
  /// * Repeats are removed — a dashboard card and the card it stands beside
  ///   are one card for the same id, and the first wins — and the total is
  ///   capped.
  @override
  List<ComponentSpec> hydrate(
    List<ComponentSpec> specs, {
    required String languageCode,
  }) {
    final byType = _byType;
    final hydrated = <ComponentSpec>[];
    final seen = <String>{};
    const cap = maxComponents;

    for (final raw in specs) {
      if (hydrated.length >= cap) break;

      final contract = byType[raw.type];
      if (contract == null) {
        final text = raw.fallbackText.trim();
        if (text.isNotEmpty) {
          hydrated.add(
            ComponentSpec(
              type: raw.type,
              fallbackText: clip(text, maxTextLength),
            ),
          );
        }
        log('intelligence: dropped unknown component "${raw.type}"');
        continue;
      }

      final spec = _normalize(contract, raw);
      if (spec == null) continue;

      final validation = contract.validate(spec.props, allowlists: _allowlists);
      if (!validation.isValid) {
        log('intelligence: dropped "${spec.type}" — ${validation.summary}');
        continue;
      }

      String? fallback;
      try {
        fallback = contract.describe?.call(spec, languageCode);
      } catch (e) {
        log('intelligence: could not describe "${spec.type}": $e');
        continue;
      }
      if (contract.describe != null && fallback == null) continue;

      final key =
          '${contract.baseType ?? spec.type}:'
          '${spec.props['id'] ?? spec.props['text']}';
      if (!seen.add(key)) continue;

      hydrated.add(
        ComponentSpec(
          type: spec.type,
          props: spec.props,
          fallbackText: fallback ?? spec.fallbackText,
        ),
      );
    }

    return hydrated;
  }

  ComponentSpec? _normalize(ComponentContract contract, ComponentSpec raw) {
    if (contract.isEntityCard) {
      final id = raw.props['id'] ?? raw.props['entityId'];
      if (id is! String || id.isEmpty) return null;
      return ComponentSpec(type: raw.type, props: {'id': id});
    }

    if (contract.type == kAgentTextComponent) {
      final text = (raw.stringProp('text') ?? raw.fallbackText).trim();
      if (text.isEmpty) return null;
      final tone = raw.stringProp('tone');
      return ComponentSpec(
        type: kAgentTextComponent,
        props: {
          'text': clip(text, maxTextLength),
          if (tone == 'success' || tone == 'warning') 'tone': tone,
        },
      );
    }

    return raw;
  }

  /// Cuts [text] to [max] characters at a word boundary where one is near.
  static String clip(String text, int max) {
    if (text.length <= max) return text;
    final cut = text.substring(0, max - 1);
    final space = cut.lastIndexOf(' ');
    return '${space > max * 0.6 ? cut.substring(0, space) : cut}…';
  }
}
