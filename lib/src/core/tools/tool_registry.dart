import 'dart:async';

import '../config/agent_remote_config.dart';
import '../engine/agent_state.dart';
import '../schema/prop_schema.dart';
import '../text/localized_text.dart';
import 'agent_tool.dart';

/// Thrown when a tool is declared unsafely or twice. Raised at registration,
/// so a bad declaration fails when the app starts rather than in front of a
/// user.
class AgentRegistrationError extends Error {
  AgentRegistrationError(this.message);

  final String message;

  @override
  String toString() => 'AgentRegistrationError: $message';
}

/// What was changed about the tools from outside the app's code — the
/// dashboard: their words, and switches that turn them off. Never what a
/// tool does.
class AgentToolOverlay {
  const AgentToolOverlay({this.off = const {}, this.text = const {}});

  /// Tools switched off. Effective "on" is the app's switch AND this one.
  final Set<String> off;

  /// Per tool name: words in place of the code's.
  final Map<String, ToolOverride> text;

  bool get isEmpty => off.isEmpty && text.isEmpty;
}

/// The tools the model may propose, as the app has them right now.
///
/// Fully dynamic: tools are added, removed, switched on and off at run time,
/// and each has an `availableWhen` predicate evaluated every turn. The
/// catalog the model sees, the prompt notes and the gate all read from here,
/// so a tool that is gone is gone everywhere at once.
class AgentToolRegistry {
  AgentToolRegistry({List<String> order = const []}) : _order = order;

  final List<String> _order;
  final Map<String, AgentTool> _tools = {};
  final Set<String> _disabled = {};
  AgentToolOverlay _overlay = const AgentToolOverlay();
  final StreamController<void> _changes = StreamController<void>.broadcast();

  /// Fires after any add, remove or enable change.
  Stream<void> get changes => _changes.stream;

  /// Adds [tool]. Throws [AgentRegistrationError] if its declaration is
  /// unsafe or its name is taken.
  void add(AgentTool tool) {
    final problems = tool.problems();
    if (problems.isNotEmpty) {
      throw AgentRegistrationError('${tool.name}: ${problems.join('; ')}');
    }
    if (_tools.containsKey(tool.name)) {
      throw AgentRegistrationError('${tool.name} is already registered');
    }
    _tools[tool.name] = tool;
    _changed();
  }

  void addAll(Iterable<AgentTool> tools) {
    for (final tool in tools) {
      add(tool);
    }
  }

  /// Removes a tool; returns whether it was there.
  bool remove(String name) {
    final removed = _tools.remove(name) != null;
    _disabled.remove(name);
    if (removed) _changed();
    return removed;
  }

  void setEnabled(String name, bool enabled) {
    final changed = enabled ? _disabled.remove(name) : _disabled.add(name);
    if (changed) _changed();
  }

  bool isEnabled(String name) => _tools.containsKey(name) && !_isOff(name);

  bool _isOff(String name) =>
      _disabled.contains(name) || _overlay.off.contains(name);

  /// What the dashboard changed. Read on every turn: the catalog, the notes,
  /// the lead lines and the gate all see a change on the next one.
  AgentToolOverlay get overlay => _overlay;

  set overlay(AgentToolOverlay value) {
    _overlay = value;
    _changed();
  }

  /// The tool called [name], enabled or not.
  AgentTool? operator [](String name) => _tools[name];

  bool contains(String name) => _tools.containsKey(name);

  /// Every tool, in catalog order.
  List<AgentTool> get all {
    final ordered = <AgentTool>[
      for (final name in _order)
        if (_tools[name] != null) _tools[name]!,
    ];
    for (final tool in _tools.values) {
      if (!_order.contains(tool.name)) ordered.add(tool);
    }
    return ordered;
  }

  /// Every enabled tool, in catalog order.
  List<AgentTool> get enabled => [
    for (final tool in all)
      if (!_isOff(tool.name)) tool,
  ];

  /// Whether [tool] may run for this [state]: registered, enabled, signed in
  /// if it needs that, and its own predicate agrees.
  bool isAvailable(AgentTool tool, AgentState state) =>
      identical(_tools[tool.name], tool) &&
      !_isOff(tool.name) &&
      (!tool.requiresSignIn || state.isSignedIn) &&
      (tool.availableWhen?.call(state) ?? true);

  /// The tool called [name] if it may run for [state], else null.
  AgentTool? usable(String name, AgentState state) {
    final tool = _tools[name];
    return tool != null && isAvailable(tool, state) ? tool : null;
  }

  /// The tool list handed to the model for this turn.
  ///
  /// Withheld, so the model cannot propose them and be refused: tools that
  /// are off, need sign-in the user lacks, or fail their predicate; and tools
  /// whose required list is empty — nothing to cancel, nothing to forget.
  List<Map<String, Object?>> catalog(
    AgentState state, {
    AgentAllowlists? allowlists,
  }) => [
    for (final tool in all)
      if (isAvailable(tool, state) && !tool.isUnusable(allowlists: allowlists))
        _withText(tool, tool.toJsonSchema(allowlists: allowlists)),
  ];

  /// The dashboard's descriptions, written into a freshly built schema in
  /// place — the order of its keys, and so the prompt, is kept.
  Map<String, Object?> _withText(AgentTool tool, Map<String, Object?> schema) {
    final text = _overlay.text[tool.name];
    if (text == null) return schema;
    final description = text.description;
    if (description != null) {
      schema['description'] =
          AgentConfigPick.text(description, tool.description) ??
          tool.description;
    }
    final properties = (schema['parameters'] as Map?)?['properties'];
    if (properties is Map) {
      for (final MapEntry(key: arg, value: override) in text.args.entries) {
        final property = properties[arg];
        final code = tool.args[arg]?.description;
        if (property is Map && code != null) {
          property['description'] =
              AgentConfigPick.text(override, code) ?? code;
        }
      }
    }
    return schema;
  }

  /// [tool]'s lead lines, with the dashboard's merged in per language.
  ToolFallback? fallbackOf(String name) {
    final tool = _tools[name];
    if (tool == null) return null;
    final text = _overlay.text[name];
    if (text == null ||
        (text.found.isEmpty && text.empty.isEmpty && text.always.isEmpty)) {
      return tool.fallback;
    }
    LocalizedText? merge(LocalizedText? code, Map<String, String> override) =>
        override.isEmpty
        ? code
        : LocalizedText({...?code?.values, ...override});
    final code = tool.fallback;
    return ToolFallback(
      found: merge(code.found, text.found),
      empty: merge(code.empty, text.empty),
      always: merge(code.always, text.always),
      tone: code.tone,
    );
  }

  /// The questions users ask [name] with, per language: the dashboard's
  /// where it gave some, else the code's.
  Map<String, List<String>> examplesOf(String name) {
    final code = _tools[name]?.doc?.examples ?? const {};
    final override = _overlay.text[name]?.examples ?? const {};
    return override.isEmpty ? code : {...code, ...override};
  }

  /// Planning notes of every enabled tool, in catalog order.
  ///
  /// Keyed on enabled rather than offered this turn: a signed-out user still
  /// gets the same guidance, so the prompt does not change shape when they
  /// sign in.
  List<String> get decideNotes => [
    for (final tool in enabled)
      if (AgentConfigPick.text(
            _overlay.text[tool.name]?.decideNotes,
            tool.decideNotes,
          )
          case final notes? when notes.trim().isNotEmpty)
        notes,
  ];

  /// Reply rules of every enabled tool, in catalog order.
  List<String> get renderNotes => [
    for (final tool in enabled)
      if (AgentConfigPick.text(
            _overlay.text[tool.name]?.renderNotes,
            tool.renderNotes,
          )
          case final notes? when notes.trim().isNotEmpty)
        notes,
  ];

  /// Runs every enabled tool's [AgentTool.prime] once, concurrently. The same
  /// primer shared by several tools runs once.
  Future<void> prime(AgentState state) {
    final primers = <ToolPrimer>{
      for (final tool in enabled)
        if (tool.prime != null) tool.prime!,
    };
    return Future.wait([for (final prime in primers) prime(state)]);
  }

  void _changed() {
    if (!_changes.isClosed) _changes.add(null);
  }

  Future<void> dispose() => _changes.close();
}
