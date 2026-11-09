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

/// A data-changing call waiting for the user's yes or no.
class ZiConfirmRequest {
  const ZiConfirmRequest({required this.callId, required this.tool, required this.title, required this.args});

  final String callId;
  final String tool;

  /// The console's question in the user's language, placeholders filled;
  /// null when the console gave none (the chat uses its own words).
  final String? title;
  final Map<String, Object?> args;
}

/// Asks the user; true when they allow the call.
typedef ZiConfirmer = Future<bool> Function(ZiConfirmRequest request);

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
    this.confirmMargin = const Duration(seconds: 5),
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

  /// How long before the round's deadline an unanswered question counts as
  /// "no", so the results still reach the server in time.
  final Duration confirmMargin;

  /// Asks the user before a data-changing call; set by the chat. Without
  /// one, such calls are declined.
  ZiConfirmer? confirmer;

  /// Results in the order of [calls]. [deadline] is the round's, from
  /// `turn.paused`: a question still open near it counts as declined.
  Future<List<ToolCallResult>> runAll(List<ClientApiRequest> calls, {DateTime? deadline}) async {
    final missing = calls.any((c) => !_handlers.containsKey(c.tool) && _bootstrap.current?.tools[c.tool] == null);
    if (missing) await _bootstrap.refresh().timeout(refreshTimeout, onTimeout: () => _bootstrap.current);
    return Future.wait([for (final c in calls) _run(c, deadline)]);
  }

  Future<ToolCallResult> _run(ClientApiRequest call, DateTime? deadline) async {
    try {
      // The wait for the user is not part of the tool's own time limit.
      if (!await _allowed(call, deadline)) {
        return ToolCallResult.error(call.callId, 'user_declined', 'The user did not allow this action.');
      }
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

  /// True for reads and in-app handlers; for a write, the user's answer.
  Future<bool> _allowed(ClientApiRequest call, DateTime? deadline) async {
    if (_handlers.containsKey(call.tool)) return true;
    final tool = _bootstrap.current?.tools[call.tool];
    if (tool == null || !tool.confirm) return true;
    final ask = confirmer;
    if (ask == null) return false;
    final language = _context().language;
    final template = tool.confirmTitle[language] ?? tool.confirmTitle['en'] ?? tool.confirmTitle.values.firstOrNull;
    final title = template?.replaceAllMapped(RegExp(r'\{(\w+)\}'), (m) => '${call.args[m[1]] ?? ''}');
    var answer = ask(ZiConfirmRequest(callId: call.callId, tool: call.tool, title: title, args: call.args));
    if (deadline != null) {
      final left = deadline.difference(DateTime.now()) - confirmMargin;
      answer = answer.timeout(left.isNegative ? Duration.zero : left, onTimeout: () => false);
    }
    return answer;
  }
}
