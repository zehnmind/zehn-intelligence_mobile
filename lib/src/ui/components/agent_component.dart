import 'package:flutter/widgets.dart';

import '../../core/engine/component_catalog.dart';
import '../../core/entities/entity_store.dart';
import '../../core/model/component_spec.dart';
import '../../core/schema/prop_schema.dart';
import '../widgets/agent_fallback_text.dart';
import 'agent_field.dart';

/// What tapping a component does. Declared by the app's component, never by
/// the model, and never a URL, a path or a deep link: a tap names a
/// destination id, a lookup that either hits or misses. The destination may
/// then open the app's own link, filled from checked arguments.
sealed class AgentTap {
  const AgentTap();

  /// Open one of the app's registered destinations.
  const factory AgentTap.open(String destination, {Map<String, Object?> args}) =
      AgentTapOpen;

  /// Run a read tool, as if the user had asked. [label] is said back as the
  /// user's turn ("West entrance").
  const factory AgentTap.invoke(
    String tool, {
    Map<String, Object?> args,
    String? label,
  }) = AgentTapInvoke;
}

final class AgentTapOpen extends AgentTap {
  const AgentTapOpen(this.destination, {this.args = const {}});

  final String destination;
  final Map<String, Object?> args;

  @override
  String toString() => 'AgentTap.open($destination, $args)';
}

final class AgentTapInvoke extends AgentTap {
  const AgentTapInvoke(this.tool, {this.args = const {}, this.label});

  final String tool;
  final Map<String, Object?> args;
  final String? label;

  @override
  String toString() => 'AgentTap.invoke($tool, $args)';
}

/// Runs a read from a button on a card; [label] is said back as the user's
/// turn.
typedef AgentInvoker =
    void Function(String tool, Map<String, Object?> args, {String? label});

/// What a component builder is handed.
class AgentBuildContext {
  const AgentBuildContext({
    required this.context,
    required this.spec,
    required this.entities,
    required this.languageCode,
    this.onTap,
    this.onInvoke,
    this.resolveTap,
  });

  final BuildContext context;
  final ComponentSpec spec;
  final EntityStore entities;

  /// The app's language right now.
  final String languageCode;

  /// Null when the component has no destination, or its destination failed
  /// its check (unknown, bad arguments, signed out). Pass it to your widget's
  /// own `onTap`: a card that cannot go anywhere then looks inert.
  final VoidCallback? onTap;

  /// For a card with buttons of its own — "Where are you now?" — each of
  /// which runs a read. Null when the host cannot run one.
  final AgentInvoker? onInvoke;

  /// What [tap] does from this card, checked as the card's own tap is: a
  /// tap the component did not declare, or one that may not run now, is
  /// null and leaves its button inert.
  final VoidCallback? Function(AgentTap tap)? resolveTap;

  /// The entity id every card is addressed by.
  String get entityId => spec.stringProp('id') ?? '';
}

/// One component the model may show: what it is told about it, how it
/// draws, and what a tap on it does.
///
/// The description, the schema, the builder, the fallback sentence and the
/// tap all live on one object, so what the model is told, what is validated,
/// what renders and where a tap goes cannot drift apart.
abstract class AgentComponent {
  const AgentComponent();

  /// A card for one entity of [kind], drawn by the app's own widget from the
  /// app's own data.
  ///
  /// The model writes `{"component": type, "id": "<id>"}` and nothing else.
  /// [resolve] finds the entity (by default in the agent's [EntityStore]);
  /// [describe] writes the sentence a screen reader, the voice and a saved
  /// transcript use; [tap] says what a tap does, and [opens] / [invokes] list
  /// every destination and tool it may name, for the audit. [fields] are
  /// what a dashboard card beside this one may show.
  static AgentComponent entity<T>({
    required String type,
    required EntityKind<T> kind,
    required String use,
    required Widget Function(AgentBuildContext ctx, T entity) build,
    required String Function(T entity, String languageCode) describe,
    AgentTap? Function(T entity, String id)? tap,
    T? Function(String id)? resolve,
    Map<String, Object?>? example,
    Set<String> opens = const {},
    Set<String> invokes = const {},
    List<AgentField<T>> fields = const [],
  }) => EntityComponent<T>(
    type: type,
    kind: kind,
    use: use,
    buildEntity: build,
    describeEntity: describe,
    tapEntity: tap,
    resolve: resolve,
    example: example,
    opens: opens,
    invokes: invokes,
    fields: fields,
  );

  /// A component with any props, drawn from [spec] directly — for a card
  /// whose data the app looks up itself. [fields] are what a dashboard card
  /// beside this one may show, and how to find its object by id.
  static AgentComponent custom({
    required ComponentContract contract,
    required Widget Function(AgentBuildContext ctx) build,
    AgentTap? Function(ComponentSpec spec)? tap,
    Set<String> opens = const {},
    Set<String> invokes = const {},
    AgentCardData? fields,
  }) => CustomComponent(
    contract: contract,
    buildWith: build,
    tapWith: tap,
    opens: opens,
    invokes: invokes,
    cardData: fields,
  );

  String get type;

  /// Every destination a tap on this component may open.
  Set<String> get opens;

  /// Every tool its buttons may run.
  Set<String> get invokes;

  /// The fields a dashboard card beside this one may show. Null when it
  /// declares none.
  AgentCardData? get cardData => null;

  /// What the model is told and how props are checked, given the agent's
  /// store.
  ComponentContract contract(EntityStore entities);

  Widget build(AgentBuildContext ctx);

  AgentTap? tapFor(ComponentSpec spec, EntityStore entities);
}

/// See [AgentComponent.custom].
class CustomComponent extends AgentComponent {
  const CustomComponent({
    required ComponentContract contract,
    required this.buildWith,
    this.tapWith,
    this.opens = const {},
    this.invokes = const {},
    this.cardData,
  }) : _contract = contract;

  final ComponentContract _contract;
  final Widget Function(AgentBuildContext ctx) buildWith;
  final AgentTap? Function(ComponentSpec spec)? tapWith;

  @override
  final Set<String> opens;

  @override
  final Set<String> invokes;

  @override
  final AgentCardData? cardData;

  @override
  String get type => _contract.type;

  @override
  ComponentContract contract(EntityStore entities) => _contract;

  @override
  Widget build(AgentBuildContext ctx) => buildWith(ctx);

  @override
  AgentTap? tapFor(ComponentSpec spec, EntityStore entities) =>
      tapWith?.call(spec);
}

/// See [AgentComponent.entity].
class EntityComponent<T> extends AgentComponent {
  const EntityComponent({
    required this.type,
    required this.kind,
    required this.use,
    required this.buildEntity,
    required this.describeEntity,
    this.tapEntity,
    this.resolve,
    this.example,
    this.opens = const {},
    this.invokes = const {},
    this.fields = const [],
  });

  @override
  final String type;
  final EntityKind<T> kind;
  final String use;
  final Widget Function(AgentBuildContext ctx, T entity) buildEntity;
  final String Function(T entity, String languageCode) describeEntity;
  final AgentTap? Function(T entity, String id)? tapEntity;
  final T? Function(String id)? resolve;
  final Map<String, Object?>? example;

  @override
  final Set<String> opens;

  @override
  final Set<String> invokes;

  /// What a dashboard card beside this one may show.
  final List<AgentField<T>> fields;

  @override
  AgentCardData? get cardData =>
      fields.isEmpty ? null : AgentFields<T>.inStore(fields, _find);

  T? _find(String id, EntityStore entities) =>
      resolve != null ? resolve!(id) : entities.get(kind, id);

  @override
  ComponentContract contract(EntityStore entities) => ComponentContract(
    type: type,
    use: use,
    example: example ?? {'component': type, 'id': '<id from the tool>'},
    props: {
      'id': PropSchema.entityId(
        kind.name,
        required: true,
        description: 'The id, copied exactly from the tool result.',
      ),
    },
    describe: (spec, language) {
      final entity = _find(spec.stringProp('id') ?? '', entities);
      return entity == null ? null : describeEntity(entity, language);
    },
  );

  @override
  Widget build(AgentBuildContext ctx) {
    final entity = _find(ctx.entityId, ctx.entities);
    // A resumed conversation: the entity is gone, the saved sentence stays.
    if (entity == null) return AgentFallbackText(ctx.spec.fallbackText);
    return buildEntity(ctx, entity);
  }

  @override
  AgentTap? tapFor(ComponentSpec spec, EntityStore entities) {
    final id = spec.stringProp('id') ?? '';
    final entity = _find(id, entities);
    return entity == null ? null : tapEntity?.call(entity, id);
  }
}
