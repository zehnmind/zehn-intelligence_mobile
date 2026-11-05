import '../schema/prop_schema.dart';

/// A kind of thing the agent can show and refer back to: a product, an
/// account, a reservation.
///
/// [name] is also the allowlist key: `PropSchema.entityId(kind.name)` accepts
/// only ids of this kind that the app has handed out.
class EntityKind<T> {
  const EntityKind(this.name, {this.prefix});

  final String name;

  /// Prefix for ids the app mints itself ([EntityStore.mint]), e.g. `rt` for
  /// a route worked out on the phone. Defaults to the first letters of
  /// [name].
  final String? prefix;

  @override
  String toString() => 'EntityKind($name)';
}

/// Something that holds per-conversation state and must forget it when a new
/// conversation starts or an old one is resumed.
abstract interface class ConversationScoped {
  void resetConversation();
}

/// Everything this conversation has fetched, by kind and id.
///
/// Three jobs, all load-bearing:
///
/// 1. **Rendering.** A card names an entity by id; what it shows comes from
///    the object stored here — the app's own data. The model never writes it.
/// 2. **Id allowlists.** An id is accepted only if a read in this
///    conversation put it here first (or a live source vouches for it), so a
///    hallucinated id fails validation instead of reaching the network.
/// 3. **Minting.** Results the app works out itself — a route, a quote — get
///    an id here, so the model can refer to them like anything else.
///
/// Two layers. The conversation layer is emptied by [clear] (a new chat, or a
/// resumed one: ids from days ago must not pass validation on the strength of
/// an old read). Live sources — reference data, lists the app keeps current —
/// survive it. Other [AgentAllowlists] can be added as sources too; those
/// that are [ConversationScoped] are reset with the store.
class EntityStore implements AgentAllowlists, ConversationScoped {
  EntityStore({DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;
  final Map<String, Map<String, Object?>> _items = {};
  final Map<String, _LiveSource> _live = {};
  final List<AgentAllowlists> _sources = [];
  int _sequence = 0;

  // ── Conversation layer ────────────────────────────────────────────────────

  /// Remembers one entity under [id].
  void remember<T>(EntityKind<T> kind, String id, T value) {
    if (id.isEmpty) return;
    (_items[kind.name] ??= {})[id] = value;
  }

  /// Remembers every value whose [idOf] is non-empty.
  void rememberAll<T>(
    EntityKind<T> kind,
    Iterable<T> values,
    String? Function(T value) idOf,
  ) {
    for (final value in values) {
      final id = idOf(value);
      if (id != null && id.isNotEmpty) remember(kind, id, value);
    }
  }

  /// Stores something the app worked out itself and returns a fresh id for
  /// it: `<prefix>_<time><sequence>`, unique across restarts.
  String mint<T>(EntityKind<T> kind, T value) {
    final prefix = kind.prefix ?? _defaultPrefix(kind.name);
    final id =
        '${prefix}_${_clock().millisecondsSinceEpoch.toRadixString(36)}'
        '${(_sequence++).toRadixString(36)}';
    remember(kind, id, value);
    return id;
  }

  /// The entity with [id]: from this conversation first, then from a live
  /// source's lookup.
  T? get<T>(EntityKind<T> kind, String id) {
    final local = _items[kind.name]?[id];
    if (local is T) return local;
    final lookup = _live[kind.name]?.lookup;
    final live = lookup?.call(id);
    return live is T ? live : null;
  }

  /// Every entity of [kind] this conversation holds, oldest first.
  Iterable<T> all<T>(EntityKind<T> kind) =>
      (_items[kind.name]?.values ?? const <Object?>[]).whereType<T>();

  void forget<T>(EntityKind<T> kind, String id) =>
      _items[kind.name]?.remove(id);

  // ── Live sources ──────────────────────────────────────────────────────────

  /// Vouches for ids the app keeps current by itself — reference data loaded
  /// once, the user's reservations as the app's own state holds them. These
  /// survive [clear].
  void addLiveSource<T>(
    EntityKind<T> kind, {
    required Iterable<String> Function() ids,
    T? Function(String id)? lookup,
  }) {
    _live[kind.name] = _LiveSource(ids, lookup);
  }

  void removeLiveSource<T>(EntityKind<T> kind) => _live.remove(kind.name);

  /// Adds another allowlist, such as a host's own typed cache.
  void addSource(AgentAllowlists source) {
    if (!_sources.contains(source)) _sources.add(source);
  }

  void removeSource(AgentAllowlists source) => _sources.remove(source);

  // ── AgentAllowlists / ConversationScoped ──────────────────────────────────

  @override
  Set<String> valuesFor(String key) => {
    ...?_items[key]?.keys,
    ...?_live[key]?.ids(),
    for (final source in _sources) ...source.valuesFor(key),
  };

  /// Forgets everything this conversation fetched. Live sources stay.
  void clear() {
    _items.clear();
    for (final source in _sources) {
      if (source is ConversationScoped) {
        (source as ConversationScoped).resetConversation();
      }
    }
  }

  @override
  void resetConversation() => clear();

  static String _defaultPrefix(String name) {
    final letters = name.replaceAll(RegExp('[^a-zA-Z]'), '').toLowerCase();
    return letters.isEmpty
        ? 'e'
        : letters.substring(0, letters.length < 2 ? letters.length : 2);
  }
}

class _LiveSource {
  const _LiveSource(this.ids, this.lookup);

  final Iterable<String> Function() ids;
  final Object? Function(String id)? lookup;
}
