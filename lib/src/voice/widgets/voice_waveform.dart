import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Three drifting sine waves whose height follows the voice.
///
/// Ported from Evonote's record screen (`SimpleWaveformPainter`), with the
/// loudness easing from its `RecordMixin`, so Zehnmind apps record with the
/// same animation.
class VoiceWaveform extends StatefulWidget {
  const VoiceWaveform({
    super.key,
    required this.level,
    required this.color,
    this.height = 64,
  });

  /// Microphone loudness, 0..1.
  final double level;
  final Color color;
  final double height;

  @override
  State<VoiceWaveform> createState() => _VoiceWaveformState();
}

class _VoiceWaveformState extends State<VoiceWaveform>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  /// The amplitude being drawn, eased toward [VoiceWaveform.level].
  double _shown = 0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..addListener(_ease);
    _controller.repeat();
  }

  /// Evonote moves 15% of the way to the new loudness every 16 ms; once a
  /// frame is the same easing without a separate timer. Registered before the
  /// builder's listener, so each frame paints the eased value.
  void _ease() => _shown += (widget.level - _shown) * 0.15;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height,
      width: double.infinity,
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) => CustomPaint(
            painter: _WaveformPainter(
              phase: _controller.value,
              amplitude: _shown,
              color: widget.color,
            ),
          ),
        ),
      ),
    );
  }
}

class _WaveformPainter extends CustomPainter {
  const _WaveformPainter({
    required this.phase,
    required this.amplitude,
    required this.color,
  });

  /// 0..1 through one cycle of the drift.
  final double phase;

  /// Voice loudness, 0..1.
  final double amplitude;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final path = Path();
    final centerY = size.height / 2;
    final offset = phase * 2 * math.pi;

    // Three waves, each faster, flatter and fainter than the one before.
    for (var wave = 0; wave < 3; wave++) {
      path.reset();
      paint.color = color.withValues(alpha: 1.0 - wave * 0.3);

      final frequency = (wave + 1) * 0.02;
      // A resting swell even in silence, rising with the voice.
      final baseAmplitude = 8.0 - wave * 2;
      final maxAmplitude = 30.0 - wave * 8;
      final height = baseAmplitude + (maxAmplitude - baseAmplitude) * amplitude;

      for (double x = 0; x <= size.width; x += 2) {
        final y = centerY + math.sin(x * frequency + offset) * height;
        if (x == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_WaveformPainter oldDelegate) =>
      oldDelegate.phase != phase ||
      oldDelegate.amplitude != amplitude ||
      oldDelegate.color != color;
}
