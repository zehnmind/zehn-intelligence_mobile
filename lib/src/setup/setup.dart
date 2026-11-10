// `dart run zehn_intelligence:setup <code>`: everything the app's developer
// would otherwise do by hand (docs/sdk.md §1.1), in one command, in the app's
// folder:
//
// 1. trades the console's one-time code (`POST /api/v1/setup`) for the app's
//    file (format 3) and the line the console's analysis wrote for it;
// 2. checks the file's package name and bundle id against android/ and ios/,
//    and writes it to assets/zehn-intelligence.json;
// 3. lists the file under `flutter: assets:` in pubspec.yaml, when no entry
//    covers it, and adds NSMicrophoneUsageDescription to ios/Runner/Info.plist
//    when it has none (iOS ends an app that records without it);
// 4. adds the analysis's line (`await ZehnIntelligence.start(dio: () => …);`)
//    before the `runApp(` of its file, the imports it needs, and makes `main`
//    async when it isn't. Without an analysis, or one that isn't sure of the
//    app's Dio, it looks for the Dio itself and asks, or prints the line for
//    the developer to finish;
// 5. runs `dart analyze` on what it changed.
//
// It only adds lines: the app's own lines stay, except `main` becoming async.
// What it changed is kept in .dart_tool/zehn_intelligence/setup.json, so
// `--remove` puts every file back exactly as it was (or, for a file edited
// since, takes out what the command wrote and names what it can't find).
//
// Pure Dart (dart:io), no Flutter: `dart run` compiles it on the developer's
// machine. Not exported from the package; an app never imports it.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'dart_source.dart' show withImport;
import 'dio_finder.dart';
import 'main_edit.dart';
import 'project_files.dart';
import 'undo.dart';

/// The console, whose nginx serves the console API (`/api`). Not the SDK's
/// host (`zi_console_url`, `zi-console-api.zehnmind.com`): that one publishes
/// only `/v1` and `/health`.
const defaultServer = 'https://zi-console.zehnmind.com';

const usage = '''
Adds Zehn Intelligence to this Flutter app: the app's file and one line in main().
Run it in the app's folder, after `flutter pub add zehn_intelligence`.

  dart run zehn_intelligence:setup <code> [options]

<code> is the one-time code from the console's Integration tab.

  --server <url>     the console (default $defaultServer)
  --file <path>      use a downloaded zehn-intelligence.json instead of a code
  --dio <expr>       the app's Dio, as main() can reach it (e.g. "getIt<Dio>()")
  --dry-run          show what would change, write nothing
  --skip-id-check    go on when the app's ids aren't the file's
  --no-analyze       don't run `dart analyze` afterwards
  --remove           put back every file this command changed
''';

class SetupFailure implements Exception {
  const SetupFailure(this.message);
  final String message;
  @override
  String toString() => message;
}

class AnalyzerError {
  const AnalyzerError(this.file, this.line, this.code, this.message);
  final String file;
  final int line;
  final String code;
  final String message;
}

/// Sends the code to the console API; the answer of `POST /api/v1/setup`.
typedef Exchange = Future<Map<String, Object?>> Function(String server, String code);

/// The analyzer's errors in [files] (relative to [root]); null when it
/// couldn't run.
typedef Analyze = Future<List<AnalyzerError>?> Function(String root, List<String> files);

/// Asks the developer; null when nobody can answer (no terminal).
typedef Ask = String? Function(String question);

class SetupOptions {
  String? code;
  String server = defaultServer;
  String? file;
  String? dio;
  bool dryRun = false;
  bool skipIdCheck = false;
  bool analyze = true;
  bool remove = false;
  bool help = false;

  static SetupOptions parse(List<String> args) {
    final o = SetupOptions();
    for (var i = 0; i < args.length; i++) {
      final a = args[i];
      String value() {
        if (i + 1 >= args.length) throw SetupFailure('$a needs a value');
        return args[++i];
      }

      switch (a) {
        case '--server':
          o.server = value();
        case '--file':
          o.file = value();
        case '--dio':
          o.dio = value();
        case '--dry-run':
          o.dryRun = true;
        case '--skip-id-check':
          o.skipIdCheck = true;
        case '--no-analyze':
          o.analyze = false;
        case '--remove':
          o.remove = true;
        case '-h' || '--help':
          o.help = true;
        default:
          if (a.startsWith('-')) throw SetupFailure('unknown option $a');
          if (o.code != null) throw const SetupFailure('one code only');
          o.code = a;
      }
    }
    return o;
  }
}

/// Runs the command in [root]; the exit code.
Future<int> runSetup(
  List<String> args, {
  String? root,
  StringSink? out,
  Ask? ask,
  Exchange? exchange,
  Analyze? analyze,
}) async {
  final o = out ?? stdout;
  try {
    final options = SetupOptions.parse(args);
    if (options.help) {
      o.write(usage);
      return 0;
    }
    final setup = _Setup(
      Directory(root ?? Directory.current.path),
      options,
      o,
      ask ?? _askTerminal,
      exchange ?? exchangeCode,
      analyze ?? dartAnalyze,
    );
    return options.remove ? await setup.remove() : await setup.run();
  } on SetupFailure catch (failure) {
    o.writeln('✗ ${failure.message}');
    return 1;
  }
}

String? _askTerminal(String question) {
  if (!stdin.hasTerminal) return null;
  stdout.write(question);
  return stdin.readLineSync() ?? '';
}

class _Setup {
  _Setup(this.root, this.options, this.out, this.ask, this.exchange, this.analyze);

  final Directory root;
  final SetupOptions options;
  final StringSink out;
  final Ask ask;
  final Exchange exchange;
  final Analyze analyze;

  /// path (relative) → new text; null deletes the file.
  final changes = <String, String?>{};
  final before = <String, String?>{};

  /// The folders this run made (relative), for `--remove`.
  final madeDirs = <String>{};

  File _file(String path) => File('${root.path}/$path');

  String? _read(String path) {
    final f = _file(path);
    return f.existsSync() ? f.readAsStringSync() : null;
  }

  void _change(String path, String? text) {
    before.putIfAbsent(path, () => _read(path));
    changes[path] = text;
  }

  /// The app's own Dart files under lib/, path → source; not generated ones,
  /// not the folder an older integration wrote.
  Map<String, String> _libFiles() {
    final lib = Directory('${root.path}/lib');
    if (!lib.existsSync()) return {};
    final files = <String, String>{};
    for (final entity in lib.listSync(recursive: true, followLinks: false)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final path = entity.path.substring(root.path.length + 1).replaceAll(r'\', '/');
      if (path.startsWith('lib/zehn_intelligence/') ||
          RegExp(r'\.(g|freezed|gr|config|mocks)\.dart$').hasMatch(path)) {
        continue;
      }
      files[path] = entity.readAsStringSync();
    }
    final sorted = files.keys.toList()..sort();
    return {for (final k in sorted) k: files[k]!};
  }

  String _pubspec() {
    final pubspec = _read('pubspec.yaml');
    if (pubspec == null) {
      throw const SetupFailure("No pubspec.yaml here: run the command in the app's folder");
    }
    return pubspec;
  }

  Future<int> run() async {
    final pubspec = _pubspec();
    if (!dependsOnSdk(pubspec)) {
      throw const SetupFailure(
          "pubspec.yaml doesn't depend on zehn_intelligence: run the console's `flutter pub add` first");
    }
    final setup = await _setupFile();
    final appName = setup.appName.isEmpty ? '' : '"${setup.appName}" ';
    final version = setup.specVersion == null ? '' : ', version ${setup.specVersion} published';
    out.writeln('✓ App $appName(${setup.packageName.isEmpty ? setup.bundleId : setup.packageName})$version');

    if (!_checkIds(setup)) return 1;

    // 1. The file.
    final existed = _read(assetPath);
    _change(assetPath, setup.file);
    out.writeln('✓ $assetPath${existed == null ? '' : ' (replaced)'}: both tracks\' keys, no spec version');
    for (final (key, builds) in [('zi_test_key', 'debug and profile'), ('zi_prod_key', 'release')]) {
      if ('${setup.config[key] ?? ''}'.isEmpty) {
        out.writeln('! $key is empty: $builds builds run without the assistant until the console issues one');
      }
    }

    // 2. pubspec.yaml.
    final listed = addAsset(pubspec);
    if (listed.problem != null) {
      out.writeln('! ${listed.problem}');
    } else if (listed.text == pubspec) {
      out.writeln('✓ pubspec.yaml lists the file already');
    } else {
      _change('pubspec.yaml', listed.text);
      out.writeln('✓ pubspec.yaml: + - $assetPath');
    }

    // 3. The microphone's purpose string on iOS, which iOS needs before the
    // SDK may record a spoken question.
    final plist = _read(infoPlistPath);
    if (plist != null) {
      final withMicrophone = addMicrophoneUse(plist);
      if (withMicrophone != null) {
        _change(infoPlistPath, withMicrophone);
        out.writeln('✓ $infoPlistPath: + NSMicrophoneUsageDescription (for voice questions)');
      }
    }

    // 4. The line in main().
    final files = _libFiles();
    final manual = <String>[];
    _placeLine(setup.integration, files, manual);

    if (options.dryRun) {
      out.writeln('\nNothing was written (--dry-run).');
      _printManual(manual);
      return 0;
    }
    _write();
    var ok = true;
    if (options.analyze) ok = await _analyze(files);
    _summary(setup, manual);
    return ok ? 0 : 1;
  }

  /// The start line before `runApp(`: the analysis's when it is sure of the
  /// app's Dio, else one with the Dio found here or given (`--dio`); with
  /// none, the line goes to [manual] for the developer to finish.
  void _placeLine(Integration? integration, Map<String, String> files, List<String> manual) {
    final mains = files.keys.where((p) => callsRunApp(files[p]!)).toList();
    final started = mains.where((p) => startsSdk(files[p]!)).toList();
    for (final p in started) {
      out.writeln('✓ $p starts the SDK already');
    }
    if (started.isNotEmpty) return;

    // Where: the analysis's file (its runApp line, or the file's first one
    // if the line moved), else every file that calls runApp.
    var targets = mains;
    int? atLine;
    final file = integration?.file;
    if (file != null && files.containsKey(file) && callsRunApp(files[file]!)) {
      targets = [file];
      atLine = integration!.line;
    } else if (file != null && mains.isNotEmpty) {
      out.writeln("! The console's analysis named $file, which has no runApp( now: using ${mains.join(', ')}");
    }
    if (targets.isEmpty) {
      manual.add('Before runApp, in main(): ${integration?.code ?? startLine("<your app's Dio>")}');
      out.writeln('! No runApp( found under lib/');
      return;
    }

    // What: the analysis's line, the developer's Dio, or the one found here.
    String line;
    var imports = const <String>[];
    if (options.dio != null) {
      line = startLine(options.dio!.trim());
    } else if (integration != null && integration.sure && !integration.code.contains("<your app's Dio>")) {
      line = integration.code;
      imports = integration.imports;
      out.writeln("✓ The console's analysis: the app's Dio is ${integration.dioWhere}");
      if (integration.notes.contains('separate_dio')) {
        out.writeln("! The line makes a second Dio the app's own way (the app registers none to share). "
            'If its token refresh is not shared between Dios, two refreshes at once may sign the user out.');
      }
    } else {
      if (integration == null) {
        out.writeln("? The console has no analysis of this app yet: looking for the app's Dio here");
      } else {
        out.writeln("? The console's analysis isn't sure of the app's Dio: looking for it here");
      }
      final dio = _chooseDio(files);
      if (dio == null) {
        manual.add('In ${targets.first}, before runApp: ${startLine("<your app's Dio>")}  '
            "(the app's Dio, as main() can reach it)");
        return;
      }
      line = startLine(dio);
    }

    for (final p in targets) {
      final edit = addLine(files[p]!, line, atLine: p == file ? atLine : null, imports: imports);
      if (edit.problem != null) {
        out.writeln('! $p: ${edit.problem}');
        manual.add('In $p, before runApp: $line');
        continue;
      }
      _change(p, edit.text);
      files[p] = edit.text;
      out.writeln('✓ $p: + $line');
      for (final note in edit.notes) {
        out.writeln('  ($note)');
      }
    }
  }

  Future<_SetupFile> _setupFile() async {
    if (options.file != null) {
      final text = File(options.file!).existsSync() ? File(options.file!).readAsStringSync() : null;
      if (text == null) throw SetupFailure('No file at ${options.file}');
      return _SetupFile.fromConfig(text);
    }
    final code = options.code;
    if (code == null) {
      throw const SetupFailure('Give the code from the console: dart run zehn_intelligence:setup <code>');
    }
    final answer = await exchange(options.server, code);
    return _SetupFile.fromAnswer(answer);
  }

  bool _checkIds(_SetupFile setup) {
    final problems = <String>[];
    final gradle = _read('android/app/build.gradle') ?? _read('android/app/build.gradle.kts');
    if (gradle != null && setup.packageName.isNotEmpty) {
      final ids = androidIds(gradle);
      if (ids.isEmpty) {
        out.writeln("! Couldn't read android's applicationId: the SDK starts only in ${setup.packageName}");
      } else if (ids.contains(setup.packageName)) {
        out.writeln('✓ Android id ${setup.packageName} matches');
      } else {
        problems.add('Android: the app is ${ids.join(', ')}, the file is for ${setup.packageName}');
      }
    }
    final pbxproj = _read('ios/Runner.xcodeproj/project.pbxproj');
    if (pbxproj != null) {
      final ids = iosIds(pbxproj);
      if (setup.bundleId.isEmpty) {
        out.writeln('! The console has no iOS bundle id${ids.isEmpty ? '' : ' (the app is ${ids.first})'}: '
            'on iOS the assistant stays off. Add it in the console, then run the command again');
      } else if (ids.isEmpty || ids.contains(setup.bundleId)) {
        out.writeln('✓ iOS bundle id ${setup.bundleId}${ids.isEmpty ? '' : ' matches'}');
      } else {
        problems.add('iOS: the app is ${ids.join(', ')}, the file is for ${setup.bundleId}');
      }
    }
    if (problems.isEmpty) return true;
    for (final p in problems) {
      out.writeln('✗ $p');
    }
    if (options.skipIdCheck) {
      out.writeln('  Going on (--skip-id-check): the SDK will not start in an app with another id');
      return true;
    }
    out.writeln('  The SDK would not start. Fix the id in the console (or in the app), '
        'or run again with --skip-id-check. Nothing was changed.');
    return false;
  }

  String? _chooseDio(Map<String, String> files) {
    final candidates = findDio(files);
    final main = files.entries.where((e) => callsRunApp(e.value)).map((e) => e.value).join('\n');
    // A lookup main() already uses comes first.
    candidates.sort((a, b) {
      int uses(DioCandidate c) => main.contains(c.expression.split(RegExp(r'[<.(]')).first) ? 0 : 1;
      final byUse = uses(a).compareTo(uses(b));
      return byUse != 0 ? byUse : a.rank.compareTo(b.rank);
    });
    final shown = candidates.take(5).toList();
    if (shown.isEmpty) {
      out.writeln("? The app's Dio: not found in lib/.");
      final typed = ask('  Type the Dart expression main() can use for it (Enter: none): ');
      final value = typed?.trim() ?? '';
      if (value.isEmpty) {
        out.writeln('! No Dio: the line is yours to finish (or run again with --dio "<expr>")');
        return null;
      }
      return value;
    }
    out.writeln("? The app's Dio:");
    for (var i = 0; i < shown.length; i++) {
      out.writeln('    ${i + 1}) ${shown[i]}');
    }
    final typed = ask('  Which one? [Enter = 1, n = none (finish the line by hand), or type an expression]: ');
    if (typed == null) {
      out.writeln('  → 1 (no terminal to ask)');
      return shown.first.expression;
    }
    final value = typed.trim();
    if (value.isEmpty) return shown.first.expression;
    if (value.toLowerCase() == 'n') return null;
    final index = int.tryParse(value);
    if (index != null && index >= 1 && index <= shown.length) return shown[index - 1].expression;
    return value;
  }

  void _write({bool keepRecord = true}) {
    changes.forEach((path, text) {
      final f = _file(path);
      if (text == null) {
        if (f.existsSync()) f.deleteSync();
      } else {
        // The folders made for it, outermost first (`assets/`).
        final parts = path.split('/')..removeLast();
        for (var i = 1; i <= parts.length; i++) {
          final dir = parts.take(i).join('/');
          if (!Directory('${root.path}/$dir').existsSync()) madeDirs.add(dir);
        }
        f.parent.createSync(recursive: true);
        f.writeAsStringSync(text);
      }
    });
    if (keepRecord) _keepRecord();
  }

  /// What this run changed, on top of what earlier runs did: each file's
  /// text before the first run and after this one, for `--remove`.
  void _keepRecord() {
    final record = _readRecord() ?? SetupRecord({});
    changes.forEach((path, text) {
      if (text == null) return;
      final first = record.files[path];
      record.files[path] = (before: first == null ? before[path] : first.before, after: text);
    });
    record.dirs.addAll(madeDirs.where((dir) => !dir.startsWith('.dart_tool')));
    final f = _file(SetupRecord.path);
    f.parent.createSync(recursive: true);
    f.writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(record.toJson())}\n');
  }

  SetupRecord? _readRecord() {
    final text = _read(SetupRecord.path);
    if (text == null) return null;
    try {
      return SetupRecord.fromJson(jsonDecode(text));
    } on FormatException {
      return null;
    }
  }

  /// `dart analyze` on the changed Dart files; an import the start line needs
  /// is added once. Whether no error is left in a line the command wrote.
  Future<bool> _analyze(Map<String, String> files) async {
    final dart = changes.keys.where((p) => p.endsWith('.dart') && changes[p] != null).toList();
    if (dart.isEmpty) return true;
    out.writeln('… dart analyze ${dart.join(' ')}');
    var errors = await analyze(root.path, dart);
    if (errors == null) {
      out.writeln("! dart analyze couldn't run: build the app to check the lines");
      return true;
    }
    errors = _ours(errors);
    if (errors.isNotEmpty && _addImports(errors, files)) {
      _write();
      errors = _ours(await analyze(root.path, dart) ?? const []);
    }
    if (errors.isEmpty) {
      out.writeln('✓ dart analyze: no errors in the lines added');
      return true;
    }
    for (final e in errors) {
      out.writeln('✗ ${e.file}:${e.line}: ${e.message}');
    }
    out.writeln('  The lines are in place: fix them (for the Dio, run again with --dio "<expr>"), '
        'or take them out with: dart run zehn_intelligence:setup --remove');
    return false;
  }

  /// The errors in lines the command added or changed.
  List<AnalyzerError> _ours(List<AnalyzerError> errors) =>
      errors.where((e) => _addedLines(e.file).contains(e.line)).toList();

  Set<int> _addedLines(String path) {
    final now = changes[path];
    if (now == null) return const {};
    final old = <String, int>{};
    for (final line in (before[path] ?? '').split('\n')) {
      old[line] = (old[line] ?? 0) + 1;
    }
    final added = <int>{};
    final lines = now.split('\n');
    for (var i = 0; i < lines.length; i++) {
      final left = old[lines[i]] ?? 0;
      if (left > 0) {
        old[lines[i]] = left - 1;
      } else {
        added.add(i + 1);
      }
    }
    return added;
  }

  /// Imports for the names the analyzer couldn't find in the added lines.
  bool _addImports(List<AnalyzerError> errors, Map<String, String> files) {
    const missing = {
      'UNDEFINED_IDENTIFIER',
      'UNDEFINED_CLASS',
      'NON_TYPE_AS_TYPE_ARGUMENT',
      'UNDEFINED_FUNCTION',
      'UNDEFINED_METHOD',
      'CREATION_WITH_NON_TYPE',
    };
    final package = packageName(_pubspec());
    var added = false;
    for (final e in errors) {
      if (!missing.contains(e.code)) continue;
      final name = RegExp(r"'([A-Za-z_$][\w$]*)'").firstMatch(e.message)?.group(1);
      if (name == null) continue;
      String? uri;
      if (name == 'WidgetsFlutterBinding') {
        uri = 'package:flutter/widgets.dart';
      } else {
        final declared = declaringFile(files, name);
        if (declared != null && package != null) uri = 'package:$package/${declared.substring(4)}';
      }
      final text = changes[e.file];
      if (uri == null || text == null) continue;
      final withIt = withImport(text, uri);
      if (withIt != text) {
        changes[e.file] = withIt;
        out.writeln('  + import \'$uri\'; in ${e.file}');
        added = true;
      }
    }
    return added;
  }

  void _summary(_SetupFile setup, List<String> manual) {
    out.writeln('\nChanged:');
    changes.forEach((path, text) {
      final was = before[path];
      if (was == null) {
        out.writeln('  $path (new)');
      } else if (text != was) {
        out.writeln('  $path  +${_addedLines(path).length} lines');
      }
    });
    if (setup.needsCode.isNotEmpty) {
      out.writeln('\n${setup.needsCode.length} tools have no request yet, so the assistant can\'t use them '
          'until the console gives them one: ${setup.needsCode.join(', ')}');
    }
    out.writeln('\nThe assistant\'s button shows by itself once a version is published for the build\'s track.');
    _printManual(manual);
    out.writeln('\nUndo: dart run zehn_intelligence:setup --remove');
  }

  void _printManual(List<String> manual) {
    if (manual.isEmpty) return;
    out.writeln('\nBy hand:');
    for (final m in manual) {
      out.writeln('  $m');
    }
  }

  Future<int> remove() async {
    final pubspec = _pubspec();
    final record = _readRecord();
    final missed = <String, List<String>>{};
    if (record != null) {
      record.files.forEach((path, kept) {
        final now = _read(path);
        if (now == kept.after || (kept.before == null && path == assetPath)) {
          // As the command left it (or the file it made): back exactly.
          if (now != kept.before) _change(path, kept.before);
          return;
        }
        if (now == null) {
          missed[path] = ['the file is gone'];
          return;
        }
        if (kept.before == null) {
          missed[path] = ['the command made it, and it was changed since: left as it is'];
          return;
        }
        final undone = undoEdits(now, before: kept.before!, after: kept.after);
        if (undone.text != now) _change(path, undone.text);
        if (undone.missed.isNotEmpty) missed[path] = undone.missed;
      });
    } else {
      // No record (.dart_tool was cleaned): the lines the command writes.
      if (_read(assetPath) != null) _change(assetPath, null);
      final withoutAsset = removeAsset(pubspec);
      if (withoutAsset != pubspec) _change('pubspec.yaml', withoutAsset);
      _libFiles().forEach((path, source) {
        final text = removeUnusedImport(removeStart(source));
        if (text != source) _change(path, text);
      });
    }
    if (changes.isEmpty && missed.isEmpty) {
      out.writeln('Nothing to take out.');
      return 0;
    }
    for (final path in changes.keys) {
      out.writeln(changes[path] == null ? '✓ deleted $path' : '✓ $path');
    }
    missed.forEach((path, lines) {
      out.writeln('! $path was edited since: take these out by hand:');
      for (final line in lines) {
        out.writeln('    $line');
      }
    });
    if (options.dryRun) {
      out.writeln('\nNothing was written (--dry-run).');
      return 0;
    }
    _write(keepRecord: false);
    final kept = _file(SetupRecord.path);
    if (kept.existsSync()) kept.deleteSync();
    // The folders the setup made, when nothing else is in them now.
    for (final dir in [...?record?.dirs.toList().reversed, SetupRecord.folder]) {
      final d = Directory('${root.path}/$dir');
      if (d.existsSync() && d.listSync().isEmpty) d.deleteSync();
    }
    if (record == null) {
      out.writeln('\nmain() stays async (harmless): the record of the setup run is gone.');
    }
    out.writeln('To drop the SDK too: flutter pub remove zehn_intelligence');
    return 0;
  }
}

/// Where the console's analysis says the start line goes
/// (`analyzer/integration.py` on the server).
class Integration {
  const Integration({
    required this.file,
    required this.line,
    required this.code,
    required this.imports,
    required this.mainAsync,
    required this.sure,
    required this.notes,
    this.dio,
  });

  static Integration? fromJson(Object? json) {
    if (json is! Map) return null;
    final code = json['code'];
    if (code is! String || code.trim().isEmpty) return null;
    final file = json['file'];
    final line = json['line'];
    return Integration(
      file: file is String && file.startsWith('lib/') ? file : null,
      line: line is int ? line : null,
      code: code.trim(),
      imports: [for (final i in json['imports'] as List? ?? const []) if (i is String) i],
      mainAsync: json['main_async'] == true,
      sure: json['sure'] == true,
      notes: [for (final n in json['notes'] as List? ?? const []) if (n is String) n],
      dio: json['dio'] is Map ? (json['dio'] as Map).cast<String, Object?>() : null,
    );
  }

  /// The file, under lib/ (`lib/main.dart`).
  final String? file;

  /// The line of its `runApp(`, 1-based, when the analysis knew it.
  final int? line;

  /// The whole line: `await ZehnIntelligence.start(dio: () => …);`.
  final String code;

  /// The `import '…';` lines it needs that the file didn't have.
  final List<String> imports;
  final bool mainAsync;

  /// Whether the analysis found both `runApp` and the app's Dio.
  final bool sure;

  /// `dio_not_found`, `separate_dio`, `run_app_not_found`, `make_main_async`.
  final List<String> notes;

  /// Where the app's Dio is: `{kind, file, line}`.
  final Map<String, Object?>? dio;

  String get dioWhere {
    final where = dio;
    if (where == null) return 'known';
    final kind = switch (where['kind']) {
      'locator' => 'the one registered as Dio',
      'global' => 'a global one',
      'made' => "made the app's own way",
      _ => 'known',
    };
    return where['file'] == null ? kind : '$kind (${where['file']}:${where['line']})';
  }
}

class _SetupFile {
  _SetupFile(this.file, this.config, this.appName, this.specVersion, this.needsCode, this.integration);

  final String file;
  final Map<String, Object?> config;
  final String appName;
  final String? specVersion;
  final List<String> needsCode;
  final Integration? integration;

  String get packageName => '${config['zi_package_name'] ?? ''}';
  String get bundleId => '${config['zi_bundle_id'] ?? ''}';

  static Map<String, Object?> _config(String file) {
    Object? config;
    try {
      config = jsonDecode(file);
    } on FormatException {
      config = null;
    }
    if (config is Map<String, Object?> && config['zi_config_format'] == '3') return config;
    if (config is Map && (config['zi_config_format'] == '1' || config['zi_config_format'] == '2')) {
      throw SetupFailure('The file is format ${config['zi_config_format']}, for older SDK builds: '
          'get the new one (format 3) from the console');
    }
    throw const SetupFailure('The file is not a zehn-intelligence.json (format 3) from the console');
  }

  static _SetupFile fromConfig(String file) => _SetupFile(file, _config(file), '', null, const [], null);

  static _SetupFile fromAnswer(Map<String, Object?> answer) {
    final file = answer['file'];
    if (file is! String) throw const SetupFailure('The console answered without a file');
    final app = (answer['app'] as Map?)?.cast<String, Object?>() ?? const {};
    final version = answer['spec_version'];
    return _SetupFile(
      file,
      _config(file),
      '${app['name'] ?? ''}',
      version is String ? version : null,
      [for (final n in (answer['needs_code'] as List? ?? const [])) '$n'],
      Integration.fromJson(answer['integration']),
    );
  }
}

/// `POST <server>/api/v1/setup {code}`.
Future<Map<String, Object?>> exchangeCode(String server, String code) async {
  final base = server.replaceAll(RegExp(r'/+$'), '').replaceAll(RegExp(r'/api/v1$'), '');
  final url = Uri.parse('$base/api/v1/setup');
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
  try {
    final request = await client.postUrl(url);
    final body = utf8.encode(jsonEncode({'code': code}));
    request.headers.contentType = ContentType.json;
    request.contentLength = body.length;
    request.add(body);
    final response = await request.close().timeout(const Duration(seconds: 30));
    final text = await response.transform(utf8.decoder).join();
    Object? json;
    try {
      json = jsonDecode(text);
    } on FormatException {
      json = null;
    }
    if (response.statusCode == 200 && json is Map<String, Object?>) return json;
    final message = json is Map && json['message'] is String ? json['message'] as String : 'HTTP ${response.statusCode}';
    throw SetupFailure('The console refused the code: $message');
  } on SocketException catch (error) {
    throw SetupFailure("Couldn't reach $base (${error.message}). Is --server right?");
  } on TimeoutException {
    throw SetupFailure('$base did not answer in 30 s');
  } on HandshakeException catch (error) {
    throw SetupFailure("Couldn't reach $base securely (${error.message})");
  } on IOException catch (error) {
    throw SetupFailure('The connection to $base failed ($error)');
  } finally {
    client.close(force: true);
  }
}

/// `dart analyze --format=machine` on [files]: its errors, or null when it
/// couldn't run.
Future<List<AnalyzerError>?> dartAnalyze(String root, List<String> files) async {
  final exe = Platform.resolvedExecutable;
  final name = exe.split(Platform.pathSeparator).last;
  final dart = name.startsWith('dart') ? exe : 'dart';
  ProcessResult result;
  try {
    result = await Process.run(dart, ['analyze', '--format=machine', ...files], workingDirectory: root);
  } on ProcessException {
    return null;
  }
  final errors = <AnalyzerError>[];
  for (final line in '${result.stdout}\n${result.stderr}'.split('\n')) {
    final parts = line.split('|');
    if (parts.length < 8 || parts[0] != 'ERROR') continue;
    var file = parts[3].replaceAll(r'\', '/');
    final prefix = '${root.replaceAll(r'\', '/')}/';
    if (file.startsWith(prefix)) file = file.substring(prefix.length);
    errors.add(AnalyzerError(file, int.tryParse(parts[4]) ?? 0, parts[2], parts.sublist(7).join('|')));
  }
  if (errors.isEmpty && result.exitCode > 3) return null; // it failed to run, not a clean result
  return errors;
}
