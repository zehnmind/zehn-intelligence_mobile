import '../../core/schema/prop_schema.dart';
import '../../core/tools/agent_tool.dart';
import '../destinations/agent_destination.dart';
import 'agent_component.dart';

/// One capability, installed or removed as a unit: its tools, the cards that
/// show their results, the screens those cards open, and any id lists the
/// app keeps itself.
///
/// A pack is how an app stays organised as it grows — "accounts", "cards",
/// "branches" — and how a capability is switched on or off at run time,
/// behind a feature flag or a subscription.
class AgentPack {
  const AgentPack({
    required this.id,
    this.tools = const [],
    this.components = const [],
    this.destinations = const [],
    this.allowlists = const [],
  });

  final String id;
  final List<AgentTool> tools;
  final List<AgentComponent> components;
  final List<AgentDestination> destinations;

  /// Id lists the app keeps itself — reservations in its own state, a
  /// catalogue loaded at start-up — joined to the agent's own.
  final List<AgentAllowlists> allowlists;
}
