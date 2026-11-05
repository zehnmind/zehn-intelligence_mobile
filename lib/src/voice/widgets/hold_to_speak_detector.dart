import 'package:flutter/widgets.dart';

/// Press, hold, let go — the gesture behind "hold to speak".
///
/// A [Listener] rather than a long-press recognizer, so recording starts the
/// moment the finger lands instead of half a second later, when the first
/// words would already be lost.
///
/// The empty vertical-drag handlers are there on purpose: they win the
/// gesture arena against the chat sheet's own drag, so sliding up to cancel —
/// or down, by accident — never moves or closes the sheet mid-sentence.
class HoldToSpeakDetector extends StatefulWidget {
  const HoldToSpeakDetector({
    super.key,
    required this.child,
    required this.onStart,
    required this.onMove,
    required this.onEnd,
    required this.onCancel,
    this.enabled = true,
  });

  final Widget child;
  final VoidCallback onStart;

  /// How far the finger has moved since it landed; negative is up.
  final ValueChanged<double> onMove;

  final VoidCallback onEnd;

  /// The system took the touch away — an incoming call, the permission prompt.
  final VoidCallback onCancel;

  /// Gates new presses only: a hold already under way always gets its end.
  final bool enabled;

  @override
  State<HoldToSpeakDetector> createState() => _HoldToSpeakDetectorState();
}

class _HoldToSpeakDetectorState extends State<HoldToSpeakDetector> {
  /// The finger being tracked. A second finger is ignored.
  int? _pointer;
  double _originY = 0;

  @override
  void dispose() {
    // Removed mid-hold: end the recording rather than leave it running. After
    // the frame, because the tree is locked while it is being torn down.
    if (_pointer != null) {
      final onCancel = widget.onCancel;
      WidgetsBinding.instance.addPostFrameCallback((_) => onCancel());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (event) {
        if (!widget.enabled || _pointer != null) return;
        _pointer = event.pointer;
        _originY = event.position.dy;
        widget.onStart();
      },
      onPointerMove: (event) {
        if (event.pointer != _pointer) return;
        widget.onMove(event.position.dy - _originY);
      },
      onPointerUp: (event) {
        if (event.pointer != _pointer) return;
        _pointer = null;
        widget.onEnd();
      },
      onPointerCancel: (event) {
        if (event.pointer != _pointer) return;
        _pointer = null;
        widget.onCancel();
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        excludeFromSemantics: true,
        onVerticalDragStart: (_) {},
        onVerticalDragUpdate: (_) {},
        child: widget.child,
      ),
    );
  }
}
