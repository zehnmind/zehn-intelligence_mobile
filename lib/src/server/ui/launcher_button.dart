import 'package:flutter/material.dart';

import 'soap_bubble.dart';
import 'style.dart';

/// The assistant's launcher: a living soap bubble with the message icon.
/// Shrinks a little under the finger.
class ZiLauncherButton extends StatefulWidget {
  const ZiLauncherButton({super.key, this.onTap, this.size = 64, this.icon, this.label});

  final VoidCallback? onTap;
  final double size;

  /// Replaces the message icon.
  final Widget? icon;

  /// Read by screen readers.
  final String? label;

  @override
  State<ZiLauncherButton> createState() => _ZiLauncherButtonState();
}

class _ZiLauncherButtonState extends State<ZiLauncherButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final iconSize = widget.size / 2;
    return Semantics(
      button: true,
      label: widget.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _down = true),
        onTapCancel: () => setState(() => _down = false),
        onTapUp: (_) {
          setState(() => _down = false);
          widget.onTap?.call();
        },
        child: AnimatedScale(
          scale: _down ? 0.92 : 1,
          duration: const Duration(milliseconds: 100),
          child: IgnorePointer(
            child: SoapBubble(
              size: widget.size,
              boxShadow: const [BoxShadow(color: Color(0x1A1D1D16), blurRadius: 16, offset: Offset(0, 8))],
              child: widget.icon ?? ZiIcon('message', size: iconSize),
            ),
          ),
        ),
      ),
    );
  }
}
