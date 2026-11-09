import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// One request the [FakeServer] received.
class RecordedRequest {
  RecordedRequest({
    required this.method,
    required this.path,
    required this.query,
    this.queryAll = const {},
    required this.headers,
    required this.body,
  });

  final String method;
  final String path;
  final Map<String, String> query;

  /// Every value of a repeated query key.
  final Map<String, List<String>> queryAll;

  /// Lower-case header names.
  final Map<String, String> headers;
  final String body;

  Object? get json => body.isEmpty ? null : jsonDecode(body);
}

typedef FakeHandler = FutureOr<void> Function(HttpRequest req, RecordedRequest rec);

/// A real HTTP server on 127.0.0.1 for tests. Handlers must close the response
/// (the helpers below do).
class FakeServer {
  FakeServer._(this._server);

  final HttpServer _server;
  final List<(String, String, FakeHandler)> _routes = [];
  final List<RecordedRequest> requests = [];

  static Future<FakeServer> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final fake = FakeServer._(server);
    server.listen(fake._handle);
    return fake;
  }

  Uri get url => Uri.parse('http://127.0.0.1:${_server.port}');

  /// A later registration for the same route wins. A path ending in `/*`
  /// matches every path with that prefix.
  void on(String method, String path, FakeHandler handler) =>
      _routes.add((method, path, handler));

  Future<void> close() => _server.close(force: true);

  Future<void> _handle(HttpRequest req) async {
    final body = await utf8.decoder.bind(req).join();
    final headers = <String, String>{};
    req.headers.forEach((name, values) => headers[name.toLowerCase()] = values.join(','));
    final rec = RecordedRequest(
      method: req.method,
      path: req.uri.path,
      query: req.uri.queryParameters,
      queryAll: req.uri.queryParametersAll,
      headers: headers,
      body: body,
    );
    requests.add(rec);
    for (final (method, path, handler) in _routes.reversed) {
      final matches = path.endsWith('/*')
          ? req.uri.path.startsWith(path.substring(0, path.length - 1))
          : req.uri.path == path;
      if (method == req.method && matches) {
        await handler(req, rec);
        return;
      }
    }
    req.response.statusCode = 404;
    await req.response.close();
  }
}

Future<void> respondJson(HttpRequest req, int status, Object? body) async {
  req.response.statusCode = status;
  req.response.headers.contentType = ContentType.json;
  req.response.write(jsonEncode(body));
  await req.response.close();
}

Future<void> respondText(HttpRequest req, int status, String body, {String type = 'text/html'}) async {
  req.response.statusCode = status;
  req.response.headers.set('content-type', type);
  req.response.write(body);
  await req.response.close();
}

/// Writes server-sent events, one every [gap].
Future<void> respondSse(
  HttpRequest req,
  List<(String, Object?)> events, {
  Duration gap = Duration.zero,
  bool close = true,
  Map<String, String> headers = const {},
}) async {
  req.response.statusCode = 200;
  req.response.headers.set('content-type', 'text/event-stream');
  headers.forEach(req.response.headers.set);
  req.response.bufferOutput = false;
  var id = 0;
  for (final (event, data) in events) {
    if (event == 'ping') {
      req.response.write(': ping\n\n');
    } else {
      id++;
      req.response.write('event: $event\nid: $id\ndata: ${jsonEncode(data)}\n\n');
    }
    await req.response.flush();
    if (gap > Duration.zero) await Future<void>.delayed(gap);
  }
  if (close) await req.response.close();
}

/// Drops the connection without an HTTP status.
Future<void> dropConnection(HttpRequest req) async {
  final socket = await req.response.detachSocket(writeHeaders: false);
  socket.destroy();
}
