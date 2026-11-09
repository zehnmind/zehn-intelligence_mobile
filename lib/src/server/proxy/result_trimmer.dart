import '../bootstrap/bootstrap.dart';

/// Keeps only what [rule] asks for: the JSON at `root`, at most `maxItems`
/// of a list, and only `fields` of each object. No rule keeps everything.
Object? trimResult(Object? body, ZiResultRule? rule) {
  if (rule == null) return body;
  var node = rule.root == null ? body : _at(body, rule.root!);
  if (node is List) {
    node = [for (final item in node.take(rule.maxItems)) _pick(item, rule.fields)];
  } else {
    node = _pick(node, rule.fields);
  }
  return node;
}

Object? _at(Object? node, String path) {
  for (final part in path.split('/').where((p) => p.isNotEmpty)) {
    if (node is Map) {
      node = node[part];
    } else if (node is List) {
      final i = int.tryParse(part);
      node = i != null && i >= 0 && i < node.length ? node[i] : null;
    } else {
      return null;
    }
  }
  return node;
}

Object? _pick(Object? item, List<String> fields) {
  if (fields.isEmpty || item is! Map) return item;
  final out = <String, Object?>{};
  for (final field in fields) {
    final parts = field.split('/').where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) continue;
    final value = _at(item, field);
    if (value == null && !_has(item, parts)) continue;
    var target = out;
    for (final key in parts.take(parts.length - 1)) {
      target = (target[key] ??= <String, Object?>{}) as Map<String, Object?>;
    }
    target[parts.last] = value;
  }
  return out;
}

bool _has(Map<Object?, Object?> item, List<String> parts) {
  Object? node = item;
  for (final part in parts) {
    if (node is! Map || !node.containsKey(part)) return false;
    node = node[part];
  }
  return true;
}
