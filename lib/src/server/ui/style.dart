import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../surface/surface.dart' show parseColor;

/// The chat's look: the zehn/intelligence assistant design (a white sheet,
/// a quiet grey ramp, one accent). The accent and the font come from the
/// console theme, so each app keeps its own brand.
class ZiChatStyle {
  const ZiChatStyle({
    this.font,
    this.accent = const Color(0xFFBE7C6C),
    this.onAccent = const Color(0xFFFFFFFF),
  });

  factory ZiChatStyle.fromTheme(Map<String, Object?> theme) {
    final colors = theme['colors'];
    Color? color(String key) => colors is Map ? parseColor(colors[key] is String ? colors[key] as String : null) : null;
    return ZiChatStyle(
      font: theme['font'] is String ? theme['font'] as String : null,
      accent: color('accent') ?? const Color(0xFFBE7C6C),
      onAccent: color('on_accent') ?? const Color(0xFFFFFFFF),
    );
  }

  /// A font family the app already ships; null uses the app's default.
  final String? font;
  final Color accent;
  final Color onAccent;

  Color get background => const Color(0xFFFFFFFF);
  Color get ink => const Color(0xE61D1D16);
  Color get muted => const Color(0x991D1D16);
  Color get faint => const Color(0x4D1D1D16);
  Color get line => const Color(0x1A1D1D16);
  Color get fill => const Color(0x0D1D1D16);
  Color get barrier => const Color(0x9919212F);
  Color get danger => const Color(0xFFD64545);

  /// 20 / 28, medium.
  TextStyle get title => _style(20, FontWeight.w500, 28);

  /// 17 / 24.
  TextStyle get body => _style(17, FontWeight.w400, 24);
  TextStyle get bodyMedium => _style(17, FontWeight.w500, 24);

  /// 15 / 20.
  TextStyle get small => _style(15, FontWeight.w400, 20);
  TextStyle get smallMedium => _style(15, FontWeight.w500, 20);

  TextStyle _style(double size, FontWeight weight, double lineHeight) => TextStyle(
    fontFamily: font,
    fontSize: size,
    fontWeight: weight,
    height: lineHeight / size,
    letterSpacing: -size / 100,
    color: ink,
  );
}

/// One of the design's icons, bundled with the SDK.
class ZiIcon extends StatelessWidget {
  const ZiIcon(this.name, {super.key, this.size = 24, this.color});

  /// `arrow_left`, `arrow_up`, `chat_history`, `close_line`, `keyboard`,
  /// `message`, `mic`, `mic_chatbot`, `search_ai`, `sparkles`, `star_chat`,
  /// `stop_square`.
  final String name;
  final double size;

  /// Recolours a single-colour icon; null keeps the icon's own colours.
  final Color? color;

  @override
  Widget build(BuildContext context) => SvgPicture.asset(
    'assets/zi_icons/$name.svg',
    package: 'zehn_intelligence',
    width: size,
    height: size,
    colorFilter: color == null ? null : ColorFilter.mode(color!, BlendMode.srcIn),
    errorBuilder: (_, _, _) => SizedBox.square(dimension: size),
  );
}
