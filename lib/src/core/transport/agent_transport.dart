import '../protocol/turn.dart';
import '../tools/tool_result.dart';

/// The seam between the app and whatever is doing the planning.
///
/// Two calls, both plain data in and plain data out, so a real gateway drops
/// in without touching anything above this interface: `decide` is the
/// tool-use turn, `render` is the final turn. Note that the transport never
/// executes anything — the engine validates, gates and runs tools, so a
/// compromised or buggy planner cannot skip a confirmation.
abstract interface class AgentTransport {
  Future<AgentDecision> decide(AgentTurnRequest request);

  Future<AgentReply> render(AgentTurnRequest request, ToolResult? result);
}

/// Thrown when the model could not be reached or answered with an error.
///
/// Distinct from a well-formed reply that simply proposes no tool: the chat
/// shows a failure for this, and a plain answer for that.
class AgentTransportException implements Exception {
  const AgentTransportException(this.message);

  final String message;

  @override
  String toString() => 'AgentTransportException: $message';
}
