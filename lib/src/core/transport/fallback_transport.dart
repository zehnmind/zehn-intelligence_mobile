import '../log.dart';
import '../protocol/turn.dart';
import '../tools/tool_result.dart';
import 'agent_transport.dart';

/// Tries each transport in turn until one answers: a primary model, then a
/// second provider, then an offline rule set.
///
/// Only a failure to answer moves on — an exception, a timeout. A model that
/// answers badly is the engine's business, not this class's. Each turn starts
/// again from the first transport.
class FallbackTransport implements AgentTransport {
  FallbackTransport(this.transports, {this.log = silentAgentLog})
    : assert(transports.isNotEmpty, 'at least one transport');

  final List<AgentTransport> transports;
  final AgentLog log;

  @override
  Future<AgentDecision> decide(AgentTurnRequest request) =>
      _first((transport) => transport.decide(request));

  @override
  Future<AgentReply> render(AgentTurnRequest request, ToolResult? result) =>
      _first((transport) => transport.render(request, result));

  Future<T> _first<T>(Future<T> Function(AgentTransport transport) call) async {
    Object? lastError;
    StackTrace? lastStack;
    for (final transport in transports) {
      try {
        return await call(transport);
      } catch (e, stack) {
        log('fallback: ${transport.runtimeType} failed ($e); trying the next');
        lastError = e;
        lastStack = stack;
      }
    }
    Error.throwWithStackTrace(lastError!, lastStack!);
  }
}
