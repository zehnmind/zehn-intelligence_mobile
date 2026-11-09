import '../../ui/zehn_integrator.dart' show ZiToolError;

/// A customer API request the server built for one tool call: the
/// `request` object of `client_api_request`. The server fills path
/// parameters, query, headers and body from the call's arguments; the phone
/// only checks it is safe, adds the user's login, and makes it.
class ZiHttpCall {
  const ZiHttpCall({
    required this.method,
    required this.path,
    this.query = const {},
    this.headers = const {},
    this.body,
    this.auth = false,
    this.authHeader = 'Authorization',
    this.authScheme = 'Bearer',
    this.result,
    this.baseUrl,
  });

  static const methods = {'GET', 'POST', 'PUT', 'PATCH', 'DELETE'};

  /// Throws [ZiToolError] the model can read: `invalid_request`,
  /// `method_not_allowed` or `host_not_allowed`.
  factory ZiHttpCall.fromJson(Object? json) {
    if (json is! Map) throw const ZiToolError('invalid_request', 'The tool has no request description.');
    final rawMethod = json['method'];
    final path = json['path'];
    if (rawMethod is! String || path is! String || path.isEmpty) {
      throw const ZiToolError('invalid_request', 'The request needs a method and a path.');
    }
    final method = rawMethod.toUpperCase();
    if (!methods.contains(method)) {
      throw ZiToolError('method_not_allowed', 'The method $method is not allowed.');
    }
    if (!path.startsWith('/') || path.startsWith('//') || path.contains('://')) {
      throw const ZiToolError('host_not_allowed', 'A tool path must be a path on the API, not a URL.');
    }
    final body = json['body'];
    if (body != null && method == 'GET') {
      throw const ZiToolError('invalid_request', 'A GET request has no body.');
    }
    Uri? baseUrl;
    final rawBase = json['base_url'];
    if (rawBase is String && rawBase.isNotEmpty) {
      baseUrl = Uri.tryParse(rawBase);
      if (baseUrl == null || (baseUrl.scheme != 'https' && baseUrl.scheme != 'http') || baseUrl.host.isEmpty) {
        throw const ZiToolError('host_not_allowed', 'The base URL must be http(s).');
      }
    }
    final auth = json['auth'];
    return ZiHttpCall(
      method: method,
      path: path,
      query: {
        if (json['query'] is Map)
          for (final e in (json['query'] as Map).entries)
            if (e.value is List)
              '${e.key}': [for (final v in e.value as List) if (v != null) '$v']
            else if (e.value != null)
              '${e.key}': '${e.value}',
      },
      headers: {
        if (json['headers'] is Map)
          for (final e in (json['headers'] as Map).entries)
            if (e.value is String) '${e.key}': e.value as String,
      },
      body: body,
      auth: auth is bool && auth,
      authHeader: json['auth_header'] is String ? json['auth_header'] as String : 'Authorization',
      authScheme: json['auth_scheme'] is String ? json['auth_scheme'] as String : 'Bearer',
      result: ZiResultRule.fromJson(json['result']),
      baseUrl: baseUrl,
    );
  }

  /// `GET`, `POST`, `PUT`, `PATCH` or `DELETE`.
  final String method;

  /// Starts with `/`, parameters already filled and URL-encoded.
  final String path;

  /// A `String`, or a `List<String>` whose key repeats (`?tag=a&tag=b`).
  final Map<String, Object> query;
  final Map<String, String> headers;

  /// The JSON body of a write; null for none.
  final Object? body;

  /// Needs the user's login.
  final bool auth;
  final String authHeader;
  final String authScheme;
  final ZiResultRule? result;

  /// Changes data: made only after the user tapped Confirm on its card.
  bool get isWrite => method != 'GET';

  /// Where the customer API is, for apps that gave callbacks rather than
  /// their own Dio (and no `apiBaseUrl` of their own).
  final Uri? baseUrl;
}

/// What part of the answer the model gets.
class ZiResultRule {
  const ZiResultRule({this.root, this.fields = const [], this.maxItems = 10});

  static ZiResultRule? fromJson(Object? json) {
    if (json is! Map) return null;
    final max = json['max_items'];
    final fields = json['fields'];
    final root = json['root'];
    return ZiResultRule(
      root: root is String && root.isNotEmpty ? root : null,
      fields: fields is List ? [for (final f in fields) if (f is String) f] : const [],
      maxItems: max is num && max > 0 ? max.toInt() : 10,
    );
  }

  /// A `/`-path into the answer; null keeps the whole answer.
  final String? root;

  /// `/`-paths kept from each object; empty keeps all.
  final List<String> fields;
  final int maxItems;
}
