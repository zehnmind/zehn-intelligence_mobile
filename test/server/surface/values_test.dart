import 'package:flutter_test/flutter_test.dart';
import 'package:zehn_intelligence/src/server/surface/values.dart';

void main() {
  const v = ZiValues({
    'form': {
      'reason': 'other',
      'guests': 2,
      'tags': ['a', 'b'],
      'agree': true,
    },
  }, 'en');

  test('equals compares the value at the path with a literal', () {
    expect(v.resolve({'path': '/form/reason', 'equals': 'other'}, null), isTrue);
    expect(v.resolve({'path': '/form/reason', 'equals': 'price'}, null), isFalse);
    expect(v.resolve({'path': '/form/guests', 'equals': 2.0}, null), isTrue); // 2 equals 2.0
    expect(v.resolve({'path': '/form/guests', 'equals': '2'}, null), isFalse); // a string never equals a number
    expect(v.resolve({'path': '/form/agree', 'equals': true}, null), isTrue);
    expect(v.resolve({'path': '/form/none', 'equals': 'x'}, null), isFalse);
  });

  test('equals on a list is true when the list holds the literal', () {
    expect(v.resolve({'path': '/form/tags', 'equals': 'b'}, null), isTrue);
    expect(v.resolve({'path': '/form/tags', 'equals': 'c'}, null), isFalse);
  });

  test('shown follows visible', () {
    expect(v.shown({'visible': {'path': '/form/reason', 'equals': 'price'}}, null), isFalse);
    expect(v.shown({'visible': {'path': '/form/agree'}}, null), isTrue);
    expect(v.shown({'visible': ''}, null), isFalse);
    expect(v.shown(const {}, null), isTrue);
  });

  test('paths, language maps, placeholders and formats read as before', () {
    const c = ZiValues({
      'name': {'uz': 'Kino', 'en': 'Cinema'},
      'price': 10000,
    }, 'en');
    expect(c.text({'path': '/name'}, null), 'Cinema');
    expect(c.text('{/price|money:UZS}', null), '10,000\u00A0UZS');
    expect(c.text({'path': 'title'}, {'title': 'Michael'}), 'Michael');
  });
}
