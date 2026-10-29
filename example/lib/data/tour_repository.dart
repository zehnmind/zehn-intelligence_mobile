import '../models/tour.dart';
import 'mock_tours.dart';

/// Source of tours. Reads the local mock data; the [latency] imitates a
/// network call so the app's loading state is real.
class TourRepository {
  const TourRepository({this.latency = const Duration(milliseconds: 500)});

  final Duration latency;

  Future<List<Tour>> fetchTours() async {
    await Future<void>.delayed(latency);
    return mockTours;
  }
}
