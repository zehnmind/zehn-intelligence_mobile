import 'package:flutter_test/flutter_test.dart';
import 'package:tour_explorer/logic/favorites_controller.dart';

void main() {
  late FavoritesController favorites;
  late int notifications;

  setUp(() {
    favorites = FavoritesController();
    notifications = 0;
    favorites.addListener(() => notifications++);
  });

  tearDown(() => favorites.dispose());

  test('starts empty', () {
    expect(favorites.ids, isEmpty);
    expect(favorites.count, 0);
    expect(favorites.isFavorite('a'), isFalse);
  });

  test('toggle saves and then removes a tour, notifying each time', () {
    favorites.toggle('a');
    expect(favorites.isFavorite('a'), isTrue);
    expect(favorites.count, 1);

    favorites.toggle('a');
    expect(favorites.isFavorite('a'), isFalse);
    expect(favorites.count, 0);
    expect(notifications, 2);
  });

  test('keeps the order tours were saved in', () {
    favorites
      ..toggle('b')
      ..toggle('a')
      ..toggle('c');
    expect(favorites.ids.toList(), ['b', 'a', 'c']);
  });

  test('add and remove only notify when something changes', () {
    favorites.add('a');
    favorites.add('a');
    expect(favorites.count, 1);
    expect(notifications, 1);

    favorites.remove('missing');
    expect(notifications, 1);

    favorites.remove('a');
    expect(favorites.count, 0);
    expect(notifications, 2);
  });

  test('ids cannot be changed from outside', () {
    favorites.add('a');
    expect(() => favorites.ids.add('b'), throwsUnsupportedError);
  });

  test('can start with saved ids', () {
    final restored = FavoritesController(['x', 'y']);
    expect(restored.ids.toList(), ['x', 'y']);
    restored.dispose();
  });
}
