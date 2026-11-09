// The setup command's edits outside Dart: the `assets:` line in pubspec.yaml,
// and the app's ids read from android/ and ios/ to check against the file.

const assetPath = 'assets/zehn-intelligence.json';

/// The `name:` of the app's package.
String? packageName(String pubspec) =>
    RegExp(r'^name:\s*([A-Za-z_]\w*)', multiLine: true).firstMatch(pubspec)?.group(1);

/// Whether the app depends on the SDK (`flutter pub add zehn_intelligence`).
bool dependsOnSdk(String pubspec) => RegExp(r'^[ \t]+zehn_intelligence\s*:', multiLine: true).hasMatch(pubspec);

class PubspecEdit {
  const PubspecEdit(this.text, {this.problem});
  final String text;
  final String? problem;
}

int _indent(String line) => line.length - line.trimLeft().length;
bool _blank(String line) => line.trim().isEmpty || line.trimLeft().startsWith('#');
String _value(String item) =>
    item.trim().substring(1).split(' #').first.trim().replaceAll(RegExp(r'''^['"]|['"]$'''), '');

/// [pubspec] listing [asset] under `flutter: assets:`, unchanged when it is
/// listed already, by itself or by its folder (`- assets/`).
PubspecEdit addAsset(String pubspec, [String asset = assetPath]) {
  final folder = asset.substring(0, asset.lastIndexOf('/') + 1);
  final lines = pubspec.split('\n');
  final top = lines.indexWhere((l) => RegExp(r'^flutter:\s*(#.*)?$').hasMatch(l));
  if (top < 0) {
    final end = pubspec.endsWith('\n') ? '' : '\n';
    return PubspecEdit('$pubspec$end\nflutter:\n  assets:\n    - $asset\n');
  }
  var blockEnd = top + 1;
  while (blockEnd < lines.length && (_blank(lines[blockEnd]) || lines[blockEnd].startsWith(RegExp(r'[ \t]')))) {
    blockEnd++;
  }
  final block = [for (var i = top + 1; i < blockEnd; i++) if (!_blank(lines[i])) i];
  final keyIndent = block.isEmpty ? 2 : block.map((i) => _indent(lines[i])).reduce((a, b) => a < b ? a : b);
  final pad = ' ' * keyIndent;
  final assets = block.where((i) => _indent(lines[i]) == keyIndent && lines[i].trimLeft().startsWith('assets:'));
  if (assets.isEmpty) {
    lines.insert(top + 1, '${pad}assets:\n$pad  - $asset');
    return PubspecEdit(lines.join('\n'));
  }
  final at = assets.first;
  if (lines[at].trim().replaceFirst(RegExp(r'#.*'), '').trim() != 'assets:') {
    return PubspecEdit(pubspec, problem: 'pubspec.yaml lists its assets in one line: add $asset to them by hand');
  }
  var last = at;
  String? itemPad;
  for (var i = at + 1; i < blockEnd; i++) {
    if (_blank(lines[i])) continue;
    if (_indent(lines[i]) <= keyIndent) break;
    if (lines[i].trimLeft().startsWith('-')) {
      itemPad ??= ' ' * _indent(lines[i]);
      final value = _value(lines[i]);
      if (value == asset || value == folder || '$value/' == folder) return PubspecEdit(pubspec);
    }
    last = i;
  }
  lines.insert(last + 1, '${itemPad ?? '$pad  '}- $asset');
  return PubspecEdit(lines.join('\n'));
}

/// [pubspec] without the line [addAsset] added.
String removeAsset(String pubspec, [String asset = assetPath]) =>
    pubspec.replaceFirst(RegExp('^[ \\t]*- ${RegExp.escape(asset)}[ \\t]*\\n', multiLine: true), '');

/// The application ids in android/app/build.gradle(.kts).
List<String> androidIds(String gradle) => [
      for (final m in RegExp(r'''applicationId\s*(?:=\s*)?["']([\w.]+)["']''').allMatches(gradle)) m.group(1)!,
    ];

/// The app's bundle ids in ios/Runner.xcodeproj/project.pbxproj (not its
/// tests', not one built from variables).
List<String> iosIds(String pbxproj) => {
      for (final m in RegExp(r'PRODUCT_BUNDLE_IDENTIFIER\s*=\s*"?([^";]+)"?;').allMatches(pbxproj))
        if (!m.group(1)!.contains(r'$') && !m.group(1)!.endsWith('Tests')) m.group(1)!,
    }.toList();

/// Where iOS keeps the app's permissions' purpose strings.
const infoPlistPath = 'ios/Runner/Info.plist';

/// The purpose string the microphone needs: iOS ends an app that opens the
/// microphone without it (docs/sdk.md §4), and the SDK records the spoken
/// question when the assistant has `stt`.
const microphoneUse = 'Hold the microphone button to ask the assistant by voice.';

/// [plist] with `NSMicrophoneUsageDescription` before its top `</dict>`,
/// with the file's own indent; `null` when it has one, or isn't a plist the
/// command can read.
String? addMicrophoneUse(String plist) {
  if (plist.contains('<key>NSMicrophoneUsageDescription</key>')) return null;
  final end = plist.lastIndexOf('</dict>');
  if (end < 0 || !plist.contains('<plist')) return null;
  final indent = RegExp(r'^([ \t]+)<key>', multiLine: true).firstMatch(plist)?.group(1) ?? '\t';
  final lineStart = plist.lastIndexOf('\n', end) + 1;
  final added = '$indent<key>NSMicrophoneUsageDescription</key>\n$indent<string>$microphoneUse</string>\n';
  return plist.substring(0, lineStart) + added + plist.substring(lineStart);
}
