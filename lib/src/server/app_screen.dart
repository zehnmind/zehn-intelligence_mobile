import 'package:flutter/widgets.dart';

/// Follows which screen of the app is open, with no code of the app's and no
/// dependency on its router package: what `button` of `GET /v1/config`
/// (where the SDK's button shows) is checked against.
///
/// - **An app with a router** (`MaterialApp.router`: go_router, auto_route,
///   beamer): the location the [Router] above the app's navigator reports to
///   its `routeInformationProvider`, the same router `openAppRoute` opens
///   screens with. It is read when the router's delegate says the screens
///   changed, so a pop counts at once.
/// - **An app with the Navigator's named routes** (and GetX): the name of the
///   top route, looked at after each frame the app draws.
/// - A sheet or a dialog over a screen keeps that screen.
/// - A screen pushed as a widget, with no name, is not known ([path] is null).
class ZiOpenScreen {
  /// [navigator] is the app's root navigator.
  ZiOpenScreen(NavigatorState navigator) : _navigator = navigator;

  final NavigatorState _navigator;

  /// The open screen's path as the app's router writes it (`/movies/42`); a
  /// route's name may still carry a query. Null when the screen isn't known.
  final ValueNotifier<String?> path = ValueNotifier(null);

  bool _following = false;

  /// The [Router] above the navigator, if the app has one.
  Element? _router;
  Listenable? _delegate;
  Listenable? _provider;

  /// The router's location, read again only after the router said it changed.
  String? _routerPath;
  bool _routerChanged = true;

  /// Reads the open screen now, and again at every change. Call once.
  void start() {
    if (_following) return;
    _following = true;
    _navigator.context.visitAncestorElements((element) {
      if (element.widget is! Router) return true;
      _router = element;
      return false;
    });
    _read();
    WidgetsBinding.instance.addPostFrameCallback(_afterFrame);
  }

  void dispose() {
    _following = false;
    _listen(null, null);
    path.dispose();
  }

  /// Each frame the app draws (none is asked for): the navigator has no way
  /// to tell an outsider its routes changed, but a change always draws.
  void _afterFrame(Duration _) {
    if (!_following) return;
    _read();
    WidgetsBinding.instance.addPostFrameCallback(_afterFrame);
  }

  void _read() {
    if (!_following || !_navigator.mounted) return;
    path.value = _routerLocation() ?? _topRouteName();
  }

  /// The router said its screens or its location changed.
  void _onRouter() {
    _routerChanged = true;
    _read();
  }

  void _listen(Listenable? delegate, Listenable? provider) {
    if (!identical(delegate, _delegate)) {
      _delegate?.removeListener(_onRouter);
      _delegate = delegate?..addListener(_onRouter);
      _routerChanged = true;
    }
    if (!identical(provider, _provider)) {
      _provider?.removeListener(_onRouter);
      _provider = provider?..addListener(_onRouter);
      _routerChanged = true;
    }
  }

  /// Null when the app has no router, or its router has no location to tell.
  String? _routerLocation() {
    final element = _router;
    if (element == null || !element.mounted) {
      _listen(null, null);
      return null;
    }
    // Read from the element each time: the app may give its Router widget
    // another delegate or provider.
    final router = element.widget as Router<Object?>;
    _listen(router.routerDelegate, router.routeInformationProvider);
    if (_routerChanged) {
      _routerChanged = false;
      _routerPath = _locationOf(router);
    }
    return _routerPath;
  }

  /// What the [Router] reports to its `routeInformationProvider` after each
  /// change (the provider's value from then on), worked out the way the
  /// Router does: the provider is told only after the frame, and tells no
  /// one. A router that reports nothing: the provider's own value.
  static String? _locationOf(Router<Object?> router) {
    RouteInformation? information;
    try {
      final shown = router.routerDelegate.currentConfiguration;
      if (shown != null) information = router.routeInformationParser?.restoreRouteInformation(shown);
    } on Object catch (e) {
      debugPrint('zehn_intelligence: the app\'s router could not tell its location: $e');
    }
    information ??= router.routeInformationProvider?.value;
    if (information == null) return null;
    return _pushed(information.state) ?? information.uri.path;
  }

  /// go_router leaves a screen opened with `push` out of the location and
  /// lists it in the state it reports, as `imperativeMatches`: the last one
  /// is the screen on top.
  static String? _pushed(Object? state) {
    if (state is! Map) return null;
    final pushed = state['imperativeMatches'];
    if (pushed is! List || pushed.isEmpty) return null;
    final top = pushed.last;
    final location = top is Map ? top['location'] : null;
    return location is String ? Uri.tryParse(location)?.path ?? location : null;
  }

  /// The name of the navigator's top route. A sheet, a dialog or any other
  /// see-through route is over a screen: the screen stays what it was.
  String? _topRouteName() {
    Route<Object?>? top;
    // Stops at the first route it is shown, the top one, and pops nothing.
    _navigator.popUntil((route) {
      top = route;
      return true;
    });
    final route = top;
    if (route == null) return null;
    if (route is PopupRoute || (route is ModalRoute && !route.opaque)) return path.value;
    final name = route.settings.name;
    return name == null || name.isEmpty ? null : name;
  }
}
