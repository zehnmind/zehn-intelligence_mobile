import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tour_explorer/app.dart';
import 'package:tour_explorer/data/mock_tours.dart';
import 'package:tour_explorer/data/tour_repository.dart';
import 'package:tour_explorer/logic/favorites_controller.dart';
import 'package:tour_explorer/logic/notifier_scope.dart';
import 'package:tour_explorer/logic/tour_catalog.dart';
import 'package:tour_explorer/logic/tour_insights.dart';
import 'package:tour_explorer/models/tour.dart';
import 'package:tour_explorer/screens/tour_detail_screen.dart';
import 'package:tour_explorer/utils/formatters.dart';
import 'package:tour_explorer/widgets/destination_card.dart';
import 'package:tour_explorer/widgets/tour_card.dart';
import 'package:tour_explorer/widgets/tour_list_tile.dart';

/// Fails the first load, then succeeds.
class _FlakyRepository extends TourRepository {
  _FlakyRepository() : super(latency: Duration.zero);

  int calls = 0;

  @override
  Future<List<Tour>> fetchTours() async {
    calls++;
    if (calls == 1) throw StateError('offline');
    return mockTours;
  }
}

Future<void> pumpApp(
  WidgetTester tester, {
  TourRepository repository = const TourRepository(latency: Duration.zero),
}) async {
  // A typical phone: 411 x 914 logical pixels.
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.625;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(TourExplorerApp(repository: repository));
  await tester.pumpAndSettle();
}

Finder navTab(String label) =>
    find.descendant(of: find.byType(NavigationBar), matching: find.text(label));

void main() {
  final topTour = popularTours(mockTours).first;

  testWidgets('home shows the greeting, destinations and popular tours', (
    tester,
  ) async {
    await pumpApp(tester);

    expect(find.text('Where to next?'), findsOneWidget);
    expect(find.text('Featured destinations'), findsOneWidget);
    expect(find.text('Popular tours'), findsOneWidget);
    expect(find.widgetWithText(TourCard, topTour.title), findsOneWidget);
  });

  testWidgets('a favorite shows up everywhere at once and can be undone', (
    tester,
  ) async {
    await pumpApp(tester);

    final card = find.widgetWithText(TourCard, topTour.title);
    await tester.tap(
      find.descendant(of: card, matching: find.byTooltip('Save to favorites')),
    );
    await tester.pump();
    expect(
      find.descendant(
        of: card,
        matching: find.byTooltip('Remove from favorites'),
      ),
      findsOneWidget,
    );

    await tester.tap(navTab('Favorites'));
    await tester.pumpAndSettle();
    expect(find.text('1 tour saved'), findsOneWidget);
    final tile = find.widgetWithText(TourListTile, topTour.title);
    expect(tile, findsOneWidget);

    await tester.tap(
      find.descendant(
        of: tile,
        matching: find.byTooltip('Remove from favorites'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('No favorites yet'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TourListTile, topTour.title), findsOneWidget);
  });

  testWidgets('search narrows results and shows an empty state', (
    tester,
  ) async {
    await pumpApp(tester);
    await tester.tap(navTab('Search'));
    await tester.pumpAndSettle();
    expect(find.text('${mockTours.length} tours found'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'maldives');
    await tester.pumpAndSettle();
    expect(find.text('3 tours found'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'atlantis');
    await tester.pumpAndSettle();
    expect(find.text('No tours match'), findsOneWidget);

    await tester.tap(find.text('Reset search'));
    await tester.pumpAndSettle();
    expect(find.text('${mockTours.length} tours found'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      isEmpty,
    );
  });

  testWidgets('filters combine, show their count and clear', (tester) async {
    await pumpApp(tester);
    await tester.tap(navTab('Search'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ChoiceChip, '🇹🇷 Turkey'));
    await tester.pumpAndSettle();
    expect(find.text('4 tours found'), findsOneWidget);

    await tester.tap(find.byTooltip('Filters'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, '4.8+'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, '4–6 days'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Show 2 tours'));
    await tester.pumpAndSettle();

    expect(find.text('2 tours found'), findsOneWidget);
    expect(find.widgetWithText(Chip, '4.8+'), findsOneWidget);

    await tester.tap(find.text('Clear filters'));
    await tester.pumpAndSettle();
    expect(find.text('${mockTours.length} tours found'), findsOneWidget);
  });

  testWidgets('a featured destination opens a filtered search', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpApp(tester);

    // Found by its accessibility label, after scrolling the carousel to it.
    final georgiaCard = find.bySemanticsLabel(RegExp(r'^Georgia, '));
    // Anchored on whichever card is built; cards scrolled away are disposed.
    final carousel = find.ancestor(
      of: find.byType(DestinationCard).first,
      matching: find.byType(ListView),
    );
    await tester.scrollUntilVisible(
      georgiaCard,
      150,
      scrollable: find
          .descendant(of: carousel, matching: find.byType(Scrollable))
          .first,
    );
    await tester.tap(georgiaCard);
    await tester.pumpAndSettle();

    expect(find.text('3 tours found'), findsOneWidget);
    final georgia = mockTours.where((t) => t.destination.label == 'Georgia');
    for (final tour in georgia) {
      expect(find.widgetWithText(TourListTile, tour.title), findsOneWidget);
    }
    semantics.dispose();
  });

  testWidgets('tour details: favorite and book a trip', (tester) async {
    await pumpApp(tester);

    await tester.ensureVisible(find.text(topTour.title));
    await tester.pumpAndSettle();
    await tester.tap(find.text(topTour.title));
    await tester.pumpAndSettle();
    expect(find.byType(TourDetailScreen), findsOneWidget);
    expect(find.text('Book now'), findsOneWidget);

    // The sections below the photo are built lazily, so scroll to them.
    final detailScroll = find
        .descendant(
          of: find.byType(TourDetailScreen),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(
      find.text(topTour.description),
      300,
      scrollable: detailScroll,
    );
    expect(find.text('About this tour'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('What\'s included'),
      300,
      scrollable: detailScroll,
    );
    await tester.scrollUntilVisible(
      find.byType(FlexibleSpaceBar),
      -300,
      scrollable: detailScroll,
    );
    await tester.pumpAndSettle();

    final detailHeart = find.descendant(
      of: find.byType(SliverAppBar),
      matching: find.byTooltip('Save to favorites'),
    );
    await tester.tap(detailHeart);
    await tester.pump();

    await tester.tap(find.text('Book now'));
    await tester.pumpAndSettle();
    expect(find.text('Book your trip'), findsOneWidget);

    await tester.tap(find.byTooltip('Add a traveler'));
    await tester.pump();
    expect(find.text(formatPrice(topTour.price * 2)), findsOneWidget);

    await tester.tap(find.text('Confirm booking'));
    await tester.pumpAndSettle();
    expect(find.text('Booking confirmed'), findsOneWidget);
    expect(find.textContaining(RegExp(r'^TX-')), findsOneWidget);

    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.text('Booking confirmed'), findsNothing);

    // The favorite set on the detail screen is visible back on the home card.
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.widgetWithText(TourCard, topTour.title),
        matching: find.byTooltip('Remove from favorites'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('a failed load shows an error that can be retried', (
    tester,
  ) async {
    final repository = _FlakyRepository();
    await pumpApp(tester, repository: repository);
    expect(find.text('Couldn\'t load tours'), findsOneWidget);

    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(repository.calls, 2);
    expect(find.text('Where to next?'), findsOneWidget);
  });

  testWidgets('an unknown tour id shows "not found"', (tester) async {
    final catalog = TourCatalog(const TourRepository(latency: Duration.zero));
    await tester.runAsync(catalog.load);
    addTearDown(catalog.dispose);

    await tester.pumpWidget(
      NotifierScope<TourCatalog>(
        notifier: catalog,
        child: NotifierScope<FavoritesController>(
          notifier: FavoritesController(),
          child: const MaterialApp(
            home: TourDetailScreen(tourId: 'no-such-tour'),
          ),
        ),
      ),
    );
    expect(find.text('Tour not found'), findsOneWidget);
  });
}
