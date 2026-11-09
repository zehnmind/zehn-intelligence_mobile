// The setup command's guess at the app's Dio: a Dart expression `main()` can
// evaluate before `runApp`, so the SDK sends the config file's requests with
// the app's base URL and sign-in. Only guesses: the command shows each one,
// asks when it can, and `dart analyze` checks the line it wrote.

import 'dart_source.dart';

class DioCandidate {
  const DioCandidate(this.expression, this.path, this.line, this.why, this.rank);

  /// The expression, e.g. `getIt<Dio>()`.
  final String expression;
  final String path;
  final int line;
  final String why;

  /// 1: registered as Dio in get_it; 2: a global or static Dio; 3: made by a
  /// method of an object registered in get_it.
  final int rank;

  @override
  String toString() => '$expression   ($why, $path:$line)';
}

final _registerDio = RegExp(
    r'([A-Za-z_$][\w$]*(?:\.[A-Za-z_$][\w$]*)*)\s*\.\s*register\w*\s*(?:<\s*Dio\s*>\s*\(|\(\s*\(\s*\)\s*(?:async\s*)?(?:=>\s*|\{\s*return\s+)Dio\s*\()');
final _getItVariable = RegExp(r'^(?:final|var|late\s+final)\s+(?:GetIt\s+)?([A-Za-z_]\w*)\s*=\s*GetIt\s*\.\s*(?:I|instance)\b',
    multiLine: true);
final _injectableDio = RegExp(r'@(?:lazySingleton|singleton|injectable|LazySingleton\(\)|Singleton\(\))\s+Dio\s+(?:get\s+)?\w+');
final _topLevelDio = RegExp(r'^(?:final|late\s+final|var)\s+(?:Dio\s+([A-Za-z]\w*)\s*=|([A-Za-z]\w*)\s*=\s*Dio\s*\()',
    multiLine: true);
final _staticDio = RegExp(
    r'\bstatic\s+(?:final\s+|late\s+final\s+|late\s+)?(?:Dio\s+(?:get\s+)?([A-Za-z]\w*)|([A-Za-z]\w*)\s*=\s*Dio\s*\()');
final _methodReturningDio = RegExp(r'(?<![\w.])Dio\s+(get\s+)?([A-Za-z]\w*)\s*(\(|=>|\{)');

/// The candidates found in the app's `lib/` [files] (path → source), the
/// likeliest first, each expression once.
List<DioCandidate> findDio(Map<String, String> files) {
  final found = <DioCandidate>[];
  final masked = {for (final e in files.entries) e.key: maskDart(e.value)};

  // 1. Dio in get_it.
  String? getItName;
  masked.forEach((path, code) {
    getItName ??= _getItVariable.firstMatch(code)?.group(1);
    for (final m in _registerDio.allMatches(code)) {
      found.add(DioCandidate('${m.group(1)}<Dio>()', path, lineOf(code, m.start), 'registered as Dio', 1));
    }
  });
  masked.forEach((path, code) {
    final m = _injectableDio.firstMatch(code);
    if (m != null) {
      final locator = getItName ?? 'getIt';
      found.add(DioCandidate('$locator<Dio>()', path, lineOf(code, m.start), 'injectable provides Dio', 1));
    }
  });

  // 2. A global or a static Dio.
  masked.forEach((path, code) {
    for (final m in _topLevelDio.allMatches(code)) {
      if (openBraces(code, m.start).isNotEmpty) continue;
      final name = m.group(1) ?? m.group(2)!;
      if (name.startsWith('_')) continue;
      found.add(DioCandidate(name, path, lineOf(code, m.start), 'a global Dio', 2));
    }
    for (final m in _staticDio.allMatches(code)) {
      final name = m.group(1) ?? m.group(2)!;
      final owner = _classAround(code, m.start);
      if (owner == null || owner.startsWith('_')) continue;
      found.add(DioCandidate('$owner.$name', path, lineOf(code, m.start), 'a static Dio', 2));
    }
  });

  // 3. A method (or getter) that returns a Dio, called on an object from
  // get_it: copied from where the app itself calls it.
  final makers = <String>{};
  for (final code in masked.values) {
    for (final m in _methodReturningDio.allMatches(code)) {
      final name = m.group(2)!;
      if (!name.startsWith('_') && name != 'get') makers.add(name);
    }
  }
  for (final name in makers) {
    final call = RegExp(r'([A-Za-z_$][\w$]*\s*<\s*[\w$]+\s*>\s*\(\s*\))\s*\.\s*' + RegExp.escape(name) + r'\b(\s*\()?');
    masked.forEach((path, code) {
      for (final m in call.allMatches(code)) {
        var end = m.end;
        if (m.group(2) != null) {
          final open = code.indexOf('(', m.end - 1);
          final close = matchingClose(code, open);
          if (close < 0) continue;
          end = close + 1;
        }
        final expression = files[path]!.substring(m.start, end).replaceAll(RegExp(r'\s+'), ' ');
        if (!_usableInMain(expression)) continue;
        found.add(DioCandidate(expression, path, lineOf(code, m.start), 'how the app makes its Dio', 3));
      }
    });
  }

  final seen = <String>{};
  final unique = [for (final c in found) if (seen.add(c.expression)) c];
  unique.sort((a, b) => a.rank.compareTo(b.rank));
  return unique;
}

/// Only lookups, names and literals: nothing private, no `this`, no context.
bool _usableInMain(String expression) =>
    !RegExp(r'(\b_\w|\bthis\b|\bcontext\b|\bref\b|\bwidget\b)').hasMatch(expression) && expression.length <= 200;

String? _classAround(String code, int offset) {
  final braces = openBraces(code, offset);
  if (braces.length != 1) return null;
  final header = code.substring(lineStartOf(code, braces.first), braces.first);
  return RegExp(r'\bclass\s+([A-Za-z_]\w*)').firstMatch(header)?.group(1) ??
      RegExp(r'\bclass\s+([A-Za-z_]\w*)')
          .allMatches(code.substring(0, braces.first))
          .lastOrNull
          ?.group(1);
}

/// Where [name] is declared at the top level of [files]: a class, enum, mixin,
/// typedef, extension type, variable or function. For an import the analyzer
/// asks for.
String? declaringFile(Map<String, String> files, String name) {
  final n = RegExp.escape(name);
  final declaration = RegExp(
      '^(?:(?:abstract|base|final|sealed|interface|mixin)\\s+)*(?:class|mixin|enum|typedef|extension\\s+type)\\s+$n\\b'
      '|^(?:final|var|const|late\\s+final|late)\\s+(?:[\\w<>?, ]+\\s+)?$n\\s*='
      '|^[\\w<>?, ]+\\s+$n\\s*[(=]',
      multiLine: true);
  for (final entry in files.entries) {
    if (declaration.hasMatch(maskDart(entry.value))) return entry.key;
  }
  return null;
}
