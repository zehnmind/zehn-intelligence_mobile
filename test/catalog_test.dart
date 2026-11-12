import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zehn_intelligence/src/server/surface/form_words.dart';
import 'package:zehn_intelligence/src/server/surface/formats.dart';
import 'package:zehn_intelligence/src/server/surface/surface.dart';
import 'package:zehn_intelligence/src/server/surface/surface_view.dart';
import 'package:zehn_intelligence/src/version.dart';

/// What the file lists but the renderer does not draw yet.
const _notYet = (
  blocks: {'TextField', 'Checkbox', 'Switch', 'Select', 'DateField'},
  actions: <String>{},
  common: <String>{},
);

/// `catalog/zehn.basic.json` is what the console's analyzer reads to draft
/// cards for this SDK. It must list exactly what `surface_view.dart` draws.
void main() {
  final catalog = jsonDecode(File('catalog/zehn.basic.json').readAsStringSync()) as Map<String, Object?>;
  final blocks = (catalog['blocks']! as Map).cast<String, Map<String, Object?>>();
  final common = (catalog['common']! as Map).cast<String, Object?>();
  Set<String> names(String key) => {for (final x in catalog[key]! as List) x as String};

  test('names the catalog and this SDK version', () {
    expect(catalog['catalog'], 'zehn.basic.v1');
    expect(catalog['sdk_version'], zehnIntelligenceVersion);
    final pubspec = RegExp(r'^version:\s*(\S+)', multiLine: true).firstMatch(File('pubspec.yaml').readAsStringSync());
    expect(pubspec?[1], zehnIntelligenceVersion);
  });

  test('lists exactly the blocks, icons, formats and actions the SDK draws', () {
    expect(blocks.keys.toSet(), {...ziCatalog, ..._notYet.blocks});
    expect(names('icons'), ziIcons.keys.toSet());
    expect(names('formats'), ziFormats);
    expect((catalog['actions']! as Map).keys.toSet(), {...ziAllowedActions, ..._notYet.actions});
  });

  test('every block says when to use it, and every property has a known type', () {
    const types = {
      'string', 'value', 'number', 'bool', 'id', 'children', 'action', 'text_style', 'color', 'radius', 'icon',
      'icon_name', 'insets', 'shadow', 'spans', 'field', 'literal', 'checks', 'options', 'date', //
    };
    bool known(Object? type) => switch (type) {
      List() => type.every((x) => x is String) && type.isNotEmpty,
      // A range: {"type": "number", "min": 6, "max": 96}.
      Map() => types.contains(type['type']) && type['min'] is num && type['max'] is num,
      _ => types.contains(type),
    };
    for (final MapEntry(key: name, value: block) in blocks.entries) {
      expect(block['about'], isA<String>().having((s) => s.length, 'length', greaterThan(10)), reason: name);
      for (final MapEntry(:key, :value) in (block['props']! as Map).entries) {
        expect(known(value), isTrue, reason: '$name.$key: $value');
      }
    }
    for (final MapEntry(:key, :value) in common.entries) {
      expect(known(value), isTrue, reason: 'common.$key: $value');
    }
    for (final MapEntry(:key, :value) in (catalog['field']! as Map).entries) {
      expect(known(value), isTrue, reason: 'field.$key: $value');
    }
  });

  test('every block has a group and says what it cannot draw without', () {
    final all = {...common.keys, ...(catalog['field']! as Map).keys};
    for (final MapEntry(key: name, value: block) in blocks.entries) {
      expect(const {'layout', 'content', 'field'}, contains(block['group']), reason: name);
      for (final need in block['needs']! as List) {
        // An entry is one property, or a list meaning "any one of these".
        for (final key in need is List ? need : [need]) {
          expect({...all, ...(block['props']! as Map).keys}, contains(key), reason: '$name needs $key');
        }
      }
    }
    expect(blocks['Text']!['needs'], [['text', 'spans']]);
    expect(blocks['Select']!['needs'], ['field', 'label', 'options']);
  });

  test('says what needs zehn.basic.v1, which checks exist, and the error colour', () {
    expect(catalog['since'], {
      'zehn.basic.v1': {
        'blocks': ['Stack', 'Wrap', 'Progress', 'Avatar', 'TextField', 'Checkbox', 'Switch', 'Select', 'DateField'],
        'common': ['position'], 'actions': ['submit'], 'values': ['equals'],
      },
    });
    expect((catalog['checks']! as Map).keys.toSet(), {'required', 'length', 'range', 'items'});
    expect(names('colors'), contains('error'));
  });

  test("the file's words are the SDK's own", () => expect(catalog['words'], ziFormWords));

  // Each block is drawn with a map that notes every key the renderer reads:
  // the file's common properties and the block's own, no more, no fewer.
  for (final name in ziCatalog) {
    testWidgets('$name: the file lists the properties the renderer reads', (tester) async {
      final spy = _Spy({
        'id': 'block',
        'component': name,
        if (name == 'Box') 'child': 'leaf',
        if (name == 'Column' || name == 'Row' || name == 'Stack' || name == 'Wrap') 'children': ['leaf'],
      });
      // Under a Column the block's flex is read, under a Stack its position.
      for (final parent in ['Column', 'Stack']) {
        final surface = ZiSurface.parse({
          'createSurface': {
            'root': 'root',
            'components': [
              {'id': 'root', 'component': parent, 'children': ['block']},
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
      }
      final listed = {...common.keys.toSet().difference(_notYet.common), ...(blocks[name]!['props']! as Map).keys.cast<String>()};
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
