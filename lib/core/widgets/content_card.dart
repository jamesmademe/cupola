import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:cupola/core/app_elevation.dart';
import 'package:cupola/core/app_gradients.dart';
import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/network/pinned_image_cache.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/artwork_decode.dart';
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

  /// Reach of the badge's shadow radial, as a fraction of the card's shorter
  /// side (its width). Half the width is about the reach the old badge-sized
  /// box had on a phone grid tile, and below 1.0 the radial reaches zero before
  /// it meets any edge of the card, so it can never be cut off.
  static const double badgeGlowRadius = 0.5;

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
          _buildImage(),

          // Shadow ink behind the badge, so it stays legible over bright
          // artwork. Painted across the whole card and fading to nothing
          // well inside it — never in a box the size of the badge: that box
          // clipped the radial while it was still a third of its strength,
          // which drew a hard-edged grey rectangle around the badge wherever
          // the ground was not dark artwork (a placeholder, a light poster).
          if (badge != null) ...[
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  key: const ValueKey('content-card-badge-glow'),
                  decoration: BoxDecoration(
                    gradient: AppGradients.serviceGlow(
                      colorScheme.shadow,
                      radius: badgeGlowRadius,
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 0,
              right: 0,
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.sm),
                child: badge!,
              ),
            ),
          ],
        ],
      ),
    );

    if (onTap == null) return card;

    return PressableScale(onTap: onTap, child: card);
  }

  Widget _buildImage() {
    if (imageUrl == null || imageUrl!.isEmpty) {
      return _buildPlaceholder();
    }

    // Decoded at the size of the tile, not the server's: see
    // [ArtworkCacheSize]. The tile is the box the card fills, which is also
    // the Hero it flies from, so the detail poster's flight starts on the
    // picture already decoded here.
    return ArtworkDecodeBox(
      builder: (context, decode) => CachedNetworkImage(
        imageUrl: imageUrl!,
        httpHeaders: httpHeaders,
        cacheManager: pinnedImageCacheFor(imageUrl),
        memCacheWidth: decode.width,
        memCacheHeight: decode.height,
        fit: BoxFit.cover,
        // The shared shimmer, not a local clone: it is the one that honours
        // Reduce Motion, and a poster grid is where an unstoppable sweep is
        // most visible.
        placeholder: (context, url) =>
            const ShimmerPlaceholder(height: double.infinity),
        errorWidget: (context, url, error) => _buildErrorPlaceholder(),
      ),
    );
  }

  // The plate, not the theme — the same well as MediaPosterCard's fallback.
  // This rectangle stands in for artwork, and a grid tile is the source of the
  // Hero flight into a detail page whose poster is a MediaPosterCard: painted
  // `surfaceContainer` it was a white tile in light theme that turned into a
  // dark well mid-flight. See `AppColors.plateSurface`.
  Widget _buildPlaceholder() {
    return Container(
      color: AppColors.plateSurface,
      child: const Icon(
        Icons.movie_outlined,
        color: AppColors.plateDimInk,
        size: 32,
      ),
    );
  }

  Widget _buildErrorPlaceholder() {
    return Container(
      color: AppColors.plateSurface,
      child: const Icon(
        Icons.broken_image_outlined,
        color: AppColors.plateDimInk,
        size: 32,
      ),
    );
  }
}
