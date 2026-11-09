import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:zehn_intelligence/src/server/app_file.dart';
import 'package:zehn_intelligence/zehn_intelligence.dart' show ZiConfigException;

final _test = 'zi_test_${'a' * 48}';
final _prod = 'zi_prod_${'b' * 48}';

Map<String, Object?> _file([Map<String, Object?> change = const {}]) => {
  'zi_config_format': '3',
  'zi_console_url': 'https://zi-console-api.zehnmind.com',
  'zi_app_id': 'a3d1f6e2-5c47-4b8e-9f10-2d6c8b7a4e91',
  'zi_package_name': 'uz.citymall.app',
  'zi_bundle_id': 'uz.citymall.ios',
  'zi_test_key': _test,
  'zi_prod_key': _prod,
  ...change,
};

ZiAppFile _parse([Map<String, Object?> change = const {}]) => ZiAppFile.parse(jsonEncode(_file(change)));

Matcher _refused(String part) =>
    throwsA(isA<ZiConfigException>().having((e) => e.message, 'message', contains(part)));

void main() {
  test('the console file of format 3 is read', () {
    final file = _parse();
    expect(file.consoleUrl, Uri.parse('https://zi-console-api.zehnmind.com'));
    expect(file.appId, 'a3d1f6e2-5c47-4b8e-9f10-2d6c8b7a4e91');
    expect(file.testKey, _test);
    expect(file.prodKey, _prod);
  });

  test('a file that is not the console format 3 is refused', () {
    expect(() => ZiAppFile.parse('{oops'), _refused('not JSON'));
    expect(() => ZiAppFile.parse('[]'), _refused('not a JSON object'));
    expect(() => _parse({'zi_config_format': '2'}), _refused('format "3"'));
    expect(() => ZiAppFile.parse(jsonEncode(_file()..remove('zi_test_key'))), _refused('zi_test_key'));
    expect(() => _parse({'zi_console_url': 'https://x.example/path'}), _refused('zi_console_url'));
    expect(() => _parse({'zi_console_url': 'http://x.example'}), _refused('zi_console_url'));
    expect(() => _parse({'zi_app_id': 'nope'}), _refused('zi_app_id'));
    expect(() => _parse({'zi_test_key': 'zi_server_${'a' * 48}'}), _refused('zi_test_key'));
    expect(() => _parse({'zi_prod_key': 'zi_prod_short'}), _refused('zi_prod_key'));
    expect(() => _parse({'zi_package_name': '', 'zi_bundle_id': ''}), _refused('both empty'));
  });

  test('http is allowed to the developer machine only', () {
    expect(_parse({'zi_console_url': 'http://10.0.2.2:8040'}).consoleUrl.port, 8040);
  });

  test('debug and profile builds send the test key, release builds the production key', () {
    final file = _parse();
    expect(file.keyFor(release: false, platform: 'android', runningId: 'uz.citymall.app'), _test);
    expect(file.keyFor(release: true, platform: 'android', runningId: 'uz.citymall.app'), _prod);
  });

  test('iOS is checked against the bundle id, Android against the package name', () {
    final file = _parse();
    expect(file.keyFor(release: false, platform: 'ios', runningId: 'uz.citymall.ios'), _test);
    expect(() => file.keyFor(release: false, platform: 'ios', runningId: 'uz.citymall.app'), _refused('zi_bundle_id'));
    expect(() => file.keyFor(release: false, platform: 'android', runningId: 'uz.other'), _refused('zi_package_name'));
  });

  test('an empty key, a production key over http, a missing id or another platform keep the assistant off', () {
    expect(
      () => _parse({'zi_test_key': ''}).keyFor(release: false, platform: 'android', runningId: 'uz.citymall.app'),
      _refused('zi_test_key is empty'),
    );
    expect(
      () => _parse({'zi_console_url': 'http://localhost:8040'})
          .keyFor(release: true, platform: 'android', runningId: 'uz.citymall.app'),
      _refused('isn\'t https'),
    );
    expect(
      () => _parse({'zi_bundle_id': ''}).keyFor(release: false, platform: 'ios', runningId: 'uz.citymall.ios'),
      _refused('no zi_bundle_id'),
    );
    expect(() => _parse().keyFor(release: false, platform: 'linux', runningId: 'x'), _refused('Android and iOS'));
  });
}
