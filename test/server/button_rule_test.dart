import 'package:flutter_test/flutter_test.dart';
import 'package:zehn_intelligence/src/server/button_rule.dart';

void main() {
  group('reading `button` of GET /v1/config', () {
    test('show_on and its paths', () {
      final rule = ZiButtonRule.fromJson({
        'show_on': 'except',
        'paths': ['/', '/auth', '/signin', '/signup', '/code-verification'],
      });
      expect(rule.showOn, ZiButtonShowOn.except);
      expect(rule.paths, ['/', '/auth', '/signin', '/signup', '/code-verification']);
      expect(ZiButtonRule.fromJson({'show_on': 'only', 'paths': ['/home']}).showOn, ZiButtonShowOn.only);
      expect(ZiButtonRule.fromJson({'show_on': 'all', 'paths': <String>[]}).showOn, ZiButtonShowOn.all);
    });

    test('a missing or unknown show_on counts as all', () {
      for (final json in <Object?>[
        null,
        'except',
        <String, Object?>{},
        {'paths': ['/auth']},
        {'show_on': 'sometimes', 'paths': ['/auth']},
        {'show_on': 7, 'paths': ['/auth']},
      ]) {
        final rule = ZiButtonRule.fromJson(json);
        expect(rule.showOn, ZiButtonShowOn.all, reason: '$json');
        expect(rule.showsOn('/auth'), isTrue, reason: '$json');
      }
    });

    test('only or except with no path to go by counts as all: the button never hides everywhere', () {
      for (final json in <Object?>[
        {'show_on': 'only'},
        {'show_on': 'only', 'paths': <String>[]},
        {'show_on': 'only', 'paths': '/home'},
        {'show_on': 'except', 'paths': [7, null, '']},
      ]) {
        expect(ZiButtonRule.fromJson(json).showOn, ZiButtonShowOn.all, reason: '$json');
      }
      // What isn't a path is left out; the rest stands.
      final rule = ZiButtonRule.fromJson({'show_on': 'only', 'paths': [7, '/home']});
      expect(rule.showOn, ZiButtonShowOn.only);
      expect(rule.paths, ['/home']);
    });
  });

  group('a path matches a screen', () {
    test('segment by segment; a :name or {name} segment matches any one segment', () {
      expect(ziPathMatches('/movies/:id', '/movies/42?day=1'), isTrue);
      expect(ziPathMatches('/orders/{id}', '/orders/7/'), isTrue);
      expect(ziPathMatches('/movies/:id', '/movies'), isFalse);
      expect(ziPathMatches('/', '/home'), isFalse);

      expect(ziPathMatches('/movies/:id', '/movies/42/seats'), isFalse);
      expect(ziPathMatches('/movies/:id/seats/{seat}', '/movies/42/seats/b7'), isTrue);
      expect(ziPathMatches('/movies/:id', '/shows/42'), isFalse);
      expect(ziPathMatches('/auth', '/Auth'), isFalse);
    });

    test('the query, a fragment and a trailing slash are left out, on either side', () {
      expect(ziPathMatches('/home', '/home/'), isTrue);
      expect(ziPathMatches('/home/', '/home'), isTrue);
      expect(ziPathMatches('/home', '/home?tab=2#top'), isTrue);
      expect(ziPathMatches('/home', '/home#top'), isTrue);
    });

    test('/ matches only /', () {
      expect(ziPathMatches('/', '/'), isTrue);
      expect(ziPathMatches('/', '/?next=%2Fhome'), isTrue);
      expect(ziPathMatches('/', '/home'), isFalse);
      expect(ziPathMatches('/:tab', '/'), isFalse);
    });
  });

  group('where the button shows', () {
    test('all: on every screen', () {
      const rule = ZiButtonRule();
      expect(rule.showsOn('/'), isTrue);
      expect(rule.showsOn('/auth'), isTrue);
      expect(rule.showsOn(null), isTrue);
    });

    test('except: on every screen but those in paths', () {
      final rule = ZiButtonRule.fromJson({'show_on': 'except', 'paths': ['/', '/auth', '/movies/:id']});
      expect(rule.showsOn('/'), isFalse);
      expect(rule.showsOn('/auth'), isFalse);
      expect(rule.showsOn('/movies/42?day=1'), isFalse);
      expect(rule.showsOn('/home'), isTrue);
      expect(rule.showsOn('/movies'), isTrue);
    });

    test('only: on the screens in paths and no other', () {
      final rule = ZiButtonRule.fromJson({'show_on': 'only', 'paths': ['/home']});
      expect(rule.showsOn('/home/'), isTrue);
      expect(rule.showsOn('/profile'), isFalse);
      expect(rule.showsOn('/'), isFalse);
    });

    test('a screen that is not known shows the button, whatever the rule', () {
      expect(ZiButtonRule.fromJson({'show_on': 'only', 'paths': ['/home']}).showsOn(null), isTrue);
      expect(ZiButtonRule.fromJson({'show_on': 'except', 'paths': ['/']}).showsOn(null), isTrue);
    });
  });
}
