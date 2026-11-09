import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zehn_intelligence/src/server/app_route.dart';
import 'package:zehn_intelligence/src/server/auth/file_store.dart';
import 'package:zehn_intelligence/src/server/runtime.dart';
import 'package:zehn_intelligence/src/server/ui/assistant_overlay.dart';
import 'package:zehn_intelligence/src/server/ui/chat_sheet.dart';
import 'package:zehn_intelligence/src/server/ui/launcher_button.dart';

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
}
