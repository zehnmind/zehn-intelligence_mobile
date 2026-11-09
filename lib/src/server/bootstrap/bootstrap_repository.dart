import 'package:flutter/foundation.dart';

import '../api/api_client.dart';
import '../auth/file_store.dart';
import 'bootstrap.dart';

/// Keeps the start-up data: the last saved copy at once, a fresh one from
/// the server when it can.
class ZiBootstrapRepository {
  ZiBootstrapRepository({required ZiApiClient api, required ZiFileStore store}) : _api = api, _store = store;

  static const _file = 'bootstrap';

  final ZiApiClient _api;
  final ZiFileStore _store;
  ZiBootstrap? _current;
  Future<ZiBootstrap?>? _pending;

  ZiBootstrap? get current => _current;

  Future<ZiBootstrap?> loadCached() async {
    final saved = await _store.read(_file);
    if (saved == null) return _current;
    try {
      _use(ZiBootstrap.fromJson(saved));
    } on FormatException {
      return _current;
    }
    return _current;
  }

  /// Fetches the published data. On any failure, keeps and returns [current].
  Future<ZiBootstrap?> refresh() => _pending ??= _fetch().whenComplete(() => _pending = null);

  Future<ZiBootstrap?> _fetch() async {
    try {
      final json = await _api.getJson('/v1/bootstrap');
      final fresh = ZiBootstrap.fromJson(json);
      _use(fresh);
      try {
        await _store.write(_file, fresh.toJson());
      } on Object catch (e) {
        debugPrint('zehn_intelligence: start-up data not saved: $e');
      }
    } on ZiApiException catch (e) {
      debugPrint('zehn_intelligence: start-up data not refreshed: $e');
    } on FormatException catch (e) {
      debugPrint('zehn_intelligence: start-up data is broken: $e');
    }
    return _current;
  }

  void _use(ZiBootstrap data) {
    _current = data;
    if (data.specVersion != null) _api.specVersion = data.specVersion;
  }
}
