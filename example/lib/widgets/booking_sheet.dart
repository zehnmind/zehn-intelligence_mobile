import 'package:flutter/material.dart';

import '../logic/booking.dart';
import '../models/tour.dart';
import '../theme/app_theme.dart';
import '../utils/formatters.dart';

/// Picks a departure date and the number of travelers. Returns the
/// [Booking] when the user confirms, or null when they dismiss the sheet.
class BookingSheet extends StatefulWidget {
  const BookingSheet({super.key, required this.tour, required this.departures});

  final Tour tour;
  final List<DateTime> departures;

  static Future<Booking?> show(BuildContext context, Tour tour) {
    return showModalBottomSheet<Booking>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => BookingSheet(
        tour: tour,
        departures: upcomingDepartures(tour, from: DateTime.now()),
      ),
    );
  }

  @override
  State<BookingSheet> createState() => _BookingSheetState();
}

class _BookingSheetState extends State<BookingSheet> {
  late DateTime? _departure = widget.departures.firstOrNull;
  int _travelers = 1;

  void _confirm() {
    Navigator.of(context).pop(
      Booking(
        reference: Booking.newReference(),
        tour: widget.tour,
        departure: _departure!,
        travelers: _travelers,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final tour = widget.tour;

    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.page,
          0,
          AppSpacing.page,
          AppSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Book your trip', style: theme.textTheme.headlineSmall),
            const SizedBox(height: AppSpacing.xs),
            Text(
              tour.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(color: muted),
            ),
            const SizedBox(height: AppSpacing.xxl),
            Text('Departure date', style: theme.textTheme.titleSmall),
            const SizedBox(height: AppSpacing.md),
            if (widget.departures.isEmpty)
              Text(
                'No upcoming departures. Please check back later.',
                style: theme.textTheme.bodyMedium?.copyWith(color: muted),
              )
            else
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  for (final date in widget.departures)
                    ChoiceChip(
                      label: Text(formatShortDate(date)),
                      selected: date == _departure,
                      onSelected: (_) => setState(() => _departure = date),
                    ),
                ],
              ),
            const SizedBox(height: AppSpacing.xxl),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Travelers', style: theme.textTheme.titleSmall),
                      Text(
                        'Up to ${tour.maxGroupSize} per booking',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: muted,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton.outlined(
                  tooltip: 'Remove a traveler',
                  onPressed: _travelers > 1
                      ? () => setState(() => _travelers--)
                      : null,
                  icon: const Icon(Icons.remove_rounded),
                ),
                SizedBox(
                  width: 44,
                  child: Semantics(
                    liveRegion: true,
                    label: formatTravelers(_travelers),
                    excludeSemantics: true,
                    child: Text(
                      '$_travelers',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleLarge,
                    ),
                  ),
                ),
                IconButton.outlined(
                  tooltip: 'Add a traveler',
                  onPressed: _travelers < tour.maxGroupSize
                      ? () => setState(() => _travelers++)
                      : null,
                  icon: const Icon(Icons.add_rounded),
                ),
              ],
            ),
            const Divider(height: AppSpacing.xxxl * 1.5),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${formatPrice(tour.price)} × ${formatTravelers(_travelers)}',
                    style: theme.textTheme.bodyMedium?.copyWith(color: muted),
                  ),
                ),
                Text(
                  formatPrice(tour.price * _travelers),
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xl),
            FilledButton(
              onPressed: _departure == null ? null : _confirm,
              child: const Text('Confirm booking'),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'No payment is taken in this demo.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(color: muted),
            ),
          ],
        ),
      ),
    );
  }
}

class BookingConfirmationDialog extends StatelessWidget {
  const BookingConfirmationDialog({super.key, required this.booking});

  final Booking booking;

  static Future<void> show(BuildContext context, Booking booking) {
    return showDialog<void>(
      context: context,
      builder: (_) => BookingConfirmationDialog(booking: booking),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return AlertDialog(
      scrollable: true,
      icon: Icon(Icons.check_circle_rounded, size: 52, color: scheme.primary),
      title: const Text('Booking confirmed'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Pack your bags, you\'re going to ${booking.tour.destination.label}!',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          DecoratedBox(
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                children: [
                  _DetailRow('Reference', booking.reference),
                  _DetailRow('Tour', booking.tour.title),
                  _DetailRow('Departure', formatShortDate(booking.departure)),
                  _DetailRow('Travelers', '${booking.travelers}'),
                  _DetailRow('Total', formatPrice(booking.totalPrice)),
                ],
              ),
            ),
          ),
        ],
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Done'),
        ),
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
