import 'package:flutter_test/flutter_test.dart';
import 'package:zehn_intelligence/src/server/bootstrap/bootstrap.dart';

import '../../support/bootstrap_fixture.dart';

void main() {
  test('parses the spec example', () {
    final b = ZiBootstrap.fromJson(bootstrapJson());
    expect(b.specVersion, '1.0.3');
    expect(b.services, {'llm', 'stt', 'tts'});
    expect(b.languages, ['uz', 'ru', 'en']);
    expect(b.defaultLanguage, 'uz');
    expect(b.api.baseUrl, Uri.parse('https://api.example.uz'));
    expect(b.api.allowedHosts, {'api.example.uz'});
    expect(b.api.authHeader, 'Authorization');
    expect(b.api.authScheme, 'Bearer');
    expect(b.api.headers, {'Accept-Language': '{language}'});

    final stores = b.tools['stores.list']!;
    expect(stores.method, 'GET');
    expect(stores.path, '/location/venues');
    expect(stores.params[1].key, 'category');
    expect(stores.params[0].key, 'page');
    expect(stores.auth, isFalse);
    expect(stores.result!.root, '/results');
    expect(stores.result!.fields, ['public_id', 'name', 'floor']);
    expect(stores.result!.maxItems, 10);

    expect(b.tools['locations.get']!.params.single.location, ZiParamIn.path);
    expect(b.tools['locations.get']!.result, isNull);
    expect(b.components['cinema_details']!.kind, ZiComponentKind.inline);
    expect(b.components['cinema_details']!.surface, isNotNull);
    expect(b.components['loyalty_page']!.route, '/loyalty');
    expect(b.theme['font'], 'CeraPro');
  });

  test('defaults: auth header, scheme, max_items', () {
    final json = bootstrapJson();
    (json['api']! as Map).remove('auth');
    final tools = json['tools']! as Map;
    ((tools['stores.list']! as Map)['result']! as Map).remove('max_items');
    final b = ZiBootstrap.fromJson(json);
    expect(b.api.authHeader, 'Authorization');
    expect(b.api.authScheme, 'Bearer');
    expect(b.tools['stores.list']!.result!.maxItems, 10);
  });

  test('a broken tool is left out, others stay', () {
    final json = bootstrapJson();
    ((json['tools']! as Map)['stores.list']! as Map)['path'] = 5;
    final b = ZiBootstrap.fromJson(json);
    expect(b.tools.containsKey('stores.list'), isFalse);
    expect(b.tools.containsKey('locations.get'), isTrue);
  });

  Map<String, Object?> withTool(String name, Map<String, Object?> tool) {
    final json = bootstrapJson();
    json['tools'] = <String, Object?>{...(json['tools']! as Map<String, Object?>), name: tool};
    return json;
  }

  test('a write tool with body params parses and needs confirmation', () {
    final b = ZiBootstrap.fromJson(withTool('parking.reserve', {
      'method': 'post',
      'path': '/parking/reservations',
      'params': [
        {'name': 'zone_id', 'in': 'body'},
        {'name': 'hours', 'in': 'body', 'key': 'duration_hours'},
      ],
      'auth': true,
      'confirm': {'title': {'en': 'Reserve a place in zone {zone_id}?'}},
    }));
    final t = b.tools['parking.reserve']!;
    expect(t.method, 'POST');
    expect(t.params.map((p) => p.location), [ZiParamIn.body, ZiParamIn.body]);
    expect(t.params[1].key, 'duration_hours');
    expect(t.confirm, isTrue);
    expect(t.confirmTitle, {'en': 'Reserve a place in zone {zone_id}?'});
  });

  test('writes need confirmation by default, reads do not', () {
    final b = ZiBootstrap.fromJson(withTool('reservation.cancel', {'method': 'DELETE', 'path': '/r/{id}', 'params': [{'name': 'id', 'in': 'path'}]}));
    expect(b.tools['reservation.cancel']!.confirm, isTrue);
    expect(b.tools['stores.list']!.confirm, isFalse);
    final quiet = ZiBootstrap.fromJson(withTool('favorite.add', {'method': 'PUT', 'path': '/f', 'confirm': false}));
    expect(quiet.tools['favorite.add']!.confirm, isFalse);
  });

  test('body params on a GET make the tool invalid', () {
    final b = ZiBootstrap.fromJson(withTool('bad.get', {'method': 'GET', 'path': '/x', 'params': [{'name': 'a', 'in': 'body'}]}));
    expect(b.tools.containsKey('bad.get'), isFalse);
  });

  test('an unknown method makes the tool invalid', () {
    final b = ZiBootstrap.fromJson(withTool('bad.trace', {'method': 'TRACE', 'path': '/x'}));
    expect(b.tools.containsKey('bad.trace'), isFalse);
  });

  test('unknown fields are ignored', () {
    final json = {...bootstrapJson(), 'brand_new': {'x': 1}};
    expect(ZiBootstrap.fromJson(json).tools, hasLength(2));
  });

  test('route component without route is left out', () {
    final json = bootstrapJson();
    (json['components']! as Map)['loyalty_page'] = {'kind': 'route'};
    expect(ZiBootstrap.fromJson(json).components.containsKey('loyalty_page'), isFalse);
  });

  test('not a map throws FormatException', () {
    expect(() => ZiBootstrap.fromJson([1]), throwsFormatException);
  });

  test('toJson round-trips', () {
    final b = ZiBootstrap.fromJson(bootstrapJson());
    expect(ZiBootstrap.fromJson(b.toJson()).tools.keys, b.tools.keys);
  });

  test('welcome copy is parsed per language', () {
    final b = ZiBootstrap.fromJson({
      ...bootstrapJson(),
      'copy': {
        'welcome_title': {'en': 'Hi!', 'uz': 'Salom!'},
        'welcome_subtitle': {'en': 'Find stores.'},
      },
    });
    expect(b.welcomeTitle, {'en': 'Hi!', 'uz': 'Salom!'});
    expect(b.welcomeSubtitle, {'en': 'Find stores.'});
    expect(ZiBootstrap.fromJson(bootstrapJson()).welcomeTitle, isEmpty);
  });
}
