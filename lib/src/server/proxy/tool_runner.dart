import 'dart:async';
import 'dart:convert';

import '../../ui/zehn_integrator.dart' show ZiToolError;
import '../api/turn_client.dart';
import '../api/turn_events.dart';
import 'http_call.dart';
import 'proxy_executor.dart';

/// An in-app tool handler (`ZehnIntelligence.registerTool`).
typedef ZiToolHandler = Future<Map<String, Object?>> Function(Map<String, Object?> args);

/// A data-changing call waiting for the user's yes or no.
class ZiConfirmRequest {
  const ZiConfirmRequest({required this.callId, required this.tool, required this.title, required this.args});

  final String callId;
  final String tool;

  /// The server's question, already in the user's language; null when it
  /// gave none (the chat uses its own words).
  final String? title;
  final Map<String, Object?> args;
}

/// Asks the user; true when they allow the call.
typedef ZiConfirmer = Future<bool> Function(ZiConfirmRequest request);

/// Runs one round of tool calls, all at once: an in-app handler if the app
/// registered one, else the request the server built (the event's `http`)
/// through the proxy, else `handler_not_registered`.
class ZiToolRunner {
  ZiToolRunner({
    required Map<String, ZiToolHandler> handlers,
    required ZiProxyExecutor proxy,
    this.timeout = const Duration(seconds: 20),
    this.maxResultBytes = 32768,
    this.confirmMargin = const Duration(seconds: 5),
  }) : _handlers = handlers,
       _proxy = proxy;

  final Map<String, ZiToolHandler> _handlers;
  final ZiProxyExecutor _proxy;
  final Duration timeout;
  final int maxResultBytes;

  /// How long before the round's deadline an unanswered question counts as
  /// "no", so the results still reach the server in time.
  final Duration confirmMargin;

  /// Asks the user before a data-changing call; set by the chat. Without
  /// one, such calls are declined.
  ZiConfirmer? confirmer;

  /// Results in the order of [calls]. [deadline] is the round's, from
  /// `turn.paused`: a question still open near it counts as declined.
  Future<List<ToolCallResult>> runAll(List<ClientApiRequest> calls, {DateTime? deadline}) =>
      Future.wait([for (final c in calls) _run(c, deadline)]);

  Future<ToolCallResult> _run(ClientApiRequest call, DateTime? deadline) async {
    try {
      final handler = _handlers[call.tool];
      final rawHttp = call.http;
      if (handler == null && rawHttp == null) {
        throw ZiToolError('handler_not_registered', 'This app has no tool ${call.tool}.');
      }
      final http = handler == null ? ZiHttpCall.fromJson(rawHttp) : null;
      // The wait for the user is not part of the tool's own time limit.
      if (http != null && http.confirm && !await _allowed(call, http, deadline)) {
        return ToolCallResult.error(call.callId, 'user_declined', 'The user did not allow this action.');
      }
      final data = await (handler != null ? handler(call.args) : _proxy.call(http!)).timeout(timeout);
      final size = utf8.encode(jsonEncode(data)).length;
      if (size > maxResultBytes) {
        return ToolCallResult.error(call.callId, 'result_too_large', 'The result is $size bytes; the limit is $maxResultBytes.');
      }
      return ToolCallResult.ok(call.callId, data);
    } on TimeoutException {
      return ToolCallResult.error(call.callId, 'timeout', 'The tool did not finish in ${timeout.inSeconds} s.');
    } on ZiToolError catch (e) {
      return ToolCallResult.error(call.callId, e.code, e.message);
    } on Object catch (e) {
      return ToolCallResult.error(call.callId, 'handler_failed', 'The tool failed: ${e.runtimeType}.');
    }
  }

  /// The user's answer to a call the server marked `confirm`.
  Future<bool> _allowed(ClientApiRequest call, ZiHttpCall http, DateTime? deadline) async {
    final ask = confirmer;
    if (ask == null) return false;
    var answer = ask(ZiConfirmRequest(callId: call.callId, tool: call.tool, title: http.confirmTitle, args: call.args));
    if (deadline != null) {
      final left = deadline.difference(DateTime.now()) - confirmMargin;
      answer = answer.timeout(left.isNegative ? Duration.zero : left, onTimeout: () => false);
    }
    return answer;
  }
}
