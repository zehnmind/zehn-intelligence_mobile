import 'package:flutter/material.dart';

/// What a chat button is for.
enum AgentButtonKind {
  /// Confirms something being made — a booking, a freeze.
  primary,

  /// Confirms something being undone — a cancellation.
  danger,

  /// Backs out.
  secondary,

  /// A small header action, like "New chat".
  compact,
}

/// Everything a button builder needs.
class AgentButtonSpec {
  const AgentButtonSpec({
    required this.label,
    required this.kind,
    required this.onTap,
    this.busy = false,
  });

  final String label;
  final AgentButtonKind kind;

  /// Null while busy.
  final VoidCallback? onTap;

  /// The action is running: show progress on the primary button, disable
  /// the others.
  final bool busy;
}

typedef AgentButtonBuilder =
    Widget Function(BuildContext context, AgentButtonSpec spec);

/// Draws a picture from the app's own data — a dashboard card's photo —
/// with the app's own image loader and cache. The card clips it.
typedef AgentImageBuilder =
    Widget Function(
      BuildContext context,
      String url, {
      double? width,
      double? height,
    });

/// How the chat looks: colours, text styles, radii, and slots for the few
/// pieces an app usually wants to supply itself — its buttons, its sheet
/// handle, its assistant icon.
///
/// Looked up from `AgentScope.theme`, then `Theme.of(context).extension`,
/// then derived from the app's [ColorScheme] and [TextTheme] — so a new app
/// gets a chat in its own colours with no configuration at all.
class AgentTheme extends ThemeExtension<AgentTheme> {
  const AgentTheme({
    required this.surface,
    required this.surfaceMuted,
    required this.userBubble,
    required this.border,
    required this.textPrimary,
    required this.textSecondary,
    required this.accent,
    required this.onAccent,
    required this.danger,
    required this.dangerBorder,
    required this.successBackground,
    required this.successBorder,
    required this.warningBackground,
    required this.warningBorder,
    required this.secondaryButton,
    required this.barrier,
    required this.body,
    required this.bodyStrong,
    required this.small,
    required this.smallStrong,
    required this.caption,
    required this.captionStrong,
    required this.title,
    this.radius = 20,
    this.sheetRadius = 32,
    this.badgeIcon,
    this.buttonBuilder,
    this.dragHandle,
    this.imageBuilder,
  });

  /// A theme in the app's own colours and type.
  factory AgentTheme.fallback(ThemeData theme) {
    final scheme = theme.colorScheme;
    final text = theme.textTheme;
    final onSurface = scheme.onSurface;
    final muted = scheme.onSurfaceVariant;
    TextStyle style(TextStyle? base, double size, FontWeight weight) =>
        (base ?? const TextStyle()).copyWith(
          fontSize: size,
          fontWeight: weight,
          height: 1.3,
        );
    return AgentTheme(
      surface: scheme.surface,
      surfaceMuted: scheme.surfaceContainerLow,
      userBubble: scheme.surfaceContainerHighest,
      border: scheme.outlineVariant,
      textPrimary: onSurface,
      textSecondary: muted,
      accent: scheme.primary,
      onAccent: scheme.onPrimary,
      danger: scheme.error,
      dangerBorder: scheme.error.withValues(alpha: 0.4),
      successBackground: const Color(0xFFE7F6EC),
      successBorder: const Color(0xFF9ED3AE),
      warningBackground: const Color(0xFFFFF4D6),
      warningBorder: const Color(0xFFF0D48A),
      secondaryButton: scheme.surfaceContainerHigh,
      barrier: Colors.black.withValues(alpha: 0.5),
      body: style(text.bodyLarge, 17, FontWeight.w400),
      bodyStrong: style(text.bodyLarge, 17, FontWeight.w500),
      small: style(text.bodyMedium, 15, FontWeight.w400),
      smallStrong: style(text.bodyMedium, 15, FontWeight.w500),
      caption: style(text.bodySmall, 13, FontWeight.w400),
      captionStrong: style(text.bodySmall, 13, FontWeight.w500),
      title: style(text.titleLarge, 20, FontWeight.w500),
    );
  }

  /// The theme in effect at [context]: the scope's, else the app theme's
  /// extension, else one derived from the app theme.
  static AgentTheme of(BuildContext context, {AgentTheme? scope}) =>
      scope ??
      Theme.of(context).extension<AgentTheme>() ??
      AgentTheme.fallback(Theme.of(context));

  /// Answer bubbles, cards, sheets.
  final Color surface;

  /// Fallback sentences and empty rows.
  final Color surfaceMuted;

  final Color userBubble;
  final Color border;
  final Color textPrimary;
  final Color textSecondary;

  /// The assistant's colour: its badge, its progress, confirm buttons.
  final Color accent;
  final Color onAccent;
  final Color danger;
  final Color dangerBorder;
  final Color successBackground;
  final Color successBorder;
  final Color warningBackground;
  final Color warningBorder;
  final Color secondaryButton;

  /// Behind the history sheet.
  final Color barrier;

  /// Prose and bubbles.
  final TextStyle body;
  final TextStyle bodyStrong;
  final TextStyle small;
  final TextStyle smallStrong;
  final TextStyle caption;
  final TextStyle captionStrong;
  final TextStyle title;

  final double radius;
  final double sheetRadius;

  /// Shown before the assistant's name on every reply. Defaults to a
  /// sparkle icon in [accent].
  final Widget? badgeIcon;

  /// Builds every button the chat shows. Defaults to Material buttons.
  final AgentButtonBuilder? buttonBuilder;

  /// Tops the history sheet. Defaults to a small rounded bar.
  final Widget? dragHandle;

  /// Draws a dashboard card's pictures. Defaults to `Image.network`, with
  /// [surfaceMuted] while it loads or when it fails.
  final AgentImageBuilder? imageBuilder;

  Widget image(
    BuildContext context,
    String url, {
    double? width,
    double? height,
  }) {
    final custom = imageBuilder;
    if (custom != null) {
      return custom(context, url, width: width, height: height);
    }
    final empty = ColoredBox(
      color: surfaceMuted,
      child: SizedBox(width: width, height: height),
    );
    return Image.network(
      url,
      width: width,
      height: height,
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => empty,
      loadingBuilder: (_, child, progress) => progress == null ? child : empty,
    );
  }

  Widget button(BuildContext context, AgentButtonSpec spec) =>
      (buttonBuilder ?? _defaultButton)(context, spec);

  Widget _defaultButton(BuildContext context, AgentButtonSpec spec) {
    final label = Text(
      spec.label,
      style: smallStrong.copyWith(
        color: spec.kind == AgentButtonKind.secondary ? textPrimary : onAccent,
      ),
    );
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(100),
    );
    switch (spec.kind) {
      case AgentButtonKind.secondary:
        return TextButton(
          onPressed: spec.busy ? null : spec.onTap,
          style: TextButton.styleFrom(
            backgroundColor: secondaryButton,
            minimumSize: const Size.fromHeight(40),
            shape: shape,
          ),
          child: label,
        );
      case AgentButtonKind.primary:
      case AgentButtonKind.danger:
      case AgentButtonKind.compact:
        final background = spec.kind == AgentButtonKind.danger
            ? danger
            : accent;
        return FilledButton(
          onPressed: spec.busy ? null : spec.onTap,
          style: FilledButton.styleFrom(
            backgroundColor: background,
            disabledBackgroundColor: background.withValues(alpha: 0.6),
            minimumSize: spec.kind == AgentButtonKind.compact
                ? const Size(0, 32)
                : const Size.fromHeight(40),
            padding: spec.kind == AgentButtonKind.compact
                ? const EdgeInsets.symmetric(horizontal: 14)
                : null,
            shape: shape,
          ),
          child: spec.busy
              ? SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: onAccent,
                  ),
                )
              : label,
        );
    }
  }

  Widget get badge =>
      badgeIcon ?? Icon(Icons.auto_awesome, size: 16, color: accent);

  Widget get handle =>
      dragHandle ??
      Container(
        width: 36,
        height: 4,
        decoration: BoxDecoration(
          color: border,
          borderRadius: BorderRadius.circular(2),
        ),
      );

  @override
  AgentTheme copyWith({
    Color? surface,
    Color? surfaceMuted,
    Color? userBubble,
    Color? border,
    Color? textPrimary,
    Color? textSecondary,
    Color? accent,
    Color? onAccent,
    Color? danger,
    Color? dangerBorder,
    Color? successBackground,
    Color? successBorder,
    Color? warningBackground,
    Color? warningBorder,
    Color? secondaryButton,
    Color? barrier,
    TextStyle? body,
    TextStyle? bodyStrong,
    TextStyle? small,
    TextStyle? smallStrong,
    TextStyle? caption,
    TextStyle? captionStrong,
    TextStyle? title,
    double? radius,
    double? sheetRadius,
    Widget? badgeIcon,
    AgentButtonBuilder? buttonBuilder,
    Widget? dragHandle,
    AgentImageBuilder? imageBuilder,
  }) => AgentTheme(
    surface: surface ?? this.surface,
    surfaceMuted: surfaceMuted ?? this.surfaceMuted,
    userBubble: userBubble ?? this.userBubble,
    border: border ?? this.border,
    textPrimary: textPrimary ?? this.textPrimary,
    textSecondary: textSecondary ?? this.textSecondary,
    accent: accent ?? this.accent,
    onAccent: onAccent ?? this.onAccent,
    danger: danger ?? this.danger,
    dangerBorder: dangerBorder ?? this.dangerBorder,
    successBackground: successBackground ?? this.successBackground,
    successBorder: successBorder ?? this.successBorder,
    warningBackground: warningBackground ?? this.warningBackground,
    warningBorder: warningBorder ?? this.warningBorder,
    secondaryButton: secondaryButton ?? this.secondaryButton,
    barrier: barrier ?? this.barrier,
    body: body ?? this.body,
    bodyStrong: bodyStrong ?? this.bodyStrong,
    small: small ?? this.small,
    smallStrong: smallStrong ?? this.smallStrong,
    caption: caption ?? this.caption,
    captionStrong: captionStrong ?? this.captionStrong,
    title: title ?? this.title,
    radius: radius ?? this.radius,
    sheetRadius: sheetRadius ?? this.sheetRadius,
    badgeIcon: badgeIcon ?? this.badgeIcon,
    buttonBuilder: buttonBuilder ?? this.buttonBuilder,
    dragHandle: dragHandle ?? this.dragHandle,
    imageBuilder: imageBuilder ?? this.imageBuilder,
  );

  @override
  AgentTheme lerp(covariant AgentTheme? other, double t) {
    if (other == null) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    TextStyle s(TextStyle a, TextStyle b) => TextStyle.lerp(a, b, t)!;
    return AgentTheme(
      surface: c(surface, other.surface),
      surfaceMuted: c(surfaceMuted, other.surfaceMuted),
      userBubble: c(userBubble, other.userBubble),
      border: c(border, other.border),
      textPrimary: c(textPrimary, other.textPrimary),
      textSecondary: c(textSecondary, other.textSecondary),
      accent: c(accent, other.accent),
      onAccent: c(onAccent, other.onAccent),
      danger: c(danger, other.danger),
      dangerBorder: c(dangerBorder, other.dangerBorder),
      successBackground: c(successBackground, other.successBackground),
      successBorder: c(successBorder, other.successBorder),
      warningBackground: c(warningBackground, other.warningBackground),
      warningBorder: c(warningBorder, other.warningBorder),
      secondaryButton: c(secondaryButton, other.secondaryButton),
      barrier: c(barrier, other.barrier),
      body: s(body, other.body),
      bodyStrong: s(bodyStrong, other.bodyStrong),
      small: s(small, other.small),
      smallStrong: s(smallStrong, other.smallStrong),
      caption: s(caption, other.caption),
      captionStrong: s(captionStrong, other.captionStrong),
      title: s(title, other.title),
      radius: radius + (other.radius - radius) * t,
      sheetRadius: sheetRadius + (other.sheetRadius - sheetRadius) * t,
      badgeIcon: t < 0.5 ? badgeIcon : other.badgeIcon,
      buttonBuilder: t < 0.5 ? buttonBuilder : other.buttonBuilder,
      dragHandle: t < 0.5 ? dragHandle : other.dragHandle,
      imageBuilder: t < 0.5 ? imageBuilder : other.imageBuilder,
    );
  }
}
