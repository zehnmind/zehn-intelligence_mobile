import 'package:flutter_test/flutter_test.dart';
import 'package:tour_explorer/logic/tour_insights.dart';
import 'package:tour_explorer/models/destination.dart';
import 'package:tour_explorer/models/tour_category.dart';

import 'helpers.dart';

void main() {
  final a = makeTour(id: 'a', rating: 4.7, reviewCount: 900, price: 700);
  final b = makeTour(
    id: 'b',
    rating: 4.9,
    reviewCount: 100,
    price: 400,
    category: TourCategory.beach,
  );
  final c = makeTour(id: 'c', rating: 4.9, reviewCount: 300, price: 900);
  final d = makeTour(
    id: 'd',
    destination: Destination.georgia,
    rating: 4.5,
    price: 300,
  );

  test('popular tours sort by rating, then by review count', () {
    expect(popularTours([a, b, c, d]), [c, b, a, d]);
  });

  test('popular tours can be limited to a category and a count', () {
    expect(popularTours([a, b, c, d], category: TourCategory.beach), [b]);
    expect(popularTours([a, b, c, d], limit: 2), [c, b]);
  });

  test('destination summaries count tours and find the lowest price', () {
    final summaries = summarizeDestinations([a, b, c, d]);
    expect(summaries.map((s) => s.destination), [
      Destination.turkey,
      Destination.georgia,
    ]);

    final turkey = summaries.first;
    expect(turkey.tourCount, 3);
    expect(turkey.lowestPrice, 400);
    expect(turkey.coverImageUrl, c.imageUrl);
  });
}
