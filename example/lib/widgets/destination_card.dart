import 'package:flutter/material.dart';

import '../logic/tour_insights.dart';
import '../theme/app_theme.dart';
import '../utils/formatters.dart';
import 'tour_image.dart';

/// Photo card for a destination on the home screen.
class DestinationCard extends StatelessWidget {
  const DestinationCard({
    super.key,
    required this.summary,
    required this.onTap,
  });

  final DestinationSummary summary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final destination = summary.destination;
    final subtitle =
        '${formatTourCount(summary.tourCount)} · from ${formatPrice(summary.lowestPrice)}';

    // One node for screen readers, with the card's tap as its action.
    return Semantics(
      container: true,
      button: true,
      label:
          '${destination.label}, ${formatTourCount(summary.tourCount)} '
          'from ${formatPrice(summary.lowestPrice)}',
      onTap: onTap,
      excludeSemantics: true,
      child: SizedBox(
        width: 156,
        child: Card(
          child: Stack(
            fit: StackFit.expand,
            children: [
              TourImage(url: summary.coverImageUrl, destination: destination),
              // Darkens the bottom so the white text stays readable on any photo.
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: [0.35, 1],
                    colors: [Colors.transparent, Color(0xCC000000)],
                  ),
                ),
              ),
              Positioned(
                left: AppSpacing.md,
                right: AppSpacing.md,
                bottom: AppSpacing.md,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${destination.flag} ${destination.label}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: Colors.white.withValues(alpha: 0.85),
                      ),
                    ),
                  ],
                ),
              ),
              Material(
                type: MaterialType.transparency,
                child: InkWell(onTap: onTap),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
