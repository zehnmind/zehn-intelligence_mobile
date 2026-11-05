import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../voice/widgets/agent_voice_composer.dart';
import '../chat/agent_chat_bloc.dart';
import '../scope/agent_scope.dart';
import '../zehn_intelligence.dart';
import 'agent_composer.dart';
import 'agent_message_list.dart';
import 'agent_voice_replies.dart';

/// A ready chat: the conversation, an input, and the header.
///
/// Every part can be replaced: [header], [emptyState] and [composer] take
/// the app's own widgets; the conversation itself is [AgentMessageList],
/// which apps with their own chat screen use directly.
class AgentChatView extends StatelessWidget {
  const AgentChatView({
    super.key,
    this.header,
    this.emptyState,
    this.composer,
    this.title,
  });

  /// Replaces the default title row.
  final Widget? header;

  /// Shown until the first message.
  final Widget? emptyState;

  /// Replaces the input. Defaults to hold-to-speak when the intelligence has voice,
  /// a text field otherwise.
  final Widget? composer;

  /// The default header's title. Defaults to the assistant's label.
  final String? title;

  @override
  Widget build(BuildContext context) {
    final theme = AgentScope.themeOf(context);
    final intelligence = AgentScope.intelligenceOf(context);
    final language =
        Localizations.maybeLocaleOf(context)?.languageCode ??
        intelligence.session.languageCode;
    // What the default session answers in: the language the chat is shown in.
    intelligence.displayLanguage = language;
    final voice = intelligence.voice;
    return AgentVoiceReplies(
      child: Column(
        children: [
          header ??
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        title ?? AgentScope.stringsOf(context).assistantLabel,
                        style: theme.title.copyWith(color: theme.textPrimary),
                      ),
                    ),
                  ],
                ),
              ),
          Expanded(
            child: BlocBuilder<AgentChatBloc, AgentChatState>(
              builder: (context, state) => state.isEmpty
                  ? (emptyState ?? const SizedBox.shrink())
                  : AgentMessageList(messages: state.messages),
            ),
          ),
          SafeArea(
            top: false,
            minimum: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child:
                composer ??
                (voice != null && voice.isAvailable
                    ? AgentVoiceComposer(voice: voice)
                    : const AgentComposer()),
          ),
        ],
      ),
    );
  }
}

/// Opens [AgentChatView] as a bottom sheet over the current screen.
///
/// With an `AgentScope` above the app it uses that; otherwise the intelligence
/// `ZehnIntelligence.start` made.
abstract final class AgentChatSheet {
  static Future<void> show(
    BuildContext context, {
    Widget? header,
    Widget? emptyState,
    Widget? composer,
    String? title,
    double heightFactor = 0.9,
  }) {
    final theme = AgentScope.themeOf(context);
    final scope = AgentScope.maybeOf(context);
    final intelligence = AgentScope.intelligenceOf(context)
      // What the dashboard published since the last check, before the
      // first question.
      ..refreshConfigIfStale();
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      backgroundColor: theme.surface,
      barrierColor: theme.barrier,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(theme.sheetRadius),
        ),
      ),
      builder: (sheetContext) => _Scoped(
        scope: scope,
        intelligence: intelligence,
        child: Padding(
          // The input sits above the keyboard.
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
          ),
          child: SizedBox(
            height: MediaQuery.sizeOf(sheetContext).height * heightFactor,
            child: Column(
              children: [
                const SizedBox(height: 8),
                theme.handle,
                Expanded(
                  child: AgentChatView(
                    header: header,
                    emptyState: emptyState,
                    composer: composer,
                    title: title,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The sheet's own `AgentScope` when the app has none above it.
class _Scoped extends StatelessWidget {
  const _Scoped({
    required this.scope,
    required this.intelligence,
    required this.child,
  });

  final AgentScope? scope;
  final ZehnIntelligence intelligence;
  final Widget child;

  @override
  Widget build(BuildContext context) => scope == null
      ? AgentScope(intelligence: intelligence, child: child)
      : child;
}
