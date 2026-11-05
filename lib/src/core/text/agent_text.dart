/// Small helpers for what tools hand the model.
///
/// Server text is data a prompt injection could hide in, and every character
/// is paid for on every turn — so fields are clipped and blanks dropped
/// before they reach a prompt.
abstract final class AgentText {
  /// A description trimmed to one short paragraph, at a word boundary, or
  /// null when blank.
  ///
  /// Enough for the model to answer "what is it?", bounded because every
  /// character is paid for on every turn — and because server text is data
  /// that a prompt injection could hide in, so less of it is safer.
  static String? snippet(String? text, int max) {
    if (text == null) return null;
    final flat = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (flat.length <= max) return flat.isEmpty ? null : flat;
    final cut = flat.substring(0, max);
    final space = cut.lastIndexOf(' ');
    return '${space > max * 0.6 ? cut.substring(0, space) : cut}…';
  }

  /// Drops null and empty values, so the model is never shown a field that
  /// says nothing — an empty "hours" invites it to guess.
  static Map<String, Object?> present(Map<String, Object?> fields) => {
    for (final entry in fields.entries)
      if (entry.value != null &&
          !(entry.value is String && (entry.value as String).trim().isEmpty))
        entry.key: entry.value,
  };
}
