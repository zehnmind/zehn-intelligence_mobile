import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zehn_intelligence/src/setup/setup.dart';
import 'package:zehn_intelligence/src/setup/undo.dart';

const config = {
  'zi_config_format': '3',
  'zi_console_url': 'https://zi-console-api.zehnmind.com',
  'zi_app_id': 'a3d1f6e2-5c47-4b8e-9f10-2d6c8b7a4e91',
  'zi_package_name': 'uz.zehnmind.tcmall',
  'zi_bundle_id': '',
  'zi_test_key': 'zi_test_9b2f4c7a1e3d5b8f0a6c2e4d7f1b3a5c8e0d2f4a6b8c1e3d',
  'zi_prod_key': '',
};

const dioLine = 'await ZehnIntelligence.start(dio: () => di<DioProvider>().createDio(di<IStorageSensitive>()));';

/// The console's analysis of the app (`integration` of `POST /api/v1/setup`).
const integration = {
  'file': 'lib/main.dart',
  'line': 7,
  'function': 'main',
  'before': 'runApp(',
  'code': dioLine,
  'imports': [
    "import 'package:zehn_intelligence/zehn_intelligence.dart';",
    "import 'package:city_mall/core/network/dio_provider.dart';",
  ],
  'main_async': false,
  'sure': true,
  'notes': ['separate_dio', 'make_main_async'],
  'dio': {'kind': 'made', 'file': 'lib/core/di/injection.dart', 'line': 5},
};

const mainDart = '''
import 'package:city_mall/core/di/injection.dart';
import 'package:flutter/material.dart';

void main() {
  init();

  runApp(MyApp());
}
''';

const injection = '''
final di = GetIt.instance;
Future<void> init() async {
  di.registerLazySingleton(() => DioProvider());
  di.registerLazySingleton<ApiClient>(
    () => ApiClientImpl(di<DioProvider>().createDio(di<IStorageSensitive>())),
  );
}
''';

const dioProvider = '''
class DioProvider {
  Dio createDio(IStorageSensitive storage) => Dio();
}
''';

const layout = '''
import 'package:flutter/material.dart';

class LayoutPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: const Text('x'),
      bottomNavigationBar: const NavBar(),
    );
  }
}
''';

const infoPlist = '''
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleName</key>
	<string>city_mall</string>
</dict>
</plist>
''';

const pubspec = '''
name: city_mall
dependencies:
  flutter:
    sdk: flutter
  zehn_intelligence:
    path: ../sdk

flutter:
  uses-material-design: true
  assets:
    - images/logo.png
''';

void main() {
  late Directory root;
  late List<String> codes;
  late Map<String, Object?>? analysis;

  String read(String path) => File('${root.path}/$path').readAsStringSync();
  bool exists(String path) => File('${root.path}/$path').existsSync();

  void write(String path, String text) {
    File('${root.path}/$path')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(text);
  }

  setUp(() {
    root = Directory.systemTemp.createTempSync('zi_setup_');
    codes = [];
    analysis = integration;
    write('pubspec.yaml', pubspec);
    write('lib/main.dart', mainDart);
    write('lib/core/di/injection.dart', injection);
    write('lib/core/network/dio_provider.dart', dioProvider);
    write('lib/features/layout/presentation/pages/layout_page.dart', layout);
    write('android/app/build.gradle.kts', 'android {\n  defaultConfig {\n    applicationId = "uz.zehnmind.tcmall"\n  }\n}\n');
    write('ios/Runner.xcodeproj/project.pbxproj', 'PRODUCT_BUNDLE_IDENTIFIER = uz.zehnmind.tcmall;\n');
    write('ios/Runner/Info.plist', infoPlist);
  });

  tearDown(() => root.deleteSync(recursive: true));

  Future<Map<String, Object?>> exchange(String server, String code) async {
    codes.add('$server $code');
    return {
      'file_name': 'zehn-intelligence.json',
      'file': '${const JsonEncoder.withIndent('  ').convert(config)}\n',
      'app': {'name': 'TCM', 'package_name': 'uz.zehnmind.tcmall', 'bundle_id': ''},
      'track': 'test',
      'spec_version': '1.2.0',
      'needs_code': ['auth.get_google_token'],
      'integration': analysis,
    };
  }

  Future<(int, String)> run(List<String> args, {List<String?> answers = const [], Analyze? analyze}) async {
    final out = StringBuffer();
    final queue = [...answers];
    final code = await runSetup(
      args,
      root: root.path,
      out: out,
      ask: (question) {
        out.write(question);
        return queue.isEmpty ? null : queue.removeAt(0);
      },
      exchange: exchange,
      analyze: analyze ?? (root, files) async => const [],
    );
    return (code, out.toString());
  }

  test('one command: the format 3 file, its assets line, and the server\'s line before runApp with the '
      'imports it needs; no button anywhere; twice changes nothing more', () async {
    final (code, out) = await run(['K7Q2-9XMD', '--server', 'http://localhost:8040']);
    expect(code, 0, reason: out);
    expect(codes, ['http://localhost:8040 K7Q2-9XMD']);
    expect(jsonDecode(read('assets/zehn-intelligence.json')), config);
    expect(read('pubspec.yaml'), contains('    - images/logo.png\n    - assets/zehn-intelligence.json\n'));
    expect(read('lib/main.dart'), '''
import 'package:city_mall/core/di/injection.dart';
import 'package:flutter/material.dart';
import 'package:zehn_intelligence/zehn_intelligence.dart';
import 'package:city_mall/core/network/dio_provider.dart';

Future<void> main() async {
  init();

  $dioLine
  runApp(MyApp());
}
''');
    expect(read('lib/features/layout/presentation/pages/layout_page.dart'), layout, reason: 'no button edit');
    expect(read('ios/Runner/Info.plist'), contains('''
	<string>city_mall</string>
	<key>NSMicrophoneUsageDescription</key>
	<string>Hold the microphone button to ask the assistant by voice.</string>
</dict>
'''));
    expect(out, contains("made the app's own way (lib/core/di/injection.dart:5)"));
    expect(out, contains('second Dio'));
    expect(out, contains('zi_prod_key is empty: release builds run without the assistant'));
    expect(out, contains('! The console has no iOS bundle id (the app is uz.zehnmind.tcmall)'));
    expect(out, contains('1 tools have no request yet'));
    expect(out, contains('main() is async now'));
    expect(exists(SetupRecord.path), isTrue);

    final main = read('lib/main.dart');
    final (again, out2) = await run(['K7Q2-9XMD']);
    expect(again, 0, reason: out2);
    expect(out2, contains('lib/main.dart starts the SDK already'));
    expect(out2, contains('assets/zehn-intelligence.json (replaced)'));
    expect(out2, contains('pubspec.yaml lists the file already'));
    expect(read('lib/main.dart'), main);
  });

  test('--remove puts every file back exactly: the line, its imports, main\'s header, the assets line, '
      'the file and the record', () async {
    await run(['K7Q2-9XMD']);
    await run(['K7Q2-9XMD']); // twice: still back to the first run's start
    final (code, out) = await run(['--remove']);
    expect(code, 0, reason: out);
    expect(read('lib/main.dart'), mainDart);
    expect(read('pubspec.yaml'), pubspec);
    expect(read('ios/Runner/Info.plist'), infoPlist);
    expect(exists('assets/zehn-intelligence.json'), isFalse);
    expect(exists(SetupRecord.path), isFalse);
    expect(Directory('${root.path}/assets').existsSync(), isFalse, reason: 'the folder it made');
    expect(Directory('${root.path}/${SetupRecord.folder}').existsSync(), isFalse);
    expect(out, isNot(contains('stays async')));
    expect((await run(['--remove'])).$2, contains('Nothing to take out.'));
  });

  test('--remove on a file edited since: what the command wrote goes, the developer\'s own lines stay, and '
      'a line moved is named', () async {
    await run(['K7Q2-9XMD']);
    write('lib/main.dart', read('lib/main.dart').replaceFirst('  init();\n', '  init();\n  setUpLogging();\n'));
    write('pubspec.yaml', '${read('pubspec.yaml')}\nflutter_icons:\n  image_path: icon.png\n');
    final (code, out) = await run(['--remove']);
    expect(code, 0, reason: out);
    expect(read('lib/main.dart'), mainDart.replaceFirst('  init();\n', '  init();\n  setUpLogging();\n'));
    expect(read('pubspec.yaml'), '$pubspec\nflutter_icons:\n  image_path: icon.png\n');

    // A line of the command's that the developer changed is left, and named.
    await run(['K7Q2-9XMD']);
    write('lib/main.dart', read('lib/main.dart').replaceFirst(dioLine, 'await ZehnIntelligence.start();'));
    final (_, out2) = await run(['--remove']);
    expect(out2, contains('! lib/main.dart was edited since: take these out by hand:'));
    expect(read('lib/main.dart'), isNot(contains("import 'package:zehn_intelligence/zehn_intelligence.dart';\n"
        "import 'package:city_mall/core/network/dio_provider.dart';")));
  });

  test('--remove without the record (.dart_tool cleaned) takes out the lines it knows', () async {
    await run(['K7Q2-9XMD']);
    File('${root.path}/${SetupRecord.path}').deleteSync();
    final (code, out) = await run(['--remove']);
    expect(code, 0, reason: out);
    expect(read('lib/main.dart'), isNot(contains('ZehnIntelligence')));
    expect(read('lib/main.dart'), contains('Future<void> main() async {'));
    expect(out, contains('main() stays async'));
    expect(read('pubspec.yaml'), pubspec);
  });

  test('without an analysis, or one not sure of the Dio: the Dio found here, or the developer\'s', () async {
    analysis = null;
    final (code, out) = await run(['K7Q2-9XMD', '--dry-run']);
    expect(code, 0, reason: out);
    expect(out, contains('The console has no analysis of this app yet'));
    expect(out, contains('+ $dioLine'));

    analysis = {...integration, 'sure': false, 'code': "await ZehnIntelligence.start(dio: () => <your app's Dio>);"};
    final (_, out2) = await run(['K7Q2-9XMD', '--dry-run'], answers: ['getIt<Dio>()']);
    expect(out2, contains("isn't sure of the app's Dio"));
    expect(out2, contains('+ await ZehnIntelligence.start(dio: () => getIt<Dio>());'));
    expect(read('lib/main.dart'), mainDart, reason: '--dry-run');
  });

  test('no Dio found and none given: the line is printed for the developer, nothing is put in', () async {
    analysis = {...integration, 'sure': false, 'code': "await ZehnIntelligence.start(dio: () => <your app's Dio>);"};
    write('lib/core/di/injection.dart', 'void init() {}\n');
    write('lib/core/network/dio_provider.dart', 'class Nothing {}\n');
    final (code, out) = await run(['K7Q2-9XMD'], answers: ['']);
    expect(code, 0, reason: out);
    expect(read('lib/main.dart'), mainDart);
    expect(out, contains("By hand:\n  In lib/main.dart, before runApp: await ZehnIntelligence.start(dio: () => <your app's Dio>);"));
  });

  test('--dio wins over the analysis\'s Dio', () async {
    final (code, out) = await run(['K7Q2-9XMD', '--dio', 'getIt<Dio>()']);
    expect(code, 0, reason: out);
    expect(read('lib/main.dart'), contains('  await ZehnIntelligence.start(dio: () => getIt<Dio>());\n  runApp(MyApp());'));
    expect(read('lib/main.dart'), isNot(contains('dio_provider.dart')));
  });

  test('the analysis\'s runApp line moved: the file\'s runApp is found again', () async {
    write('lib/main.dart', '// a comment line added since\n$mainDart');
    final (code, out) = await run(['K7Q2-9XMD']);
    expect(code, 0, reason: out);
    expect(read('lib/main.dart'), contains('  $dioLine\n  runApp(MyApp());'));
  });

  test('a downloaded file works without a code; an older format is refused', () async {
    write('downloaded.json', jsonEncode(config));
    final (code, out) = await run(['--file', '${root.path}/downloaded.json']);
    expect(code, 0, reason: out);
    expect(codes, isEmpty);
    expect(read('lib/main.dart'), contains(dioLine), reason: 'the Dio found here');

    write('old.json', jsonEncode({...config, 'zi_config_format': '2', 'tools': []}));
    final (old, out2) = await run(['--file', '${root.path}/old.json']);
    expect(old, 1);
    expect(out2, contains('format 2, for older SDK builds'));
  });

  test('another app id stops it before anything is written', () async {
    write('android/app/build.gradle.kts', 'applicationId = "uz.other.app"\n');
    final (code, out) = await run(['K7Q2-9XMD']);
    expect(code, 1);
    expect(out, contains('Android: the app is uz.other.app, the file is for uz.zehnmind.tcmall'));
    expect(read('lib/main.dart'), mainDart);
    expect(exists('assets/zehn-intelligence.json'), isFalse);
    expect(exists(SetupRecord.path), isFalse);
  });

  test('--dry-run writes nothing', () async {
    final (code, out) = await run(['K7Q2-9XMD', '--dry-run']);
    expect(code, 0, reason: out);
    expect(out, contains('+ $dioLine'));
    expect(read('lib/main.dart'), mainDart);
    expect(exists('assets/zehn-intelligence.json'), isFalse);
    expect(exists(SetupRecord.path), isFalse);
  });

  test('an import the analyzer asks for is added; an error left is reported', () async {
    analysis = {...integration, 'imports': <String>[]};
    var calls = 0;
    Future<List<AnalyzerError>?> analyze(String root, List<String> files) async {
      calls++;
      if (calls == 1) {
        return const [
          AnalyzerError('lib/main.dart', 8, 'NON_TYPE_AS_TYPE_ARGUMENT',
              "The name 'DioProvider' isn't a type, so it can't be used as a type argument."),
          AnalyzerError('lib/main.dart', 2, 'URI_DOES_NOT_EXIST', 'the app\'s own error, not ours'),
        ];
      }
      return const [AnalyzerError('lib/main.dart', 9, 'UNDEFINED_IDENTIFIER', "Undefined name 'nope'.")];
    }

    final (code, out) = await run(['K7Q2-9XMD'], analyze: analyze);
    expect(read('lib/main.dart'), contains("import 'package:city_mall/core/network/dio_provider.dart';"));
    expect(out, contains("+ import 'package:city_mall/core/network/dio_provider.dart';"));
    expect(code, 1);
    expect(out, contains("✗ lib/main.dart:9: Undefined name 'nope'."));
    expect(out, isNot(contains('not ours')));
    // The import the analyzer asked for comes out with --remove too.
    await run(['--remove']);
    expect(read('lib/main.dart'), mainDart);
  });

  test('a missing dependency or a refused code says what to do', () async {
    write('pubspec.yaml', 'name: x\n');
    expect((await run(['K7Q2-9XMD'])).$2, contains('flutter pub add'));
    write('pubspec.yaml', pubspec);
    final out = StringBuffer();
    final code = await runSetup(['BAD'], root: root.path, out: out, ask: (_) => null,
        exchange: (_, _) async => throw const SetupFailure('The console refused the code: expired'),
        analyze: (_, _) async => const []);
    expect(code, 1);
    expect(out.toString(), contains('✗ The console refused the code: expired'));
  });

  test('the options the button needed are gone', () async {
    for (final option in ['--button', '--no-button', '--no-dio']) {
      final (code, out) = await run(['K7Q2-9XMD', option]);
      expect(code, 1);
      expect(out, contains('unknown option $option'));
    }
  });
}
