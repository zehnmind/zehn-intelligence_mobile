import 'package:flutter/material.dart';

import '../logic/notifier_scope.dart';
import '../logic/tour_catalog.dart';
import '../models/tour.dart';
import 'empty_state.dart';

/// Shows a spinner while tours load, an error with a retry if loading fails,
/// and [builder]'s content once they are ready.
class CatalogGate extends StatelessWidget {
  const CatalogGate({super.key, required this.builder});

  final Widget Function(BuildContext context, List<Tour> tours) builder;

  @override
  Widget build(BuildContext context) {
    final catalog = context.catalog;
    return switch (catalog.status) {
      CatalogStatus.loading => const Center(child: CircularProgressIndicator()),
      CatalogStatus.error => EmptyState(
        icon: Icons.cloud_off_rounded,
        title: 'Couldn\'t load tours',
        message: 'Something went wrong while loading tours. Please try again.',
        actionLabel: 'Try again',
        onAction: catalog.load,
      ),
      CatalogStatus.ready => builder(context, catalog.tours),
    };
  }
}
