import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:cupola/core/app_elevation.dart';
import 'package:cupola/core/app_gradients.dart';
import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/network/pinned_image_cache.dart';
import 'package:cupola/core/widgets/pressable_scale.dart';
import 'package:cupola/core/widgets/shimmer_placeholder.dart';

/// A card widget for displaying media content with cached images.
///
/// Designed to work seamlessly with Hero transitions and follows
/// Material Design 3 styling guidelines with Seerr-inspired colors.
class ContentCard extends StatelessWidget {
  /// URL of the image to display
  final String? imageUrl;

  /// Optional headers used when fetching protected images.
  final Map<String, String>? httpHeaders;

  /// Optional badge widget to display in the corner (e.g., status badge).
  final Widget? badge;

  /// Optional callback for tap gesture
  final VoidCallback? onTap;

  const ContentCard({
    super.key,
    required this.imageUrl,
    this.httpHeaders,
    this.badge,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final card = Container(
      decoration: BoxDecoration(
        borderRadius: AppRadius.borderRadiusMd,
        boxShadow: AppElevation.level2(colorScheme),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Image
          _buildImage(context, colorScheme),

          // Gradient overlay for better badge visibility
          if (badge != null)
            Positioned(
              top: 0,
              right: 0,
              child: Container(
                decoration: BoxDecoration(
                  gradient: AppGradients.serviceGlow(
                    colorScheme.shadow,
                    radius: 1.5,
                  ),
                ),
                padding: const EdgeInsets.all(AppSpacing.sm),
                child: badge!,
              ),
            ),
        ],
      ),
    );

    if (onTap == null) return card;

    return PressableScale(onTap: onTap, child: card);
  }

  Widget _buildImage(BuildContext context, ColorScheme colorScheme) {
    if (imageUrl == null || imageUrl!.isEmpty) {
      return _buildPlaceholder(colorScheme);
    }

    return CachedNetworkImage(
      imageUrl: imageUrl!,
      httpHeaders: httpHeaders,
      cacheManager: pinnedImageCacheFor(imageUrl),
      fit: BoxFit.cover,
      // The shared shimmer, not a local clone: it is the one that honours
      // Reduce Motion, and a poster grid is where an unstoppable sweep is
      // most visible.
      placeholder: (context, url) =>
          const ShimmerPlaceholder(height: double.infinity),
      errorWidget: (context, url, error) => _buildErrorPlaceholder(colorScheme),
    );
  }

  Widget _buildPlaceholder(ColorScheme colorScheme) {
    return Container(
      color: colorScheme.surfaceContainer,
      child: Icon(
        Icons.movie_outlined,
        color: colorScheme.onSurfaceVariant,
        size: 32,
      ),
    );
  }

  Widget _buildErrorPlaceholder(ColorScheme colorScheme) {
    return Container(
      color: colorScheme.surfaceContainerHighest,
      child: Icon(
        Icons.broken_image_outlined,
        color: colorScheme.onSurfaceVariant,
        size: 32,
      ),
    );
  }
}
