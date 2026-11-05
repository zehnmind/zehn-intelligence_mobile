import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../core/engine/agent_state.dart';
import '../../core/entities/entity_store.dart';
import '../../core/log.dart';
import '../../core/schema/prop_schema.dart';
import '../../core/tools/tool_registry.dart';
import '../../core/tools/tool_result.dart';
import 'agent_link.dart';

/// Whether opening a destination keeps the chat on screen.
enum DestinationPresentation {
  /// Opens on top of the chat — a sheet, a full-screen page — and closing it
  /// comes straight back to the conversation.
  overChat,

  /// Closes the chat first, then goes there — a tab, a screen in the app's
  /// own navigation.
  leavesChat,
}

/// The reviewer's statement that opening a destination does nothing by
/// itself: no request that changes anything, no camera, no payment.
///
/// "Navigation is never the action." A screen that performs work on arrival
/// — a scanner, a splash that redirects, a checkout — must not be a
/// destination: a model could then trigger that work by choosing where the
/// user lands. The audit fails a destination without this statement.
class ArrivalReview {
  const ArrivalReview.inert(this.note);

  /// What the screen does when it opens, e.g. "shows the account; reads its
  /// transactions only".
  final String note;
}

/// What a destination is opened with.
class DestinationRequest {
  const DestinationRequest({
    required this.args,
    required this.state,
    required this.postNote,
    this.entities,
    this.openLink = AgentLinks.deliver,
  });

  /// Already validated against the destination's schema.
  final Map<String, Object?> args;
  final AgentState state;

  /// Records in the conversation something the user did on the opened screen
  /// — "Reserved in the app" — with the tool's own copy and cards, so a
  /// follow-up like "cancel it" has something to refer to.
  final void Function(ToolResult result) postNote;

  /// What this conversation fetched, to look an id up in.
  final EntityStore? entities;

  /// Opens the app's own links: `ZehnIntelligence.start(openLink: …)`, else
  /// [AgentLinks.deliver].
  final AgentLinkOpener openLink;

  String? string(String key) {
    final value = args[key];
    return value is String && value.isNotEmpty ? value : null;
  }
}

typedef DestinationOpener =
    FutureOr<void> Function(BuildContext context, DestinationRequest request);

/// A screen or sheet a component may open when tapped.
///
/// Only the app declares destinations, and only its components open them —
/// the model never names one. Arguments are checked against [args] like any
/// tool's.
///
/// A destination opens one of two ways: by running the app's own code
/// ([open]), or by the app's own link ([AgentDestination.link]).
class AgentDestination {
  const AgentDestination({
    required this.id,
    required this.description,
    required this.arrival,
    required this.open,
    this.args = const {},
    this.requiresSignIn = false,
    this.presentation = DestinationPresentation.overChat,
  }) : link = null;

  /// A screen the app reaches by its own link — a path in the app with
  /// `{name}` slots its [args] fill:
  ///
  /// ```dart
  /// AgentDestination.link(
  ///   id: 'page.order',
  ///   link: '/orders/{id}',
  ///   args: {'id': PropSchema.entityId('order', required: true)},
  ///   description: 'The order',
  ///   arrival: ArrivalReview.inert('Shows the order; reads only.'),
  /// )
  /// ```
  ///
  /// The link opens the way `ZehnIntelligence.start(openLink: …)` says — by
  /// default as the phone delivers a deep link. It leaves the chat by
  /// default, since a router may rebuild the screens under it; keep it
  /// [DestinationPresentation.overChat] when the opener pushes (named
  /// routes do; for go_router use `AgentLinks.goOrPush`).
  factory AgentDestination.link({
    required String id,
    required String description,
    required ArrivalReview arrival,
    required String link,
    Map<String, PropSchema> args = const {},
    bool requiresSignIn = false,
    DestinationPresentation presentation = DestinationPresentation.leavesChat,
  }) {
    final template = AgentLink(link);
    final overChat = presentation == DestinationPresentation.overChat;
    return AgentDestination._(
      id: id,
      description: description,
      arrival: arrival,
      args: args,
      requiresSignIn: requiresSignIn,
      presentation: presentation,
      link: template,
      open: (context, request) {
        final uri = template.fill(request.args);
        if (uri == null) return null;
        return request.openLink(context, uri, overChat: overChat);
      },
    );
  }

  const AgentDestination._({
    required this.id,
    required this.description,
    required this.arrival,
    required this.open,
    required this.args,
    required this.requiresSignIn,
    required this.presentation,
    required this.link,
  });

  /// Stable id a component names, e.g. `sheet.card` or `tab.transfers`.
  final String id;

  /// What the user sees there — for the capabilities document.
  final String description;
  final ArrivalReview arrival;
  final DestinationOpener open;
  final Map<String, PropSchema> args;

  /// The app's link this destination opens, when it opens by link.
  final AgentLink? link;

  /// When true, a tap is inert for a signed-out user.
  final bool requiresSignIn;
  final DestinationPresentation presentation;

  bool get leavesChat => presentation == DestinationPresentation.leavesChat;

  /// What is wrong with this declaration.
  List<String> problems() => [
    if (id.trim().isEmpty) 'has no id',
    if (arrival.note.trim().isEmpty)
      'has no arrival review — say what the screen does when it opens',
    for (final MapEntry(key: arg, value: schema) in args.entries)
      for (final problem in schema.problems()) 'argument "$arg" $problem',
    ...?link?.problems(args),
  ];

  /// Why [args] cannot open this destination for [state], or null.
  String? refuse(
    Map<String, Object?> args,
    AgentState state, {
    AgentAllowlists? allowlists,
  }) {
    if (requiresSignIn && !state.isSignedIn) return 'needs sign-in';
    final validation = SchemaValidation.run(
      this.args,
      args,
      allowlists: allowlists,
    );
    if (!validation.isValid) return validation.summary;
    final link = this.link;
    if (link != null && link.fill(args) == null) {
      return 'cannot fill its link $link';
    }
    return null;
  }
}

/// The destinations the app has declared, as it has them right now.
class AgentDestinationRegistry {
  AgentDestinationRegistry({this.log = silentAgentLog});

  final AgentLog log;
  final Map<String, AgentDestination> _destinations = {};

  void add(AgentDestination destination) {
    final problems = destination.problems();
    if (problems.isNotEmpty) {
      throw AgentRegistrationError('${destination.id}: ${problems.join('; ')}');
    }
    if (_destinations.containsKey(destination.id)) {
      throw AgentRegistrationError('${destination.id} is already registered');
    }
    _destinations[destination.id] = destination;
  }

  bool remove(String id) => _destinations.remove(id) != null;

  AgentDestination? operator [](String id) => _destinations[id];

  Iterable<AgentDestination> get all => _destinations.values;
}
