import 'dart:async';
import 'dart:convert';

import '../log.dart';
import 'agent_config_client.dart';
import 'agent_remote_config.dart';

/// The outcome of a refresh.
sealed class AgentConfigRefresh {
  const AgentConfigRefresh();
}

/// A different config was published: apply it.
final class ConfigChanged extends AgentConfigRefresh {
  const ConfigChanged(this.envelope);

  final AgentConfigEnvelope envelope;
}

/// The backend no longer has this agent: go back to the code.
final class ConfigCleared extends AgentConfigRefresh {
  const ConfigCleared();
}

/// Same as before, too soon to ask again, or no answer: keep what is
/// applied.
final class ConfigKept extends AgentConfigRefresh {
  const ConfigKept(this.reason);

  final String reason;
}

/// Keeps one agent's config current without ever holding up a turn.
class AgentConfigSync {
  AgentConfigSync({
    required this.client,
    required this.agentId,
    required this.appVersion,
    required this.pluginVersion,
    this.channel = AgentConfigChannel.live,
    this.minInterval = const Duration(minutes: 5),
    DateTime Function()? clock,
    this.log = silentAgentLog,
  }) : _clock = clock ?? DateTime.now;

  final AgentConfigClient client;
  final String agentId;
  final String appVersion;
  final String pluginVersion;
  final AgentConfigChannel channel;

  /// How long a check stays fresh for [isStale].
  final Duration minInterval;
  final DateTime Function() _clock;
  final AgentLog log;

  DateTime? _lastAsked;
  DateTime? _retryAfter;
  Future<AgentConfigRefresh>? _inFlight;
  _CacheEntry? _cache;

  /// Whether [refresh] would ask the backend now.
  bool get isStale {
    final now = _clock();
    if (_retryAfter != null && now.isBefore(_retryAfter!)) return false;
    return _lastAsked == null || now.difference(_lastAsked!) >= minInterval;
  }

  /// The last config stored for this agent and channel, or null.
  AgentConfigEnvelope? cached() {
    final entry = _cache;
    if (entry == null) return null;
    return AgentConfigEnvelope.fromJson(entry.response);
  }

  /// Asks the backend for what is published. One request at a time; a call
  /// while one runs waits for it. Without [force], a check younger than
  /// [minInterval] is not repeated.
  Future<AgentConfigRefresh> refresh({bool force = false}) {
    final running = _inFlight;
    if (running != null) return running;
    if (!force && !isStale) {
      return Future.value(const ConfigKept('checked recently'));
    }
    final future = _refresh().whenComplete(() => _inFlight = null);
    return _inFlight = future;
  }

  Future<AgentConfigRefresh> _refresh() async {
    _lastAsked = _clock();
    final cache = _cache;
    final fetch = await client.fetch(
      agentId: agentId,
      appVersion: appVersion,
      pluginVersion: pluginVersion,
      channel: channel,
      etag: cache?.etag,
    );
    switch (fetch) {
      case ConfigFetched(:final envelope, :final body, :final etag):
        _writeCache(body, etag);
        log(
          'intelligence: config revision ${envelope.revision} '
          '(${channel.name}) received',
        );
        return ConfigChanged(envelope);
      case ConfigNotModified():
        return const ConfigKept('not modified');
      case ConfigGone():
        _cache = null;
        log('intelligence: config for "$agentId" is gone; using the code\'s');
        return const ConfigCleared();
      case ConfigUnavailable(:final reason, :final retryAfter):
        if (retryAfter != null) _retryAfter = _clock().add(retryAfter);
        log('intelligence: config not refreshed ($reason)');
        return ConfigKept(reason);
    }
  }

  void _writeCache(String body, String? etag) {
    try {
      final response = jsonDecode(body);
      if (response is Map) {
        _cache = _CacheEntry(etag: etag, response: response);
      }
    } on FormatException {
      return;
    }
  }
}

class _CacheEntry {
  const _CacheEntry({required this.etag, required this.response});

  final String? etag;
  final Map<Object?, Object?> response;
}
