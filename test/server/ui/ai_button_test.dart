import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zehn_intelligence/src/server/auth/file_store.dart';
import 'package:zehn_intelligence/src/server/runtime.dart';
import 'package:zehn_intelligence/src/server/ui/launcher_button.dart';
import 'package:zehn_intelligence/src/server/ui/strings.dart';
import 'package:zehn_intelligence/zehn_intelligence.dart' show ZehnAiButton;

import '../../support/test_info.dart';

void main() {
  testWidgets('ZehnAiButton is hidden while the assistant is not published', (tester) async {
    final runtime = (await tester.runAsync(() async {
      final dir = await Directory.systemTemp.createTemp('zi_button');
      addTearDown(() => dir.delete(recursive: true));
      return ZiRuntime.create(
        config: ZiInitConfig(appKey: 'zi_test_abc', consoleUrl: Uri.parse('http://127.0.0.1:9')),
        info: info,
        store: ZiFileStore(() async => dir),
      );
    }))!;
    ZiRuntime.instance = runtime;
    addTearDown(() => ZiRuntime.instance = null);
    runtime.available.value = false;
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: ZehnAiButton())));
    expect(find.byType(ZiLauncherButton), findsNothing);
    runtime.available.value = true;
    await tester.pump();
    expect(find.byType(ZiLauncherButton), findsOneWidget);
  });

  testWidgets("ZehnAiButton takes the app's language, not the phone's", (tester) async {
    final runtime = (await tester.runAsync(() async {
      final dir = await Directory.systemTemp.createTemp('zi_button');
      addTearDown(() => dir.delete(recursive: true));
      return ZiRuntime.create(
        config: ZiInitConfig(appKey: 'zi_test_abc', consoleUrl: Uri.parse('http://127.0.0.1:9')),
        info: info,
        store: ZiFileStore(() async => dir),
      );
    }))!;
    ZiRuntime.instance = runtime;
    addTearDown(() => ZiRuntime.instance = null);
    // The test phone is en_US; the app is shown in Russian.
    await tester.pumpWidget(
      const MaterialApp(
        locale: Locale('ru'),
        supportedLocales: [Locale('uz'), Locale('ru'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: Scaffold(body: ZehnAiButton()),
      ),
    );
    expect(runtime.language, 'ru');
    expect(tester.widget<ZiLauncherButton>(find.byType(ZiLauncherButton)).label, ZiStrings.of('ru').ask);
  });
}
