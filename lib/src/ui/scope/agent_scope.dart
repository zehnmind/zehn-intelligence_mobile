import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../chat/agent_chat_bloc.dart';
import '../components/agent_component.dart';
import '../components/agent_component_registry.dart';
import '../destinations/agent_destination.dart';
import '../destinations/agent_link.dart';
import '../speech/agent_speech_output.dart';
import '../theme/agent_strings.dart';
import '../theme/agent_theme.dart';
import '../zehn_intelligence.dart';

/// Asks the host to verify the user again — a fingerprint, a PIN — before
/// a write the app marked as sensitive. True only when verified.
typedef AgentStepUp =
    Future<bool> Function(BuildContext context, String reason);

/// Shows a short message: "Microphone access is off", "Not confirmed".
typedef AgentNotice = void Function(BuildContext context, String message);

/// Makes a [ZehnIntelligence] available to the chat widgets, with how they look,
/// what they say, and the host services they may call.
///
/// Put it above `MaterialApp`, so the conversation outlives any screen and
/// every route can reach it:
///
/// ```dart
/// AgentScope(
///   intelligence: intelligence,
///   stepUp: (context, reason) => biometrics.authenticate(reason),
///   child: MaterialApp(...),
/// )
/// ```
class AgentScope extends StatelessWidget {
  const AgentScope({
    super.key,
    required ZehnIntelligence intelligence,
    required this.child,
    this.theme,
    this.strings,
    AgentSpeechOutput? speech,
    AgentStepUp? stepUp,
    this.onNotice,
  }) : _intelligence = intelligence,
       _speech = speech,
       _stepUp = stepUp;

  /// Backwards compatibility constructor accepting `agent`.
  const AgentScope.agent({
    Key? key,
    required ZehnIntelligence agent,
    required Widget child,
    AgentTheme? theme,
    AgentStrings Function(BuildContext context)? strings,
    AgentSpeechOutput? speech,
    AgentStepUp? stepUp,
    AgentNotice? onNotice,
  }) : this(
         key: key,
         intelligence: agent,
         child: child,
         theme: theme,
         strings: strings,
         speech: speech,
         stepUp: stepUp,
         onNotice: onNotice,
       );

  final ZehnIntelligence _intelligence;
  ZehnIntelligence get intelligence => _intelligence;
  ZehnIntelligence get agent => _intelligence;
  final Widget child;

  /// Overrides `Theme.of(context).extension<AgentTheme>()`.
  final AgentTheme? theme;

  /// The chat's words in the app's current language. Defaults to the
  /// built-in Uzbek, Russian and English.
  final AgentStrings Function(BuildContext context)? strings;

  final AgentSpeechOutput? _speech;
  final AgentStepUp? _stepUp;

  /// Reads replies aloud: the one given here, else the intelligence's own voice
  /// (`ZehnIntelligence.start` sets it up). Null means silent.
  AgentSpeechOutput? get speech => _speech ?? intelligence.voice?.speaker;

  /// Verifies the user again before a write whose card asks for it: the one
  /// given here, else the intelligence's (`ZehnIntelligence.start(stepUp: …)`). Without
  /// one, such writes cannot be confirmed.
  AgentStepUp? get stepUp => _stepUp ?? intelligence.stepUp;

  /// Defaults to a SnackBar.
  final AgentNotice? onNotice;

  static AgentScope of(BuildContext context) {
    final scope = maybeOf(context);
    assert(scope != null, 'No AgentScope above this widget.');
    return scope!;
  }

  static AgentScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_AgentScopeData>()?.scope;

  /// The intelligence at [context]: the scope's, else the one `ZehnIntelligence.start`
  /// made.
  static ZehnIntelligence intelligenceOf(BuildContext context) {
    final intelligence =
        maybeOf(context)?.intelligence ?? ZehnIntelligence.instance;
    if (intelligence == null) {
      throw FlutterError(
        'No ZehnIntelligence. Call `await ZehnIntelligence.start(…)` in main(), or put an '
        'AgentScope above the app.',
      );
    }
    return intelligence;
  }

  static ZehnIntelligence agentOf(BuildContext context) =>
      intelligenceOf(context);

  /// The chat's theme at [context].
  static AgentTheme themeOf(BuildContext context) =>
      AgentTheme.of(context, scope: maybeOf(context)?.theme);

  /// The chat's words at [context].
  static AgentStrings stringsOf(BuildContext context) {
    final scope = maybeOf(context);
    final custom = scope?.strings;
    if (custom != null) return custom(context);
    final language =
        Localizations.maybeLocaleOf(context)?.languageCode ??
        scope?.agent.session.languageCode ??
        'en';
    return AgentStrings.forLanguage(language);
  }

  /// Shows [message] the way the host wants.
  void notice(BuildContext context, String message) {
    final custom = onNotice;
    if (custom != null) return custom(context, message);
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(SnackBar(content: Text(message)));
  }

  /// What taps do inside the chat.
  AgentTapResolver get taps => ChatTapResolver(this, agent.chat);

  @override
  Widget build(BuildContext context) => BlocProvider<AgentChatBloc>.value(
    value: agent.chat,
    child: _AgentScopeData(scope: this, child: child),
  );
}

class _AgentScopeData extends InheritedWidget {
  const _AgentScopeData({required this.scope, required super.child});

  final AgentScope scope;

  @override
  bool updateShouldNotify(_AgentScopeData oldWidget) =>
      !identical(scope, oldWidget.scope);
}

/// The standard tap behaviour inside a chat.
///
/// * A destination that stays over the chat opens from the tapped card's
///   context; closing it returns to the conversation.
/// * A destination that leaves the chat closes it first, then opens on the
///   next frame from the root navigator — the chat's own context is gone by
///   then.
/// * Either kind opens by running the app's code, or by the app's own link
///   through `ZehnIntelligence.openLink` ([AgentLinks.deliver] by default).
/// * A card's button runs a read through the same gate as the model's
///   proposals, and says the user's choice back as their turn.
///
/// A tap that would fail its check resolves to null, so the card looks inert
/// rather than showing an error the user cannot act on.
class ChatTapResolver implements AgentTapResolver {
  ChatTapResolver(this.scope, this.chat);

  final AgentScope scope;
  final AgentChatBloc chat;

  ZehnIntelligence get _agent => scope.intelligence;

  @override
  VoidCallback? resolve(BuildContext context, AgentTap tap) {
    switch (tap) {
      case AgentTapOpen(:final destination, :final args):
        final target = _agent.destinations[destination];
        if (target == null) {
          _agent.log('intelligence: no destination "$destination"');
          return null;
        }
        final state = _agent.engine.snapshot();
        final refused = target.refuse(args, state, allowlists: _agent.entities);
        if (refused != null) {
          _agent.log('intelligence: blocked "$destination" — $refused');
          return null;
        }
        return () => _open(context, target, args);
      case AgentTapInvoke(:final tool, :final args, :final label):
        if (!_agent.engine.canInvoke(tool)) {
          _agent.log('intelligence: blocked button for "$tool"');
          return null;
        }
        return () => invoker(tool, args, label: label);
    }
  }

  @override
  AgentInvoker get invoker => (tool, args, {label}) {
    if (!_agent.engine.canInvoke(tool)) {
      _agent.log('intelligence: blocked button for "$tool"');
      return;
    }
    scope.speech?.stop();
    chat.add(AgentInvokeRequested(tool, args: args, echo: label));
  };

  void _open(
    BuildContext context,
    AgentDestination destination,
    Map<String, Object?> args,
  ) {
    // Checked again at tap time: the user may have signed out since the
    // card was drawn.
    final state = _agent.engine.snapshot();
    if (destination.refuse(args, state, allowlists: _agent.entities) != null) {
      return;
    }
    scope.speech?.stop();
    final request = DestinationRequest(
      args: args,
      state: state,
      postNote: (result) => chat.add(AgentNotePosted(result)),
      entities: _agent.entities,
      openLink: _agent.openLink ?? AgentLinks.deliver,
    );

    if (destination.leavesChat) {
      final root = Navigator.of(context, rootNavigator: true).context;
      Navigator.of(context).maybePop();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (root.mounted) destination.open(root, request);
      });
      return;
    }

    FocusScope.of(context).unfocus();
    destination.open(context, request);
  }
}
