import '../text/localized_text.dart';

/// What the host app tells the agent about the user, read fresh every turn.
///
/// Fail closed: when the app cannot tell whether the user is signed in, say
/// no.
abstract interface class AgentSession {
  /// A session from callbacks into the app's own state — no class needed:
  ///
  /// ```dart
  /// AgentSession.from(
  ///   isSignedIn: () => auth.state is Authenticated,
  ///   languageCode: () => locale.current.languageCode,
  /// )
  /// ```
  ///
  /// Without [isSignedIn] the user counts as signed out, and tools that need
  /// sign-in are never offered.
  factory AgentSession.from({
    bool Function()? isSignedIn,
    String Function()? languageCode,
  }) = CallbackAgentSession;

  /// The language the app is showing, e.g. `uz`.
  String get languageCode;

  bool get isSignedIn;
}

/// See [AgentSession.from].
class CallbackAgentSession implements AgentSession {
  CallbackAgentSession({
    bool Function()? isSignedIn,
    String Function()? languageCode,
  }) : _isSignedIn = isSignedIn,
       _languageCode = languageCode;

  final bool Function()? _isSignedIn;
  final String Function()? _languageCode;

  /// Whether the app said how to tell the user is signed in.
  bool get knowsSignIn => _isSignedIn != null;

  /// Fail closed: no callback, or one that throws, means signed out.
  @override
  bool get isSignedIn {
    try {
      return _isSignedIn?.call() ?? false;
    } catch (_) {
      return false;
    }
  }

  @override
  String get languageCode => _languageCode?.call() ?? 'en';
}

/// A snapshot of the session, taken when a turn starts, plus the host's
/// flags — which screen is open, which feature is switched on.
class AgentState {
  const AgentState({
    required this.languageCode,
    required this.isSignedIn,
    this.flags = const {},
  });

  final String languageCode;
  final bool isSignedIn;
  final Map<String, Object?> flags;

  /// True when [name] is set to `true`.
  bool flag(String name) => flags[name] == true;

  @override
  String toString() =>
      'AgentState($languageCode, signedIn: $isSignedIn, $flags)';
}

/// The numbers that keep a turn bounded. The defaults are what the first app
/// Something the assistant deliberately cannot do, and where in the app the
/// user does it instead. Listed in the generated capabilities document.
class AgentLimitation {
  const AgentLimitation(this.what, this.instead);

  final String what;
  final String instead;
}

/// How the generated capabilities document describes this app.
class AgentDocProfile {
  const AgentDocProfile({
    this.title,
    this.serverName = 'server',
    this.deviceName = 'this phone',
  });

  /// The document's heading. Defaults to "What the `appName` assistant can do".
  final String? title;

  /// Where remote writes land, as the table says it: "Edit — bank server".
  final String serverName;

  /// Where local writes land: "Edit — this phone".
  final String deviceName;
}

/// Who the assistant is and how it is told to behave, for one app.
///
/// Everything app-specific in the prompt comes from here or from the tools
/// themselves; the package supplies only the protocol and the rules that hold
/// for every app.
class AgentProfile {
  const AgentProfile({
    required this.appName,
    this.languages = const ['en'],
    this.defaultLanguage = 'en',
    this.decideGuidance,
    this.decideTrailer,
    this.renderRules,
    this.renderTrailer = const [],
    this.catalogOrder = const [],
    this.helpText,
    this.failedText,
    this.limitations = const [],
    this.docs = const AgentDocProfile(),
  });

  final String appName;

  /// Language codes the assistant answers in, e.g. `['uz', 'ru', 'en']`.
  final List<String> languages;

  /// Used for app-written copy when a reply's language has none.
  final String defaultLanguage;

  /// The paragraph that says when to use a tool at all. Null uses a generic
  /// one.
  final String? decideGuidance;

  /// A closing paragraph for the decide prompt, after every tool's notes.
  final String? decideTrailer;

  /// The bullet rules of the render prompt. Null uses the package's generic
  /// rules. `{locale}` is replaced with the turn's language.
  final List<String>? renderRules;

  /// Bullets that come after every tool's render notes.
  final List<String> renderTrailer;

  /// Tool names in the order the model should see them. Tools not listed
  /// follow in the order they were added.
  final List<String> catalogOrder;

  /// What the assistant says when the model produced nothing usable: what it
  /// can help with.
  final LocalizedText? helpText;

  /// What the assistant says when a tool failed without a reason for the
  /// user.
  final LocalizedText? failedText;

  /// What the assistant cannot do, for the capabilities document.
  final List<AgentLimitation> limitations;

  final AgentDocProfile docs;
}
