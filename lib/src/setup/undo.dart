// What `--remove` puts back: the setup command keeps, for each file it
// changed, the file as it was before and as it wrote it (`.dart_tool/
// zehn_intelligence/setup.json`). A file as the command left it gets its
// old text back exactly. A file the developer edited since gets each of the
// command's edits undone where it still stands as written, and the ones it
// can't find are named, never guessed at.

/// The record of a setup run: per file (relative path), its text before the
/// first run (`null`: the command made it) and after the last.
class SetupRecord {
  SetupRecord(this.files, [Set<String>? dirs]) : dirs = dirs ?? {};

  final Map<String, ({String? before, String after})> files;

  /// The folders the command made (`assets`), outermost first: `--remove`
  /// takes away the ones left empty.
  final Set<String> dirs;

  static const folder = '.dart_tool/zehn_intelligence';
  static const path = '$folder/setup.json';

  static SetupRecord? fromJson(Object? json) {
    if (json is! Map || json['files'] is! Map) return null;
    final files = <String, ({String? before, String after})>{};
    for (final MapEntry(:key, :value) in (json['files'] as Map).entries) {
      if (key is! String || value is! Map || value['after'] is! String) {
        return null;
      }
      final before = value['before'];
      if (before != null && before is! String) return null;
      files[key] = (before: before as String?, after: value['after'] as String);
    }
    final dirs = json['dirs'];
    return SetupRecord(files, {
      if (dirs is List)
        for (final dir in dirs)
          if (dir is String && !dir.contains('..')) dir,
    });
  }

  Map<String, Object?> toJson() => {
    'version': 1,
    'files': {
      for (final MapEntry(:key, :value) in files.entries)
        key: {'before': value.before, 'after': value.after},
    },
    'dirs': [...dirs],
  };
}

/// [current] with the edits that made [after] out of [before] undone.
class Undo {
  const Undo(this.text, this.missed);

  final String text;

  /// The command's lines that are no longer as it wrote them: left as
  /// they are, for the developer.
  final List<String> missed;
}

/// Undoes, in [current], each change from [before] to [after]: a run of
/// lines the command wrote goes back to the lines it replaced (none, for a
/// line it added). Each run is found by its lines with the line before and
/// after it, else by its lines alone when they are there once. A run not
/// found whole is undone line by line: a line it changed goes back where it
/// still stands as written, a line it added goes where it is found once,
/// and every other line is named.
Undo undoEdits(String current, {required String before, required String after}) {
  final a = before.split('\n');
  final b = after.split('\n');
  final c = current.split('\n');
  final missed = <String>[];
  for (final hunk in _hunks(a, b).reversed) {
    final wrote = b.sublist(hunk.bFrom, hunk.bTo);
    final was = a.sublist(hunk.aFrom, hunk.aTo);
    final ahead = hunk.bFrom > 0 ? b[hunk.bFrom - 1] : null;
    final behind = hunk.bTo < b.length ? b[hunk.bTo] : null;
    var at = _find(c, wrote, ahead, behind);
    if (at == null && wrote.isNotEmpty) at = _find(c, wrote, null, null);
    if (at != null) {
      c.replaceRange(at, at + wrote.length, was);
      continue;
    }
    // Line by line: the first lines of the run replaced the old ones, the
    // rest were added.
    for (final (i, line) in wrote.indexed) {
      final found = _find(c, [line], null, null);
      if (found == null) {
        if (line.trim().isNotEmpty) missed.add(line);
      } else if (i < was.length) {
        c[found] = was[i];
      } else {
        c.removeAt(found);
      }
    }
  }
  return Undo(c.join('\n'), missed);
}

/// Where [lines] stand in [text] once, between [ahead] and [behind] when
/// given; `null` when nowhere or more than once.
int? _find(List<String> text, List<String> lines, String? ahead, String? behind) {
  int? found;
  for (var at = 0; at + lines.length <= text.length; at++) {
    var same = true;
    for (var i = 0; i < lines.length && same; i++) {
      same = text[at + i] == lines[i];
    }
    if (!same) continue;
    if (ahead != null && (at == 0 || text[at - 1] != ahead)) continue;
    final end = at + lines.length;
    if (behind != null && (end >= text.length || text[end] != behind)) continue;
    if (lines.isEmpty && ahead == null && behind == null) return null;
    if (found != null) return null; // more than once: not this one's to pick
    found = at;
  }
  return found;
}

typedef _Hunk = ({int aFrom, int aTo, int bFrom, int bTo});

/// The runs where [a] and [b] differ, from the longest common run of lines.
List<_Hunk> _hunks(List<String> a, List<String> b) {
  var head = 0;
  while (head < a.length && head < b.length && a[head] == b[head]) {
    head++;
  }
  var tail = 0;
  while (tail < a.length - head &&
      tail < b.length - head &&
      a[a.length - 1 - tail] == b[b.length - 1 - tail]) {
    tail++;
  }
  final n = a.length - head - tail;
  final m = b.length - head - tail;
  // The longest common subsequence of the middle, from its end.
  final lcs = List.generate(n + 1, (_) => List<int>.filled(m + 1, 0));
  for (var i = n - 1; i >= 0; i--) {
    for (var j = m - 1; j >= 0; j--) {
      lcs[i][j] = a[head + i] == b[head + j]
          ? lcs[i + 1][j + 1] + 1
          : (lcs[i + 1][j] >= lcs[i][j + 1] ? lcs[i + 1][j] : lcs[i][j + 1]);
    }
  }
  final hunks = <_Hunk>[];
  var i = 0;
  var j = 0;
  int? aFrom;
  int? bFrom;
  void close() {
    if (aFrom != null) {
      hunks.add((aFrom: head + aFrom!, aTo: head + i, bFrom: head + bFrom!, bTo: head + j));
      aFrom = bFrom = null;
    }
  }

  while (i < n || j < m) {
    if (i < n && j < m && a[head + i] == b[head + j]) {
      close();
      i++;
      j++;
    } else {
      aFrom ??= i;
      bFrom ??= j;
      if (j < m && (i >= n || lcs[i][j + 1] >= lcs[i + 1][j])) {
        j++;
      } else {
        i++;
      }
    }
  }
  close();
  return hunks;
}
