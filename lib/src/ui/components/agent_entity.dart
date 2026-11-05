import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../core/entities/entity_store.dart';
import '../../core/schema/prop_schema.dart';
import '../../core/text/default_copy.dart';
import '../../core/text/localized_text.dart';
import '../../core/tools/agent_tool.dart';
import '../../core/tools/tool_result.dart';
import '../destinations/agent_destination.dart';
import 'agent_component.dart';
import 'agent_field.dart';
import 'agent_pack.dart';

/// How tapping an entity's card opens the app's own screen for it: by
/// running the app's code, or by the app's own link.
class AgentOpen<T> {
  /// [open] is what the app already calls to show the entity — a sheet, a
  /// page. [arrival] says what that screen does when it opens: nothing but
  /// show it ("Shows the order; reads only."). A screen that pays, scans or
  /// sends on arrival must not be opened from a card.
  const AgentOpen(
    FutureOr<void> Function(BuildContext context, T entity) this.open, {
    required this.arrival,
    this.description,
    this.requiresSignIn = false,
    this.presentation = DestinationPresentation.overChat,
  }) : link = null;

  /// Opens the entity's screen by the app's own link; `{id}` is the
  /// entity's id: `AgentOpen.link('/orders/{id}', arrival: 'Shows the
  /// order; reads only.')`. See `AgentDestination.link` for the rules and
  /// why it leaves the chat by default.
  const AgentOpen.link(
    String this.link, {
    required this.arrival,
    this.description,
    this.requiresSignIn = false,
    this.presentation = DestinationPresentation.leavesChat,
  }) : open = null;

  /// The app's code that shows the entity, when it opens by code.
  final FutureOr<void> Function(BuildContext context, T entity)? open;

  /// The app's link to the entity's screen, when it opens by link.
  final String? link;
  final String arrival;

  /// What the screen shows, for the capabilities document.
  final String? description;
  final bool requiresSignIn;

  /// Over the chat (a sheet, a page — closing it returns to the chat), or
  /// leaving it (a tab).
  final DestinationPresentation presentation;
}

/// One kind of thing the app shows — an order, a card, a branch — declared
/// once: its id, its card (the app's own widget), the sentence it is read
/// aloud as, and the screen a tap opens. Its tools, card and screen come
/// from this one declaration:
///
/// ```dart
/// final orders = AgentEntity<Order>(
///   name: 'order',
///   id: (order) => order.id,
///   card: (context, order, onTap) => OrderTile(order: order, onTap: onTap),
///   describe: (order, language) => 'Order ${order.number}: ${order.status.name}',
///   open: AgentOpen((context, order) => showOrderSheet(context, order),
///       arrival: 'Shows the order; reads only.'),
/// );
///
/// final ordersPack = orders.pack(id: 'orders', tools: [
///   orders.list(
///     name: 'orders.list',
///     description: "The user's recent orders.",
///     requiresSignIn: true,
///     load: (call) => repository.recent(),
///     examples: {'en': ['Where is my order?'], 'uz': ['Buyurtmam qayerda?']},
///   ),
/// ]);
/// ```
class AgentEntity<T> {
  AgentEntity({
    required this.name,
    required this.id,
    required this.card,
    required this.describe,
    this.use,
    this.lookup,
    this.known,
    this.open,
    this.fields = const [],
  }) : kind = EntityKind<T>(name);

  /// Lowercase, e.g. `order`. Names the card (`order_card`), the ids it
  /// accepts, and the screen it opens (`open.order`).
  final String name;
  final String Function(T entity) id;

  /// The app's own widget. Pass [onTap] to its own tap handler: it is null
  /// when the tap would be refused, so the card looks inert.
  final Widget Function(BuildContext context, T entity, VoidCallback? onTap)
  card;

  /// The card as a sentence, in [languageCode]: what a screen reader, the
  /// voice and a saved chat use.
  final String Function(T entity, String languageCode) describe;

  /// When the model should show the card. Defaults to "One order." for the
  /// name `order`.
  final String? use;

  /// The app's current copy of an entity, so cards always show it as it is
  /// now. Without it, cards show what the tool loaded.
  final T? Function(String id)? lookup;

  /// Ids the app keeps current itself — the user's cards, their bookings —
  /// so the model can name one without listing first. Return nothing when
  /// the user is signed out.
  final Iterable<String> Function()? known;

  final AgentOpen<T>? open;

  /// What a dashboard card beside this one may show: named, typed getters
  /// over the entity. Only these can ever appear on such a card.
  final List<AgentField<T>> fields;

  final EntityKind<T> kind;

  String get cardType => '${name}_card';

  String get destinationId => 'open.$name';

  /// The card, as the model may show it.
  AgentComponent get component => AgentComponent.entity<T>(
    type: cardType,
    kind: kind,
    use: use ?? 'One $name.',
    resolve: lookup,
    build: (ctx, entity) => card(ctx.context, entity, ctx.onTap),
    describe: describe,
    tap: open == null
        ? null
        : (_, entityId) => AgentTap.open(destinationId, args: {'id': entityId}),
    opens: {if (open != null) destinationId},
    fields: fields,
  );

  /// The screen a tap on the card opens, when there is one.
  AgentDestination? get destination {
    final open = this.open;
    if (open == null) return null;
    final description = open.description ?? "The $name's own screen";
    final arrival = ArrivalReview.inert(open.arrival);
    final args = {
      'id': PropSchema.entityId(
        name,
        required: true,
        description: 'The $name.',
      ),
    };
    final link = open.link;
    if (link != null) {
      return AgentDestination.link(
        id: destinationId,
        description: description,
        arrival: arrival,
        link: link,
        args: args,
        requiresSignIn: open.requiresSignIn,
        presentation: open.presentation,
      );
    }
    final show = open.open!;
    return AgentDestination(
      id: destinationId,
      description: description,
      arrival: arrival,
      requiresSignIn: open.requiresSignIn,
      presentation: open.presentation,
      args: args,
      open: (context, request) {
        final key = request.string('id');
        if (key == null) return null;
        final entity = lookup?.call(key) ?? request.entities?.get(kind, key);
        return entity == null ? null : show(context, entity);
      },
    );
  }

  /// A read that loads entities and shows each as its card: "my orders",
  /// "branches open now". [facts] are what the model may say about each
  /// (never a full card number); [examples] are questions users ask, per
  /// language.
  AgentTool list({
    required String name,
    required String description,
    required Future<Iterable<T>> Function(ToolCall call) load,
    Map<String, PropSchema> args = const {},
    bool requiresSignIn = false,
    ToolAvailability? availableWhen,
    Map<String, Object?> Function(T entity, String languageCode)? facts,
    int max = 10,
    LocalizedText? found,
    LocalizedText? empty,
    Map<String, List<String>> examples = const {},
    String? source,
    String? decideNotes,
    String? renderNotes,
  }) => AgentTool(
    name: name,
    description: description,
    kind: ToolKind.read,
    args: args,
    requiresSignIn: requiresSignIn,
    availableWhen: availableWhen,
    decideNotes: decideNotes,
    renderNotes: renderNotes,
    run: (call) async {
      final all = (await load(call)).toList();
      final shown = all.take(max).toList();
      call.entities.rememberAll(kind, shown, id);
      return ToolResult.items(
        call.tool,
        'Found ${all.length} of kind "${this.name}".',
        items: [
          for (final entity in shown)
            ToolItem(
              cardType,
              id(entity),
              facts: facts?.call(entity, call.language) ?? const {},
            ),
        ],
        data: {
          if (all.length > shown.length)
            'note': 'Only the first ${shown.length} are shown as cards.',
        },
      );
    },
    fallback: ToolFallback(
      found: found ?? AgentDefaultCopy.found,
      empty: empty ?? AgentDefaultCopy.empty,
    ),
    doc: ToolDoc(
      summary: description,
      source: source,
      examples: examples,
      returns: '`$cardType` for each ${this.name}',
    ),
  );

  /// The entity's card and screen, with [tools] — and any writes, other
  /// cards or screens that belong with them.
  AgentPack pack({
    required String id,
    List<AgentTool> tools = const [],
    List<AgentComponent> components = const [],
    List<AgentDestination> destinations = const [],
  }) {
    final screen = destination;
    final ids = known;
    return AgentPack(
      id: id,
      tools: tools,
      components: [component, ...components],
      destinations: [?screen, ...destinations],
      allowlists: [if (ids != null) LiveAllowlist(name, ids)],
    );
  }
}
