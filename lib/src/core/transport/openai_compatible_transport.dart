import 'dart:convert';

import 'package:dio/dio.dart';

import '../log.dart';
import '../model/component_spec.dart';
import '../protocol/agent_json.dart';
import '../protocol/turn.dart';
import '../tools/tool_result.dart';
import 'agent_transport.dart';
import 'zehn.dart';

/// Plans and renders a turn against any OpenAI-compatible chat endpoint —
/// the Zehn gateway, OpenRouter, OpenAI, a vLLM server, or your own backend
/// proxy.
///
/// As with every transport, it only ever *proposes*: the engine validates
/// each proposal against the registry and owns the confirmation gate, so a
/// wrong, malformed or hostile reply is rejected rather than run.
///
/// SECURITY, two points:
///
/// 1. Its own bare [Dio], never the app's. An app's Dio usually attaches the
///    user's `Authorization: Bearer` header to every request, and this class
///    sets that header to the model key — sharing one client would leak one
///    or the other to the wrong server.
/// 2. A key compiled into an app can be extracted from it. For real users,
///    point [baseUrl] at a backend that holds the key and pass an empty
///    `apiKey`; no `Authorization` header is then sent.
class OpenAiCompatibleTransport implements AgentTransport {
  OpenAiCompatibleTransport({
    required String baseUrl,
    required String apiKey,
    this.model,
    Map<String, String> extraHeaders = const {},
    bool jsonMode = true,
    Dio? httpClient,
    HttpClientAdapter? httpClientAdapter,
    this.label = 'llm',
    this.temperature = 0.2,
    this.decideMaxTokens = 700,
    this.renderMaxTokens = 900,
    Duration connectTimeout = const Duration(seconds: 20),
    Duration receiveTimeout = const Duration(seconds: 90),
    this.log = silentAgentLog,
  }) : _jsonMode = jsonMode,
       _dio =
           httpClient ??
           _bareDio(
             baseUrl: baseUrl,
             apiKey: apiKey,
             extraHeaders: extraHeaders,
             connectTimeout: connectTimeout,
             receiveTimeout: receiveTimeout,
             adapter: httpClientAdapter,
           );

  /// The Zehn gateway.
  factory OpenAiCompatibleTransport.zehn({
    required String apiKey,
    String? model,
    String baseUrl = Zehn.baseUrl,
    Dio? httpClient,
    HttpClientAdapter? httpClientAdapter,
    AgentLog log = silentAgentLog,
  }) => OpenAiCompatibleTransport(
    baseUrl: baseUrl,
    apiKey: apiKey,
    model: model,
    httpClient: httpClient,
    httpClientAdapter: httpClientAdapter,
    label: 'zehn',
    log: log,
  );

  /// A client of its own, carrying only the model key — never the app's
  /// client, whose headers carry the user's token.
  static Dio _bareDio({
    required String baseUrl,
    required String apiKey,
    required Map<String, String> extraHeaders,
    required Duration connectTimeout,
    required Duration receiveTimeout,
    HttpClientAdapter? adapter,
  }) {
    final dio = Dio(
      BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: connectTimeout,
        // A large model on a shared GPU can be slow to first token.
        receiveTimeout: receiveTimeout,
        headers: {
          'Content-Type': 'application/json',
          if (apiKey.trim().isNotEmpty) 'Authorization': 'Bearer $apiKey',
          ...extraHeaders,
        },
      ),
    );
    if (adapter != null) dio.httpClientAdapter = adapter;
    return dio;
  }

  final String? model;
  final double temperature;
  final int decideMaxTokens;
  final int renderMaxTokens;
  final Dio _dio;

  /// Log prefix, e.g. `zehn` or `openrouter`.
  final String label;
  final AgentLog log;

  /// Whether to ask the server for guaranteed-JSON output. Switched off for
  /// the rest of the session the first time a server rejects it.
  bool _jsonMode;

  // ── decide ────────────────────────────────────────────────────────────────

  @override
  Future<AgentDecision> decide(AgentTurnRequest request) async {
    final content = await _complete([
      ..._history(request),
      _message('user', request.userText),
    ], maxTokens: decideMaxTokens);

    return parseDecision(content, languages: request.languages);
  }

  /// Reads a decide reply. Public so the parsing — the part most exposed to
  /// model quirks — can be tested directly.
  static AgentDecision parseDecision(
    String content, {
    Iterable<String>? languages,
  }) {
    final json = AgentJson.extractObject(content);

    if (json == null) {
      // The model ignored the format and simply answered. That is a usable
      // reply, so show it rather than failing the turn.
      if (!AgentJson.looksLikeJson(content) && content.trim().isNotEmpty) {
        return AgentDecision(reply: _proseReply(content));
      }
      return const AgentDecision.none();
    }

    // {"action": {"id": …, "args": …}}, tolerating the common variants:
    // `name` for `id`, `arguments` for `args`, arguments as a JSON string,
    // and a bare {"action": "places.find", "args": {…}}.
    final action = json['action'];
    if (action is Map) {
      final id = action['id'] ?? action['name'];
      if (id is String && id.isNotEmpty) {
        return AgentDecision(
          tool: id,
          args: _arguments(action['args'] ?? action['arguments']),
        );
      }
    } else if (action is String && action.isNotEmpty) {
      return AgentDecision(
        tool: action,
        args: _arguments(json['args'] ?? json['arguments']),
      );
    }

    final reply = parseReply(json, languages: languages);
    return reply.isEmpty
        ? const AgentDecision.none()
        : AgentDecision(reply: reply);
  }

  static Map<String, Object?> _arguments(Object? raw) {
    if (raw is Map) return Map<String, Object?>.from(raw);
    if (raw is String && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) return Map<String, Object?>.from(decoded);
      } catch (_) {}
    }
    return const {};
  }

  // ── render ────────────────────────────────────────────────────────────────

  @override
  Future<AgentReply> render(
    AgentTurnRequest request,
    ToolResult? result,
  ) async {
    final outcome = result == null
        ? 'No tool was used.'
        : 'Tool result for "${result.tool}": ${result.summary}\n${jsonEncode(result.data)}';
    final content = await _complete([
      ..._history(request),
      // One user message, not two: Gemma's chat template rejects consecutive
      // turns with the same role.
      _message('user', '${request.userText}\n\n$outcome'),
    ], maxTokens: renderMaxTokens);

    final json = AgentJson.extractObject(content);
    if (json == null) {
      return !AgentJson.looksLikeJson(content) && content.trim().isNotEmpty
          ? _proseReply(content)
          : const AgentReply.empty();
    }
    return parseReply(json, languages: request.languages);
  }

  /// Reads `{"lang": …, "reply": [...]}`, also accepting `components` for
  /// `reply`. A language outside [languages] is dropped. Public for the same
  /// reason as [parseDecision].
  static AgentReply parseReply(
    Map<String, Object?> json, {
    Iterable<String>? languages,
  }) {
    final raw = json['reply'] ?? json['components'];
    final components = <ComponentSpec>[];
    if (raw is List) {
      for (final item in raw.take(kAgentMaxChildren)) {
        final spec = ComponentSpec.fromJson(item);
        if (spec != null) components.add(spec);
      }
    }

    final lang = json['lang'] ?? json['language'];
    final known = languages == null || languages.contains(lang);
    return AgentReply(
      components: components,
      language: lang is String && lang.isNotEmpty && known ? lang : null,
    );
  }

  static AgentReply _proseReply(String content) => AgentReply(
    components: [
      ComponentSpec(
        type: kAgentTextComponent,
        fallbackText: content.trim(),
        props: {'text': content.trim()},
      ),
    ],
  );

  // ── HTTP ──────────────────────────────────────────────────────────────────

  List<Map<String, String>> _history(AgentTurnRequest request) => [
    for (final entry in request.history)
      _message(entry.isUser ? 'user' : 'assistant', entry.text),
  ];

  static Map<String, String> _message(String role, String content) => {
    'role': role,
    'content': content,
  };

  /// Makes the message list acceptable to strict chat templates.
  ///
  /// Gemma's template raises unless turns strictly alternate user / assistant
  /// after the system message, and must start and end on a user turn.
  /// History can break that — a failed turn leaves a user message with no
  /// reply — so adjacent same-role messages are merged and a leading
  /// assistant turn is dropped.
  static List<Map<String, String>> alternate(
    List<Map<String, String>> messages,
  ) {
    final out = <Map<String, String>>[];
    for (final message in messages) {
      final content = message['content'] ?? '';
      if (content.trim().isEmpty) continue;
      final role = message['role']!;

      if (out.isEmpty && role == 'assistant') continue;
      if (out.length == 1 &&
          out.first['role'] == 'system' &&
          role == 'assistant') {
        continue;
      }

      if (out.isNotEmpty && out.last['role'] == role) {
        out[out.length - 1] = _message(
          role,
          '${out.last['content']}\n\n$content',
        );
      } else {
        out.add(_message(role, content));
      }
    }
    return out;
  }

  Future<String> _complete(
    List<Map<String, String>> messages, {
    required int maxTokens,
  }) async {
    final body = <String, Object?>{
      if (model != null && model!.isNotEmpty) 'model': model,
      'messages': alternate(messages),
      'temperature': temperature,
      'max_tokens': maxTokens,
      'stream': false,
      if (_jsonMode) 'response_format': const {'type': 'json_object'},
    };

    try {
      return _contentOf(await _post(body));
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      final detail = _errorMessage(e.response?.data);

      // A server that does not support guaranteed-JSON output rejects the
      // request outright. Drop it for the session and retry once without —
      // the prompt already asks for JSON, and the parser is lenient.
      if (_jsonMode && status == 400) {
        log('$label: server refused response_format ($detail); retrying');
        _jsonMode = false;
        body.remove('response_format');
        try {
          return _contentOf(await _post(body));
        } on DioException catch (retry) {
          throw _failure(retry);
        }
      }

      // Never log the request: its headers carry the key.
      throw AgentTransportException('${status ?? e.type}: $detail');
    }
  }

  static AgentTransportException _failure(DioException e) =>
      AgentTransportException(
        '${e.response?.statusCode ?? e.type}: '
        '${_errorMessage(e.response?.data)}',
      );

  Future<Map<String, Object?>> _post(Map<String, Object?> body) async {
    final response = await _dio.post<Object?>('chat/completions', data: body);
    final data = response.data;
    final map = data is Map
        ? Map<String, Object?>.from(data)
        : data is String
        ? (AgentJson.extractObject(data) ?? const <String, Object?>{})
        : const <String, Object?>{};

    // Some gateways report an upstream failure as a 200 with an error body.
    if (map['error'] != null) {
      throw AgentTransportException(_errorMessage(map));
    }
    return map;
  }

  String _contentOf(Map<String, Object?> response) {
    final choices = response['choices'];
    if (choices is! List || choices.isEmpty) {
      throw const AgentTransportException('no choices in response');
    }
    final first = choices.first;
    final message = first is Map ? first['message'] : null;
    final content = message is Map ? message['content'] : null;
    if (content is String) return content;

    final finish = first is Map ? first['finish_reason'] : null;
    throw AgentTransportException('empty content (finish_reason: $finish)');
  }

  static String _errorMessage(Object? data) {
    if (data is Map) {
      final error = data['error'];
      if (error is Map && error['message'] is String) {
        return error['message'] as String;
      }
      if (error is String) return error;
      if (data['detail'] is String) return data['detail'] as String;
    }
    return 'no detail';
  }
}
