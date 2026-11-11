import 'dart:async';
import 'dart:convert';

import '../../ui/zehn_integrator.dart' show ZiArg, ZiToolError;
import '../api/turn_client.dart';
import '../api/turn_events.dart';
import 'http_call.dart';
import 'proxy_executor.dart';

/// An in-app tool handler (`ZehnIntelligence.registerTool`).
typedef ZiToolHandler = Future<Map<String, Object?>> Function(Map<String, Object?> args);

/// Runs one round of tool calls, all at once: an in-app handler if the app
/// registered one, else the request the server built (the event's `request`)
/// through the proxy, else `handler_not_registered`. A handler whose tool
/// declared its arguments ([args]) runs only for a call that fits them;
/// another is `invalid_args`.
///
/// A write (any method but `GET`) is made only for an action the user
/// confirmed in the chat ([takeConfirmed]), once; otherwise it is
/// `not_confirmed` and nothing is sent.
///
/// How long a call may take and how big its result may be come from the
/// turn's pause (`turn.paused`: `expires_in − 5 s` and `max_result_bytes`);
/// [timeout] and [maxResultBytes] are for a round that says neither.
class ZiToolRunner {
  ZiToolRunner({
    required Map<String, ZiToolHandler> handlers,
    required ZiProxyExecutor proxy,
    Map<String, Map<String, ZiArg>> args = const {},
    this.timeout = const Duration(seconds: 20),
    this.maxResultBytes = 32768,
  }) : _handlers = handlers,
       _args = args,
       _proxy = proxy;

  final Map<String, ZiToolHandler> _handlers;

  /// What each registered tool declared of its arguments, by tool name.
  final Map<String, Map<String, ZiArg>> _args;
  final ZiProxyExecutor _proxy;
  final Duration timeout;
  final int maxResultBytes;

  /// True, once, for an action the user tapped Confirm on; set by the chat.
  /// Without it no write is made.
  bool Function(String actionId)? takeConfirmed;

  /// What is left of the pause's `expires_in` for the calls to finish: the
  /// server waits that long for the results, and the post itself needs a
  /// few seconds.
  static const resultsGrace = Duration(seconds: 5);

  /// Results in the order of [calls]. [expiresIn] and [maxResultBytes] are
  /// the pause's (`turn.paused`): each call gets `expiresIn − 5 s` (at least
  /// one second), and a result over [maxResultBytes] is `result_too_large`.
  Future<List<ToolCallResult>> runAll(
    List<ClientApiRequest> calls, {
    Duration? expiresIn,
    int? maxResultBytes,
  }) {
    final limit = expiresIn == null ? timeout : _within(expiresIn);
    final most = maxResultBytes ?? this.maxResultBytes;
    return Future.wait([for (final c in calls) _run(c, limit, most)]);
  }

  static Duration _within(Duration expiresIn) {
    final left = expiresIn - resultsGrace;
    return left < const Duration(seconds: 1) ? const Duration(seconds: 1) : left;
  }

  Future<ToolCallResult> _run(ClientApiRequest call, Duration limit, int maxResultBytes) async {
    try {
      final handler = _handlers[call.tool];
      final raw = call.request;
      if (handler == null && raw == null) {
        throw ZiToolError('handler_not_registered', 'This app has no tool ${call.tool}.');
      }
      final Future<Object?> work;
      if (handler != null) {
        _check(call);
        work = handler(call.args);
      } else {
        final http = ZiHttpCall.fromJson(raw);
        if (http.isWrite && !_confirmed(call.actionId)) {
          throw const ZiToolError('not_confirmed', 'The user has not confirmed this action.');
        }
        work = _proxy.call(http, timeout: limit);
      }
      final data = await work.timeout(limit);
      final size = utf8.encode(jsonEncode(data)).length;
      if (size > maxResultBytes) {
        return ToolCallResult.error(call.callId, 'result_too_large', 'The result is $size bytes; the limit is $maxResultBytes.');
      }
      return ToolCallResult.ok(call.callId, data);
    } on TimeoutException {
      return ToolCallResult.error(call.callId, 'timeout', 'The tool did not finish in ${limit.inSeconds} s.');
    } on ZiToolError catch (e) {
      return ToolCallResult.error(call.callId, e.code, e.message);
    } on Object catch (e) {
      return ToolCallResult.error(call.callId, 'handler_failed', 'The tool failed: ${e.runtimeType}.');
    }
  }

  /// Throws `invalid_args` for the first declared argument [call] breaks.
  void _check(ClientApiRequest call) {
    final declared = _args[call.tool];
    if (declared == null) return;
    for (final MapEntry(key: name, value: arg) in declared.entries) {
      final problem = arg.problem(name, call.args[name]);
      if (problem != null) throw ZiToolError('invalid_args', problem);
    }
  }

  bool _confirmed(String? actionId) {
    final take = takeConfirmed;
    return actionId != null && take != null && take(actionId);
  }
}
