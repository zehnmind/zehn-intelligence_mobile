import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zehn_intelligence/src/server/app_route.dart';
import 'package:zehn_intelligence/src/server/auth/file_store.dart';
import 'package:zehn_intelligence/src/server/runtime.dart';
import 'package:zehn_intelligence/src/server/ui/assistant_overlay.dart';
import 'package:zehn_intelligence/src/server/ui/chat_sheet.dart';
import 'package:zehn_intelligence/src/server/ui/launcher_button.dart';
import 'package:zehn_intelligence/src/server/ui/strings.dart';

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
  Future<ZiRuntime> startRuntime(WidgetTester tester) async {
    final runtime = (await tester.runAsync(() async {
      final dir = await Directory.systemTemp.createTemp('zi_overlay');
      addTearDown(() => dir.delete(recursive: true));
      return ZiRuntime.create(
        config: ZiInitConfig(appKey: 'zi_test_abc', consoleUrl: Uri.parse('http://127.0.0.1:9')),
        info: info,
        store: ZiFileStore(() async => dir),
      );
    }))!;
    ZiRuntime.instance = runtime;
    addTearDown(() {
      ZiRuntime.instance = null;
      ZiAssistantOverlay.remove();
    });
    return runtime;
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
