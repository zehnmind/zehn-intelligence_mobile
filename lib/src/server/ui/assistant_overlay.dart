import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart';

import '../runtime.dart';
import 'launcher_button.dart';
import 'strings.dart';

/// The SDK's own button, drawn over the app with no code of the app's:
/// `ZehnIntelligence.start(dio: …)` puts it in the root navigator's overlay,
/// found from `WidgetsBinding.instance.rootElement` once the app has drawn a
/// frame. Until the app has a navigator (a splash before `MaterialApp`), it
/// looks again at each frame the app draws.
///
/// It shows while the assistant is available (nothing published hides it)
/// and the chat isn't open.
abstract final class ZiAssistantOverlay {
  static OverlayEntry? _entry;
  static bool _looking = false;

  /// Whether the button is in an overlay.
  static bool get isInstalled => _entry != null;

  /// Puts the button over the app, once; called again, it does nothing.
  static void install() {
    if (_entry != null || _looking) return;
    _looking = true;
    WidgetsBinding.instance.addPostFrameCallback(_look);
  }

  static void _look(Duration _) {
    if (!_looking) return;
    final overlay = rootNavigator()?.overlay;
    if (overlay == null) {
      // Not yet: at the next frame the app draws (no frame is asked for).
      WidgetsBinding.instance.addPostFrameCallback(_look);
      return;
    }
    _looking = false;
    final entry = _entry = OverlayEntry(builder: (_) => const ZiFloatingAssistant());
    overlay.insert(entry);
  }

  /// The app's root navigator: the first [NavigatorState] from the root
  /// element, breadth first, so a nested navigator (deeper) never wins.
  static NavigatorState? rootNavigator() {
    final root = WidgetsBinding.instance.rootElement;
    if (root == null) return null;
    final queue = Queue<Element>()..add(root);
    while (queue.isNotEmpty) {
      final element = queue.removeFirst();
      if (element is StatefulElement && element.state is NavigatorState) return element.state as NavigatorState;
      element.visitChildren(queue.add);
    }
    return null;
  }

  /// The button left the tree: if its overlay went away (the app built a new
  /// navigator), it goes into the new one after this frame.
  static void _left() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final entry = _entry;
      if (entry == null || entry.mounted) return;
      _entry = null;
      install();
    });
  }

  /// Takes the button away (tests).
  @visibleForTesting
  static void remove() {
    final entry = _entry;
    _entry = null;
    _looking = false;
    if (entry != null && entry.mounted) entry.remove();
  }
}

/// The floating button: draggable, snapped to the nearest side, above the
/// keyboard and clear of a bottom navigation bar.
class ZiFloatingAssistant extends StatefulWidget {
  const ZiFloatingAssistant({super.key});

  static const size = 56.0;
  static const margin = 16.0;

  /// Room kept free at the bottom for a bottom navigation bar (Material 3's
  /// `NavigationBar` is 80).
  static const bottomBar = 80.0;

  /// Its first place: the end side, above where an app keeps its own
  /// floating button.
  static const aboveAppButton = 72.0;

  @override
  State<ZiFloatingAssistant> createState() => _ZiFloatingAssistantState();
}

class _ZiFloatingAssistantState extends State<ZiFloatingAssistant> {
  /// Where the user left it, as a share of the free room (0 to 1 across and
  /// down), so it keeps its place when the screen turns; null: its first place.
  Offset? _place;
  bool _dragging = false;
  bool _chatOpen = false;
  Offset? _dragAt;

  @override
  void dispose() {
    ZiAssistantOverlay._left();
    super.dispose();
  }

  Future<void> _open(ZiRuntime runtime) async {
    if (_chatOpen) return;
    setState(() => _chatOpen = true);
    try {
      await runtime.openChat(context);
    } on Object catch (e) {
      debugPrint('zehn_intelligence: the chat could not open: $e');
    } finally {
      if (mounted) setState(() => _chatOpen = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final runtime = ZiRuntime.instance;
    if (runtime == null) return const SizedBox.shrink();
    return ValueListenableBuilder<bool>(
      valueListenable: runtime.available,
      builder: (context, available, _) {
        if (!available || _chatOpen) return const SizedBox.shrink();
        final media = MediaQuery.of(context);
        return LayoutBuilder(
          builder: (context, constraints) {
            final room = _room(media, constraints.biggest);
            final place = _place;
            final at =
                _dragAt ??
                (place == null
                    ? Offset(room.right, math.max(room.top, room.bottom - ZiFloatingAssistant.aboveAppButton))
                    : Offset(room.left + place.dx * room.width, room.top + place.dy * room.height));
            final left = at.dx.clamp(room.left, room.right).toDouble();
            final top = at.dy.clamp(room.top, room.bottom).toDouble();
            return Stack(
              children: [
                AnimatedPositioned(
                  duration: _dragging ? Duration.zero : const Duration(milliseconds: 200),
                  curve: Curves.easeOut,
                  left: left,
                  top: top,
                  child: GestureDetector(
                    // The button follows the finger from where it went down.
                    dragStartBehavior: DragStartBehavior.down,
                    onPanStart: (_) => setState(() {
                      _dragging = true;
                      _dragAt = Offset(left, top);
                    }),
                    onPanUpdate: (details) => setState(() => _dragAt = (_dragAt ?? Offset(left, top)) + details.delta),
                    onPanEnd: (_) => _drop(room),
                    onPanCancel: () => _drop(room),
                    child: ZiLauncherButton(
                      size: ZiFloatingAssistant.size,
                      label: ZiStrings.of(runtime.language).ask,
                      onTap: () => unawaited(_open(runtime)),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// Where the button's top-left may be: inside the safe area, above the
  /// keyboard, clear of a bottom navigation bar.
  static Rect _room(MediaQueryData media, Size area) {
    const size = ZiFloatingAssistant.size;
    const margin = ZiFloatingAssistant.margin;
    final keyboard = media.viewInsets.bottom;
    final bottomFree = keyboard > 0 ? keyboard : media.padding.bottom + ZiFloatingAssistant.bottomBar;
    final left = media.padding.left + margin;
    final top = media.padding.top + margin;
    final right = math.max(left, area.width - media.padding.right - margin - size);
    final bottom = math.max(top, area.height - bottomFree - margin - size);
    return Rect.fromLTRB(left, top, right, bottom);
  }

  /// Let go: to the nearest side, at the height it was dropped.
  void _drop(Rect room) {
    final at = _dragAt;
    setState(() {
      _dragging = false;
      _dragAt = null;
      if (at == null) return;
      final across = (at.dx - room.left) < (room.right - at.dx) ? 0.0 : 1.0;
      final down = room.height <= 0 ? 0.0 : ((at.dy - room.top) / room.height).clamp(0.0, 1.0);
      _place = Offset(across, down);
    });
  }
}
