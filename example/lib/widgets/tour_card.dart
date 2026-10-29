import 'package:flutter/material.dart';

import '../models/tour.dart';
import '../theme/app_theme.dart';
import '../theme/visuals.dart';
import 'favorite_button.dart';
import 'tour_image.dart';
import 'tour_meta.dart';
import 'tour_tap_overlay.dart';

/// Large card with the photo on top, used on the home screen.
class TourCard extends StatelessWidget {
  const TourCard({super.key, required this.tour, required this.onTap});

  final Tour tour;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Stack(
        children: [
          ExcludeSemantics(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AspectRatio(
                  aspectRatio: 16 / 10,
                  child: TourImage(
                    url: tour.imageUrl,
                    destination: tour.destination,
                    fallbackIcon: tour.category.icon,
                    iconSize: 56,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.md,
                    AppSpacing.lg,
                    AppSpacing.lg,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      LocationLabel(tour: tour),
                      const SizedBox(height: AppSpacing.xs + 2),
                      Text(
                        tour.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          // Wraps onto two lines with large text or narrow cards.
                          Expanded(
                            child: Wrap(
                              spacing: AppSpacing.lg,
                              runSpacing: AppSpacing.xs,
                              children: [
                                RatingLabel(tour: tour),
                                DurationLabel(days: tour.durationDays),
                              ],
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          PriceLabel(price: tour.price),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Tap target over the whole card; the heart sits above it.
          TourTapOverlay(tour: tour, onTap: onTap),
          Positioned(
            top: AppSpacing.md,
            left: AppSpacing.md,
            child: CategoryBadge(category: tour.category),
          ),
          Positioned(
            top: AppSpacing.xs + 2,
            right: AppSpacing.xs + 2,
            child: FavoriteButton(tourId: tour.id, onImage: true),
          ),
        ],
      ),
    );
  }
}
