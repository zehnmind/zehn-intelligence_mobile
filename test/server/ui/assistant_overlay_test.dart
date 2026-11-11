import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zehn_intelligence/src/server/app_route.dart';
import 'package:zehn_intelligence/src/server/auth/file_store.dart';
import 'package:zehn_intelligence/src/server/chat/chat_settings.dart';
import 'package:zehn_intelligence/src/server/runtime.dart';
import 'package:zehn_intelligence/src/server/ui/assistant_overlay.dart';
import 'package:zehn_intelligence/src/server/ui/chat_sheet.dart';
import 'package:zehn_intelligence/src/server/ui/launcher_button.dart';
import 'package:zehn_intelligence/src/server/ui/strings.dart';

import '../../support/fake_server.dart';
import '../../support/test_info.dart';

/// The app's handler of the navigation channel was set up outside the test's
/// fake clock, so it runs on real time.
Future<void> openInRealZone(WidgetTester tester, String path) async {
  await tester.runAsync(() async {
    openAppRoute(path);
    await Future<void>.delayed(const Duration(milliseconds: 50));
  });
  await tester.pumpAndSettle();
}

void main() {
  /// A runtime with the config the console published: [button] is its `button`
  /// (every screen when left out). With [config] false it has none, as at a
  /// first start before the server answers.
  Future<ZiRuntime> startRuntime(WidgetTester tester, {Map<String, Object?>? button, bool config = true}) async {
    final runtime = (await tester.runAsync(() async {
      final dir = await Directory.systemTemp.createTemp('zi_overlay');
      addTearDown(() => dir.delete(recursive: true));
      return ZiRuntime.create(
        config: ZiInitConfig(appKey: 'zi_test_abc', consoleUrl: Uri.parse('http://127.0.0.1:9')),
        info: info,
        store: ZiFileStore(() async => dir),
      );
    }))!;
    if (config) {
      runtime.settings.value = ZiChatSettings.fromJson({'button': ?button});
      runtime.hasConfig.value = true;
    }
    ZiRuntime.instance = runtime;
    addTearDown(() {
      ZiRuntime.instance = null;
      ZiAssistantOverlay.remove();
    });
    return runtime;
  }

  bool buttonShows() => find.byType(ZiLauncherButton).evaluate().isNotEmpty;

  /// The app is up and the SDK puts its button over it.
  Future<void> showOver(WidgetTester tester, Widget app) async {
    await tester.pumpWidget(app);
    ZiAssistantOverlay.install();
    await tester.pump(); // the frame that finds the navigator and inserts the button
    await tester.pump(); // the frame that draws it
  }

  testWidgets('the SDK draws its own button over an app that has none', (tester) async {
    await startRuntime(tester);
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: Text('the app'))));
    ZiAssistantOverlay.install();
    await tester.pump(); // the frame that finds the navigator and inserts the button
    await tester.pump(); // the frame that draws it
    expect(ZiAssistantOverlay.isInstalled, isTrue);
    expect(find.byType(ZiLauncherButton), findsOneWidget);
  });

  testWidgets('the button waits for the app navigator and goes into the root one', (tester) async {
    await startRuntime(tester);
    ZiAssistantOverlay.install();
    await tester.pumpWidget(const Directionality(textDirection: TextDirection.ltr, child: Text('splash')));
    expect(ZiAssistantOverlay.isInstalled, isFalse);
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: Navigator(onGenerateRoute: (_) => MaterialPageRoute(builder: (_) => const Text('nested'))))),
    );
    await tester.pump();
    expect(ZiAssistantOverlay.isInstalled, isTrue);
    expect(ZiAssistantOverlay.rootNavigator(), same(tester.state<NavigatorState>(find.byType(Navigator).first)));
    expect(find.byType(ZiLauncherButton), findsOneWidget);
  });

  testWidgets('the button hides while nothing is published, and opens the chat', (tester) async {
    final runtime = await startRuntime(tester);
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: Text('the app'))));
    ZiAssistantOverlay.install();
    await tester.pump();
    await tester.pump();
    runtime.available.value = false;
    await tester.pump();
    expect(find.byType(ZiLauncherButton), findsNothing);
    runtime.available.value = true;
    await tester.pump();
    await tester.tap(find.byType(ZiLauncherButton));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(ZiChatSheet), findsOneWidget);
    expect(find.byType(ZiLauncherButton), findsNothing);
  });

  testWidgets('a screen opens like a deep link in a go_router app', (tester) async {
    final router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (_, _) => const Text('home')),
        GoRoute(path: '/venues/:id', builder: (_, state) => Text('venue ${state.pathParameters['id']}')),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await openInRealZone(tester, '/venues/a1');
    expect(find.text('venue a1'), findsOneWidget);
  });

  testWidgets('a screen opens like a deep link in an app with named routes', (tester) async {
    await tester.pumpWidget(
      MaterialApp(routes: {'/': (_) => const Text('home'), '/map': (_) => const Text('map')}),
    );
    await openInRealZone(tester, '/map');
    expect(find.text('map'), findsOneWidget);
  });

  group('where the button shows', () {
    /// What `pumpAndSettle` is for, without waiting for the button to stop
    /// animating (it never does: the soap bubble runs a ticker): the frame
    /// that builds, a second for the route's transition, and the frame that
    /// draws what the open screen then told the button.
    Future<void> settle(WidgetTester tester) async {
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
    }

    GoRouter appRouter() {
      final router = GoRouter(
        routes: [
          GoRoute(path: '/', builder: (_, _) => const Text('splash')),
          GoRoute(path: '/auth', builder: (_, _) => const Text('auth')),
          GoRoute(path: '/home', builder: (_, _) => const Text('home')),
          GoRoute(path: '/profile', builder: (_, _) => const Text('profile')),
          GoRoute(path: '/movies/:id', builder: (_, state) => Text('movie ${state.pathParameters['id']}')),
        ],
      );
      addTearDown(router.dispose);
      return router;
    }

    Future<void> goTo(WidgetTester tester, GoRouter router, String location) async {
      router.go(location);
      await settle(tester);
    }

    Widget namedRoutes({String initialRoute = '/'}) => MaterialApp(
      initialRoute: initialRoute,
      onGenerateRoute: (settings) => MaterialPageRoute(settings: settings, builder: (_) => Text('screen ${settings.name}')),
    );

    testWidgets('no config yet (a first start, before the server answers): hidden, and it shows once there is one', (tester) async {
      final runtime = await startRuntime(tester, config: false);
      await showOver(tester, const MaterialApp(home: Scaffold(body: Text('the app'))));
      expect(ZiAssistantOverlay.isInstalled, isTrue);
      expect(buttonShows(), isFalse);

      runtime.settings.value = ZiChatSettings.fromJson({});
      runtime.hasConfig.value = true;
      await tester.pump();
      expect(buttonShows(), isTrue);
    });

    testWidgets('except ["/", "/auth"]: hidden on the splash and on /auth, shown on /home', (tester) async {
      await startRuntime(tester, button: {'show_on': 'except', 'paths': ['/', '/auth']});
      final router = appRouter();
      await showOver(tester, MaterialApp.router(routerConfig: router));
      expect(find.text('splash'), findsOneWidget);
      expect(buttonShows(), isFalse);

      await goTo(tester, router, '/auth');
      expect(buttonShows(), isFalse);
      await goTo(tester, router, '/home');
      expect(buttonShows(), isTrue);
      await goTo(tester, router, '/');
      expect(buttonShows(), isFalse);
    });

    testWidgets('except ["/movies/:id"]: hidden on /movies/42?day=1', (tester) async {
      await startRuntime(tester, button: {'show_on': 'except', 'paths': ['/movies/:id']});
      final router = appRouter();
      await showOver(tester, MaterialApp.router(routerConfig: router));
      await goTo(tester, router, '/home');
      expect(buttonShows(), isTrue);
      await goTo(tester, router, '/movies/42?day=1');
      expect(find.text('movie 42'), findsOneWidget);
      expect(buttonShows(), isFalse);
    });

    testWidgets('only ["/home"]: shown on /home/, hidden on /profile', (tester) async {
      await startRuntime(tester, button: {'show_on': 'only', 'paths': ['/home']});
      final router = appRouter();
      await showOver(tester, MaterialApp.router(routerConfig: router));
      expect(buttonShows(), isFalse);
      await goTo(tester, router, '/home/');
      expect(find.text('home'), findsOneWidget);
      expect(buttonShows(), isTrue);
      await goTo(tester, router, '/profile');
      expect(buttonShows(), isFalse);
    });

    testWidgets('a screen pushed over a hidden one follows its own path, and a pop goes back', (tester) async {
      await startRuntime(tester, button: {'show_on': 'except', 'paths': ['/auth']});
      final router = appRouter();
      await showOver(tester, MaterialApp.router(routerConfig: router));
      await goTo(tester, router, '/auth');
      expect(buttonShows(), isFalse);
      unawaited(router.push('/profile'));
      await settle(tester);
      expect(buttonShows(), isTrue);
      router.pop();
      await settle(tester);
      expect(buttonShows(), isFalse);
    });

    testWidgets('a bottom sheet over /home is /home', (tester) async {
      await startRuntime(tester, button: {'show_on': 'only', 'paths': ['/home']});
      await showOver(tester, namedRoutes(initialRoute: '/home'));
      expect(buttonShows(), isTrue);
      unawaited(showModalBottomSheet<void>(context: tester.element(find.text('screen /home')), builder: (_) => const Text('a sheet')));
      await settle(tester);
      expect(find.text('a sheet'), findsOneWidget);
      expect(buttonShows(), isTrue);

      // The same over a screen the rule hides.
      tester.state<NavigatorState>(find.byType(Navigator).first).pop();
      await settle(tester);
      tester.state<NavigatorState>(find.byType(Navigator).first).pushReplacementNamed('/profile');
      await settle(tester);
      expect(buttonShows(), isFalse);
      unawaited(showModalBottomSheet<void>(context: tester.element(find.text('screen /profile')), builder: (_) => const Text('a sheet')));
      await settle(tester);
      expect(buttonShows(), isFalse);
    });

    testWidgets('named routes: hidden on the screens of the rule, shown on the others', (tester) async {
      await startRuntime(tester, button: {'show_on': 'except', 'paths': ['/', '/auth']});
      await showOver(tester, namedRoutes());
      expect(buttonShows(), isFalse);
      final navigator = tester.state<NavigatorState>(find.byType(Navigator).first);
      navigator.pushNamed('/home');
      await settle(tester);
      expect(buttonShows(), isTrue);
      navigator.pushNamed('/auth');
      await settle(tester);
      expect(buttonShows(), isFalse);
      navigator.pop();
      await settle(tester);
      expect(buttonShows(), isTrue);
    });

    testWidgets('a screen pushed with no name is not known: the button shows', (tester) async {
      await startRuntime(tester, button: {'show_on': 'only', 'paths': ['/home']});
      await showOver(tester, namedRoutes(initialRoute: '/profile'));
      expect(buttonShows(), isFalse);
      tester
          .state<NavigatorState>(find.byType(Navigator).first)
          .push(MaterialPageRoute<void>(builder: (_) => const Text('a widget')));
      await settle(tester);
      expect(find.text('a widget'), findsOneWidget);
      expect(buttonShows(), isTrue);
    });

    testWidgets('a config that arrives later is followed at once', (tester) async {
      final runtime = await startRuntime(tester);
      final router = appRouter();
      await showOver(tester, MaterialApp.router(routerConfig: router));
      expect(buttonShows(), isTrue);
      // What a refresh of the config brings: the console published another rule.
      runtime.settings.value = ZiChatSettings.fromJson({'button': {'show_on': 'except', 'paths': ['/']}});
      await tester.pump();
      expect(buttonShows(), isFalse);
      await goTo(tester, router, '/home');
      expect(buttonShows(), isTrue);
    });

    testWidgets('back in the foreground, a config that could not load is asked for again', (tester) async {
      // flutter_test answers every HttpClient request with a 400; this test
      // talks to a real server on the loopback.
      final overrides = HttpOverrides.current;
      HttpOverrides.global = null;
      addTearDown(() => HttpOverrides.global = overrides);
      final server = (await tester.runAsync(FakeServer.start))!;
      addTearDown(() async => server.close());
      var up = false;
      server.on('GET', '/v1/config', (req, _) {
        return up
            ? respondJson(req, 200, {'button': {'show_on': 'except', 'paths': ['/']}})
            : respondJson(req, 503, {});
      });
      final runtime = (await tester.runAsync(() async {
        final dir = await Directory.systemTemp.createTemp('zi_overlay');
        addTearDown(() => dir.delete(recursive: true));
        final runtime = await ZiRuntime.create(
          config: ZiInitConfig(appKey: 'zi_test_abc', consoleUrl: server.url),
          info: info,
          store: ZiFileStore(() async => dir),
        );
        await runtime.loadConfig(); // the start-up try, which fails
        return runtime;
      }))!;
      ZiRuntime.instance = runtime;
      addTearDown(() {
        ZiRuntime.instance = null;
        ZiAssistantOverlay.remove();
      });
      await showOver(tester, namedRoutes(initialRoute: '/home'));
      expect(buttonShows(), isFalse);

      up = true;
      // In the real zone: the request is real I/O, and one begun inside the
      // test's fake clock would never get its microtasks run while this waits.
      // Nothing but the lifecycle change asks for the config again here.
      await tester.runAsync(() async {
        // ignore: invalid_use_of_protected_member
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        // ignore: invalid_use_of_protected_member
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        for (var i = 0; i < 100 && !runtime.hasConfig.value; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
      });
      await tester.pump();
      expect(server.requests.where((r) => r.path == '/v1/config'), hasLength(2));
      expect(runtime.hasConfig.value, isTrue);
      expect(buttonShows(), isTrue);
    });
  });

  group('the chat speaks the language the app is shown in', () {
    // The test phone is en_US. The app keeps its own language and hands it to
    // `MaterialApp(locale: …)`, as an app with its own language setting does.
    Widget app(Locale locale) => MaterialApp(
      locale: locale,
      supportedLocales: const [Locale('uz'), Locale('ru'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: const Text('the app'),
    );
    String? label(WidgetTester tester) => tester.widget<ZiLauncherButton>(find.byType(ZiLauncherButton)).label;

    Future<void> showButton(WidgetTester tester, Widget app) async {
      await tester.pumpWidget(app);
      ZiAssistantOverlay.install();
      await tester.pump();
      await tester.pump();
    }

    testWidgets("the app's language, not the phone's", (tester) async {
      final runtime = await startRuntime(tester);
      await showButton(tester, app(const Locale('ru')));
      expect(runtime.language, 'ru');
      expect(label(tester), ZiStrings.of('ru').ask);
    });

    testWidgets('a change of language in the app reaches the next turn', (tester) async {
      final runtime = await startRuntime(tester);
      await showButton(tester, app(const Locale('ru')));
      await tester.pumpWidget(app(const Locale('uz')));
      await tester.pump();
      expect(runtime.language, 'uz');
      expect(label(tester), ZiStrings.of('uz').ask);
    });

    testWidgets("ZehnIntelligence.setLanguage still wins over the app's language", (tester) async {
      final runtime = await startRuntime(tester);
      runtime.language = 'en';
      await showButton(tester, app(const Locale('ru')));
      expect(runtime.language, 'en');
    });

    testWidgets('an app that never set a language leaves it to the phone', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: Text('the app')));
      // Flutter's own en_US, not a choice the app made.
      expect(ziAppLanguageOf(tester.element(find.text('the app'))), isNull);
      await tester.pumpWidget(app(const Locale('uz')));
      expect(ziAppLanguageOf(tester.element(find.text('the app'))), 'uz');
    });
  });
}
