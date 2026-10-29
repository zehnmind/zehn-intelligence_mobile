import 'package:flutter/material.dart';

import '../models/tour.dart';
import '../models/tour_category.dart';
import '../theme/app_theme.dart';
import '../theme/visuals.dart';
import '../utils/formatters.dart';

/// "🇹🇷 Göreme, Cappadocia".
class LocationLabel extends StatelessWidget {
  const LocationLabel({super.key, required this.tour, this.style});

  final Tour tour;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      '${tour.destination.flag}  ${tour.location}',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style:
          style ??
          theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
    );
  }
}

/// Star, score and compact review count.
class RatingLabel extends StatelessWidget {
  const RatingLabel({super.key, required this.tour});

  final Tour tour;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      label: 'Rated ${tour.rating} from ${tour.reviewCount} reviews',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.star_rounded, size: 18, color: AppColors.star),
          const SizedBox(width: 2),
          Text(
            tour.rating.toStringAsFixed(1),
            style: theme.textTheme.labelLarge,
          ),
          const SizedBox(width: 2),
          Text(
            '(${formatCompactCount(tour.reviewCount)})',
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class DurationLabel extends StatelessWidget {
  const DurationLabel({super.key, required this.days});

  final int days;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.onSurfaceVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.schedule_rounded, size: 16, color: color),
        const SizedBox(width: AppSpacing.xs),
        Text(
          formatDuration(days),
          style: theme.textTheme.labelMedium?.copyWith(color: color),
        ),
      ],
    );
  }
}

/// "$890 /person".
class PriceLabel extends StatelessWidget {
  const PriceLabel({super.key, required this.price, this.large = false});

  final int price;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final priceStyle = large
        ? theme.textTheme.titleLarge
        : theme.textTheme.titleMedium;
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: formatPrice(price),
            style: priceStyle?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w800,
            ),
          ),
          TextSpan(
            text: ' /person',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// Small pill with the category icon and name, readable on photos.
class CategoryBadge extends StatelessWidget {
  const CategoryBadge({super.key, required this.category});

  final TourCategory category;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm + 2,
          vertical: AppSpacing.xs + 2,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(category.icon, size: 14, color: scheme.primary),
            const SizedBox(width: AppSpacing.xs),
            Text(
              category.label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: scheme.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
