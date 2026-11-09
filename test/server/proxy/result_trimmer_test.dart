import 'package:flutter_test/flutter_test.dart';
import 'package:zehn_intelligence/src/server/proxy/http_call.dart';
import 'package:zehn_intelligence/src/server/proxy/result_trimmer.dart';

void main() {
  final items = [
    for (var i = 0; i < 12; i++)
      {
        'id': i,
        'secret': 'x',
        'category': {'name': 'c$i', 'icon': 'i'},
      },
  ];

  test('keeps root, max_items and fields', () {
    final out = trimResult(
      {'total': 12, 'results': items},
      const ZiResultRule(root: '/results', fields: ['id', 'category/name'], maxItems: 10),
    ) as List;
    expect(out, hasLength(10));
    expect(out.first, {
      'id': 0,
      'category': {'name': 'c0'},
    });
  });

  test('no rule returns body unchanged', () {
    final body = {'a': 1};
    expect(trimResult(body, null), same(body));
  });

  test('object root with fields', () {
    final out = trimResult(
      {'data': {'id': 1, 'name': 'n', 'secret': 's'}},
      const ZiResultRule(root: '/data', fields: ['id', 'name']),
    );
    expect(out, {'id': 1, 'name': 'n'});
  });

  test('a list body is capped even without a root', () {
    expect(trimResult(items, const ZiResultRule(maxItems: 3)), hasLength(3));
  });

  test('a missing root is null', () {
    expect(trimResult({'a': 1}, const ZiResultRule(root: '/results')), isNull);
  });

  test('a missing field is left out', () {
    final out = trimResult({'id': 1}, const ZiResultRule(fields: ['id', 'nope/deep']));
    expect(out, {'id': 1});
  });
}
