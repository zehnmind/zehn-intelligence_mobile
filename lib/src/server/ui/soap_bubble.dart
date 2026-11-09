import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// The zehn/intelligence soap bubble: a thin-film interference shader
/// (`shaders/bubble.frag`, bundled with the SDK). Every colour comes from a
/// film thickness, Fresnel coefficients and the CIE colour matching
/// functions, so it moves like a bubble rather than like a gradient.
///
/// It holds still when the phone asks for reduced motion.
class SoapBubble extends StatefulWidget {
  const SoapBubble({
    super.key,
    this.size = 64,
    this.backdrop = const Color(0xFFFFFFFF),
    this.drive = 0,
    this.onTap,
    this.child,
    this.boxShadow,
  });

  final double size;

  /// What shows through the film (the page colour).
  final Color backdrop;

  /// 0..1 voice energy: makes the film ripple while listening.
  final double drive;

  /// Also gives the bubble a one-second capillary burst.
  final VoidCallback? onTap;
  final Widget? child;
  final List<BoxShadow>? boxShadow;

  /// Loaded once and shared by every bubble.
  static Future<ui.FragmentProgram?> program = _load();

  static Future<ui.FragmentProgram?> _load() async {
    try {
      return await ui.FragmentProgram.fromAsset('packages/zehn_intelligence/shaders/bubble.frag');
    } on Object catch (e) {
      debugPrint('zehn_intelligence: the bubble shader did not load: $e');
      return null;
    }
  }

  @override
  State<SoapBubble> createState() => _SoapBubbleState();
}

class _SoapBubbleState extends State<SoapBubble> with TickerProviderStateMixin {
  ui.FragmentShader? _shader;
  late final Ticker _ticker = createTicker(_onTick);
  late final AnimationController _kick = AnimationController(vsync: this, duration: const Duration(seconds: 1))
    ..addListener(_repaint);
  double _clock = 0;
  Duration _last = Duration.zero;

  @override
  void initState() {
    super.initState();
    unawaited(SoapBubble.program.then((program) {
      if (program != null && mounted) setState(() => _shader = program.fragmentShader());
    }));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (still && _ticker.isActive) {
      _ticker.stop();
    } else if (!still && !_ticker.isActive) {
      _last = Duration.zero;
      unawaited(_ticker.start());
    }
  }

  void _onTick(Duration elapsed) {
    if (_last != Duration.zero) {
      _clock += ((elapsed - _last).inMicroseconds / 1e6).clamp(0.0, 0.05);
    }
    _last = elapsed;
    _repaint();
  }

  void _repaint() {
    if (mounted && _shader != null) setState(() {});
  }

  @override
  void dispose() {
    _ticker.dispose();
    _kick.dispose();
    _shader?.dispose();
    super.dispose();
  }

  void _tap() {
    if (!(MediaQuery.maybeDisableAnimationsOf(context) ?? false)) unawaited(_kick.forward(from: 0));
    widget.onTap?.call();
  }

  @override
  Widget build(BuildContext context) {
    final age = _kick.isAnimating ? _kick.value : 1.0;
    Widget content = SizedBox.square(
      dimension: widget.size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (_shader != null)
            CustomPaint(
              size: Size.square(widget.size),
              painter: _BubblePainter(
                shader: _shader!,
                time: _clock,
                drive: widget.drive,
                kick: (1 - age) * (1 - age),
                backdrop: widget.backdrop,
              ),
            ),
          ?widget.child,
        ],
      ),
    );
    if (widget.boxShadow != null) {
      content = DecoratedBox(
        decoration: BoxDecoration(shape: BoxShape.circle, boxShadow: widget.boxShadow),
        child: content,
      );
    }
    return GestureDetector(behavior: HitTestBehavior.opaque, onTap: _tap, child: content);
  }
}

class _BubblePainter extends CustomPainter {
  const _BubblePainter({
    required this.shader,
    required this.time,
    required this.drive,
    required this.kick,
    required this.backdrop,
  });

  final ui.FragmentShader shader;
  final double time;
  final double drive;
  final double kick;
  final Color backdrop;

  @override
  void paint(Canvas canvas, Size size) {
    // Uniform order of bubble.frag: uRes, uTime, uDrive, uKick, uBack.
    shader
      ..setFloat(0, size.width)
      ..setFloat(1, size.height)
      ..setFloat(2, time)
      ..setFloat(3, drive)
      ..setFloat(4, kick)
      ..setFloat(5, backdrop.r)
      ..setFloat(6, backdrop.g)
      ..setFloat(7, backdrop.b);
    canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
  }

  @override
  bool shouldRepaint(_BubblePainter old) =>
      old.time != time || old.drive != drive || old.kick != kick || old.backdrop != backdrop;
}
