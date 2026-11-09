// Tries the SDK's server flow against the mock server:
//
//   dart run zehn_intelligence:mock_server        (from the package root)
//   cd example && flutter run                      (iOS simulator)
//
// The whole integration is the init call and ZehnAiButton.

import 'package:flutter/material.dart';
import 'package:zehn_intelligence/zehn_intelligence.dart';

/// What the assistant last asked the app to open. A real app pushes the route.
final _lastRoute = ValueNotifier<String?>(null);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ZehnIntelligence.init(
    token: 'zi_test_mock',
    consoleUrl: Uri.parse('http://localhost:8787'),
    accessToken: () => 'demo',
    openRoute: (route) => _lastRoute.value = route,
  );
  runApp(const ExampleApp());
}

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData(colorSchemeSeed: const Color(0xFFBE7C6C)),
    home: Scaffold(
      appBar: AppBar(title: const Text('Zehn Intelligence example')),
      body: Center(
        child: ValueListenableBuilder<String?>(
          valueListenable: _lastRoute,
          builder: (context, route, _) => Text(
            route == null ? 'Tap the button to open the assistant.' : 'openRoute("$route")',
            textAlign: TextAlign.center,
          ),
        ),
      ),
      floatingActionButton: const ZehnAiButton(),
    ),
  );
}
