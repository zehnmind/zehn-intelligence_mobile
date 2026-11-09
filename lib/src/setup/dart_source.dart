// The setup command's view of a Dart file (bin/setup.dart): enough structure to
// place one line safely, without the Dart analyzer as a dependency of every app.
//
// Everything works on a *masked* copy of the source: the same length, with
// comments and string literals (their interpolations too) blanked to spaces and
// line breaks kept. A brace, a paren or `runApp(` found in the masked copy is
// code, never text in a comment or a string; its offset is the same in the
// original.

/// [source] with comments and string literals blanked (line breaks kept).
String maskDart(String source) {
  final out = source.codeUnits.toList();
  var i = 0;
  while (i < source.length) {
    final end = _skipNonCode(source, i);
    if (end > i) {
      for (var k = i; k < end; k++) {
        if (out[k] != 0x0A) out[k] = 0x20;
      }
      i = end;
    } else {
      i++;
    }
  }
  return String.fromCharCodes(out);
}

/// The end of the comment or string literal at [i], or [i] when there is none.
int _skipNonCode(String s, int i) {
  final c = s[i];
  final next = i + 1 < s.length ? s[i + 1] : '';
  if (c == '/' && next == '/') {
    final end = s.indexOf('\n', i);
    return end < 0 ? s.length : end;
  }
  if (c == '/' && next == '*') return _skipBlockComment(s, i);
  if (c == "'" || c == '"') return _skipString(s, i, raw: false);
  if (c == 'r' && (next == "'" || next == '"') && !_isIdentifierChar(s, i - 1)) {
    return _skipString(s, i + 1, raw: true);
  }
  return i;
}

int _skipBlockComment(String s, int i) {
  var depth = 0;
  while (i < s.length) {
    if (s.startsWith('/*', i)) {
      depth++;
      i += 2;
    } else if (s.startsWith('*/', i)) {
      depth--;
      i += 2;
      if (depth == 0) return i;
    } else {
      i++;
    }
  }
  return s.length;
}

/// The end of the string literal whose opening quote is at [i].
int _skipString(String s, int i, {required bool raw}) {
  final quote = s[i];
  final triple = s.startsWith(quote * 3, i);
  final close = triple ? quote * 3 : quote;
  i += close.length;
  while (i < s.length) {
    final c = s[i];
    if (!raw && c == r'\') {
      i += 2;
      continue;
    }
    if (!triple && c == '\n') return i; // an unterminated literal: stop at the line
    if (s.startsWith(close, i)) return i + close.length;
    if (!raw && c == r'$' && i + 1 < s.length && s[i + 1] == '{') {
      i = _skipInterpolation(s, i + 2);
      continue;
    }
    i++;
  }
  return s.length;
}

/// The end of the `${...}` whose code starts at [i] (after the closing brace).
int _skipInterpolation(String s, int i) {
  var depth = 1;
  while (i < s.length) {
    final end = _skipNonCode(s, i);
    if (end > i) {
      i = end;
      continue;
    }
    final c = s[i];
    if (c == '{') depth++;
    if (c == '}') {
      depth--;
      if (depth == 0) return i + 1;
    }
    i++;
  }
  return s.length;
}

bool _isIdentifierChar(String s, int i) {
  if (i < 0 || i >= s.length) return false;
  final c = s.codeUnitAt(i);
  return (c >= 0x30 && c <= 0x39) ||
      (c >= 0x41 && c <= 0x5A) ||
      (c >= 0x61 && c <= 0x7A) ||
      c == 0x5F ||
      c == 0x24;
}

const _pairs = {'(': ')', '[': ']', '{': '}'};

/// The offset of the bracket that closes the one at [open] in [masked], or -1.
int matchingClose(String masked, int open) {
  final opener = masked[open];
  final closer = _pairs[opener]!;
  var depth = 0;
  for (var i = open; i < masked.length; i++) {
    final c = masked[i];
    if (c == opener) depth++;
    if (c == closer) {
      depth--;
      if (depth == 0) return i;
    }
  }
  return -1;
}

/// The offset of the bracket that opens the one at [close] in [masked], or -1.
int matchingOpen(String masked, int close) {
  final closer = masked[close];
  final opener = _pairs.entries.firstWhere((e) => e.value == closer).key;
  var depth = 0;
  for (var i = close; i >= 0; i--) {
    final c = masked[i];
    if (c == closer) depth++;
    if (c == opener) {
      depth--;
      if (depth == 0) return i;
    }
  }
  return -1;
}

/// The offsets of the `{` still open at [offset], the outermost first.
List<int> openBraces(String masked, int offset) {
  final stack = <int>[];
  for (var i = 0; i < offset && i < masked.length; i++) {
    final c = masked[i];
    if (c == '{') stack.add(i);
    if (c == '}' && stack.isNotEmpty) stack.removeLast();
  }
  return stack;
}

/// The innermost function body around a statement: its `{`, whether it is
/// `async`, and the function's name (`''` for a closure).
class FunctionBody {
  const FunctionBody(this.brace, this.isAsync, this.name, this.headerStart);

  /// The offset of the body's `{`.
  final int brace;
  final bool isAsync;
  final String name;

  /// Where the declaration's line starts (for `void main() {`), or -1.
  final int headerStart;
}

const _controlWords = {'if', 'for', 'while', 'switch', 'catch', 'on'};
const _blockWords = {'else', 'try', 'finally', 'do'};

/// The function whose body holds [offset], or null when a brace between them
/// is neither a function's nor a control statement's (a class body, a
/// collection literal): no line can be placed there safely.
FunctionBody? enclosingFunction(String masked, int offset) {
  final braces = openBraces(masked, offset);
  for (final brace in braces.reversed) {
    var j = brace - 1;
    while (j >= 0 && _isSpace(masked[j])) {
      j--;
    }
    if (j < 0) return null;
    var isAsync = false;
    final before = masked.substring(0, j + 1);
    final marker = RegExp(r'(async\*?|sync\*)$').firstMatch(before);
    if (marker != null) {
      isAsync = marker.group(1)!.startsWith('async');
      j = marker.start - 1;
      while (j >= 0 && _isSpace(masked[j])) {
        j--;
      }
    }
    final word = RegExp(r'([A-Za-z_]\w*)$').firstMatch(masked.substring(0, j + 1));
    if (word != null && _blockWords.contains(word.group(1))) continue;
    if (j < 0 || masked[j] != ')') {
      return null; // a class body, a map or set literal, a switch arm...
    }
    final paren = matchingOpen(masked, j);
    if (paren < 0) return null;
    var k = paren - 1;
    while (k >= 0 && _isSpace(masked[k])) {
      k--;
    }
    final name = RegExp(r'([A-Za-z_]\w*)\s*(<[^()]*>)?$')
        .firstMatch(masked.substring(0, k + 1));
    final called = name?.group(1) ?? '';
    if (_controlWords.contains(called)) continue;
    final lineStart = masked.lastIndexOf('\n', paren) + 1;
    return FunctionBody(brace, isAsync, called, lineStart);
  }
  return null;
}

bool _isSpace(String c) => c == ' ' || c == '\t' || c == '\n' || c == '\r';

/// Where the statement holding [offset] starts, in the function body whose
/// `{` is at [bodyBrace]: after the last `;` or block that ended at the body's
/// own level before it, blanks skipped. -1 when that is the tail of another
/// statement (`} else runApp(...)`): no line can go before it.
int statementStart(String masked, int offset, int bodyBrace) {
  var depth = 0;
  var start = bodyBrace + 1;
  for (var i = bodyBrace + 1; i < offset; i++) {
    final c = masked[i];
    if (c == '(' || c == '[' || c == '{') {
      depth++;
    } else if (c == ')' || c == ']' || c == '}') {
      depth--;
      if (depth == 0 && c == '}') start = i + 1;
    } else if (c == ';' && depth == 0) {
      start = i + 1;
    }
  }
  while (start < offset && _isSpace(masked[start])) {
    start++;
  }
  if (RegExp(r'(else|catch|finally|on|while)\b').matchAsPrefix(masked, start) != null) {
    return -1;
  }
  return start;
}

/// The offset where line [offset] starts.
int lineStartOf(String text, int offset) => offset <= 0 ? 0 : text.lastIndexOf('\n', offset - 1) + 1;

/// The blanks at the start of the line holding [offset].
String indentOf(String text, int offset) {
  final start = lineStartOf(text, offset);
  var end = start;
  while (end < text.length && (text[end] == ' ' || text[end] == '\t')) {
    end++;
  }
  return text.substring(start, end);
}

/// The 1-based line number of [offset].
int lineOf(String text, int offset) =>
    '\n'.allMatches(text.substring(0, offset)).length + 1;

/// [source] with `import '<uri>';` after its last import (or before its first
/// declaration), unchanged when the URI is imported already.
String withImport(String source, String uri) {
  final masked = maskDart(source);
  if (RegExp("import\\s+['\"]${RegExp.escape(uri)}['\"]").hasMatch(source)) {
    return source;
  }
  final line = "import '$uri';";
  final imports = RegExp(r'^(import|export)\b[^;]*;', multiLine: true)
      .allMatches(masked)
      .toList();
  if (imports.isNotEmpty) {
    final at = imports.last.end;
    return '${source.substring(0, at)}\n$line${source.substring(at)}';
  }
  final directive = RegExp(r'^(library|part)\b[^;]*;', multiLine: true)
      .allMatches(masked)
      .toList();
  if (directive.isNotEmpty) {
    final at = directive.last.end;
    return '${source.substring(0, at)}\n\n$line${source.substring(at)}';
  }
  // After the file's leading comments.
  final first = RegExp(r'\S').firstMatch(masked);
  final at = first == null ? source.length : lineStartOf(source, first.start);
  return '${source.substring(0, at)}$line\n\n${source.substring(at)}';
}
