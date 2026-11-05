/// Text in several languages, keyed by language code.
///
/// Agent copy — a fallback lead line, a confirmation card — is written by the
/// app in every language it supports, and picked per reply: the reply's
/// language can differ from the app's when the user writes in another one.
class LocalizedText {
  const LocalizedText(this.values);

  /// The same text in every language.
  LocalizedText.same(String text) : values = {'*': text};

  final Map<String, String> values;

  /// The text for [language], else for [fallback], else any.
  String resolve(String language, {String fallback = 'en'}) =>
      values[language] ??
      values[fallback] ??
      values['*'] ??
      (values.isEmpty ? '' : values.values.first);

  bool get isEmpty => values.isEmpty;

  @override
  String toString() => 'LocalizedText($values)';
}
