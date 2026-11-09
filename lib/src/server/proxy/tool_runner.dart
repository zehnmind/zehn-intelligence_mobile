import 'dart:async';
import 'dart:convert';

import '../../ui/zehn_integrator.dart' show ZiToolError;
import '../api/turn_client.dart';
import '../api/turn_events.dart';
import '../bootstrap/bootstrap_repository.dart';
import 'proxy_executor.dart';
import 'request_builder.dart';

/// An in-app tool handler (`ZehnIntelligence.registerTool`).
typedef ZiToolHandler = Future<Map<String, Object?>> Function(Map<String, Object?> args);

/// Runs one round of tool calls, all at once: an in-app handler if the app
/// registered one, else the console's HTTP tool through the proxy, else
/// `handler_not_registered`.
class ZiToolRunner {
  ZiToolRunner({
    required Map<String, ZiToolHandler> handlers,
    required ZiProxyExecutor proxy,
    required ZiBootstrapRepository bootstrap,
    required ZiRequestContext Function() context,
    this.timeout = const Duration(seconds: 20),
    this.maxResultBytes = 32768,
    this.refreshTimeout = const Duration(seconds: 5),
  }) : _handlers = handlers,
       _proxy = proxy,
       _bootstrap = bootstrap,
       _context = context;

  final Map<String, ZiToolHandler> _handlers;
  final ZiProxyExecutor _proxy;
  final ZiBootstrapRepository _bootstrap;
  final ZiRequestContext Function() _context;
  final Duration timeout;
  final int maxResultBytes;

  /// How long a round may wait for fresh start-up data; the server's
  /// deadline for the whole round is 60 s.
  final Duration refreshTimeout;

  /// Results in the order of [calls].
  Future<List<ToolCallResult>> runAll(List<ClientApiRequest> calls) async {
    final missing = calls.any((c) => !_handlers.containsKey(c.tool) && _bootstrap.current?.tools[c.tool] == null);
    if (missing) await _bootstrap.refresh().timeout(refreshTimeout, onTimeout: () => _bootstrap.current);
    return Future.wait([for (final c in calls) _run(c)]);
  }

  Future<ToolCallResult> _run(ClientApiRequest call) async {
    try {
      final data = await _data(call).timeout(timeout);
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

  Future<Object?> _data(ClientApiRequest call) {
    final handler = _handlers[call.tool];
    if (handler != null) return handler(call.args);
    final boot = _bootstrap.current;
    final tool = boot?.tools[call.tool];
    if (boot == null || tool == null) {
      throw ZiToolError('handler_not_registered', 'This app has no tool ${call.tool}.');
    }
    return _proxy.call(tool, call.args, boot, _context());
  }
}
