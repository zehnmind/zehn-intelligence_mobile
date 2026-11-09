import 'package:flutter_test/flutter_test.dart';
import 'package:zehn_intelligence/src/setup/dart_source.dart';
import 'package:zehn_intelligence/src/setup/dio_finder.dart';
import 'package:zehn_intelligence/src/setup/main_edit.dart';
import 'package:zehn_intelligence/src/setup/project_files.dart';

const sdk = "import 'package:zehn_intelligence/zehn_intelligence.dart';";

void main() {
  group('maskDart', () {
    test('blanks comments and strings, interpolations too, and keeps lines', () {
      const source = '''
// runApp(a)
final s = 'runApp(\${x({1: 2})}) }';
/* a /* nested */ runApp( */ final t = r"\\{";
runApp(App());
''';
      final masked = maskDart(source);
      expect(masked.length, source.length);
      expect('\n'.allMatches(masked).length, '\n'.allMatches(source).length);
      expect(RegExp(r'runApp\(').allMatches(masked).length, 1);
      expect(masked.contains('{'), isFalse);
    });
  });

  group('the start line', () {
    test('goes before runApp, after the app\'s own setup, with its indent', () {
      const source = '''
import 'package:flutter/material.dart';
import 'core/di/injection.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await init();
  final locale = LocaleController();

  runApp(MyApp(locale));
}
''';
      final edit = addStart(source, 'di<DioProvider>().createDio(di<IStorageSensitive>())');
      expect(edit.problem, isNull);
      expect(edit.notes, isEmpty);
      expect(edit.text, '''
import 'package:flutter/material.dart';
import 'core/di/injection.dart';
$sdk

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await init();
  final locale = LocaleController();

  await ZehnIntelligence.start(dio: () => di<DioProvider>().createDio(di<IStorageSensitive>()));
  runApp(MyApp(locale));
}
''');
      // Again: nothing more.
      expect(addStart(edit.text, 'x').text, edit.text);
    });

    test('makes a plain main async; no binding line (start() makes it)', () {
      const source = '''
import 'package:flutter/material.dart';

void main() {
  runApp(
    const App(),
  );
}
''';
      final edit = addStart(source, null);
      expect(edit.text, '''
import 'package:flutter/material.dart';
$sdk

Future<void> main() async {
  await ZehnIntelligence.start();
  runApp(
    const App(),
  );
}
''');
      expect(edit.notes, ['main() is async now: the line awaits the SDK']);
    });

    test('turns an arrow main into a body', () {
      const source = "import 'package:flutter/material.dart';\n\nvoid main() => runApp(const App());\n";
      final edit = addStart(source, 'getIt<Dio>()');
      expect(edit.text, '''
import 'package:flutter/material.dart';
$sdk

Future<void> main() async {
  await ZehnIntelligence.start(dio: () => getIt<Dio>());
  runApp(const App());
}
''');
    });

    test('the server\'s line goes before the runApp of its line, with the '
        'imports the file lacks', () {
      const source = '''
import 'package:flutter/material.dart';
import 'package:city_mall/core/di/injection.dart';

void main() async {
  await init();
  if (kDebugMode) {
    runApp(const DebugApp());
    return;
  }
  runApp(const App());
}
''';
      const line =
          'await ZehnIntelligence.start(dio: () => di<DioProvider>().createDio(di<IStorageSensitive>()));';
      final edit = addLine(source, line, atLine: 10, imports: [
        "import 'package:zehn_intelligence/zehn_intelligence.dart';",
        "import 'package:city_mall/core/di/injection.dart';",
        "import 'package:city_mall/core/network/dio_provider.dart';",
      ]);
      expect(edit.problem, isNull);
      expect(edit.text, '''
import 'package:flutter/material.dart';
import 'package:city_mall/core/di/injection.dart';
$sdk
import 'package:city_mall/core/network/dio_provider.dart';

void main() async {
  await init();
  if (kDebugMode) {
    runApp(const DebugApp());
    return;
  }
  $line
  runApp(const App());
}
''');
      // The line moved since the analysis: before the statement that holds
      // the first runApp(, in main's own body.
      final moved = addLine(source, line, atLine: 3);
      expect(moved.text, contains('  await init();\n  $line\n  if (kDebugMode) {'));
    });

    test('goes inside an async zone, and not into a sync closure', () {
      const zoned = '''
void main() {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    if (kDebugMode) {
      debugPrint('x');
    }
    runApp(const App());
  }, (e, s) {});
}
''';
      final edit = addStart(zoned, null);
      expect(edit.problem, isNull);
      expect(edit.text, contains('    }\n    await ZehnIntelligence.start();\n    runApp(const App());'));
      expect(edit.text, contains('void main() {'), reason: 'main stays as it was');

      const sync = '''
void main() {
  runZonedGuarded(() {
    runApp(const App());
  }, (e, s) {});
}
''';
      expect(addStart(sync, null).problem, contains('closure'));
    });

    test('ignores runApp in a comment and stops at a shared line', () {
      expect(addStart('// runApp(App());\n', null).problem, 'no runApp( here');
      expect(addStart('void main() async { runApp(App()); }\n', null).problem, contains('shares its line'));
    });

    test('comes out again, and the import with it', () {
      const source = '''
import 'package:flutter/material.dart';

Future<void> main() async {
  runApp(const App());
}
''';
      final added = addStart(source, 'getIt<Dio>()').text;
      expect(removeUnusedImport(removeStart(added)), source);
      // Wrapped by dart format, it comes out too.
      final wrapped = added.replaceFirst(
          'await ZehnIntelligence.start(dio: () => getIt<Dio>());',
          'await ZehnIntelligence.start(\n    dio: () => getIt<Dio>(),\n  );');
      expect(removeUnusedImport(removeStart(wrapped)), source);
    });
  });

  group("the app's Dio", () {
    test('registered in get_it', () {
      final found = findDio({
        'lib/di.dart': '''
final getIt = GetIt.instance;
void setup() {
  getIt.registerLazySingleton<Dio>(() => Dio(BaseOptions(baseUrl: 'x')));
}
''',
      });
      expect(found.first.expression, 'getIt<Dio>()');
      expect(found.first.rank, 1);
    });

    test("made by a provider's method, as the app's DI calls it", () {
      final found = findDio({
        'lib/core/network/dio_provider.dart': '''
class DioProvider {
  Dio createDio(IStorageSensitive storage, {Dio? refreshClient}) {
    Dio dio = Dio(BaseOptions());
    return dio;
  }
}
''',
        'lib/core/di/injection.dart': '''
final di = GetIt.instance;
Future<void> init() async {
  di.registerLazySingleton(() => DioProvider());
  di.registerLazySingleton<ApiClient>(
    () => ApiClientImpl(di<DioProvider>().createDio(di<IStorageSensitive>())),
  );
}
''',
      });
      expect(found.map((c) => c.expression), ['di<DioProvider>().createDio(di<IStorageSensitive>())']);
      expect(found.single.path, 'lib/core/di/injection.dart');
    });

    test('a global or a static one; never a private one', () {
      final found = findDio({
        'lib/api.dart': '''
final dio = Dio();
final _hidden = Dio();
class Api {
  static final Dio client = Dio();
}
''',
      });
      expect(found.map((c) => c.expression), ['dio', 'Api.client']);
    });

    test('where a name the analyzer misses is declared', () {
      final files = {'lib/core/di/injection.dart': 'final di = GetIt.instance;\n', 'lib/x.dart': 'class DioProvider {}\n'};
      expect(declaringFile(files, 'di'), 'lib/core/di/injection.dart');
      expect(declaringFile(files, 'DioProvider'), 'lib/x.dart');
      expect(declaringFile(files, 'Nope'), isNull);
    });
  });

  group('pubspec.yaml', () {
    test('a folder that holds the file is enough', () {
      const pubspec = 'name: app\nflutter:\n  uses-material-design: true\n  assets:\n    - assets/\n    - assets/images/\n';
      expect(addAsset(pubspec).text, pubspec);
    });

    test('the line goes after the last asset, or a list is made', () {
      const listed = 'flutter:\n  assets:\n    - images/a.png # logo\n\n  fonts:\n    - family: X\n';
      expect(addAsset(listed).text,
          'flutter:\n  assets:\n    - images/a.png # logo\n    - assets/zehn-intelligence.json\n\n  fonts:\n    - family: X\n');
      expect(removeAsset(addAsset(listed).text), listed);
      const none = 'name: app\nflutter:\n  uses-material-design: true\nflutter_icons:\n  x: y\n';
      expect(addAsset(none).text,
          'name: app\nflutter:\n  assets:\n    - assets/zehn-intelligence.json\n  uses-material-design: true\nflutter_icons:\n  x: y\n');
      expect(addAsset('name: app\n').text, 'name: app\n\nflutter:\n  assets:\n    - assets/zehn-intelligence.json\n');
      expect(addAsset('flutter:\n  assets: [a.png]\n').problem, isNotNull);
    });

    test('the dependency, the name and the app ids', () {
      const pubspec = 'name: city_mall\ndependencies:\n  zehn_intelligence:\n    path: ../sdk\n';
      expect(dependsOnSdk(pubspec), isTrue);
      expect(dependsOnSdk('name: x\ndependencies:\n  dio: ^5.0.0\n'), isFalse);
      expect(packageName(pubspec), 'city_mall');
      expect(androidIds('defaultConfig {\n applicationId = "uz.app"\n}\n'), ['uz.app']);
      expect(androidIds("applicationId 'uz.app.groovy'"), ['uz.app.groovy']);
      expect(
          iosIds('PRODUCT_BUNDLE_IDENTIFIER = uz.app;\nPRODUCT_BUNDLE_IDENTIFIER = uz.app.RunnerTests;\n'
              'PRODUCT_BUNDLE_IDENTIFIER = "\$(BASE).dev";\nPRODUCT_BUNDLE_IDENTIFIER = uz.app;\n'),
          ['uz.app']);
    });
  });

  group('Info.plist', () {
    test('the microphone\'s purpose string goes before the top </dict>, once', () {
      const plist = '<plist version="1.0">\n<dict>\n    <key>A</key>\n    <string>b</string>\n</dict>\n</plist>\n';
      final added = addMicrophoneUse(plist)!;
      expect(added, '<plist version="1.0">\n<dict>\n    <key>A</key>\n    <string>b</string>\n'
          '    <key>NSMicrophoneUsageDescription</key>\n    <string>$microphoneUse</string>\n</dict>\n</plist>\n');
      expect(addMicrophoneUse(added), isNull);
      expect(addMicrophoneUse('not a plist'), isNull);
    });
  });
}
