import 'dart:async';
import 'dart:math';

import '../api/api_client.dart';
import 'file_store.dart';

/// Where the `Authorization: Bearer …` token for console calls comes from.
abstract interface class ZiTokenSource {
  /// The current token, fetched if there is none yet.
  Future<String> token();

  /// A new token, after the server said the old one is expired or bad.
  Future<String> refresh();
}

/// A Zehn user token the app gets from its own backend (which calls
/// `POST /v1/user-tokens` with its server key).
class CallbackTokenSource implements ZiTokenSource {
  CallbackTokenSource(this._fetch);

  final FutureOr<String?> Function() _fetch;
  String? _token;

  @override
  Future<String> token() async => _token ?? await refresh();

  @override
  Future<String> refresh() async {
    final value = await _fetch();
    if (value == null || value.isEmpty) {
      _token = null;
      throw const ZiApiException('user_token_required', message: 'The app gave no user token.');
    }
    return _token = value;
  }
}

/// An anonymous token for this install, from `POST /v1/installs`. Used when
/// the app gives no user token.
class InstallTokenSource implements ZiTokenSource {
  InstallTokenSource({required ZiApiClient api, required ZiFileStore store, DateTime Function()? now})
    : _api = api,
      _store = store,
      _now = now ?? DateTime.now;

  static const _file = 'install';

  final ZiApiClient _api;
  final ZiFileStore _store;
  final DateTime Function() _now;

  String? _installId;
  String? _token;
  DateTime? _expiresAt;
  Future<String>? _pending;

  @override
  Future<String> token() async {
    await _load();
    final expires = _expiresAt;
    if (_token != null && expires != null && expires.isAfter(_now().add(const Duration(seconds: 60)))) {
      return _token!;
    }
    return refresh();
  }

  @override
  Future<String> refresh() => _pending ??= _issue().whenComplete(() => _pending = null);

  Future<void> _load() async {
    if (_installId != null) return;
    final saved = await _store.read(_file);
    final id = saved?['install_id'];
    _installId = id is String && id.length == 32 ? id : _newId();
    final token = saved?['token'];
    final expires = saved?['expires_at'];
    if (token is String && expires is String) {
      _token = token;
      _expiresAt = DateTime.tryParse(expires);
    }
  }

  Future<String> _issue() async {
    await _load();
    final body = await _api.postJson('/v1/installs', {'install_id': _installId});
    final token = body is Map ? body['token'] : null;
    if (token is! String || token.isEmpty) {
      throw const ZiApiException('invalid_response', message: 'No token in the install answer.');
    }
    final expiresIn = body is Map && body['expires_in'] is num ? (body['expires_in'] as num).toInt() : 3600;
    _token = token;
    _expiresAt = _now().add(Duration(seconds: expiresIn));
    await _store.write(_file, {
      'install_id': _installId,
      'token': token,
      'expires_at': _expiresAt!.toIso8601String(),
    });
    return token;
  }

  static String _newId() {
    final random = Random.secure();
    return List.generate(16, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  }
}
