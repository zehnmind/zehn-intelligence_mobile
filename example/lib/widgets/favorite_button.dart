import 'package:flutter/material.dart';

import '../logic/notifier_scope.dart';
import '../theme/app_theme.dart';

/// Heart toggle for one tour. Reads and writes the shared favorites, so every
/// copy of the button for that tour updates together.
class FavoriteButton extends StatelessWidget {
  const FavoriteButton({
    super.key,
    required this.tourId,
    this.onImage = false,
    this.onChanged,
  });

  final String tourId;

  /// Draws a light circular backdrop so the heart stays visible on photos.
  final bool onImage;

  /// Called after a tap with the new state.
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final favorites = context.favorites;
    final isFavorite = favorites.isFavorite(tourId);
    final scheme = Theme.of(context).colorScheme;

    return IconButton(
      tooltip: isFavorite ? 'Remove from favorites' : 'Save to favorites',
      isSelected: isFavorite,
      onPressed: () {
        favorites.toggle(tourId);
        onChanged?.call(!isFavorite);
      },
      style: onImage
          ? IconButton.styleFrom(
              backgroundColor: scheme.surface.withValues(alpha: 0.9),
            )
          : null,
      icon: Icon(
        Icons.favorite_border_rounded,
        color: onImage ? scheme.onSurface : scheme.onSurfaceVariant,
      ),
      selectedIcon: const Icon(
        Icons.favorite_rounded,
        color: AppColors.favorite,
      ),
    );
  }
}
