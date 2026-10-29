import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../logic/notifier_scope.dart';
import '../models/tour.dart';
import '../theme/app_theme.dart';
import '../theme/visuals.dart';
import '../utils/formatters.dart';
import '../widgets/booking_sheet.dart';
import '../widgets/catalog_gate.dart';
import '../widgets/empty_state.dart';
import '../widgets/favorite_button.dart';
import '../widgets/tour_image.dart';
import '../widgets/tour_meta.dart';

class TourDetailScreen extends StatefulWidget {
  const TourDetailScreen({super.key, required this.tourId});

  final String tourId;

  static Future<void> open(BuildContext context, String tourId) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => TourDetailScreen(tourId: tourId)),
    );
  }

  @override
  State<TourDetailScreen> createState() => _TourDetailScreenState();
}

class _TourDetailScreenState extends State<TourDetailScreen> {
  static const _expandedHeight = 340.0;

  final _scrollController = ScrollController();

  /// True once the photo has scrolled away and the app bar is plain surface.
  bool _collapsed = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_updateCollapsed);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _updateCollapsed() {
    final topInset = MediaQuery.paddingOf(context).top;
    final collapsed =
        _scrollController.offset > _expandedHeight - kToolbarHeight - topInset;
    if (collapsed != _collapsed) setState(() => _collapsed = collapsed);
  }

  Future<void> _book(Tour tour) async {
    final booking = await BookingSheet.show(context, tour);
    if (booking == null || !mounted) return;
    await BookingConfirmationDialog.show(context, booking);
  }

  @override
  Widget build(BuildContext context) {
    final tour = context.catalog.tourById(widget.tourId);
    if (tour == null) {
      return Scaffold(
        appBar: AppBar(),
        body: CatalogGate(
          builder: (context, _) => EmptyState(
            icon: Icons.search_off_rounded,
            title: 'Tour not found',
            message: 'This tour is no longer available.',
            actionLabel: 'Go back',
            onAction: () => Navigator.of(context).maybePop(),
          ),
        ),
      );
    }

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = scheme.onSurfaceVariant;
    // Light status bar icons over the photo, theme-matching ones once collapsed.
    final overlayStyle = !_collapsed || theme.brightness == Brightness.dark
        ? SystemUiOverlayStyle.light
        : SystemUiOverlayStyle.dark;

    return Scaffold(
      body: CustomScrollView(
        controller: _scrollController,
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: _expandedHeight,
            systemOverlayStyle: overlayStyle,
            backgroundColor: scheme.surface,
            leading: Center(
              child: IconButton(
                tooltip: 'Back',
                style: IconButton.styleFrom(
                  backgroundColor: scheme.surface.withValues(alpha: 0.9),
                ),
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.arrow_back_rounded),
              ),
            ),
            title: _collapsed
                ? Text(tour.title, maxLines: 1, overflow: TextOverflow.ellipsis)
                : null,
            actions: [
              FavoriteButton(tourId: tour.id, onImage: true),
              const SizedBox(width: AppSpacing.sm),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  TourImage(
                    url: tour.imageUrl,
                    destination: tour.destination,
                    fallbackIcon: tour.category.icon,
                    iconSize: 72,
                  ),
                  // Keeps the status bar readable on bright photos.
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        stops: [0, 0.4],
                        colors: [Color(0x73000000), Colors.transparent],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.page,
              AppSpacing.xl,
              AppSpacing.page,
              AppSpacing.xxxl,
            ),
            sliver: SliverList.list(
              children: [
                Wrap(
                  spacing: AppSpacing.md,
                  runSpacing: AppSpacing.sm,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _Tag(icon: tour.category.icon, label: tour.category.label),
                    Text(
                      '${tour.destination.flag}  ${tour.location}, '
                      '${tour.destination.label}',
                      style: theme.textTheme.labelLarge?.copyWith(color: muted),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                Text(tour.title, style: theme.textTheme.headlineSmall),
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    const Icon(
                      Icons.star_rounded,
                      color: AppColors.star,
                      size: 22,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Text(
                      tour.rating.toStringAsFixed(1),
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Text(
                      '${formatThousands(tour.reviewCount)} reviews',
                      style: theme.textTheme.bodyMedium?.copyWith(color: muted),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xl),
                _InfoGrid(tour: tour),
                _Section(
                  title: 'About this tour',
                  child: Text(
                    tour.description,
                    style: theme.textTheme.bodyLarge?.copyWith(height: 1.5),
                  ),
                ),
                _Section(
                  title: 'Highlights',
                  child: _BulletList(
                    items: tour.highlights,
                    icon: Icons.auto_awesome_rounded,
                  ),
                ),
                _Section(
                  title: 'What\'s included',
                  child: _BulletList(
                    items: tour.included,
                    icon: Icons.check_circle_rounded,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: _BookingBar(tour: tour, onBook: () => _book(tour)),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm + 2,
          vertical: AppSpacing.xs + 1,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: scheme.onPrimaryContainer),
            const SizedBox(width: AppSpacing.xs),
            Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: scheme.onPrimaryContainer,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoGrid extends StatelessWidget {
  const _InfoGrid({required this.tour});

  final Tour tour;

  @override
  Widget build(BuildContext context) {
    Widget row(Widget first, Widget second) => IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: first),
          const SizedBox(width: AppSpacing.md),
          Expanded(child: second),
        ],
      ),
    );

    return Column(
      children: [
        row(
          _InfoTile(
            icon: Icons.schedule_rounded,
            label: 'Duration',
            value: formatDuration(tour.durationDays),
          ),
          _InfoTile(
            icon: Icons.groups_rounded,
            label: 'Group size',
            value: 'Up to ${tour.maxGroupSize}',
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        row(
          _InfoTile(
            icon: Icons.translate_rounded,
            label: 'Languages',
            value: tour.languages.join(', '),
          ),
          _InfoTile(
            icon: Icons.event_rounded,
            label: 'Departs',
            value: formatWeekdays(tour.departureWeekdays),
          ),
        ),
      ],
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.sm),
                child: Icon(icon, size: 20, color: scheme.onPrimaryContainer),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(value, style: theme.textTheme.labelLarge),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xxl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: AppSpacing.md),
          child,
        ],
      ),
    );
  }
}

class _BulletList extends StatelessWidget {
  const _BulletList({required this.items, required this.icon});

  final List<String> items;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        for (final item in items)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs + 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 20, color: theme.colorScheme.primary),
                const SizedBox(width: AppSpacing.md),
                Expanded(child: Text(item, style: theme.textTheme.bodyLarge)),
              ],
            ),
          ),
      ],
    );
  }
}

class _BookingBar extends StatelessWidget {
  const _BookingBar({required this.tour, required this.onBook});

  final Tour tour;
  final VoidCallback onBook;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.page,
            AppSpacing.md,
            AppSpacing.page,
            AppSpacing.md,
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Price',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    PriceLabel(price: tour.price, large: true),
                  ],
                ),
              ),
              FilledButton.icon(
                onPressed: onBook,
                icon: const Icon(Icons.event_available_rounded),
                label: const Text('Book now'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
