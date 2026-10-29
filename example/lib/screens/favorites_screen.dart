import 'package:flutter/material.dart';

import '../logic/favorites_controller.dart';
import '../logic/notifier_scope.dart';
import '../models/tour.dart';
import '../theme/app_theme.dart';
import '../utils/formatters.dart';
import '../widgets/catalog_gate.dart';
import '../widgets/empty_state.dart';
import '../widgets/tour_list_tile.dart';
import 'tour_detail_screen.dart';

class FavoritesScreen extends StatelessWidget {
  const FavoritesScreen({super.key, required this.onExploreTap});

  final VoidCallback onExploreTap;

  void _showRemoved(
    BuildContext context,
    Tour tour,
    FavoritesController favorites,
  ) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('Removed ${tour.title}'),
          // Snack bars with an action stay up by default; this one should not.
          persist: false,
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () => favorites.add(tour.id),
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final favorites = context.favorites;
    final catalog = context.catalog;

    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.page,
              AppSpacing.lg,
              AppSpacing.page,
              AppSpacing.xs,
            ),
            child: Text('Favorites', style: theme.textTheme.headlineMedium),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.page),
            child: Text(
              favorites.count == 0
                  ? 'Tours you save appear here'
                  : '${formatTourCount(favorites.count)} saved',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: CatalogGate(
              builder: (context, _) {
                // Most recently saved first.
                final saved = [
                  for (final id in favorites.ids.toList().reversed)
                    ?catalog.tourById(id),
                ];
                if (saved.isEmpty) {
                  return EmptyState(
                    icon: Icons.favorite_border_rounded,
                    title: 'No favorites yet',
                    message:
                        'Tap the heart on any tour to save it here for later.',
                    actionLabel: 'Explore tours',
                    onAction: onExploreTap,
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.page,
                    AppSpacing.lg,
                    AppSpacing.page,
                    AppSpacing.xxl,
                  ),
                  itemCount: saved.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(height: AppSpacing.md),
                  itemBuilder: (context, index) {
                    final tour = saved[index];
                    return TourListTile(
                      tour: tour,
                      onTap: () => TourDetailScreen.open(context, tour.id),
                      onFavoriteChanged: (isFavorite) {
                        if (!isFavorite) _showRemoved(context, tour, favorites);
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
