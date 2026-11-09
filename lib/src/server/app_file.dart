import 'dart:convert';

import 'package:flutter/services.dart';

import '../ui/zehn_integrator.dart' show ZiConfigException;

/// The app's file from the console: `assets/zehn-intelligence.json`, listed
/// under `flutter: assets:` in the app's `pubspec.yaml`. The setup command
/// (`dart run zehn_intelligence:setup <code>`) puts both in place.
///
/// ```json
/// {"zi_config_format": "3", "zi_console_url": "https://zi-console-api.zehnmind.com",
///  "zi_app_id": "…", "zi_package_name": "uz.citymall.app", "zi_bundle_id": "uz.citymall.app",
///  "zi_test_key": "zi_test_…", "zi_prod_key": "zi_prod_…"}
/// ```
///
/// One file for every build (format 3): no spec version and no tools, the
/// server decides what the assistant can do. The rules are the server's
/// `config3.schema.json`, so the SDK refuses what the console never writes.
class ZiAppFile {
  const ZiAppFile._({
    required this.consoleUrl,
    required this.appId,
    required this.packageName,
    required this.bundleId,
    required this.testKey,
    required this.prodKey,
  });

  /// Where the app keeps the file.
  static const assetPath = 'assets/zehn-intelligence.json';

  /// What a developer runs to get the file.
  static const setupCommand = 'dart run zehn_intelligence:setup <code>';

  static const _keys = [
    'zi_config_format',
    'zi_console_url',
    'zi_app_id',
    'zi_package_name',
    'zi_bundle_id',
    'zi_test_key',
    'zi_prod_key',
  ];

  // The patterns of config3.schema.json, copied exactly.
  static final _consoleUrl = RegExp(
    r'^(https://[a-z0-9.-]+(:[0-9]{1,5})?|http://(localhost|127\.0\.0\.1|10\.0\.2\.2)(:[0-9]{1,5})?)$',
  );
  static final _uuid = RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$');
  static final _packageName = RegExp(r'^([A-Za-z0-9._-]{1,255})?$');
  static final _bundleId = RegExp(r'^([A-Za-z0-9.-]{1,255})?$');
  static final _testKey = RegExp(r'^(zi_test_[0-9a-f]{48})?$');
  static final _prodKey = RegExp(r'^(zi_prod_[0-9a-f]{48})?$');

  /// The server, e.g. `https://zi-console-api.zehnmind.com`.
  final Uri consoleUrl;

  /// The app's uuid in the console.
  final String appId;

  /// The Android package name; `''` when the app has no Android build.
  final String packageName;

  /// The iOS bundle id; `''` when the app has no iOS build.
  final String bundleId;

  /// For debug and profile builds; `''` when the console has no active one.
  final String testKey;

  /// For release builds; `''` when none is issued.
  final String prodKey;

  /// Reads and checks the file built into the app. Throws
  /// [ZiConfigException] when there is none or it isn't the console's.
  static Future<ZiAppFile> load(AssetBundle bundle) async {
    final String text;
    try {
      text = await bundle.loadString(assetPath, cache: false);
    } on Object {
      throw const ZiConfigException(
        'The app has no $assetPath. Run `$setupCommand` in the app\'s folder with the code from the '
        'console\'s Integration tab, or put the console\'s file there and list it under '
        '`flutter: assets:` in pubspec.yaml.',
      );
    }
    return parse(text);
  }

  /// Checks [text], the file's contents, by the schema's rules. Throws
  /// [ZiConfigException] for the first problem.
  static ZiAppFile parse(String text) {
    final Object? json;
    try {
      json = jsonDecode(text);
    } on FormatException {
      throw const ZiConfigException('$assetPath is not JSON. Get it again from the console.');
    }
    if (json is! Map) throw const ZiConfigException('$assetPath is not a JSON object. Get it again from the console.');
    final Map<Object?, Object?> map = json;
    final format = map['zi_config_format'];
    if (format != '3') {
      throw ZiConfigException(
        'zi_config_format is ${format ?? 'missing'}, but this SDK reads format "3". Run '
        '`$setupCommand` again, or download the file from the console\'s Integration tab.',
      );
    }
    final missing = [for (final key in _keys) if (map[key] is! String) key];
    if (missing.isNotEmpty) {
      throw ZiConfigException('The file has no ${missing.join(', ')}. Use the whole file from the console.');
    }
    String value(String key) => map[key] as String;

    final url = value('zi_console_url');
    if (url.length > 200 || !_consoleUrl.hasMatch(url)) {
      throw ZiConfigException(
        'zi_console_url "$url" is not a server address: https://host[:port] with no path, or '
        'http:// only for localhost, 127.0.0.1 or 10.0.2.2.',
      );
    }
    if (!_uuid.hasMatch(value('zi_app_id'))) {
      throw const ZiConfigException('zi_app_id must be the app\'s uuid from the console.');
    }
    if (!_packageName.hasMatch(value('zi_package_name'))) {
      throw const ZiConfigException('zi_package_name is not an Android package name.');
    }
    if (!_bundleId.hasMatch(value('zi_bundle_id'))) {
      throw const ZiConfigException('zi_bundle_id is not an iOS bundle id.');
    }
    // The keys stay out of the messages: those end up in bug reports.
    if (!_testKey.hasMatch(value('zi_test_key'))) {
      throw const ZiConfigException('zi_test_key must be empty or zi_test_ and 48 hex characters.');
    }
    if (!_prodKey.hasMatch(value('zi_prod_key'))) {
      throw const ZiConfigException('zi_prod_key must be empty or zi_prod_ and 48 hex characters.');
    }
    if (value('zi_package_name').isEmpty && value('zi_bundle_id').isEmpty) {
      throw const ZiConfigException('zi_package_name and zi_bundle_id are both empty. Set them in the console.');
    }
    return ZiAppFile._(
      consoleUrl: Uri.parse(url),
      appId: value('zi_app_id'),
      packageName: value('zi_package_name'),
      bundleId: value('zi_bundle_id'),
      testKey: value('zi_test_key'),
      prodKey: value('zi_prod_key'),
    );
  }

  /// The key this build sends as `X-ZI-App-Key`: the production key in a
  /// [release] build, else the test key. Throws [ZiConfigException] when that
  /// key is empty, when a production key would go over plain http, or when
  /// the running app ([platform] `android` or `ios`, its [runningId]: package
  /// name or bundle id) isn't the file's.
  String keyFor({required bool release, required String platform, required String runningId}) {
    final key = release ? prodKey : testKey;
    final name = release ? 'zi_prod_key' : 'zi_test_key';
    if (key.isEmpty) {
      throw ZiConfigException(
        '$name is empty, so ${release ? 'release' : 'debug and profile'} builds run without the assistant. '
        'Issue a ${release ? 'production' : 'test'} key in the console and get the file again.',
      );
    }
    if (release && consoleUrl.scheme != 'https') {
      throw ZiConfigException('A release build sends $name, but zi_console_url "$consoleUrl" isn\'t https.');
    }
    final (expected, field) = switch (platform) {
      'android' => (packageName, 'zi_package_name'),
      'ios' => (bundleId, 'zi_bundle_id'),
      _ => throw ZiConfigException('Zehn Intelligence runs on Android and iOS, not on $platform.'),
    };
    if (expected.isEmpty) {
      throw ZiConfigException('The file has no $field, so it can\'t run on $platform. Set it in the console.');
    }
    if (runningId != expected) {
      throw ZiConfigException(
        'This app is "$runningId", but the file is for "$expected" ($field). Use this app\'s file, '
        'or fix it in the console.',
      );
    }
    return key;
  }
}
