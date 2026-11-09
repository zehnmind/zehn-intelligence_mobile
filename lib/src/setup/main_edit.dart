// The setup command's edit of the app's `main()`: one line before `runApp`,
// `await ZehnIntelligence.start(dio: () => <the app's Dio>);` (the server's
// line, from its analysis of the app, or one made here), and the imports it
// needs. Only lines are added; the app's own lines stay as they are, except
// `main` becoming `async` (and `void` `Future<void>`) when it wasn't. No
// binding line: `start()` makes the binding itself.

import 'dart_source.dart';

const sdkImport = 'package:zehn_intelligence/zehn_intelligence.dart';

/// What [addStart] did to one file.
class MainEdit {
  const MainEdit(this.text, {this.notes = const [], this.problem});

  /// The file after the edit (unchanged when there was nothing to do or a
  /// [problem]).
  final String text;

  /// What the developer should know (main made async, a binding line added).
  final List<String> notes;

  /// Why the line couldn't be placed: the developer adds it by hand.
  final String? problem;
}

/// The start line, as written into `main()`.
String startLine(String? dioExpression) => dioExpression == null
    ? 'await ZehnIntelligence.start();'
    : 'await ZehnIntelligence.start(dio: () => $dioExpression);';

final _runApp = RegExp(r'(?<![\w.$])runApp\s*\(');
final _started = RegExp(r'\bZehnIntelligence\s*\.\s*(start|init)\s*\(');

/// Whether [source] calls `runApp(` (in code, not in a comment or string).
bool callsRunApp(String source) => _runApp.hasMatch(maskDart(source));

/// Whether [source] already starts the SDK.
bool startsSdk(String source) => _started.hasMatch(maskDart(source));

/// [source] with the start line before its first `runApp(`.
MainEdit addStart(String source, String? dioExpression) =>
    addLine(source, startLine(dioExpression));

/// [source] with [line] (one statement) before the statement that holds
/// `runApp(`: the one on line [atLine] (1-based) when that line still holds
/// it, else the first. [imports] (whole `import '…';` lines) are added when
/// the file lacks them, with the SDK's own always.
MainEdit addLine(
  String source,
  String line, {
  int? atLine,
  List<String> imports = const [],
}) {
  final masked = maskDart(source);
  if (_started.hasMatch(masked)) return MainEdit(source);
  final run = _runAppAt(masked, atLine) ?? _runApp.firstMatch(masked);
  if (run == null) return MainEdit(source, problem: 'no runApp( here');
  final uris = [
    sdkImport,
    for (final import in imports)
      ?RegExp('''^\\s*import\\s+['"]([^'"]+)['"]''').firstMatch(import)?.group(1),
  ];

  final arrow = _arrowMain(source, masked, run.start, line, uris);
  if (arrow != null) return arrow;

  final body = enclosingFunction(masked, run.start);
  if (body == null) {
    return MainEdit(source, problem: 'runApp( is not inside a function body');
  }
  final start = statementStart(masked, run.start, body.brace);
  if (start < 0 || masked.substring(lineStartOf(masked, start), start).trim().isNotEmpty) {
    return MainEdit(source, problem: 'the statement with runApp( shares its line');
  }
  if (!body.isAsync && body.name != 'main') {
    return MainEdit(
      source,
      problem: 'runApp( is in ${body.name.isEmpty ? 'a closure' : '${body.name}()'}, which is not async',
    );
  }

  final notes = <String>[];
  final indent = indentOf(source, start);
  final added = '$indent$line\n';

  // Edits from the end of the file to its start, so the offsets hold.
  var text = source;
  final at = lineStartOf(source, start);
  text = text.substring(0, at) + added + text.substring(at);
  if (!body.isAsync) {
    var j = body.brace - 1;
    while (j >= 0 && (masked[j] == ' ' || masked[j] == '\t' || masked[j] == '\n')) {
      j--;
    }
    text = '${text.substring(0, j + 1)} async${text.substring(j + 1)}';
    final header = masked.substring(body.headerStart, body.brace);
    final voidMain = RegExp(r'\bvoid(\s+main\b)').firstMatch(header);
    if (voidMain != null) {
      final from = body.headerStart + voidMain.start;
      text = '${text.substring(0, from)}Future<void>${text.substring(from + 4)}';
    }
    notes.add('main() is async now: the line awaits the SDK');
  }
  return MainEdit(_withImports(text, uris), notes: notes);
}

String _withImports(String source, List<String> uris) {
  var text = source;
  for (final uri in uris) {
    text = withImport(text, uri);
  }
  return text;
}

/// The `runApp(` on line [atLine] (1-based), when that line holds one.
RegExpMatch? _runAppAt(String masked, int? atLine) {
  if (atLine == null || atLine < 1) return null;
  var start = 0;
  for (var i = 1; i < atLine; i++) {
    final next = masked.indexOf('\n', start);
    if (next < 0) return null;
    start = next + 1;
  }
  final end = masked.indexOf('\n', start);
  final found = _runApp.firstMatch(
    masked.substring(start, end < 0 ? masked.length : end),
  );
  if (found == null) return null;
  return _runApp.allMatches(masked).where((m) => m.start == start + found.start).firstOrNull;
}

/// `void main() => runApp(...);` as a body with the start line.
MainEdit? _arrowMain(
  String source,
  String masked,
  int runAt,
  String line,
  List<String> uris,
) {
  final header = RegExp(r'^([ \t]*)(?:(?:Future<void>|void)\s+)?main\s*\(([^)]*)\)\s*(?:async\s*)?=>\s*',
          multiLine: true)
      .allMatches(masked)
      .where((m) => m.start < runAt && masked.substring(m.end, runAt).trim().isEmpty)
      .firstOrNull;
  if (header == null) return null;
  var depth = 0;
  var end = -1;
  for (var i = header.end; i < masked.length; i++) {
    final c = masked[i];
    if (c == '(' || c == '[' || c == '{') depth++;
    if (c == ')' || c == ']' || c == '}') depth--;
    if (c == ';' && depth == 0) {
      end = i;
      break;
    }
  }
  if (end < 0) return null;
  final indent = header.group(1)!;
  final args = header.group(2)!.trim();
  final expression = source.substring(header.end, end).trim();
  final body = StringBuffer()
    ..writeln('${indent}Future<void> main($args) async {')
    ..writeln('$indent  $line')
    ..writeln('$indent  $expression;')
    ..write('$indent}');
  final text = source.substring(0, header.start) + body.toString() + source.substring(end + 1);
  return MainEdit(
    _withImports(text, uris),
    notes: ['main() => runApp(...) became a body with the line'],
  );
}

/// [source] without the start line: what `--remove` does when the record of
/// the setup run is gone (`main` stays async, which is harmless).
String removeStart(String source) {
  final masked = maskDart(source);
  final found = RegExp(r'await\s+ZehnIntelligence\s*\.\s*start\s*\(').firstMatch(masked);
  if (found == null) return source;
  final open = masked.indexOf('(', found.start);
  final close = matchingClose(masked, open);
  if (close < 0) return source;
  var end = close + 1;
  while (end < masked.length && masked[end] == ' ') {
    end++;
  }
  if (end < masked.length && masked[end] == ';') end++;
  final from = lineStartOf(source, found.start);
  final lineEnd = source.indexOf('\n', end);
  final to = lineEnd < 0 ? source.length : lineEnd + 1;
  if (source.substring(from, found.start).trim().isNotEmpty || source.substring(end, to).trim().isNotEmpty) {
    return source; // not a line of its own: not ours
  }
  return source.substring(0, from) + source.substring(to);
}

/// [source] without the SDK's import once nothing in it uses the SDK.
String removeUnusedImport(String source) {
  final line = RegExp("^import\\s+['\"]${RegExp.escape(sdkImport)}['\"]\\s*;[ \\t]*\\n", multiLine: true);
  final found = line.firstMatch(source);
  if (found == null) return source;
  final rest = maskDart(source.substring(0, found.start) + source.substring(found.end));
  if (RegExp(r'\b(ZehnIntelligence|ZehnAiButton|Zi[A-Z]\w*)\b').hasMatch(rest)) return source;
  return source.substring(0, found.start) + source.substring(found.end);
}
