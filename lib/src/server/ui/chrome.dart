import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'style.dart';

const _iridescent = [
  Color(0xFF37CDCE), // cyan
  Color(0xFF3AE1B1), // teal
  Color(0xFFE1E64B), // yellow
  Color(0xFFE28673), // coral
  Color(0xFFDC6DA5), // pink
];
const _iridescentStops = [0.0, 0.10, 0.50481, 0.90, 1.0];

bool _still(BuildContext context) => MediaQuery.maybeDisableAnimationsOf(context) ?? false;

/// The soft iridescent wash behind the handle and header.
class ZiTopAura extends StatelessWidget {
  const ZiTopAura({super.key});

  static const double height = 150;

  // Fitted to the design's render: ~86% strong for 20px, gone by 150px.
  static const _offsets = [0.0, 20, 31, 51, 71, 91, 101, 131, 150];
  static const _alphas = [0.86, 0.86, 0.59, 0.33, 0.245, 0.155, 0.10, 0.03, 0.0];

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (bounds) => LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [for (final a in _alphas) Colors.white.withValues(alpha: a)],
        stops: [for (final o in _offsets) o / height],
      ).createShader(bounds),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [for (final c in _iridescent) c.withValues(alpha: 0.5)],
            stops: _iridescentStops,
          ),
        ),
      ),
    ),
  );
}

class ZiDragHandle extends StatelessWidget {
  const ZiDragHandle({super.key, required this.style});

  final ZiChatStyle style;

  @override
  Widget build(BuildContext context) => Center(
    child: Container(
      width: 48,
      height: 6,
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(color: style.line, borderRadius: BorderRadius.circular(100)),
    ),
  );
}

/// A 48px round button with one icon.
class ZiCircleButton extends StatelessWidget {
  const ZiCircleButton({
    super.key,
    required this.icon,
    required this.onTap,
    required this.background,
    required this.iconColor,
    this.tooltip,
  });

  final String icon;
  final VoidCallback? onTap;
  final Color background;
  final Color iconColor;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final button = GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(color: background, shape: BoxShape.circle),
        alignment: Alignment.center,
        child: ZiIcon(icon, color: iconColor),
      ),
    );
    return tooltip == null ? button : Semantics(button: true, label: tooltip, child: button);
  }
}

/// Close or back on the left, a title and a subtitle.
class ZiHeaderBar extends StatelessWidget {
  const ZiHeaderBar({
    super.key,
    required this.style,
    required this.title,
    required this.subtitle,
    required this.leadingIcon,
    required this.leadingKey,
    required this.leadingLabel,
    required this.onLeading,
  });

  final ZiChatStyle style;
  final String title;
  final String? subtitle;

  /// `close_line` or `arrow_left`.
  final String leadingIcon;
  final Key leadingKey;
  final String leadingLabel;
  final VoidCallback onLeading;

  @override
  Widget build(BuildContext context) => Container(
    height: 64,
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    child: Row(children: [
      ZiCircleButton(
        key: leadingKey,
        icon: leadingIcon,
        onTap: onLeading,
        background: style.fill,
        iconColor: style.ink,
        tooltip: leadingLabel,
      ),
      const SizedBox(width: 16),
      Expanded(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: style.title, maxLines: 1, overflow: TextOverflow.ellipsis),
            if (subtitle != null)
              Text(subtitle!, style: style.small.copyWith(color: style.muted), maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
      // Keeps the title centred where the design puts the history button.
      const SizedBox(width: 64),
    ]),
  );
}

/// The iridescent halo that blooms behind the bubble while listening.
class ZiListeningHalo extends StatefulWidget {
  const ZiListeningHalo({super.key});

  @override
  State<ZiListeningHalo> createState() => _ZiListeningHaloState();
}

class _ZiListeningHaloState extends State<ZiListeningHalo> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3095),
  );
  static const Curve _scaleCurve = Interval(0.20766, 1.0, curve: Cubic(0.5, 0.0, 0.1, 1.0));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_still(context)) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    child: const SizedBox.square(
      dimension: 200,
      child: DecoratedBox(
        decoration: BoxDecoration(gradient: LinearGradient(colors: _iridescent, stops: _iridescentStops)),
      ),
    ),
    builder: (context, square) {
      final v = _controller.value;
      return ImageFiltered(
        imageFilter: ui.ImageFilter.blur(sigmaX: 80, sigmaY: 80),
        child: Transform.scale(
          scale: 1.0 + 0.1 * _scaleCurve.transform(v),
          child: Transform.rotate(angle: -math.pi + math.pi * Curves.easeIn.transform(v), child: square),
        ),
      );
    },
  );
}

/// Cancel, a live waveform, stop and send, while recording.
class ZiWaveformBar extends StatefulWidget {
  const ZiWaveformBar({
    super.key,
    required this.style,
    required this.level,
    required this.onCancel,
    required this.onStop,
    required this.onSend,
  });

  final ZiChatStyle style;

  /// 0..1 microphone loudness.
  final double level;
  final VoidCallback onCancel;
  final VoidCallback onStop;
  final VoidCallback onSend;

  @override
  State<ZiWaveformBar> createState() => _ZiWaveformBarState();
}

class _ZiWaveformBarState extends State<ZiWaveformBar> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  static const _heights = <double>[
    4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 12, 10, 16, 20, 12, 14, 16, 20, 4, 4, 4, 12, 10, 16, 20, 4, 4, 4, 4, 4, 4, //
    14, 16, 8, 6, 4, 4, 4, 4, 12, 10, 16, 20, 4, 4, 4, 12, 10, 16, 20, 12, 14, 16, 20, 4, 4, 4, 12, 10, 16, 20,
  ];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_still(context)) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.style;
    return SizedBox(
      height: 48,
      child: Row(children: [
        ZiCircleButton(
          key: const ValueKey('zi-cancel'),
          icon: 'close_line',
          onTap: widget.onCancel,
          background: s.line,
          iconColor: s.muted,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Container(
            height: 48,
            decoration: BoxDecoration(color: s.line, borderRadius: BorderRadius.circular(16)),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            alignment: Alignment.center,
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                final t = _controller.value * 2 * math.pi;
                // Louder speech, taller bars; silence still breathes a little.
                final gain = 0.45 + 0.9 * widget.level.clamp(0.0, 1.0);
                return FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(children: [
                    for (var i = 0; i < _heights.length; i++)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 1),
                        child: Container(
                          width: 2,
                          height: (_heights[i] + math.sin(t * 3 + i * 0.35) * _heights[i] * gain).clamp(3.0, 22.0),
                          decoration: BoxDecoration(color: s.muted, borderRadius: BorderRadius.circular(100)),
                        ),
                      ),
                  ]),
                );
              },
            ),
          ),
        ),
        const SizedBox(width: 8),
        ZiCircleButton(
          key: const ValueKey('zi-stop'),
          icon: 'stop_square',
          onTap: widget.onStop,
          background: s.line,
          iconColor: s.muted,
        ),
        const SizedBox(width: 8),
        ZiCircleButton(
          key: const ValueKey('zi-listen-send'),
          icon: 'arrow_up',
          onTap: widget.onSend,
          background: s.accent,
          iconColor: s.onAccent,
        ),
      ]),
    );
  }
}
