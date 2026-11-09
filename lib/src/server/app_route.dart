import 'package:flutter/services.dart';

/// Opens [path] in the app the way a deep link does: `pushRouteInformation`
/// on the navigation channel, handled by the app's own router. With
/// go_router (or any `Router`) the router goes to the path; with a
/// `MaterialApp`'s named routes the navigator pushes it. No code of the
/// app's and no dependency on its router package.
///
/// What `ZehnIntelligence.start(dio: …)` opens a screen with: the server
/// sends the path already filled (`/venues/a1`).
void openAppRoute(String path) {
  final message = const JSONMethodCodec().encodeMethodCall(
    MethodCall('pushRouteInformation', <String, Object?>{'location': path, 'state': null}),
  );
  ServicesBinding.instance.channelBuffers.push(SystemChannels.navigation.name, message, (_) {});
}
