import 'package:flutter/material.dart';

import '../models/tour.dart';
import '../utils/formatters.dart';

/// One tap target over a whole tour card, placed in the card's [Stack] above
/// its content. Screen readers hear a single summary of the tour instead of
/// each line of the card, so wrap the visual content in [ExcludeSemantics].
class TourTapOverlay extends StatelessWidget {
  const TourTapOverlay({super.key, required this.tour, required this.onTap});

  final Tour tour;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Semantics(
        container: true,
        button: true,
        label:
            '${tour.title}. ${tour.location}, ${tour.destination.label}. '
            '${formatPrice(tour.price)} per person, '
            '${formatDuration(tour.durationDays)}, rated ${tour.rating}.',
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(onTap: onTap),
        ),
      ),
    );
  }
}
