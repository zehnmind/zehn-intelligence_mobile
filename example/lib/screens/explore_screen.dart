import 'package:flutter/material.dart';

import '../logic/tour_insights.dart';
import '../models/destination.dart';
import '../models/tour_category.dart';
import '../theme/app_theme.dart';
import '../theme/visuals.dart';
import '../widgets/catalog_gate.dart';
import '../widgets/destination_card.dart';
import '../widgets/section_header.dart';
import '../widgets/tour_card.dart';
import 'tour_detail_screen.dart';

class ExploreScreen extends StatefulWidget {
  const ExploreScreen({
    super.key,
    required this.onSearchTap,
    required this.onDestinationTap,
    required this.onSeeAllTap,
  });

  final VoidCallback onSearchTap;
  final ValueChanged<Destination> onDestinationTap;
  final VoidCallback onSeeAllTap;

  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen> {
  /// Narrows the popular tours; null shows every category.
  TourCategory? _category;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: CatalogGate(
        builder: (context, tours) {
          final destinations = summarizeDestinations(tours);
          final popular = popularTours(tours, category: _category);

          return CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: _Header(onSearchTap: widget.onSearchTap),
              ),
              const SliverToBoxAdapter(
                child: SectionHeader(title: 'Featured destinations'),
              ),
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 200,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.page,
                      vertical: AppSpacing.xs,
                    ),
                    itemCount: destinations.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(width: AppSpacing.md),
                    itemBuilder: (context, index) {
                      final summary = destinations[index];
                      return DestinationCard(
                        summary: summary,
                        onTap: () =>
                            widget.onDestinationTap(summary.destination),
                      );
                    },
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.xl)),
              SliverToBoxAdapter(
                child: SectionHeader(
                  title: 'Popular tours',
                  actionLabel: 'See all',
                  onAction: widget.onSeeAllTap,
                ),
              ),
              SliverToBoxAdapter(
                child: _CategoryChips(
                  selected: _category,
                  onSelected: (category) =>
                      setState(() => _category = category),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.page,
                  AppSpacing.md,
                  AppSpacing.page,
                  AppSpacing.xxl,
                ),
                sliver: SliverList.separated(
                  itemCount: popular.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(height: AppSpacing.lg),
                  itemBuilder: (context, index) {
                    final tour = popular[index];
                    return TourCard(
                      tour: tour,
                      onTap: () => TourDetailScreen.open(context, tour.id),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.onSearchTap});

  final VoidCallback onSearchTap;

  static String _greeting(DateTime now) => switch (now.hour) {
    < 5 => 'Good evening',
    < 12 => 'Good morning',
    < 18 => 'Good afternoon',
    _ => 'Good evening',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.page,
        AppSpacing.lg,
        AppSpacing.page,
        AppSpacing.xxl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${_greeting(DateTime.now())}, traveler 👋',
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Where to next?',
                      style: theme.textTheme.headlineMedium,
                    ),
                  ],
                ),
              ),
              CircleAvatar(
                radius: 24,
                backgroundColor: scheme.primaryContainer,
                child: Icon(
                  Icons.travel_explore_rounded,
                  color: scheme.onPrimaryContainer,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          Semantics(
            button: true,
            label: 'Search tours or destinations',
            excludeSemantics: true,
            child: Material(
              color: scheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(AppRadius.md),
              child: InkWell(
                onTap: onSearchTap,
                borderRadius: BorderRadius.circular(AppRadius.md),
                child: SizedBox(
                  height: 56,
                  child: Row(
                    children: [
                      const SizedBox(width: AppSpacing.lg),
                      Icon(
                        Icons.search_rounded,
                        color: scheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Text(
                          'Search tours or destinations',
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      Icon(Icons.tune_rounded, color: scheme.primary),
                      const SizedBox(width: AppSpacing.lg),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryChips extends StatelessWidget {
  const _CategoryChips({required this.selected, required this.onSelected});

  final TourCategory? selected;
  final ValueChanged<TourCategory?> onSelected;

  @override
  Widget build(BuildContext context) {
    final options = <TourCategory?>[null, ...TourCategory.values];
    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.page),
        itemCount: options.length,
        separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sm),
        itemBuilder: (context, index) {
          final category = options[index];
          return Center(
            child: ChoiceChip(
              avatar: Icon(category?.icon ?? Icons.apps_rounded),
              label: Text(category?.label ?? 'All'),
              selected: selected == category,
              onSelected: (_) => onSelected(category),
            ),
          );
        },
      ),
    );
  }
}
