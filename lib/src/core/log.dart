/// Where the agent writes its diagnostics — which tool ran, why a proposal was
/// refused, which transport was picked.
///
/// Never handed a request, a header or a key: callers log decisions, not
/// payloads, so pointing this at a crash reporter is safe.
typedef AgentLog = void Function(String message);

/// The default: says nothing.
void silentAgentLog(String message) {}
