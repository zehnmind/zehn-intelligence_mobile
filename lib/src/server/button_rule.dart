/// How `button.show_on` of `GET /v1/config` reads `button.paths`.
enum ZiButtonShowOn {
  /// On every screen.
  all,

  /// Only on the screens in the paths.
  only,

  /// On every screen except those in the paths.
  except,
}

/// Where the SDK's own button shows: `button` of `GET /v1/config`.
///
/// ```json
/// {"show_on": "except", "paths": ["/", "/auth", "/movies/:id"]}
/// ```
///
/// A path is the app's route as its router writes it. A publish hides the
/// button on the screens before sign-in; the developer changes it in the
/// console.
class ZiButtonRule {
  const ZiButtonRule({this.showOn = ZiButtonShowOn.all, this.paths = const []});

  /// A missing or unknown `show_on` counts as `all`. So does `only` or
  /// `except` with no path to go by (the server never sends that), so a
  /// broken rule can't hide the button on every screen.
  factory ZiButtonRule.fromJson(Object? json) {
    if (json is! Map) return const ZiButtonRule();
    final showOn = switch (json['show_on']) {
      'only' => ZiButtonShowOn.only,
      'except' => ZiButtonShowOn.except,
      _ => ZiButtonShowOn.all,
    };
    final listed = json['paths'];
    final paths = [
      if (listed is List)
        for (final path in listed)
          if (path is String && path.isNotEmpty) path,
    ];
    if (showOn == ZiButtonShowOn.all || paths.isEmpty) return const ZiButtonRule();
    return ZiButtonRule(showOn: showOn, paths: paths);
  }

  final ZiButtonShowOn showOn;

  /// Empty for [ZiButtonShowOn.all].
  final List<String> paths;

  /// Whether the button shows on [screen]: the open screen's path, as the
  /// app's router writes it (`/movies/42?day=1`). Null is a screen that isn't
  /// known (one pushed as a widget, with no name): the button shows.
  bool showsOn(String? screen) {
    if (showOn == ZiButtonShowOn.all || screen == null) return true;
    final listed = paths.any((path) => ziPathMatches(path, screen));
    return showOn == ZiButtonShowOn.only ? listed : !listed;
  }
}

/// Whether [screen], the open screen's path, is the route [path]: every
/// segment matches, and a `:name` or `{name}` segment of [path] matches any
/// one segment. The query, a fragment and a trailing slash are left out, so
/// `/movies/42?day=1` is `/movies/:id`, and `/` is only `/`.
bool ziPathMatches(String path, String screen) {
  final route = _segments(path);
  final open = _segments(screen);
  if (route.length != open.length) return false;
  for (var i = 0; i < route.length; i++) {
    if (!_isParameter(route[i]) && route[i] != open[i]) return false;
  }
  return true;
}

List<String> _segments(String path) {
  final end = path.indexOf(RegExp('[?#]'));
  return [
    for (final segment in (end < 0 ? path : path.substring(0, end)).split('/'))
      if (segment.isNotEmpty) segment,
  ];
}

bool _isParameter(String segment) =>
    (segment.length > 1 && segment.startsWith(':')) ||
    (segment.length > 2 && segment.startsWith('{') && segment.endsWith('}'));
