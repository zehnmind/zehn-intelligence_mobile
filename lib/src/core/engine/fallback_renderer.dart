import '../model/component_spec.dart';
import '../protocol/turn.dart';
import '../text/default_copy.dart';
import '../tools/tool_registry.dart';
import '../tools/tool_result.dart';
import 'agent_state.dart';

/// Renders a tool result without a model.
///
/// Two callers. An offline transport uses it as its only renderer. The engine
/// uses it as a safety net: if a tool succeeded but the model's reply came
/// back empty, unparseable or entirely invalid, the user still gets their
/// answer instead of a blank bubble.
class AgentFallbackRenderer {
  const AgentFallbackRenderer(this._tools, this._profile);

  final AgentToolRegistry _tools;
  final AgentProfile _profile;

  /// [language] if the app answers in it, else the profile's default.
  String supported(String language) => _profile.languages.contains(language)
      ? language
      : _profile.defaultLanguage;

  AgentReply render(ToolResult result, String language) {
    final lang = supported(language);
    final fallbackLanguage = _profile.defaultLanguage;

    if (!result.ok) {
      // A failure that knows its reason — "that card is already frozen" —
      // says it, in the user's language, rather than "couldn't do that".
      return AgentReply(
        components: [
          text(
            result.text ??
                (_profile.failedText ?? AgentDefaultCopy.failed).resolve(
                  lang,
                  fallback: fallbackLanguage,
                ),
            tone: 'warning',
          ),
        ],
        language: lang,
      );
    }

    final items = result.items;
    final tool = _tools[result.tool];
    final fallback = _tools.fallbackOf(result.tool);
    final lead = fallback?.leadFor(
      lang,
      hasItems: items.isNotEmpty,
      fallbackLanguage: fallbackLanguage,
    );
    final tone =
        fallback?.tone ?? (tool == null || tool.isRead ? 'neutral' : 'success');

    // Prose-only results carry their answer pre-written in the user's
    // language, so even this fallback shows the actual data.
    final prose = result.text;

    return AgentReply(
      components: [
        if (lead != null) text(lead, tone: tone),
        if (prose != null) text(prose),
        for (final (component, id) in items)
          ComponentSpec(type: component, props: {'id': id}),
      ],
      language: lang,
    );
  }

  /// A reply with no tool, for when the planner produced nothing usable.
  AgentReply help(String language) {
    final lang = supported(language);
    return AgentReply(
      components: [
        text(
          (_profile.helpText ?? AgentDefaultCopy.help).resolve(
            lang,
            fallback: _profile.defaultLanguage,
          ),
        ),
      ],
      language: lang,
    );
  }

  static ComponentSpec text(String value, {String tone = 'neutral'}) =>
      ComponentSpec(
        type: kAgentTextComponent,
        fallbackText: value,
        props: {'text': value, 'tone': tone},
      );
}
