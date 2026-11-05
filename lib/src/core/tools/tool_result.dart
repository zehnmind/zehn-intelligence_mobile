/// One card a tool result offers: which component shows it and the id of the
/// entity behind it, plus facts the model may use to write its sentence.
///
/// The facts never reach the card — it is drawn from the app's own data for
/// [id] — so a model that repeats them wrongly cannot put a wrong name or
/// price on screen.
class ToolItem {
  const ToolItem(this.component, this.id, {this.facts = const {}});

  final String component;
  final String id;
  final Map<String, Object?> facts;

  Map<String, Object?> toJson() => {
    'component': component,
    'id': id,
    for (final entry in facts.entries)
      if (!_isBlank(entry.value)) entry.key: entry.value,
  };

  static bool _isBlank(Object? value) =>
      value == null || (value is String && value.trim().isEmpty);
}

/// What running a tool produced.
///
/// The wire shape the model is shown is fixed:
///
/// * [summary] — one English sentence for the model ("Found 3 places.").
/// * `data.items` — `[{component, id, ...facts}]`, one per card to offer.
/// * `data.text` — prose already written in the user's language. Shown as is
///   when the model's reply is unusable, so even the offline fallback
///   carries the real answer.
/// * anything else in [data] — further facts for the model.
class ToolResult {
  const ToolResult({
    required this.tool,
    required this.ok,
    required this.summary,
    this.data = const {},
  });

  /// A failure whose [summary] is for the model only; the user sees a
  /// generic line.
  const ToolResult.failure(this.tool, this.summary)
    : ok = false,
      data = const {};

  /// A success with cards and optional prose.
  factory ToolResult.items(
    String tool,
    String summary, {
    List<ToolItem> items = const [],
    String? text,
    Map<String, Object?> data = const {},
  }) => ToolResult(
    tool: tool,
    ok: true,
    summary: summary,
    data: {
      ...data,
      if (items.isNotEmpty) 'items': [for (final item in items) item.toJson()],
      if (text != null && text.trim().isNotEmpty) 'text': text,
    },
  );

  /// A failure the user is told about in their own language — "level 1 is
  /// full" rather than "couldn't do that".
  factory ToolResult.refusal(String tool, String summary, {String? text}) =>
      ToolResult(
        tool: tool,
        ok: false,
        summary: summary,
        data: {if (text != null && text.trim().isNotEmpty) 'text': text},
      );

  /// The tool that ran.
  final String tool;
  final bool ok;

  /// Human-readable result, safe to show and to feed back to the model.
  final String summary;

  /// Structured result the render step turns into components.
  final Map<String, Object?> data;

  /// `(component, id)` for each card offered, in order.
  List<(String, String)> get items {
    final raw = data['items'];
    if (raw is! List) return const [];
    return [
      for (final item in raw)
        if (item is Map &&
            item['component'] is String &&
            item['id'] is String &&
            (item['id'] as String).isNotEmpty)
          (item['component'] as String, item['id'] as String),
    ];
  }

  /// The prose written by the app, if any.
  String? get text {
    final value = data['text'];
    return value is String && value.trim().isNotEmpty ? value.trim() : null;
  }

  @override
  String toString() => 'ToolResult($tool, ok: $ok, $summary)';
}
