import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Small JSON files the SDK keeps between launches (the install id), in
/// the app's support folder.
class ZiFileStore {
  ZiFileStore([Future<Directory> Function()? dir]) : _dir = dir ?? _defaultDir;

  final Future<Directory> Function() _dir;

  static Future<Directory> _defaultDir() async {
    final base = await getApplicationSupportDirectory();
    return Directory('${base.path}/zehn_intelligence');
  }

  Future<File> _file(String name) async => File('${(await _dir()).path}/$name.json');

  /// Null when the file is missing, unreadable or not a JSON object.
  Future<Map<String, Object?>?> read(String name) async {
    try {
      final file = await _file(name);
      if (!await file.exists()) return null;
      final decoded = jsonDecode(await file.readAsString());
      return decoded is Map ? decoded.cast<String, Object?>() : null;
    } on Object {
      return null;
    }
  }

  Future<void> write(String name, Map<String, Object?> json) async {
    final file = await _file(name);
    await file.parent.create(recursive: true);
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(jsonEncode(json), flush: true);
    await temp.rename(file.path);
  }

  Future<void> delete(String name) async {
    final file = await _file(name);
    if (await file.exists()) await file.delete();
  }
}
