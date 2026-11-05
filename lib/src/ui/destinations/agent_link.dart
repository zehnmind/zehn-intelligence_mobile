import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../core/schema/prop_schema.dart';

/// Opens one of the app's own links.
///
/// [overChat] is true when the screen opens on top of the chat — push it, so
/// closing it comes back to the conversation — and false when the chat has
/// already closed: go there.
typedef AgentLinkOpener =
    FutureOr<void> Function(
      BuildContext context,
      Uri link, {
      required bool overChat,
    });

/// One of the app's own links, with `{name}` slots its arguments fill:
/// `/orders/{id}`, `/transactions?account={accountId}`.
///
/// A link is a path inside the app, as its router sees it — no scheme, no
/// host. A slot fills a whole path segment or a whole query value, and a
/// value that could change which screen opens (a `/`, a `?`, a `..`) is
/// refused, so an argument chooses *which* order opens, never *where* the
/// user lands.
class AgentLink {
  AgentLink(this.template) : _parsed = _Template.parse(template);

  final String template;
  final _Template _parsed;

  /// The slot names, in the order they appear.
  List<String> get slots => _parsed.slots;

  /// What is wrong with this link for a destination taking [args].
  List<String> problems(Map<String, PropSchema> args) => [
    for (final error in _parsed.errors) 'link "$template" $error',
    for (final slot in slots)
      if (!args.containsKey(slot))
        'link "$template" has a slot {$slot} with no argument',
    for (final name in args.keys)
      if (!slots.contains(name)) 'argument "$name" is not in the link',
    for (final slot in _parsed.pathSlots)
      if (args[slot] case final schema? when !schema.isRequired)
        'argument "$slot" fills a path segment, so it must be required',
    for (final MapEntry(key: name, value: schema) in args.entries)
      if (schema.isFreeText)
        'argument "$name" is free text — a link takes ids, choices, '
            'patterns, numbers or yes/no',
  ];

  /// The link with [values] in its slots, or null when one cannot go there:
  /// a path value that is missing, empty, `.` or `..`, or holds `/ \ ? # %`;
  /// a query value holding `& = + # %`. An absent query value is left out.
  Uri? fill(Map<String, Object?> values) {
    if (_parsed.errors.isNotEmpty) return null;
    final path = StringBuffer();
    for (final segment in _parsed.segments) {
      path.write('/');
      final slot = segment.slot;
      if (slot == null) {
        path.write(segment.text);
        continue;
      }
      final value = _text(values[slot]);
      if (value == null || !_fitsSegment(value)) return null;
      path.write(Uri.encodeComponent(value));
    }
    if (path.isEmpty) path.write('/');

    final query = <String>[];
    for (final (key, value) in _parsed.query) {
      final slot = value.slot;
      if (slot == null) {
        query.add(value.text == null ? key : '$key=${value.text}');
        continue;
      }
      final text = _text(values[slot]);
      if (text == null) continue;
      if (!_fitsQuery(text)) return null;
      query.add('$key=${Uri.encodeQueryComponent(text)}');
    }
    return Uri.tryParse(query.isEmpty ? '$path' : '$path?${query.join('&')}');
  }

  @override
  String toString() => template;

  static String? _text(Object? value) => switch (value) {
    final String text => text.isEmpty ? null : text,
    num() || bool() => '$value',
    _ => null,
  };

  static final _notInSegment = RegExp(r'[/\\?#%\x00-\x1F\x7F]');
  static final _notInQuery = RegExp(r'[&=+#%\x00-\x1F\x7F]');

  static bool _fitsSegment(String value) =>
      value != '.' && value != '..' && !_notInSegment.hasMatch(value);

  static bool _fitsQuery(String value) => !_notInQuery.hasMatch(value);
}

/// A literal piece of a link, or a slot.
class _Part {
  const _Part.text(this.text) : slot = null;
  const _Part.slot(this.slot) : text = null;

  final String? text;
  final String? slot;
}

class _Template {
  _Template(this.segments, this.query, this.errors);

  factory _Template.parse(String template) {
    final errors = <String>[];
    final segments = <_Part>[];
    final query = <(String, _Part)>[];
    final seen = <String>{};

    _Part? part(String text, String where) {
      if (!text.contains('{') && !text.contains('}')) return _Part.text(text);
      final slot = _slot.firstMatch(text)?.group(1);
      if (slot == null) {
        errors.add('has "$text" — a slot fills a whole $where');
        return null;
      }
      if (!seen.add(slot)) errors.add('uses the slot {$slot} twice');
      return _Part.slot(slot);
    }

    if (!template.startsWith('/') || template.startsWith('//')) {
      errors.add(
        'must be a path in the app starting with "/", as its router sees it '
        '— no scheme or host',
      );
    }
    if (template.contains('#')) errors.add('has a fragment ("#")');

    final mark = template.indexOf('?');
    final path = mark == -1 ? template : template.substring(0, mark);
    final rest = mark == -1 ? '' : template.substring(mark + 1);

    if (path.length > 1) {
      for (final text in path.substring(1).split('/')) {
        final piece = part(text, 'path segment');
        if (piece != null) segments.add(piece);
      }
    }

    final keys = <String>{};
    for (final pair in rest.split('&')) {
      if (pair.isEmpty) continue;
      final equals = pair.indexOf('=');
      final key = equals == -1 ? pair : pair.substring(0, equals);
      if (key.contains('{') || key.contains('}')) {
        errors.add('has a slot in the query key "$key"');
        continue;
      }
      if (!keys.add(key)) errors.add('repeats the query key "$key"');
      if (equals == -1) {
        query.add((key, const _Part.text(null)));
        continue;
      }
      final piece = part(pair.substring(equals + 1), 'query value');
      if (piece != null) query.add((key, piece));
    }

    final parsed = _Template(segments, query, errors);
    if (errors.isEmpty && Uri.tryParse(parsed._sample()) == null) {
      errors.add('is not a valid link');
    }
    return parsed;
  }

  static final _slot = RegExp(r'^\{([A-Za-z_][A-Za-z0-9_]*)\}$');

  final List<_Part> segments;
  final List<(String, _Part)> query;
  final List<String> errors;

  List<String> get slots => [
    ...pathSlots,
    for (final (_, value) in query) ?value.slot,
  ];

  List<String> get pathSlots => [for (final segment in segments) ?segment.slot];

  /// The link with a plain value in every slot, to check what is left.
  String _sample() {
    final path = segments.map((s) => s.text ?? 'x').join('/');
    final pairs = [
      for (final (key, value) in query)
        value.slot != null
            ? '$key=x'
            : value.text == null
            ? key
            : '$key=${value.text}',
    ];
    return '/$path${pairs.isEmpty ? '' : '?${pairs.join('&')}'}';
  }
}

/// Ready-made ways to open links.
abstract final class AgentLinks {
  /// Hands [link] to the app the way the phone hands it a deep link, so the
  /// same redirects and sign-in guards apply:
  ///
  /// * to the router, for `MaterialApp.router` apps (go_router, auto_route…)
  ///   — for go_router that is a `go`;
  /// * to the navigator's named routes otherwise (`routes:`,
  ///   `onGenerateRoute:`), pushed.
  ///
  /// Throws a [FlutterError] when the app has no route for it.
  static void deliver(
    BuildContext context,
    Uri link, {
    required bool overChat,
  }) {
    final router = _routerProvider(context);
    if (router != null) {
      if (overChat) _hintPush(link);
      unawaited(router.didPushRouteInformation(RouteInformation(uri: link)));
      return;
    }
    final navigator = Navigator.maybeOf(context, rootNavigator: true);
    final route = navigator?.widget.onGenerateRoute?.call(
      RouteSettings(name: _routeName(link)),
    );
    if (navigator == null || route == null) {
      throw FlutterError.fromParts([
        ErrorSummary('zehn_intelligence: no route for the link $link.'),
        ErrorHint(
          'Add it to the app\'s routes (routes:, onGenerateRoute:, or its '
          'router), or pass openLink: to ZehnIntelligence.start to open links your '
          'own way.',
        ),
      ]);
    }
    unawaited(navigator.push<Object?>(route));
  }

  /// For routers that can both push and go — go_router:
  ///
  /// ```dart
  /// openLink: AgentLinks.goOrPush(go: router.go, push: router.push),
  /// ```
  ///
  /// A screen over the chat is pushed, so closing it comes back to the
  /// conversation; one that leaves the chat — a tab — is gone to.
  static AgentLinkOpener goOrPush({
    required void Function(String location) go,
    required Future<Object?> Function(String location) push,
  }) => (context, link, {required overChat}) async {
    if (overChat) {
      await push('$link');
    } else {
      go('$link');
    }
  };

  /// The outermost router that takes deep links — the app's own.
  static WidgetsBindingObserver? _routerProvider(BuildContext context) {
    WidgetsBindingObserver? found;
    void consider(Widget widget) {
      if (widget is! Router<Object?>) return;
      if (widget.routeInformationProvider
          case final WidgetsBindingObserver provider) {
        found = provider;
      }
    }

    consider(context.widget);
    context.visitAncestorElements((element) {
      consider(element.widget);
      return true;
    });
    return found;
  }

  /// The name `WidgetsApp` pushes for a deep link: path, query and
  /// fragment, decoded.
  static String _routeName(Uri link) => Uri.decodeComponent(
    Uri(
      path: link.path.isEmpty ? '/' : link.path,
      queryParameters: link.queryParametersAll.isEmpty
          ? null
          : link.queryParametersAll,
      fragment: link.fragment.isEmpty ? null : link.fragment,
    ).toString(),
  );

  static bool _hinted = false;

  static void _hintPush(Uri link) {
    if (!kDebugMode || _hinted) return;
    _hinted = true;
    debugPrint(
      'zehn_intelligence: $link opens over the chat, but this app\'s router can '
      'only go to it, which may replace the screen the chat is on. Push it '
      'instead: ZehnIntelligence.start(openLink: AgentLinks.goOrPush(go: router.go, '
      'push: router.push)).',
    );
  }
}
