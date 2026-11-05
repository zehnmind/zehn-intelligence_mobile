import 'dart:convert';

/// Pulls one JSON object out of whatever a model actually returned.
///
/// Asked for "JSON only", models still wrap it in ```json fences, prefix it
/// with "Sure! Here you go:", or trail an explanation after it. Rejecting all
/// of that as malformed turns an otherwise-correct answer into a blank reply,
/// so this takes the outermost `{…}` and tries that.
abstract final class AgentJson {
  static Map<String, Object?>? extractObject(String? text) {
    if (text == null) return null;
    var body = text.trim();
    if (body.isEmpty) return null;

    final fenced = RegExp(r'```(?:json)?\s*([\s\S]*?)```').firstMatch(body);
    if (fenced != null) body = fenced.group(1)!.trim();

    final direct = _tryDecode(body);
    if (direct != null) return direct;

    final start = body.indexOf('{');
    final end = body.lastIndexOf('}');
    if (start == -1 || end <= start) return null;
    return _tryDecode(body.substring(start, end + 1));
  }

  static Map<String, Object?>? _tryDecode(String text) {
    try {
      final decoded = jsonDecode(text);
      return decoded is Map ? Map<String, Object?>.from(decoded) : null;
    } catch (_) {
      return null;
    }
  }

  /// True when [text] looks like it was meant to be JSON, so failing to parse
  /// it means the model broke format rather than chose to answer in prose.
  static bool looksLikeJson(String text) {
    final trimmed = text.trimLeft();
    return trimmed.startsWith('{') ||
        trimmed.startsWith('[') ||
        trimmed.startsWith('```');
  }
}
