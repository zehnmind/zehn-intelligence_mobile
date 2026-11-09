/// How the chat looks and what it may do: `GET /v1/config`, asked for in
/// the background at start-up and again each time the chat opens. Missing or
/// broken fields fall back to the SDK's own defaults.
class ZiChatSettings {
  const ZiChatSettings({
    this.services = const {},
    this.languages = const [],
    this.defaultLanguage,
    this.theme = const {},
    this.assistantName,
    this.appName,
    Object? welcomeTitle,
    Object? welcomeSubtitle,
  }) : _welcomeTitle = welcomeTitle,
       _welcomeSubtitle = welcomeSubtitle;

  factory ZiChatSettings.fromJson(Object? json) {
    if (json is! Map) return const ZiChatSettings();
    final theme = json['theme'];
    final copy = json['copy'] is Map ? json['copy'] as Map : const {};
    return ZiChatSettings(
      services: _strings(json['services']).toSet(),
      languages: _strings(json['languages']),
      defaultLanguage: _string(json['default_language']),
      theme: theme is Map ? theme.cast<String, Object?>() : const {},
      assistantName: _string(json['assistant_name']),
      appName: _string(json['app_name']),
      welcomeTitle: copy['welcome_title'],
      welcomeSubtitle: copy['welcome_subtitle'],
    );
  }

  /// Switched-on services: `llm`, `stt` (the mic), `tts` (spoken replies).
  final Set<String> services;

  /// Languages the assistant speaks; empty means the SDK's own list.
  final List<String> languages;
  final String? defaultLanguage;

  /// Colours, text styles, radii and font for the chat and its cards
  /// (`docs/DYNAMIC_CARDS.md`, section 9).
  final Map<String, Object?> theme;

  /// The chat's title; null uses the SDK's word.
  final String? assistantName;
  final String? appName;

  /// One string, or a language map.
  final Object? _welcomeTitle;
  final Object? _welcomeSubtitle;

  bool get speech => services.contains('stt');
  bool get voiceReply => services.contains('tts');

  /// In [language], else the app's default, else `en`, else the first; null
  /// uses the SDK's words.
  String? welcomeTitle(String language) => _pick(_welcomeTitle, language);
  String? welcomeSubtitle(String language) => _pick(_welcomeSubtitle, language);

  String? _pick(Object? value, String language) {
    if (value is String) return _string(value);
    if (value is! Map) return null;
    for (final key in [language, defaultLanguage, 'en']) {
      final text = _string(value[key]);
      if (text != null) return text;
    }
    for (final text in value.values) {
      if (_string(text) case final found?) return found;
    }
    return null;
  }
}

String? _string(Object? v) => v is String && v.isNotEmpty ? v : null;

List<String> _strings(Object? v) => v is List ? [for (final x in v) if (x is String) x] : const [];
