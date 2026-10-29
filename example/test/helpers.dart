import 'package:tour_explorer/models/destination.dart';
import 'package:tour_explorer/models/tour.dart';
import 'package:tour_explorer/models/tour_category.dart';

/// A tour with sensible defaults, so each test only states what it checks.
Tour makeTour({
  required String id,
  String title = 'Sample tour',
  Destination destination = Destination.turkey,
  String location = 'Somewhere',
  TourCategory category = TourCategory.city,
  int price = 500,
  int durationDays = 3,
  double rating = 4.5,
  int reviewCount = 100,
  List<int> departureWeekdays = const [DateTime.monday],
}) {
  return Tour(
    id: id,
    title: title,
    destination: destination,
    location: location,
    category: category,
    price: price,
    durationDays: durationDays,
    rating: rating,
    reviewCount: reviewCount,
    imageUrl: 'https://example.com/$id.jpg',
    description: 'Description of $title.',
    highlights: const ['A highlight'],
    included: const ['Something included'],
    maxGroupSize: 10,
    languages: const ['English'],
    departureWeekdays: departureWeekdays,
  );
}
