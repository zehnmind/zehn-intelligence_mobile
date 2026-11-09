import 'package:flutter_test/flutter_test.dart';
import 'package:zehn_intelligence/src/server/proxy/http_call.dart';
import 'package:zehn_intelligence/zehn_intelligence.dart' show ZiToolError;

Matcher toolError(String code) => throwsA(isA<ZiToolError>().having((e) => e.code, 'code', code));

void main() {
  test('parses a GET request the server built', () {
    final c = ZiHttpCall.fromJson({
      'method': 'get',
      'path': '/location/venues/a%2Fb',
      'query': {'page': '1', 'size': 10},
      'headers': {'Accept-Language': 'ru'},
      'auth': true,
      'result': {'root': '/results', 'fields': ['id', 'name'], 'max_items': 5},
    });
    expect(c.method, 'GET');
    expect(c.path, '/location/venues/a%2Fb');
    expect(c.query, {'page': '1', 'size': '10'});
    expect(c.headers, {'Accept-Language': 'ru'});
    expect(c.auth, isTrue);
    expect(c.authHeader, 'Authorization');
    expect(c.authScheme, 'Bearer');
    expect(c.result!.root, '/results');
    expect(c.result!.fields, ['id', 'name']);
    expect(c.result!.maxItems, 5);
    expect(c.body, isNull);
    expect(c.confirm, isFalse);
    expect(c.baseUrl, isNull);
  });

  test('a write carries its body and asks first by default', () {
    final c = ZiHttpCall.fromJson({
      'method': 'POST',
      'path': '/parking/reservations',
      'body': {'zone_id': 7, 'plates': ['01A123BC']},
      'base_url': 'https://api.example.uz',
    });
    expect(c.body, {'zone_id': 7, 'plates': ['01A123BC']});
    expect(c.confirm, isTrue);
    expect(c.confirmTitle, isNull);
    expect(c.baseUrl, Uri.parse('https://api.example.uz'));
  });

  test('confirm can carry the question, or be switched off', () {
    final asked = ZiHttpCall.fromJson({
      'method': 'DELETE',
      'path': '/r/x9',
      'confirm': {'title': 'Cancel reservation x9?'},
    });
    expect(asked.confirm, isTrue);
    expect(asked.confirmTitle, 'Cancel reservation x9?');
    final quiet = ZiHttpCall.fromJson({'method': 'PUT', 'path': '/f', 'confirm': false});
    expect(quiet.confirm, isFalse);
    final readAsked = ZiHttpCall.fromJson({'method': 'GET', 'path': '/x', 'confirm': true});
    expect(readAsked.confirm, isTrue);
  });

  test('the auth header and scheme can be renamed', () {
    final c = ZiHttpCall.fromJson({'method': 'GET', 'path': '/x', 'auth_header': 'X-Token', 'auth_scheme': ''});
    expect(c.authHeader, 'X-Token');
    expect(c.authScheme, '');
  });

  test('a path that is a URL is host_not_allowed', () {
    for (final path in ['https://evil.example/x', '//evil.example/x', 'x']) {
      expect(() => ZiHttpCall.fromJson({'method': 'GET', 'path': path}), toolError('host_not_allowed'), reason: path);
    }
  });

  test('an unknown method is method_not_allowed', () {
    expect(() => ZiHttpCall.fromJson({'method': 'TRACE', 'path': '/x'}), toolError('method_not_allowed'));
  });

  test('a GET with a body, or no path, is invalid_request', () {
    expect(() => ZiHttpCall.fromJson({'method': 'GET', 'path': '/x', 'body': {'a': 1}}), toolError('invalid_request'));
    expect(() => ZiHttpCall.fromJson({'method': 'GET'}), toolError('invalid_request'));
    expect(() => ZiHttpCall.fromJson('nope'), toolError('invalid_request'));
  });

  test('a base_url that is not http(s) is host_not_allowed', () {
    expect(() => ZiHttpCall.fromJson({'method': 'GET', 'path': '/x', 'base_url': 'file:///etc'}), toolError('host_not_allowed'));
  });
}
