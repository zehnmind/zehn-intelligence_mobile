import 'package:flutter/material.dart';

import '../models/tour.dart';
import '../theme/app_theme.dart';
import '../theme/visuals.dart';
import 'favorite_button.dart';
import 'tour_image.dart';
import 'tour_meta.dart';
import 'tour_tap_overlay.dart';

/// Compact row with a square thumbnail, used in search results and favorites.
class TourListTile extends StatelessWidget {
  const TourListTile({
    super.key,
    required this.tour,
    required this.onTap,
    this.onFavoriteChanged,
  });

  final Tour tour;
  final VoidCallback onTap;
  final ValueChanged<bool>? onFavoriteChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Stack(
        children: [
          ExcludeSemantics(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.sm + 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    child: SizedBox.square(
                      dimension: 104,
                      child: TourImage(
                        url: tour.imageUrl,
                        destination: tour.destination,
                        fallbackIcon: tour.category.icon,
                        iconSize: 32,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Padding(
                      // Leaves room for the heart in the top-right corner.
                      padding: const EdgeInsets.only(
                        top: AppSpacing.xs,
                        right: 36,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          LocationLabel(tour: tour),
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            tour.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall,
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          Wrap(
                            spacing: AppSpacing.md,
                            runSpacing: AppSpacing.xs,
                            children: [
                              RatingLabel(tour: tour),
                              DurationLabel(days: tour.durationDays),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.xs + 2),
                          PriceLabel(price: tour.price),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Tap target over the whole card; the heart sits above it.
          TourTapOverlay(tour: tour, onTap: onTap),
          Positioned(
            top: 0,
            right: 0,
            child: FavoriteButton(
              tourId: tour.id,
              onChanged: onFavoriteChanged,
            ),
          ),
        ],
      ),
    );
  }
}
