import 'package:flutter/material.dart';

import '../models/destination.dart';
import '../theme/visuals.dart';

/// A remote photo that fills its box, with a progress indicator while it
/// loads and a local gradient placeholder if it fails.
class TourImage extends StatelessWidget {
  const TourImage({
    super.key,
    required this.url,
    required this.destination,
    this.fallbackIcon = Icons.landscape_rounded,
    this.iconSize = 40,
  });

  final String url;

  /// Sets the fallback's colors.
  final Destination destination;
  final IconData fallbackIcon;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: scheme.surfaceContainerHighest,
      child: Image.network(
        url,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        excludeFromSemantics: true,
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          final total = progress.expectedTotalBytes;
          return Center(
            child: SizedBox.square(
              dimension: 28,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                value: total == null
                    ? null
                    : progress.cumulativeBytesLoaded / total,
              ),
            ),
          );
        },
        errorBuilder: (context, error, stackTrace) => ImageFallback(
          destination: destination,
          icon: fallbackIcon,
          iconSize: iconSize,
        ),
      ),
    );
  }
}

class ImageFallback extends StatelessWidget {
  const ImageFallback({
    super.key,
    required this.destination,
    required this.icon,
    this.iconSize = 40,
  });

  final Destination destination;
  final IconData icon;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: destination.gradient,
        ),
      ),
      child: Center(
        child: Icon(
          icon,
          size: iconSize,
          color: Colors.white.withValues(alpha: 0.85),
        ),
      ),
    );
  }
}
