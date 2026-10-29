import 'package:flutter_test/flutter_test.dart';
// The library exports nothing yet, so nothing from it is used here. The import
// is still the point of this test: if the public library stops resolving or
// compiling, this file fails to load and `flutter test` fails.
// ignore: unused_import
import 'package:zehn_intelligence/zehn_intelligence.dart';

void main() {
  test('the public library imports', () {
    // Reaching this line means the import above compiled.
    expect(true, isTrue);
  });
}
