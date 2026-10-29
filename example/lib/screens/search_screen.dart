import 'package:flutter/material.dart';

import '../logic/notifier_scope.dart';
import '../logic/search_filter_controller.dart';
import '../logic/tour_filter.dart';
import '../models/destination.dart';
import '../models/tour.dart';
import '../theme/app_theme.dart';
import '../utils/formatters.dart';
import '../widgets/catalog_gate.dart';
import '../widgets/empty_state.dart';
import '../widgets/filter_sheet.dart';
import '../widgets/tour_list_tile.dart';
import 'tour_detail_screen.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key, required this.focusNode});

  /// Owned by the shell so the home screen's search bar can focus the field.
  final FocusNode focusNode;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _textController = TextEditingController();
  SearchFilterController? _searchFilter;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final searchFilter = NotifierScope.read<SearchFilterController>(context);
    if (searchFilter != _searchFilter) {
      _searchFilter?.removeListener(_syncTextField);
      _searchFilter = searchFilter..addListener(_syncTextField);
      _syncTextField();
    }
  }

  @override
  void dispose() {
    _searchFilter?.removeListener(_syncTextField);
    _textController.dispose();
    super.dispose();
  }

  /// Other screens can reset the query, so the field follows the filter.
  void _syncTextField() {
    final query = _searchFilter!.filter.query;
    if (_textController.text == query) return;
    _textController.value = TextEditingValue(
      text: query,
      selection: TextSelection.collapsed(offset: query.length),
    );
  }

  Future<void> _openFilters(
    SearchFilterController searchFilter,
    List<Tour> tours,
  ) async {
    widget.focusNode.unfocus();
    final result = await FilterSheet.show(
      context,
      initial: searchFilter.filter,
      tours: tours,
    );
    if (result != null) searchFilter.update(result);
  }

  void _openTour(String tourId) {
    widget.focusNode.unfocus();
    TourDetailScreen.open(context, tourId);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final searchFilter = context.searchFilter;
    final filter = searchFilter.filter;
    final allTours = context.catalog.tours;

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
              AppSpacing.lg,
            ),
            child: Text('Search', style: theme.textTheme.headlineMedium),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.page),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _textController,
                    focusNode: widget.focusNode,
                    onChanged: searchFilter.setQuery,
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      hintText: 'Search tours or destinations',
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: filter.query.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Clear search',
                              icon: const Icon(Icons.close_rounded),
                              onPressed: () => searchFilter.setQuery(''),
                            ),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Badge.count(
                  count: filter.activeFilterCount,
                  isLabelVisible: filter.hasActiveFilters,
                  child: IconButton.filledTonal(
                    tooltip: 'Filters',
                    style: IconButton.styleFrom(
                      minimumSize: const Size.square(52),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.md),
                      ),
                    ),
                    onPressed: () => _openFilters(searchFilter, allTours),
                    icon: const Icon(Icons.tune_rounded),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          _DestinationChips(
            selected: filter.destination,
            onSelected: searchFilter.setDestination,
          ),
          Expanded(
            child: CatalogGate(
              builder: (context, tours) =>
                  _buildResults(context, tours, filter, searchFilter),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResults(
    BuildContext context,
    List<Tour> tours,
    TourFilter filter,
    SearchFilterController searchFilter,
  ) {
    final theme = Theme.of(context);
    final results = filter.apply(tours);

    final summary = Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.page,
        AppSpacing.sm,
        AppSpacing.sm,
        0,
      ),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              liveRegion: true,
              child: Text(
                '${formatTourCount(results.length)} found',
                style: theme.textTheme.titleSmall,
              ),
            ),
          ),
          if (filter.hasActiveFilters)
            TextButton(
              onPressed: searchFilter.clearFilters,
              child: const Text('Clear filters'),
            )
          else
            const SizedBox(height: 48),
        ],
      ),
    );
    final activeFilters = _ActiveFilterChips(
      filter: filter,
      onChanged: searchFilter.update,
    );

    if (results.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          summary,
          activeFilters,
          Expanded(
            child: EmptyState(
              icon: Icons.search_off_rounded,
              title: 'No tours match',
              message:
                  'Try a different destination or search term, or loosen '
                  'your filters.',
              actionLabel: 'Reset search',
              onAction: searchFilter.reset,
            ),
          ),
        ],
      );
    }

    return CustomScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      slivers: [
        SliverToBoxAdapter(child: summary),
        SliverToBoxAdapter(child: activeFilters),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.page,
            AppSpacing.sm,
            AppSpacing.page,
            AppSpacing.xxl,
          ),
          sliver: SliverList.separated(
            itemCount: results.length,
            separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
            itemBuilder: (context, index) {
              final tour = results[index];
              return TourListTile(tour: tour, onTap: () => _openTour(tour.id));
            },
          ),
        ),
      ],
    );
  }
}

class _DestinationChips extends StatelessWidget {
  const _DestinationChips({required this.selected, required this.onSelected});

  final Destination? selected;
  final ValueChanged<Destination?> onSelected;

  @override
  Widget build(BuildContext context) {
    final options = <Destination?>[null, ...Destination.values];
    return SizedBox(
      height: 52,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.page),
        itemCount: options.length,
        separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sm),
        itemBuilder: (context, index) {
          final destination = options[index];
          return Center(
            child: ChoiceChip(
              label: Text(
                destination == null
                    ? 'All destinations'
                    : '${destination.flag} ${destination.label}',
              ),
              selected: selected == destination,
              onSelected: (_) => onSelected(destination),
            ),
          );
        },
      ),
    );
  }
}

/// Removable chips for the filters set in the filter sheet. The destination
/// is left out because the chip row above already shows it.
class _ActiveFilterChips extends StatelessWidget {
  const _ActiveFilterChips({required this.filter, required this.onChanged});

  final TourFilter filter;
  final ValueChanged<TourFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    final maxPrice = filter.maxPrice;
    final minRating = filter.minRating;
    final chips = [
      if (maxPrice != null)
        Chip(
          label: Text('Up to ${formatPrice(maxPrice)}'),
          deleteButtonTooltipMessage: 'Remove price filter',
          onDeleted: () => onChanged(filter.copyWith(maxPrice: () => null)),
        ),
      if (minRating != null)
        Chip(
          avatar: const Icon(Icons.star_rounded, color: AppColors.star),
          label: Text('$minRating+'),
          deleteButtonTooltipMessage: 'Remove rating filter',
          onDeleted: () => onChanged(filter.copyWith(minRating: () => null)),
        ),
      if (filter.duration != DurationRange.any)
        Chip(
          avatar: const Icon(Icons.schedule_rounded),
          label: Text(filter.duration.label),
          deleteButtonTooltipMessage: 'Remove duration filter',
          onDeleted: () =>
              onChanged(filter.copyWith(duration: DurationRange.any)),
        ),
    ];
    if (chips.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.page,
        AppSpacing.xs,
        AppSpacing.page,
        AppSpacing.xs,
      ),
      child: Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.sm,
        children: chips,
      ),
    );
  }
}
