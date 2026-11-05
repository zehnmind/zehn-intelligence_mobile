import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/cards/card_values.dart';
import '../../core/config/agent_remote_config.dart';
import '../../core/config/config_caps.dart';
import '../scope/agent_scope.dart';
import '../theme/agent_theme.dart';
import 'agent_fallback_text.dart';

/// A dashboard card, drawn from the plugin's blocks in the app's theme.
///
/// Everything it shows is [values]: the app's own data, read by the getters
/// the app declared. A slot whose field is empty is left out, a block
/// without its text is hidden, and a card with nothing left shows its
/// sentence instead of an empty box.
class AgentDashboardCard extends StatelessWidget {
  const AgentDashboardCard({
    super.key,
    required this.spec,
    required this.values,
    required this.languageCode,
    required this.fallbackLanguage,
    required this.fallbackText,
    this.onTap,
    this.onButton,
  });

  final AgentCardSpec spec;
  final Map<String, CardValue?> values;
  final String languageCode;

  /// The app's default language, for text the dashboard wrote in some
  /// languages only.
  final String fallbackLanguage;

  /// The card's sentence: what shows when nothing else can.
  final String fallbackText;

  /// Null leaves the card inert.
  final VoidCallback? onTap;

  /// What each button does, resolved by the host; null leaves it inert.
  final VoidCallback? Function(CardButton button)? onButton;

  @override
  Widget build(BuildContext context) {
    final theme = AgentScope.themeOf(context);
    final shown = [
      for (final block in spec.blocks)
        if (_shows(block.when, values))
          if (_block(context, theme, block) case final widget?) (block, widget),
    ];
    // Buttons and dividers alone say nothing about the result.
    final saysSomething = shown.any(
      (entry) => entry.$1 is! ButtonsBlock && entry.$1 is! DividerBlock,
    );
    if (!saysSomething) return AgentFallbackText(fallbackText);
    final blocks = [for (final (_, widget) in shown) widget];

    return Material(
      color: theme.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(theme.radius),
        side: BorderSide(color: theme.border),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < blocks.length; i++) ...[
                if (i > 0) const SizedBox(height: 8),
                blocks[i],
              ],
            ],
          ),
        ),
      ),
    );
  }

  String? _fill(CardText text, [Map<String, CardValue?>? scope]) =>
      CardFill.text(
        text,
        scope ?? values,
        languageCode: languageCode,
        fallbackLanguage: fallbackLanguage,
      );

  String? _image(String? field) {
    final value = field == null ? null : values[field];
    return value is CardImageValue && CardFill.holds(value) ? value.url : null;
  }

  /// A flag the app doesn't know (its getter gave null) is neither true nor
  /// false: `"!open"` shows only for a place known to be closed.
  static bool _shows(CardCondition? condition, Map<String, CardValue?> scope) {
    if (condition == null) return true;
    final value = scope[condition.field];
    return condition.negated
        ? value is CardFlagValue && !value.flag
        : CardFill.holds(value);
  }

  Widget? _block(BuildContext context, AgentTheme theme, CardBlock block) {
    switch (block) {
      case HeaderBlock(:final image, :final title, :final line):
        final heading = _fill(title);
        if (heading == null) return null;
        final subtitle = line == null ? null : _fill(line);
        final url = _image(image);
        return Row(
          children: [
            if (url != null) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: theme.image(context, url, width: 44, height: 44),
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    heading,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.bodyStrong.copyWith(color: theme.textPrimary),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.small.copyWith(color: theme.textSecondary),
                    ),
                ],
              ),
            ),
          ],
        );
      case ImageBlock(:final field, :final effectiveShape):
        final url = _image(field);
        if (url == null) return null;
        return ClipRRect(
          // Inside the card's corner; never rounder than the theme.
          borderRadius: BorderRadius.circular(
            math.min(theme.radius, math.max(4, theme.radius - 8)),
          ),
          child: AspectRatio(
            aspectRatio: effectiveShape == CardImageShape.wide ? 16 / 9 : 1,
            child: theme.image(
              context,
              url,
              width: double.infinity,
              height: double.infinity,
            ),
          ),
        );
      case TextBlock(:final text, :final effectiveStyle):
        final words = _fill(text);
        if (words == null) return null;
        return Text(
          words,
          maxLines: 4,
          overflow: TextOverflow.ellipsis,
          style: switch (effectiveStyle) {
            CardTextStyle.body => theme.body.copyWith(color: theme.textPrimary),
            CardTextStyle.strong => theme.bodyStrong.copyWith(
              color: theme.textPrimary,
            ),
            CardTextStyle.secondary => theme.small.copyWith(
              color: theme.textSecondary,
            ),
            CardTextStyle.caption => theme.caption.copyWith(
              color: theme.textSecondary,
            ),
          },
        );
      case BadgeBlock(:final text, :final effectiveTone):
        final words = _fill(text);
        if (words == null) return null;
        final (background, foreground) = switch (effectiveTone) {
          CardTone.neutral => (theme.surfaceMuted, theme.textSecondary),
          CardTone.accent => (
            theme.accent.withValues(alpha: 0.12),
            theme.accent,
          ),
          CardTone.success => (theme.successBackground, theme.textPrimary),
          CardTone.warning => (theme.warningBackground, theme.textPrimary),
        };
        return Align(
          alignment: AlignmentDirectional.centerStart,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              child: Text(
                words,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.captionStrong.copyWith(color: foreground),
              ),
            ),
          ),
        );
      case RowsBlock(:final items):
        return _rows(theme, [
          for (final row in items) (_fill(row.label), _fill(row.value)),
        ]);
      case ListRowsBlock(:final from, :final label, :final value, :final only):
        final list = values[from];
        if (list is! CardListValue) return null;
        return _rows(theme, [
          for (final item in list.items)
            if (_shows(only, item)) (_fill(label, item), _fill(value, item)),
        ]);
      case ButtonsBlock(:final items):
        final shown = [
          for (final item in items)
            if (_fill(item.label) case final label?) (item, label),
        ];
        if (shown.isEmpty) return null;
        Widget button((CardButton, String) entry, AgentButtonKind kind) =>
            theme.button(
              context,
              AgentButtonSpec(
                label: entry.$2,
                kind: kind,
                onTap: onButton?.call(entry.$1),
              ),
            );
        // An inert button swallows its tap rather than passing it to the
        // card underneath.
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {},
          child: shown.length == 1
              ? button(shown.single, AgentButtonKind.primary)
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final first = button(
                      shown.first,
                      AgentButtonKind.secondary,
                    );
                    // As on the app's confirmation cards: the second is the
                    // main one.
                    final second = button(shown.last, AgentButtonKind.primary);
                    final half = (constraints.maxWidth - 8) / 2;
                    final sideBySide = shown.every(
                      (entry) => _labelWidth(context, theme, entry.$2) <= half,
                    );
                    if (!sideBySide) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [first, const SizedBox(height: 8), second],
                      );
                    }
                    return Row(
                      children: [
                        Expanded(child: first),
                        const SizedBox(width: 8),
                        Expanded(child: second),
                      ],
                    );
                  },
                ),
        );
      case DividerBlock():
        return Divider(height: 1, thickness: 1, color: theme.border);
    }
  }

  /// About how wide a button with [label] is: the words at the reader's text
  /// size, and room for the button's own padding.
  static double _labelWidth(
    BuildContext context,
    AgentTheme theme,
    String label,
  ) {
    final painter = TextPainter(
      text: TextSpan(text: label, style: theme.bodyStrong),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width + 40;
  }

  /// Label and value rows; a row missing either is left out, at most six.
  Widget? _rows(AgentTheme theme, List<(String?, String?)> rows) {
    final shown = [
      for (final (label, value) in rows)
        if (label != null && value != null) (label, value),
    ].take(AgentConfigCaps.cardRows).toList();
    if (shown.isEmpty) return null;
    return Column(
      children: [
        for (final (label, value) in shown)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.small.copyWith(color: theme.textSecondary),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    value,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.end,
                    style: theme.smallStrong.copyWith(color: theme.textPrimary),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
