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

/// This install's id: a random UUID (version 4) in lower case, with hyphens,
/// made once and kept in the SDK's support folder. Sent as `X-ZI-Install-Id`
/// on every console call; the server refuses any other form
/// (`400 invalid_header`).
Future<String> loadInstallId(ZiFileStore store) async {
  const file = 'install';
  final kept = (await store.read(file))?['install_id'];
  if (kept is String && _uuid.hasMatch(kept)) return kept;
  // An id an earlier build kept as 32 hex characters: the same id, with hyphens.
  final id = kept is String && RegExp(r'^[0-9a-f]{32}$').hasMatch(kept) ? _hyphenated(kept) : newInstallId(Random.secure());
  await store.write(file, {'install_id': id});
  return id;
}

/// A new install id in place of the kept one: after a sign-out the next
/// person on the phone is a new user, with none of the last one's history.
Future<String> renewInstallId(ZiFileStore store) async {
  final id = newInstallId(Random.secure());
  await store.write('install', {'install_id': id});
  return id;
}

final _uuid = RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$');

String _hyphenated(String hex) =>
    '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';

/// A random UUID, version 4, in lower case.
String newInstallId(Random random) {
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40; // version 4
  bytes[8] = (bytes[8] & 0x3f) | 0x80; // the RFC 4122 variant
  return _hyphenated(bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join());
}
