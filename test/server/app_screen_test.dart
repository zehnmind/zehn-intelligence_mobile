import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zehn_intelligence/src/server/app_screen.dart';

void main() {
  NavigatorState rootNavigator(WidgetTester tester) => tester.state<NavigatorState>(find.byType(Navigator).first);

  /// Follows the app that is on screen, as the SDK's button does.
  ZiOpenScreen follow(WidgetTester tester) {
    final screen = ZiOpenScreen(rootNavigator(tester))..start();
    addTearDown(screen.dispose);
    return screen;
  }

  group('an app with a router (go_router)', () {
    GoRouter router({String initialLocation = '/', bool signedIn = true}) {
      final router = GoRouter(
        initialLocation: initialLocation,
        redirect: (_, state) => !signedIn && state.matchedLocation == '/profile' ? '/auth' : null,
        routes: [
          GoRoute(path: '/', builder: (_, _) => const Text('splash')),
          GoRoute(path: '/auth', builder: (_, _) => const Text('auth')),
          GoRoute(path: '/movies/:id', builder: (_, state) => Text('movie ${state.pathParameters['id']}')),
          ShellRoute(
            builder: (_, _, child) => Scaffold(body: child, bottomNavigationBar: const Text('tabs')),
            routes: [
              GoRoute(path: '/home', builder: (_, _) => const Text('home')),
              GoRoute(path: '/profile', builder: (_, _) => const Text('profile')),
            ],
          ),
        ],
      );
      addTearDown(router.dispose);
      return router;
    }

    testWidgets('the screen is the location the router is at', (tester) async {
      final app = router();
      await tester.pumpWidget(MaterialApp.router(routerConfig: app));
      final screen = follow(tester);
      expect(screen.path.value, '/');

      app.go('/home');
      await tester.pumpAndSettle();
      expect(screen.path.value, '/home');

      // The query is not part of the path.
      app.go('/movies/42?day=1');
      await tester.pumpAndSettle();
      expect(find.text('movie 42'), findsOneWidget);
      expect(screen.path.value, '/movies/42');
    });

    testWidgets('an app that starts on another screen', (tester) async {
      await tester.pumpWidget(MaterialApp.router(routerConfig: router(initialLocation: '/home')));
      expect(follow(tester).path.value, '/home');
    });

    testWidgets('a screen opened with push is the open screen, and the one below it after a pop', (tester) async {
      final app = router(initialLocation: '/home');
      await tester.pumpWidget(MaterialApp.router(routerConfig: app));
      final screen = follow(tester);

      // go_router keeps a pushed screen out of the location it reports.
      unawaited(app.push('/movies/42?day=1'));
      await tester.pumpAndSettle();
      expect(find.text('movie 42'), findsOneWidget);
      expect(app.routeInformationProvider.value.uri.path, '/home');
      expect(screen.path.value, '/movies/42');

      unawaited(app.push('/auth'));
      await tester.pumpAndSettle();
      expect(screen.path.value, '/auth');

      app.pop();
      await tester.pumpAndSettle();
      expect(screen.path.value, '/movies/42');

      app.pop();
      await tester.pumpAndSettle();
      expect(find.text('home'), findsOneWidget);
      expect(screen.path.value, '/home');
    });

    testWidgets('a redirect: the screen the router ended at', (tester) async {
      final app = router(initialLocation: '/home', signedIn: false);
      await tester.pumpWidget(MaterialApp.router(routerConfig: app));
      final screen = follow(tester);
      app.go('/profile');
      await tester.pumpAndSettle();
      expect(find.text('auth'), findsOneWidget);
      expect(screen.path.value, '/auth');
    });

    testWidgets('a sheet or a dialog over a screen keeps that screen', (tester) async {
      await tester.pumpWidget(MaterialApp.router(routerConfig: router(initialLocation: '/home')));
      final screen = follow(tester);
      unawaited(showDialog<void>(context: tester.element(find.text('home')), builder: (_) => const Text('a dialog')));
      await tester.pumpAndSettle();
      expect(find.text('a dialog'), findsOneWidget);
      expect(screen.path.value, '/home');
    });

    testWidgets('each change is told once, as it happens', (tester) async {
      final app = router(initialLocation: '/home');
      await tester.pumpWidget(MaterialApp.router(routerConfig: app));
      final screen = follow(tester);
      final seen = <String?>[];
      screen.path.addListener(() => seen.add(screen.path.value));
      app.go('/profile');
      await tester.pumpAndSettle();
      unawaited(app.push('/auth'));
      await tester.pumpAndSettle();
      app.pop();
      await tester.pumpAndSettle();
      expect(seen, ['/profile', '/auth', '/profile']);
    });
  });

  group('an app with the Navigator and named routes', () {
    Widget app({String? initialRoute}) => MaterialApp(
      initialRoute: initialRoute,
      onGenerateRoute: (settings) => MaterialPageRoute(settings: settings, builder: (_) => Text('screen ${settings.name}')),
    );

    testWidgets('the screen is the top route\'s name', (tester) async {
      await tester.pumpWidget(app());
      final screen = follow(tester);
      final navigator = rootNavigator(tester);
      expect(screen.path.value, '/');

      navigator.pushNamed('/auth');
      await tester.pump();
      await tester.pump();
      expect(screen.path.value, '/auth');
      await tester.pumpAndSettle();

      navigator.pushReplacementNamed('/movies/42?day=1');
      await tester.pumpAndSettle();
      expect(screen.path.value, '/movies/42?day=1');

      navigator.pop();
      await tester.pumpAndSettle();
      expect(screen.path.value, '/');
    });

    testWidgets('an app that starts on another screen', (tester) async {
      await tester.pumpWidget(app(initialRoute: '/home'));
      expect(follow(tester).path.value, '/home');
    });

    testWidgets('a home: screen is /', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: Text('the app')));
      expect(follow(tester).path.value, '/');
    });

    testWidgets('a sheet or a dialog over a screen keeps that screen', (tester) async {
      await tester.pumpWidget(app(initialRoute: '/home'));
      final screen = follow(tester);
      final context = tester.element(find.text('screen /home'));

      unawaited(showDialog<void>(context: context, builder: (_) => const Text('a dialog')));
      await tester.pumpAndSettle();
      expect(find.text('a dialog'), findsOneWidget);
      expect(screen.path.value, '/home');

      unawaited(showModalBottomSheet<void>(context: context, builder: (_) => const Text('a sheet')));
      await tester.pumpAndSettle();
      expect(find.text('a sheet'), findsOneWidget);
      expect(screen.path.value, '/home');

      rootNavigator(tester)
        ..pop()
        ..pop();
      await tester.pumpAndSettle();
      expect(screen.path.value, '/home');
    });

    testWidgets('a see-through route over a screen keeps that screen', (tester) async {
      await tester.pumpWidget(app(initialRoute: '/home'));
      final screen = follow(tester);
      rootNavigator(tester).push(PageRouteBuilder<void>(opaque: false, pageBuilder: (_, _, _) => const Text('over it')));
      await tester.pumpAndSettle();
      expect(screen.path.value, '/home');
    });

    testWidgets('a screen pushed as a widget, with no name, is not known', (tester) async {
      await tester.pumpWidget(app(initialRoute: '/home'));
      final screen = follow(tester);
      final navigator = rootNavigator(tester);

      navigator.push(MaterialPageRoute<void>(builder: (_) => const Text('a widget')));
      await tester.pumpAndSettle();
      expect(screen.path.value, isNull);

      // A dialog over a screen that isn't known: still not known.
      unawaited(showDialog<void>(context: tester.element(find.text('a widget')), builder: (_) => const Text('a dialog')));
      await tester.pumpAndSettle();
      expect(screen.path.value, isNull);
      navigator.pop();
      await tester.pumpAndSettle();

      navigator.pop();
      await tester.pumpAndSettle();
      expect(screen.path.value, '/home');

      // Pushed as a widget, but named: the name.
      navigator.push(MaterialPageRoute<void>(settings: const RouteSettings(name: '/terms'), builder: (_) => const Text('terms')));
      await tester.pumpAndSettle();
      expect(screen.path.value, '/terms');
    });
  });

  testWidgets('after dispose it follows nothing', (tester) async {
    final app = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (_, _) => const Text('home')),
        GoRoute(path: '/auth', builder: (_, _) => const Text('auth')),
      ],
    );
    addTearDown(app.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: app));
    final screen = ZiOpenScreen(rootNavigator(tester))..start();
    var told = 0;
    screen.path.addListener(() => told++);
    screen.dispose();
    app.go('/auth');
    await tester.pumpAndSettle();
    expect(told, 0);
  });
}
