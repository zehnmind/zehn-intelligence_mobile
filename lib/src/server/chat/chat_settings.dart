/// How the chat looks and what it may do: the `chat` field of
/// `GET /v1/suggestions`, which the SDK asks for each time the chat opens
/// empty. Missing or broken fields fall back to the SDK's own defaults.
class ZiChatSettings {
  const ZiChatSettings({
    this.services = const {},
    this.languages = const [],
    this.defaultLanguage,
    this.theme = const {},
    this.welcomeTitle,
    this.welcomeSubtitle,
    this.specVersion,
  });

  factory ZiChatSettings.fromJson(Object? json) {
    if (json is! Map) return const ZiChatSettings();
    final theme = json['theme'];
    return ZiChatSettings(
      services: _strings(json['services']).toSet(),
      languages: _strings(json['languages']),
      defaultLanguage: _string(json['default_language']),
      theme: theme is Map ? theme.cast<String, Object?>() : const {},
      welcomeTitle: _string(json['welcome_title']),
      welcomeSubtitle: _string(json['welcome_subtitle']),
      specVersion: _string(json['spec_version']),
    );
  }

  /// Switched-on services: `llm`, `stt` (the mic), `tts` (spoken replies).
  final Set<String> services;

  /// Languages the assistant speaks; empty means the SDK's own list.
  final List<String> languages;
  final String? defaultLanguage;

  /// Colours, radius and font for the chat and its cards
  /// (`docs/DYNAMIC_CARDS.md`).
  final Map<String, Object?> theme;

  /// Already in the language the suggestions were asked in; null uses the
  /// SDK's words.
  final String? welcomeTitle;
  final String? welcomeSubtitle;

  /// Sent back as `X-ZI-Spec-Version` when set.
  final String? specVersion;

  bool get speech => services.contains('stt');
  bool get voiceReply => services.contains('tts');
}

String? _string(Object? v) => v is String && v.isNotEmpty ? v : null;

List<String> _strings(Object? v) => v is List ? [for (final x in v) if (x is String) x] : const [];
