import '../../ui/zehn_integrator.dart' show ZiToolError;
import '../bootstrap/bootstrap.dart';

/// Values the header placeholders read.
class ZiRequestContext {
  const ZiRequestContext({required this.language, required this.appVersion, required this.platform});

  final String language;
  final String appVersion;
  final String platform;
}

/// A customer API request, before the base URL and login are added.
class ZiHttpRequest {
  const ZiHttpRequest({required this.method, required this.path, required this.query, required this.headers, this.body});

  final String method;

  /// Starts with `/`; path parameters are already URL-encoded.
  final String path;
  final Map<String, String> query;
  final Map<String, String> headers;

  /// The JSON body of a write, from its `body` params; null for none.
  final Map<String, Object?>? body;
}

/// Turns a tool call into a request. Throws [ZiToolError] with
/// `method_not_allowed`, `host_not_allowed` or `invalid_args`.
ZiHttpRequest buildRequest(ZiHttpTool tool, Map<String, Object?> args, ZiApiSettings api, ZiRequestContext ctx) {
  if (!ZiHttpTool.methods.contains(tool.method)) {
    throw ZiToolError('method_not_allowed', 'The method ${tool.method} is not allowed.');
  }
  if (!tool.path.startsWith('/') || tool.path.startsWith('//') || tool.path.contains('://')) {
    throw const ZiToolError('host_not_allowed', 'A tool path must be a path on the API, not a URL.');
  }

  String fill(String template) => template
      .replaceAll('{language}', ctx.language)
      .replaceAll('{app_version}', ctx.appVersion)
      .replaceAll('{platform}', ctx.platform);

  final headers = <String, String>{
    for (final e in api.headers.entries) e.key: fill(e.value),
    for (final e in tool.headers.entries) e.key: fill(e.value),
  };
  final query = <String, String>{};
  final body = <String, Object?>{};
  var path = tool.path;

  for (final param in tool.params) {
    if (param.location == ZiParamIn.body) {
      // JSON types are kept: a number stays a number, a list a list.
      if (args[param.name] != null) body[param.key] = args[param.name];
      continue;
    }
    final value = _text(args[param.name]);
    switch (param.location) {
      case ZiParamIn.path:
        if (value == null || value.isEmpty) {
          throw ZiToolError('invalid_args', 'Missing ${param.name}.');
        }
        path = path.replaceAll('{${param.key}}', Uri.encodeComponent(value));
      case ZiParamIn.query:
        if (value != null) query[param.key] = value;
      case ZiParamIn.header:
        if (value != null) headers[param.key] = value;
      case ZiParamIn.body:
        break;
    }
  }
  if (RegExp(r'\{[^}]+\}').hasMatch(path)) {
    throw ZiToolError('invalid_args', 'The path still has a parameter: $path');
  }
  final hasBody = tool.params.any((p) => p.location == ZiParamIn.body);
  return ZiHttpRequest(
    method: tool.method,
    path: path,
    query: query,
    headers: headers,
    body: hasBody ? body : null,
  );
}

String? _text(Object? value) => switch (value) {
  null => null,
  final List<Object?> list => list.map((v) => '$v').join(','),
  _ => '$value',
};
