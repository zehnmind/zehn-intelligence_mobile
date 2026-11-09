import 'dart:async';
import 'dart:convert';

import '../../ui/zehn_integrator.dart' show ZiToolError;
import '../api/turn_client.dart';
import '../api/turn_events.dart';
import 'http_call.dart';
import 'proxy_executor.dart';

/// An in-app tool handler (`ZehnIntelligence.registerTool`).
typedef ZiToolHandler = Future<Map<String, Object?>> Function(Map<String, Object?> args);

/// Runs one round of tool calls, all at once: an in-app handler if the app
/// registered one, else the request the server built (the event's `request`)
/// through the proxy, else `handler_not_registered`.
///
/// A write (any method but `GET`) is made only for an action the user
/// confirmed in the chat ([takeConfirmed]), once; otherwise it is
/// `not_confirmed` and nothing is sent.
class ZiToolRunner {
  ZiToolRunner({
    required Map<String, ZiToolHandler> handlers,
    required ZiProxyExecutor proxy,
    this.timeout = const Duration(seconds: 20),
    this.maxResultBytes = 32768,
  }) : _handlers = handlers,
       _proxy = proxy;

  final Map<String, ZiToolHandler> _handlers;
  final ZiProxyExecutor _proxy;
  final Duration timeout;
  final int maxResultBytes;

  /// True, once, for an action the user tapped Confirm on; set by the chat.
  /// Without it no write is made.
  bool Function(String actionId)? takeConfirmed;

  /// Results in the order of [calls].
  Future<List<ToolCallResult>> runAll(List<ClientApiRequest> calls) => Future.wait([for (final c in calls) _run(c)]);

  Future<ToolCallResult> _run(ClientApiRequest call) async {
    try {
      final handler = _handlers[call.tool];
      final raw = call.request;
      if (handler == null && raw == null) {
        throw ZiToolError('handler_not_registered', 'This app has no tool ${call.tool}.');
      }
      final Future<Object?> work;
      if (handler != null) {
        work = handler(call.args);
      } else {
        final http = ZiHttpCall.fromJson(raw);
        if (http.isWrite && !_confirmed(call.actionId)) {
          throw const ZiToolError('not_confirmed', 'The user has not confirmed this action.');
        }
        work = _proxy.call(http);
      }
      final data = await work.timeout(timeout);
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

  bool _confirmed(String? actionId) {
    final take = takeConfirmed;
    return actionId != null && take != null && take(actionId);
  }
}
