import 'package:flutter_test/flutter_test.dart';
import 'package:zehn_intelligence/src/server/bootstrap/bootstrap.dart';
import 'package:zehn_intelligence/src/server/proxy/request_builder.dart';
import 'package:zehn_intelligence/zehn_intelligence.dart' show ZiToolError;

const ctx = ZiRequestContext(language: 'ru', appVersion: '1.2.0+5', platform: 'ios');

Matcher toolError(String code) => throwsA(isA<ZiToolError>().having((e) => e.code, 'code', code));

void main() {
  const venue = ZiHttpTool(
    method: 'GET',
    path: '/location/venues/{id}',
    params: [
      ZiParam(name: 'id', location: ZiParamIn.path),
      ZiParam(name: 'category_id', location: ZiParamIn.query, key: 'category'),
      ZiParam(name: 'client', location: ZiParamIn.header, key: 'X-Client'),
    ],
  );

  test('fills path, query and header params', () {
    final r = buildRequest(venue, {'id': 'a/b', 'category_id': 5, 'client': 'v'}, const ZiApiSettings(), ctx);
    expect(r.method, 'GET');
    expect(r.path, '/location/venues/a%2Fb');
    expect(r.query, {'category': '5'});
    expect(r.headers['X-Client'], 'v');
  });

  test('path traversal stays inside one segment', () {
    final r = buildRequest(venue, {'id': '../admin'}, const ZiApiSettings(), ctx);
    expect(r.path, '/location/venues/..%2Fadmin');
  });

  test('fills header placeholders', () {
    const api = ZiApiSettings(headers: {'Accept-Language': '{language}', 'X-App': '{app_version}/{platform}'});
    const tool = ZiHttpTool(method: 'GET', path: '/x', headers: {'X-Tool': 'on'});
    final r = buildRequest(tool, {}, api, ctx);
    expect(r.headers, {'Accept-Language': 'ru', 'X-App': '1.2.0+5/ios', 'X-Tool': 'on'});
  });

  test('rejects POST with method_not_allowed', () {
    const tool = ZiHttpTool(method: 'POST', path: '/x');
    expect(() => buildRequest(tool, {}, const ZiApiSettings(), ctx), toolError('method_not_allowed'));
  });

  test('rejects a full-URL path with host_not_allowed', () {
    for (final path in ['https://evil.example/x', '//evil.example/x', 'x']) {
      final tool = ZiHttpTool(method: 'GET', path: path);
      expect(() => buildRequest(tool, {}, const ZiApiSettings(), ctx), toolError('host_not_allowed'), reason: path);
    }
  });

  test('missing path param is invalid_args', () {
    expect(() => buildRequest(venue, {}, const ZiApiSettings(), ctx), toolError('invalid_args'));
  });

  test('omits missing optional query params', () {
    final r = buildRequest(venue, {'id': '7', 'category_id': null}, const ZiApiSettings(), ctx);
    expect(r.query, isEmpty);
    expect(r.headers.containsKey('X-Client'), isFalse);
  });

  test('list query values are joined with commas', () {
    const tool = ZiHttpTool(method: 'GET', path: '/x', params: [ZiParam(name: 'ids', location: ZiParamIn.query)]);
    expect(buildRequest(tool, {'ids': [1, 2]}, const ZiApiSettings(), ctx).query, {'ids': '1,2'});
  });
}
