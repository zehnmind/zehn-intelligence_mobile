import 'package:flutter_test/flutter_test.dart';
import 'package:zehn_intelligence/src/setup/undo.dart';

const before = '''
import 'package:flutter/material.dart';

void main() {
  runApp(const App());
}
''';

const after = '''
import 'package:flutter/material.dart';
import 'package:zehn_intelligence/zehn_intelligence.dart';

Future<void> main() async {
  await ZehnIntelligence.start(dio: () => getIt<Dio>());
  runApp(const App());
}
''';

void main() {
  test('the file as the command left it comes back exactly', () {
    final undo = undoEdits(after, before: before, after: after);
    expect(undo.text, before);
    expect(undo.missed, isEmpty);
  });

  test('the developer\'s own lines stay, wherever they went', () {
    final edited = after
        .replaceFirst("import 'package:flutter/material.dart';\n",
            "import 'package:flutter/material.dart';\nimport 'package:logging/logging.dart';\n")
        .replaceFirst('  runApp(const App());\n', '  Logger.root.level = Level.ALL;\n  runApp(const App());\n');
    final undo = undoEdits(edited, before: before, after: after);
    expect(undo.text, '''
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';

void main() {
  Logger.root.level = Level.ALL;
  runApp(const App());
}
''');
    expect(undo.missed, isEmpty);
  });

  test('a line the developer changed is named, and the rest still comes out', () {
    final edited = after.replaceFirst('Future<void> main() async {', 'Future<void> main(List<String> args) async {');
    final undo = undoEdits(edited, before: before, after: after);
    expect(undo.missed, ['Future<void> main() async {']);
    expect(undo.text, isNot(contains('ZehnIntelligence')));
    expect(undo.text, contains('Future<void> main(List<String> args) async {'));
  });

  test('a line that is there twice is not guessed at', () {
    const was = 'a\nb\n';
    const wrote = 'a\nx\nb\n';
    final undo = undoEdits('x\nq\nx\n', before: was, after: wrote);
    expect(undo.text, 'x\nq\nx\n');
    expect(undo.missed, ['x']);
  });

  test('the record reads back what it wrote, and refuses what it didn\'t', () {
    final record = SetupRecord({
      'lib/main.dart': (before: before, after: after),
      'assets/zehn-intelligence.json': (before: null, after: '{}'),
    });
    final read = SetupRecord.fromJson(record.toJson())!;
    expect(read.files['lib/main.dart'], (before: before, after: after));
    expect(read.files['assets/zehn-intelligence.json']!.before, isNull);
    for (final bad in [
      null,
      'x',
      {'files': 3},
      {
        'files': {
          'a': {'before': 1, 'after': 'x'},
        },
      },
      {
        'files': {
          'a': {'before': 'x'},
        },
      },
    ]) {
      expect(SetupRecord.fromJson(bad), isNull, reason: '$bad');
    }
  });
}
