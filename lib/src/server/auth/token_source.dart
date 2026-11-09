import 'dart:async';
import 'dart:math';

import '../api/api_client.dart';
import 'file_store.dart';

/// Where the `Authorization: Bearer …` token for console calls comes from.
abstract interface class ZiTokenSource {
  /// The current token, fetched if there is none yet; null sends none.
  Future<String?> token();

  /// A new token, after the server said the old one is expired or bad;
  /// null when there is no way to get one.
  Future<String?> refresh();
}

/// A Zehn user token the app gets from its own backend (which calls
/// `POST /v1/user-tokens` with its server key).
class CallbackTokenSource implements ZiTokenSource {
  CallbackTokenSource(this._fetch);

  final FutureOr<String?> Function() _fetch;
  String? _token;

  @override
  Future<String?> token() async => _token ?? await refresh();

  @override
  Future<String?> refresh() async {
    final value = await _fetch();
    if (value == null || value.isEmpty) {
      _token = null;
      throw const ZiApiException('user_token_required', message: 'The app gave no user token.');
    }
    return _token = value;
  }
}

/// No Zehn user token: the user is known only by the install id
/// (`X-ZI-Install-Id`), and no `Authorization` header is sent.
class AnonymousTokenSource implements ZiTokenSource {
  const AnonymousTokenSource();

  @override
  Future<String?> token() async => null;

  @override
  Future<String?> refresh() async => null;
}

/// This install's id: 32 hex characters, made once and kept in the SDK's
/// support folder. Sent as `X-ZI-Install-Id` on every console call.
Future<String> loadInstallId(ZiFileStore store) async {
  const file = 'install';
  final id = (await store.read(file))?['install_id'];
  if (id is String && RegExp(r'^[0-9a-f]{32}$').hasMatch(id)) return id;
  final random = Random.secure();
  final fresh = List.generate(16, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  await store.write(file, {'install_id': fresh});
  return fresh;
}
