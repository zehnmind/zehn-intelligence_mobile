// A pretend Zehn console backend and a pretend customer API, for trying the
// SDK's server flow without either:
//
//   dart run zehn_intelligence:mock_server [--port 8787]
//
// Console side: POST /v1/installs, POST /v1/turns,
// POST /v1/turns/{id}/tool-results, GET /v1/suggestions (with the chat
// settings). Customer side, under /customer: GET /cinematica/ (public) and
// GET /loyalty/cards/my (needs `Authorization: Bearer demo`). Every request is
// logged as one line.
//
// Like the real backend, it builds each tool call's customer request
// (`client_api_request.http`) and sends each card's template with the card
// (`mount_component.surface`), from an app description: the built-in one, or
// `--app <file.json>` with a real app's endpoints, cards and theme.
//
// Ask about the cinema ("kino", "cinema", "кино") for a tool call and a
// console-made card; about "card"/"karta"/"карта" for a login-only tool;
// "loyalty" opens an app route. Anything else is echoed.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// What the console knows about the app: `api` (base_url, auth, headers),
/// `tools`, `components`, `theme`, `copy`, `services`, `languages`,
/// `default_language`, `spec_version`.
late Map<String, Object?> _app;

Future<void> main(List<String> args) async {
  String? arg(String name) {
    final i = args.indexOf(name);
    return i >= 0 && i + 1 < args.length ? args[i + 1] : null;
  }

  final port = int.parse(arg('--port') ?? '8787');
  // --bootstrap is the old name of --app.
  final file = arg('--app') ?? arg('--bootstrap');
  _app = file != null ? (jsonDecode(File(file).readAsStringSync()) as Map).cast<String, Object?>() : _builtInApp(port);
  if (file != null) stdout.writeln('app description from $file');
  final server = await HttpServer.bind(InternetAddress.anyIPv4, port);
  stdout.writeln('mock server on http://localhost:$port');
  await for (final req in server) {
    unawaited(_handle(req, port).catchError((Object e) {
      stdout.writeln('error: $e');
    }));
  }
}

final _turns = <String, _PendingTurn>{};
var _nextTurn = 0;

class _PendingTurn {
  _PendingTurn(this.language, this.tool);

  final String language;
  final String tool;
}

Future<void> _handle(HttpRequest req, int port) async {
  final path = req.uri.path;
  final body = await utf8.decoder.bind(req).join();
  final json = body.isEmpty ? null : jsonDecode(body);
  var status = 200;
  try {
    if (req.method == 'POST' && path == '/v1/installs') {
      await _json(req, 200, {'token': 'install-token', 'token_type': 'Bearer', 'expires_in': 3600});
    } else if (req.method == 'GET' && path == '/v1/suggestions') {
      final language = req.uri.queryParameters['language'] ?? 'en';
      await _json(req, 200, {'suggestions': _starters[language] ?? _starters['en'], 'chat': _chat(language)});
    } else if (req.method == 'POST' && path == '/v1/turns') {
      if (!_signedIn(req)) {
        status = 401;
        await _json(req, 401, {'code': 'user_token_required', 'message': 'No token'});
      } else {
        await _startTurn(req, (json as Map).cast<String, Object?>());
      }
    } else if (req.method == 'POST' && path.startsWith('/v1/turns/') && path.endsWith('/tool-results')) {
      final id = path.split('/')[3];
      await _results(req, id, (json as Map).cast<String, Object?>());
    } else if (req.method == 'GET' && path == '/customer/cinematica/') {
      await _json(req, 200, _cinema);
    } else if (req.method == 'GET' && path == '/customer/loyalty/cards/my') {
      if (req.headers.value('authorization') == 'Bearer demo') {
        await _json(req, 200, {'card_number': '9860 •••• 1234', 'current_points': 1250, 'tier': 'Gold'});
      } else {
        status = 401;
        await _json(req, 401, {'detail': 'Not signed in'});
      }
    } else {
      status = 404;
      await _json(req, 404, {'code': 'not_found'});
    }
  } finally {
    stdout.writeln('${req.method} $path $status');
  }
}

bool _signedIn(HttpRequest req) => (req.headers.value('authorization') ?? '').startsWith('Bearer ');

Future<void> _json(HttpRequest req, int status, Object? body) async {
  req.response
    ..statusCode = status
    ..headers.contentType = ContentType.json
    ..write(jsonEncode(body));
  await req.response.close();
}

Future<void> _sse(HttpRequest req, String turnId, List<(String, Map<String, Object?>)> events) async {
  req.response
    ..statusCode = 200
    ..headers.set('content-type', 'text/event-stream; charset=utf-8')
    ..headers.set('x-zi-turn-id', turnId)
    ..bufferOutput = false;
  var seq = 0;
  for (final (name, data) in events) {
    seq++;
    req.response.write('event: $name\nid: $seq\ndata: ${jsonEncode({'turn_id': turnId, 'seq': seq, ...data})}\n\n');
    await req.response.flush();
    await Future<void>.delayed(const Duration(milliseconds: 120));
  }
  await req.response.close();
}

String _text(Map<String, Object?> body) {
  final input = body['input'];
  if (input is Map && input['type'] == 'audio') return 'kino';
  return input is Map && input['text'] is String ? (input['text'] as String).toLowerCase() : '';
}

Future<void> _startTurn(HttpRequest req, Map<String, Object?> body) async {
  final turnId = 'turn_${++_nextTurn}';
  final language = body['language'] is String ? body['language'] as String : 'en';
  final conversation = body['conversation_id'] is String ? body['conversation_id'] as String : 'conv_$turnId';
  final text = _text(body);
  final started = ('turn.started', <String, Object?>{'conversation_id': conversation, 'conversation_new': body['conversation_id'] == null});
  final spoken = (body['input'] as Map?)?['type'] == 'audio';
  final transcript = [if (spoken) ('transcript', <String, Object?>{'text': 'kino haqida', 'language': language})];

  String? tool;
  if (RegExp('kino|cinema|кино').hasMatch(text)) tool = 'cinemas.list';
  if (RegExp('card|karta|карта').hasMatch(text)) tool = 'loyalty_cards.get';

  if (text.contains('loyalty')) {
    await _sse(req, turnId, [
      started,
      ('text.delta', {'text': _w(language, 'Sodiqlik sahifasini ochyapman.', 'Открываю раздел лояльности.', 'Opening the loyalty page.')}),
      ('mount_component', _mount('m_1', 'loyalty_page', const {})),
      ('done', {'outcome': 'answered'}),
    ]);
    return;
  }
  if (tool == null) {
    await _sse(req, turnId, [
      started,
      ...transcript,
      ('text.delta', {'text': _w(language, 'Siz yozdingiz: ', 'Вы написали: ', 'You wrote: ')}),
      ('text.delta', {'text': '*$text*'}),
      ('suggestions', {'items': _starters[language] ?? _starters['en']}),
      ('done', {'outcome': 'answered'}),
    ]);
    return;
  }
  _turns[turnId] = _PendingTurn(language, tool);
  await _sse(req, turnId, [
    started,
    ...transcript,
    ('text.delta', {'text': _w(language, 'Bir daqiqa… ', 'Минутку… ', 'One moment… ')}),
    ('client_api_request', {'call_id': 'c_1', 'tool': tool, 'args': <String, Object?>{}, 'http': _http(tool, const {}, language)}),
    (
      'turn.paused',
      {
        'call_ids': ['c_1'],
        'deadline': DateTime.now().toUtc().add(const Duration(seconds: 60)).toIso8601String(),
        'expires_in': 60,
        'max_result_bytes': 32768,
      },
    ),
  ]);
}

Future<void> _results(HttpRequest req, String turnId, Map<String, Object?> body) async {
  final pending = _turns.remove(turnId);
  final language = pending?.language ?? 'en';
  final results = body['results'] is List ? body['results'] as List : const [];
  final first = results.isEmpty ? null : (results.first as Map).cast<String, Object?>();
  stdout.writeln('  tool result: ${jsonEncode(first).substring(0, jsonEncode(first).length.clamp(0, 160))}');
  if (first == null || first['ok'] != true) {
    final code = (first?['error'] as Map?)?['code'] ?? 'no_result';
    await _sse(req, turnId, [
      ('text.delta', {'text': _w(language, 'Ilova xato qaytardi: `$code`.', 'Приложение вернуло ошибку: `$code`.', 'The app returned an error: `$code`.')}),
      ('done', {'outcome': 'answered'}),
    ]);
    return;
  }
  final data = first['data'];
  if (pending?.tool == 'loyalty_cards.get') {
    final points = data is Map ? data['current_points'] : null;
    await _sse(req, turnId, [
      (
        'text.delta',
        {
          'text': points == null
              ? _w(language, 'Kartangiz ma’lumoti olindi.', 'Данные карты получены.', 'I got your card details.')
              : _w(
                  language,
                  'Kartangizda **$points** ball bor.',
                  'На вашей карте **$points** баллов.',
                  'Your card has **$points** points.',
                ),
        },
      ),
      ('done', {'outcome': 'answered'}),
    ]);
    return;
  }
  await _sse(req, turnId, [
    ('text.delta', {'text': _w(language, 'Mana **Cinematica** haqida:', 'Вот что есть о **Cinematica**:', "Here's **Cinematica**:")}),
    ('mount_component', _mount('m_1', 'cinema_details', data is Map ? data.cast<String, Object?>() : const {})),
    ('suggestions', {'items': _w3(language, ['Bugun qanday filmlar bor?', 'Kartamni ko‘rsat'], ['Какие фильмы сегодня?', 'Покажи мою карту'], ["What's on today?", 'Show my card'])}),
    ('done', {'outcome': 'answered'}),
  ]);
}

Map<String, Object?> _map(Object? v) => v is Map ? v.cast<String, Object?>() : const {};

/// A `{language: text}` map, or plain text, in [language].
String? _pick(Object? v, String language) {
  if (v is String) return v;
  if (v is! Map) return null;
  final text = v[language] ?? v['en'] ?? (v.values.isEmpty ? null : v.values.first);
  return text is String ? text : null;
}

/// The customer request for one call, as the backend builds it: path
/// parameters filled, query, headers, body, login and result rule.
Map<String, Object?> _http(String tool, Map<String, Object?> args, String language) {
  final api = _map(_app['api']);
  final spec = _map(_map(_app['tools'])[tool]);
  var path = spec['path'] as String? ?? '/';
  final query = <String, Object?>{};
  final body = <String, Object?>{};
  for (final p in spec['params'] is List ? spec['params'] as List : const []) {
    final param = _map(p);
    final name = param['name'] as String?;
    final value = args[name];
    if (name == null || value == null) continue;
    final key = param['key'] as String? ?? name;
    switch (param['in']) {
      case 'path':
        path = path.replaceAll('{$name}', Uri.encodeComponent('$value'));
      case 'query':
        query[key] = value;
      case 'body':
        body[key] = value;
    }
  }
  final headers = {
    for (final e in {..._map(api['headers']), ..._map(spec['headers'])}.entries) e.key: '${e.value}'.replaceAll('{language}', language),
  };
  final auth = _map(api['auth']);
  final confirm = spec['confirm'];
  final title = confirm is Map ? _pick(confirm['title'], language) : null;
  return {
    'method': spec['method'] ?? 'GET',
    'path': path,
    if (query.isNotEmpty) 'query': query,
    if (headers.isNotEmpty) 'headers': headers,
    if (body.isNotEmpty) 'body': body,
    'auth': spec['auth'] == true,
    'auth_header': ?auth['header'],
    'auth_scheme': ?auth['scheme'],
    'result': ?spec['result'],
    if (confirm is bool) 'confirm': confirm,
    if (confirm is Map) 'confirm': {'title': ?title?.replaceAllMapped(RegExp(r'\{(\w+)\}'), (m) => '${args[m[1]] ?? ''}')},
    'base_url': ?api['base_url'],
  };
}

/// A card or route with what the phone needs to show it.
Map<String, Object?> _mount(String callId, String component, Map<String, Object?> props) {
  final def = _map(_map(_app['components'])[component]);
  return {
    'call_id': callId,
    'component': component,
    'kind': def['kind'] ?? 'inline',
    'props': props,
    'surface': ?def['surface'],
    'route': ?def['route'],
  };
}

/// The `chat` field of `GET /v1/suggestions`.
Map<String, Object?> _chat(String language) {
  final copy = _map(_app['copy']);
  return {
    'services': ?_app['services'],
    'languages': ?_app['languages'],
    'default_language': ?_app['default_language'],
    'theme': ?_app['theme'],
    'welcome_title': ?_pick(copy['welcome_title'], language),
    'welcome_subtitle': ?_pick(copy['welcome_subtitle'], language),
    'spec_version': ?_app['spec_version'],
  };
}

String _w(String language, String uz, String ru, String en) => switch (language) {
  'ru' => ru,
  'en' => en,
  _ => uz,
};

List<String> _w3(String language, List<String> uz, List<String> ru, List<String> en) => switch (language) {
  'ru' => ru,
  'en' => en,
  _ => uz,
};

const _starters = {
  'uz': ['Kinoteatr haqida aytib ber', 'Kartamda nechta ball bor?', 'Loyalty sahifasini och'],
  'ru': ['Расскажи про кинотеатр', 'Сколько баллов на моей карте?', 'Открой loyalty'],
  'en': ['Tell me about the cinema', 'How many points are on my card?', 'Open loyalty'],
};

Map<String, Object?> _builtInApp(int port) => {
  'spec_version': '1.0.3',
  'services': ['llm', 'stt', 'tts'],
  'languages': ['uz', 'ru', 'en'],
  'default_language': 'uz',
  'api': {
    'base_url': 'http://localhost:$port/customer',
    'auth': {'header': 'Authorization', 'scheme': 'Bearer'},
    'headers': {'Accept-Language': '{language}'},
  },
  'tools': {
    'cinemas.list': {'method': 'GET', 'path': '/cinematica/', 'auth': false},
    'loyalty_cards.get': {
      'method': 'GET',
      'path': '/loyalty/cards/my',
      'auth': true,
      'result': {'fields': ['card_number', 'current_points', 'tier']},
    },
  },
  'components': {
    'cinema_details': {'kind': 'inline', 'surface': {'createSurface': jsonDecode(_cinemaSurface)}},
    'loyalty_page': {'kind': 'route', 'route': '/loyalty'},
  },
  'theme': jsonDecode(_theme),
};

final Map<String, Object?> _cinema = (jsonDecode(_data) as Map).cast<String, Object?>();

// From spikes/dynamic_card_spike, with /cinema/ paths moved to the props root.
const _cinemaSurface = r'''{"surfaceId": "cinema_details", "catalogId": "zehn.basic.v0", "root": "root", "components": [{"id": "root", "component": "Box", "color": "surface", "radius": "card", "padding": 16, "child": "body"}, {"id": "body", "component": "Column", "gap": 16, "children": ["photo", "intro", "contacts", "now_header", "movies", "buy"]}, {"id": "photo", "component": "Image", "src": {"path": "/photo_url"}, "height": 170, "radius": "image"}, {"id": "intro", "component": "Column", "gap": 8, "children": ["chips", "name", "description"]}, {"id": "chips", "component": "Row", "gap": 8, "children": ["category", "floor"]}, {"id": "category", "component": "Chip", "icon": "theaters", "text": {"path": "/category_name"}, "visible": {"path": "/category_name"}}, {"id": "floor", "component": "Chip", "icon": "layers", "text": {"uz": "{/floor}-qavat", "ru": "Этаж {/floor}", "en": "Floor {/floor}"}}, {"id": "name", "component": "Text", "style": "display", "text": {"path": "/name"}}, {"id": "description", "component": "Text", "style": "body", "maxLines": 4, "text": {"path": "/description"}}, {"id": "contacts", "component": "Column", "gap": 0, "children": ["hours", "phone", "site"]}, {"id": "hours", "component": "InfoRow", "icon": "schedule", "text": {"path": "/working_hours"}}, {"id": "phone", "component": "InfoRow", "icon": "phone", "text": {"path": "/phone"}, "action": {"name": "open_url", "args": {"url": "tel:{/phone}"}}}, {"id": "site", "component": "InfoRow", "icon": "language", "text": {"path": "/website"}, "action": {"name": "open_url", "args": {"url": "https://{/website}"}}}, {"id": "now_header", "component": "Header", "icon": "movie", "title": {"uz": "Hozir namoyishda", "ru": "В прокате", "en": "Now Showing"}, "action": {"name": "ask", "args": {"text": {"uz": "Bugun qanday filmlar bor?", "ru": "Какие фильмы сегодня?", "en": "What's on today?"}}}}, {"id": "movies", "component": "Row", "gap": 10, "scroll": true, "children": {"componentId": "movie_card", "path": "/movies"}}, {"id": "movie_card", "component": "Column", "width": 136, "gap": 6, "children": ["movie_poster", "movie_title", "movie_genre", "movie_rating"], "action": {"name": "call_tool", "args": {"tool": "movies.get", "title": {"path": "title"}}}}, {"id": "movie_poster", "component": "Image", "src": {"path": "image"}, "height": 196, "radius": "image"}, {"id": "movie_title", "component": "Text", "style": "title", "maxLines": 2, "text": {"path": "title"}}, {"id": "movie_genre", "component": "Text", "style": "caption", "color": "muted", "maxLines": 1, "text": {"path": "genre"}}, {"id": "movie_rating", "component": "Chip", "text": {"path": "rating"}}, {"id": "buy", "component": "Button", "icon": "ticket", "label": {"uz": "Chipta sotib olish", "ru": "Купить билет", "en": "Buy Ticket"}, "action": {"name": "open_route", "args": {"route": "/explore/{/id}/tickets"}}}]}''';
const _theme = r'''{"font": "CeraPro", "colors": {"surface": "#FF19212F", "on_surface": "#E6FFFFFF", "muted": "#99FFFFFF", "chip": "#0DFFFFFF", "image_bg": "#08FFFFFF", "border": "#0DFFFFFF", "accent": "#FFBE7C6C", "on_accent": "#FFFFFFFF"}, "text": {"display": {"size": 30, "weight": 500, "height": 1.15}, "title": {"size": 17, "weight": 500, "height": 1.25}, "body": {"size": 15, "weight": 400, "height": 1.4}, "caption": {"size": 13, "weight": 400, "height": 1.3}}, "radius": {"card": 24, "image": 20, "chip": 100, "button": 16}}''';
const _data = r'''{"id": 1, "name": "Cinematica", "floor": "4", "category_name": {"uz": "Kinoteatr", "ru": "Кинотеатр", "en": "Cinema"}, "description": {"uz": "Tashkent City Mall'dagi zamonaviy kinoteatr: 8 ta zal, IMAX va qulay o'rindiqlar.", "ru": "Современный кинотеатр в Tashkent City Mall: 8 залов, IMAX и удобные кресла.", "en": "A modern cinema in Tashkent City Mall: 8 halls, IMAX and comfortable seats."}, "working_hours": {"uz": "Har kuni 10:00 – 02:00", "ru": "Ежедневно 10:00 – 02:00", "en": "Every day 10:00 – 02:00"}, "phone": "+998 71 000 00 00", "website": "cinematica.example", "photo_url": "https://images.unsplash.com/photo-1517604931442-7e0c8ed2963c?auto=format&fit=crop&w=800&q=80", "movies": [{"title": "Michael", "genre": "Drama, Biography", "rating": "13+", "image": "https://images.unsplash.com/photo-1485846234645-a62644f84728?auto=format&fit=crop&w=500&q=80"}, {"title": "F1: The Movie", "genre": "Action, Drama, Sport", "rating": "13+", "image": "https://images.unsplash.com/photo-1500530855697-b586d89ba3ee?auto=format&fit=crop&w=500&q=80"}, {"title": "The Fantastic Four: First Steps", "genre": "Action", "rating": "13+", "image": "https://images.unsplash.com/photo-1536440136628-849c177e76a1?auto=format&fit=crop&w=500&q=80"}]}''';
