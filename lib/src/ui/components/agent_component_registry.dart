import 'package:flutter/widgets.dart';

import '../../core/config/agent_remote_config.dart';
import '../../core/engine/component_catalog.dart';
import '../../core/entities/entity_store.dart';
import '../../core/log.dart';
import '../../core/model/component_spec.dart';
import '../../core/tools/tool_registry.dart';
import '../widgets/agent_fallback_text.dart';
import '../widgets/agent_text_block.dart';
import 'agent_component.dart';

/// Resolves what a tap does, for whoever hosts the chat.
abstract interface class AgentTapResolver {
  /// A callback that performs [tap] from [context], or null when it may not
  /// run right now — an unknown destination, bad arguments, signed out, a
  /// tool that is not a read.
  VoidCallback? resolve(BuildContext context, AgentTap tap);

  /// Runs a read from a card's own buttons, or null when the host cannot.
  AgentInvoker? get invoker;
}

/// The components the model may show, as the app has them right now.
///
/// Each is one of the app's own widgets, addressed by a component id. The
/// model says which component and which entity; everything on screen comes
/// from the app's data. A component type that is not in here cannot render,
/// so a hallucinated one degrades to text instead of a blank rectangle.
class AgentComponentRegistry implements AgentComponentCatalog {
  AgentComponentRegistry({
    required this.entities,
    this.log = silentAgentLog,
    String textExample = 'Your order will arrive tomorrow.',
  }) : _codeTextExample = textExample,
       _textExample = textExample {
    _components[kAgentTextComponent] = _textComponent();
    _hydrator = ComponentHydrator(
      contracts: () => [
        for (final component in _components.values)
          component.contract(entities),
        for (final card in _cards.values) card.contract(entities),
      ],
      allowlists: entities,
      log: log,
    );
  }

  final EntityStore entities;
  final AgentLog log;

  final Map<String, AgentComponent> _components = {};

  /// The dashboard's cards, after the code's, in the order it gave them.
  Map<String, AgentComponent> _cards = const {};
  late final ComponentHydrator _hydrator;

  final String _codeTextExample;
  String _textExample;
  Map<String, String> _use = const {};
  Set<String> _hidden = const {};

  /// What the dashboard changed about the cards: when to show each, which
  /// to hide from the model (those of a pack switched off, and the
  /// dashboard cards beside them), the example answer, and the cards it
  /// added. Null [textExample] keeps the app's.
  void applyOverlay({
    Map<String, String> use = const {},
    Set<String> hidden = const {},
    String? textExample,
    List<AgentComponent> cards = const [],
  }) {
    _use = use;
    _hidden = hidden;
    _cards = {for (final card in cards) card.type: card};
    final example =
        AgentConfigPick.text(textExample, _codeTextExample) ?? _codeTextExample;
    if (example != _textExample) {
      _textExample = example;
      _components[kAgentTextComponent] = _textComponent();
    }
  }

  AgentComponent _textComponent() => AgentComponent.custom(
    contract: textComponentContract(
      maxTextLength: ComponentHydrator.maxTextLength,
      example: _textExample,
    ),
    build: (ctx) => AgentTextBlock(
      text: ctx.spec.stringProp('text') ?? '',
      tone: switch (ctx.spec.stringProp('tone')) {
        'success' => AgentTextTone.success,
        'warning' => AgentTextTone.warning,
        _ => AgentTextTone.neutral,
      },
    ),
  );

  /// Adds [component]. Throws if its type is taken.
  void add(AgentComponent component) {
    if (_components.containsKey(component.type)) {
      throw AgentRegistrationError(
        'component "${component.type}" is already registered',
      );
    }
    _components[component.type] = component;
  }

  /// Removes a component; the built-in `text` stays.
  bool remove(String type) =>
      type != kAgentTextComponent && _components.remove(type) != null;

  AgentComponent? operator [](String type) => _components[type];

  /// The code's components. The dashboard's cards are in [dashboardCards].
  Iterable<AgentComponent> get all => _components.values;

  Iterable<AgentComponent> get dashboardCards => _cards.values;

  @override
  List<Map<String, Object?>> catalogEntries() => [
    for (final entry in _hydrator.catalogEntries())
      if (!_hidden.contains(entry['component']) &&
          !_hidden.contains(entry['for']))
        _withUse(entry),
  ];

  /// The dashboard's "when to show", written into a fresh entry in place.
  Map<String, Object?> _withUse(Map<String, Object?> entry) {
    final use = _use[entry['component']];
    final code = entry['use'];
    if (use != null && code is String) {
      entry['use'] = AgentConfigPick.text(use, code) ?? code;
    }
    return entry;
  }

  @override
  List<ComponentSpec> hydrate(
    List<ComponentSpec> specs, {
    required String languageCode,
  }) => _hydrator.hydrate(specs, languageCode: languageCode);

  /// Renders one hydrated component.
  ///
  /// An entity card whose entity is no longer known — a resumed
  /// conversation — renders its saved fallback sentence instead of an empty
  /// card.
  Widget build(
    BuildContext context,
    ComponentSpec spec, {
    required AgentTapResolver taps,
    required String languageCode,
  }) {
    final component = _components[spec.type] ?? _cards[spec.type];
    if (component == null) return _fallback(spec);

    final contract = component.contract(entities);
    if (!contract.validate(spec.props, allowlists: entities).isValid) {
      return _fallback(spec);
    }

    AgentTap? tap;
    try {
      tap = component.tapFor(spec, entities);
    } catch (e) {
      log('intelligence: tap for "${spec.type}" failed: $e');
    }

    return component.build(
      AgentBuildContext(
        context: context,
        spec: spec,
        entities: entities,
        languageCode: languageCode,
        onTap: tap == null ? null : _allowed(component, tap, taps, context),
        onInvoke: taps.invoker,
        resolveTap: (tap) => _allowed(component, tap, taps, context),
      ),
    );
  }

  /// The saved sentence, or nothing at all when there is none.
  static Widget _fallback(ComponentSpec spec) =>
      spec.fallbackText.trim().isEmpty
      ? const SizedBox.shrink()
      : AgentFallbackText(spec.fallbackText);

  /// A tap the component did not declare is inert: the audit reads the
  /// declarations, so an undeclared destination would escape review.
  VoidCallback? _allowed(
    AgentComponent component,
    AgentTap tap,
    AgentTapResolver taps,
    BuildContext context,
  ) {
    final declared = switch (tap) {
      AgentTapOpen(:final destination) => component.opens.contains(destination),
      AgentTapInvoke(:final tool) => component.invokes.contains(tool),
    };
    if (!declared) {
      log('intelligence: "${component.type}" tapped to undeclared $tap');
      assert(false, '"${component.type}" must declare $tap in opens/invokes');
      return null;
    }
    return taps.resolve(context, tap);
  }
}
