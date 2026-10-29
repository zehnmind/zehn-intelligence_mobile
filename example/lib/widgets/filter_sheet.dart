import 'package:flutter/material.dart';

import '../logic/tour_filter.dart';
import '../models/destination.dart';
import '../models/tour.dart';
import '../theme/app_theme.dart';
import '../utils/formatters.dart';

/// Bottom sheet that edits a copy of the filter and returns it on "Show".
/// Dismissing the sheet discards the changes.
class FilterSheet extends StatefulWidget {
  const FilterSheet({super.key, required this.initial, required this.tours});

  final TourFilter initial;

  /// All tours, used for the price range and the live result count.
  final List<Tour> tours;

  static Future<TourFilter?> show(
    BuildContext context, {
    required TourFilter initial,
    required List<Tour> tours,
  }) {
    return showModalBottomSheet<TourFilter>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => FilterSheet(initial: initial, tours: tours),
    );
  }

  @override
  State<FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<FilterSheet> {
  static const _priceStep = 100;
  static const _ratingOptions = <double?>[null, 4.5, 4.7, 4.8];

  late TourFilter _draft = widget.initial;
  late final _bounds = priceBounds(widget.tours, step: _priceStep);

  void _update(TourFilter filter) => setState(() => _draft = filter);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final resultCount = _draft.apply(widget.tours).length;
    final maxPrice = _draft.maxPrice;
    final sliderValue = (maxPrice ?? _bounds.max)
        .clamp(_bounds.min, _bounds.max)
        .toDouble();

    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.page,
              0,
              AppSpacing.sm,
              AppSpacing.sm,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text('Filters', style: theme.textTheme.headlineSmall),
                ),
                TextButton(
                  onPressed: _draft.hasActiveFilters
                      ? () => _update(_draft.withoutFilters())
                      : null,
                  child: const Text('Reset'),
                ),
              ],
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.page),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _SectionLabel('Destination'),
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: [
                      ChoiceChip(
                        label: const Text('Any'),
                        selected: _draft.destination == null,
                        onSelected: (_) =>
                            _update(_draft.copyWith(destination: () => null)),
                      ),
                      for (final destination in Destination.values)
                        ChoiceChip(
                          label: Text(
                            '${destination.flag} ${destination.label}',
                          ),
                          selected: _draft.destination == destination,
                          onSelected: (_) => _update(
                            _draft.copyWith(destination: () => destination),
                          ),
                        ),
                    ],
                  ),
                  _SectionLabel(
                    'Maximum price',
                    trailing: Text(
                      maxPrice == null
                          ? 'Any price'
                          : 'Up to ${formatPrice(maxPrice)}',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                  Slider(
                    value: sliderValue,
                    min: _bounds.min.toDouble(),
                    max: _bounds.max.toDouble(),
                    divisions: (_bounds.max - _bounds.min) ~/ _priceStep,
                    label: formatPrice(sliderValue.round()),
                    semanticFormatterCallback: (value) => value >= _bounds.max
                        ? 'Any price'
                        : 'Up to ${formatPrice(value.round())}',
                    onChanged: (value) {
                      final price = value.round();
                      _update(
                        _draft.copyWith(
                          maxPrice: () => price >= _bounds.max ? null : price,
                        ),
                      );
                    },
                  ),
                  const _SectionLabel('Minimum rating'),
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: [
                      for (final rating in _ratingOptions)
                        ChoiceChip(
                          avatar: rating == null
                              ? null
                              : const Icon(
                                  Icons.star_rounded,
                                  color: AppColors.star,
                                ),
                          label: Text(rating == null ? 'Any' : '$rating+'),
                          selected: _draft.minRating == rating,
                          onSelected: (_) =>
                              _update(_draft.copyWith(minRating: () => rating)),
                        ),
                    ],
                  ),
                  const _SectionLabel('Duration'),
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: [
                      for (final range in DurationRange.values)
                        ChoiceChip(
                          label: Text(range.label),
                          selected: _draft.duration == range,
                          onSelected: (_) =>
                              _update(_draft.copyWith(duration: range)),
                        ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xxl),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.page,
              AppSpacing.sm,
              AppSpacing.page,
              AppSpacing.lg,
            ),
            child: FilledButton(
              onPressed: () => Navigator.of(context).pop(_draft),
              child: Text('Show ${formatTourCount(resultCount)}'),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text, {this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xl, bottom: AppSpacing.md),
      child: Row(
        children: [
          Expanded(
            child: Text(text, style: Theme.of(context).textTheme.titleSmall),
          ),
          ?trailing,
        ],
      ),
    );
  }
}
