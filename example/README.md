# Tour Explorer

The example app of the `zehn_intelligence` SDK (the repository root). It stands
in for a company's own app: the SDK will be added to it in task P1-SDK-07, so
that the assistant answers with these tours, cards and booking sheet. Until
then it doesn't use the SDK; it only depends on it (`path: ../` in
`pubspec.yaml`). Run the commands below from this `example/` folder.

A Flutter (Material 3) app for browsing and discovering tours. It runs on local
mock data: no backend, no accounts.

- **Explore:** greeting, search shortcut, featured destinations, and popular
  tours with category chips (Beach, Culture, Adventure, City, Nature).
- **Search:** text search over title, location, country and category (ignores
  case and accents, so "goreme" finds "Göreme"). Filters for destination,
  maximum price, minimum rating and duration combine with each other and with
  the search text. Shows a live result count, removable filter chips, and an
  empty state.
- **Tour details:** large photo, facts (duration, group size, languages,
  departure days), description, highlights, what's included, a favorite
  button, and booking (date and travelers, then a confirmation with a
  reference). Nothing is charged or sent anywhere.
- **Favorites:** save and remove from any screen; every heart and the tab badge
  update at once. Removing from the Favorites tab offers Undo.

## Run

```bash
flutter pub get
flutter run                      # on a connected device or emulator
flutter build apk --release      # build/app/outputs/flutter-apk/app-release.apk
```

## Check

```bash
flutter analyze
flutter test
```

## Structure

```
lib/
  main.dart, app.dart     entry point; app-wide state sits above MaterialApp
  models/                 Tour, Destination, TourCategory
  data/                   mock_tours.dart (20 tours), tour_repository.dart
  logic/                  filtering, favorites, catalog loading, rankings,
                          departures and bookings, NotifierScope (state access)
  screens/                home shell (bottom navigation), explore, search,
                          favorites, tour detail
  widgets/                cards, image with fallback, sheets, empty state
  theme/                  colors, spacing, radii, ThemeData
  utils/formatters.dart   prices, counts, dates
test/                     unit tests for the logic, widget tests for the flows
```

State uses `ChangeNotifier` and `InheritedNotifier`; there are no third-party
packages. Tours and favorites are referenced by stable string ids.

## Images and limitations

- Photos load from the Unsplash and Pexels CDNs (free licenses). While a photo
  loads, a progress indicator shows; if it fails, or the device is offline, a
  gradient placeholder with the tour's category icon replaces it.
- Favorites live in memory: they survive navigation but not an app restart.
- Bookings are a demo flow and are not stored.
- The launcher icon is still Flutter's default.
