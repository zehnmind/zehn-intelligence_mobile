import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zehn_intelligence/src/server/surface/formats.dart';
import 'package:zehn_intelligence/src/server/surface/surface.dart';
import 'package:zehn_intelligence/src/server/surface/surface_view.dart';
import 'package:zehn_intelligence/src/version.dart';

/// `catalog/zehn.basic.json` is what the console's analyzer reads to draft
/// cards for this SDK. It must list exactly what `surface_view.dart` draws.
void main() {
  final catalog = jsonDecode(File('catalog/zehn.basic.json').readAsStringSync()) as Map<String, Object?>;
  final blocks = (catalog['blocks']! as Map).cast<String, Map<String, Object?>>();
  final common = (catalog['common']! as Map).cast<String, Object?>();
  Set<String> names(String key) => {for (final x in catalog[key]! as List) x as String};

  test('names the catalog and this SDK version', () {
    expect(catalog['catalog'], 'zehn.basic.v0');
    expect(catalog['sdk_version'], zehnIntelligenceVersion);
    final pubspec = RegExp(r'^version:\s*(\S+)', multiLine: true).firstMatch(File('pubspec.yaml').readAsStringSync());
    expect(pubspec?[1], zehnIntelligenceVersion);
  });

  test('lists exactly the blocks, icons, formats and actions the SDK draws', () {
    expect(blocks.keys.toSet(), ziCatalog);
    expect(names('icons'), ziIcons.keys.toSet());
    expect(names('formats'), ziFormats);
    expect((catalog['actions']! as Map).keys.toSet(), ziAllowedActions);
  });

  test('every block says when to use it, and every property has a known type', () {
    const types = {'string', 'value', 'number', 'bool', 'id', 'children', 'action', 'text_style', 'color', 'radius', 'icon'};
    bool known(Object? type) => type is List ? type.every((x) => x is String) && type.isNotEmpty : types.contains(type);
    for (final MapEntry(key: name, value: block) in blocks.entries) {
      expect(block['about'], isA<String>().having((s) => s.length, 'length', greaterThan(10)), reason: name);
      for (final MapEntry(:key, :value) in (block['props']! as Map).entries) {
        expect(known(value), isTrue, reason: '$name.$key: $value');
      }
    }
    for (final MapEntry(:key, :value) in common.entries) {
      expect(known(value), isTrue, reason: 'common.$key: $value');
    }
  });

  // Each block is drawn with a map that notes every key the renderer reads:
  // the file's common properties and the block's own, no more, no fewer.
  for (final name in ziCatalog) {
    testWidgets('$name: the file lists the properties the renderer reads', (tester) async {
      final spy = _Spy({
        'id': 'block',
        'component': name,
        if (name == 'Box') 'child': 'leaf',
        if (name == 'Column' || name == 'Row') 'children': ['leaf'],
      });
      final surface = ZiSurface.parse({
        'createSurface': {
          'root': 'root',
          'components': [
            {'id': 'root', 'component': 'Column', 'children': ['block']},
            spy,
            {'id': 'leaf', 'component': 'Text', 'text': 'x'},
          ],
        },
      });
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ZiSurfaceView(surface: surface, data: const {}, theme: const ZiTheme({}), language: 'en', onAction: (_) {}),
        ),
      ));
      final listed = {...common.keys, ...(blocks[name]!['props']! as Map).keys.cast<String>()};
      expect(spy.reads, listed);
    });
  }
}

class _Spy extends MapBase<String, Object?> {
  _Spy(this._inner);

  final Map<String, Object?> _inner;
  final Set<String> reads = {};

  @override
  Object? operator [](Object? key) {
    reads.add('$key');
    return _inner[key];
  }

  @override
  bool containsKey(Object? key) {
    reads.add('$key');
    return _inner.containsKey(key);
  }

  @override
  void operator []=(String key, Object? value) => _inner[key] = value;

  @override
  void clear() => _inner.clear();

  @override
  Iterable<String> get keys => _inner.keys;

  @override
  Object? remove(Object? key) => _inner.remove(key);
}
