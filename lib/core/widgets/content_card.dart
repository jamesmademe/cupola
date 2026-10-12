import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:cupola/core/app_animation.dart';
import 'package:cupola/core/app_elevation.dart';
import 'package:cupola/core/app_gradients.dart';
import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/network/pinned_image_cache.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/side_pane_route.dart';
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

  /// The hero tag of the tile this poster belongs to: on a tablet, the poster
  /// whose title the pane shows wears a ring.
  final String? paneTag;

  /// The glyph on the plate when there is no artwork: what kind of thing the
  /// tile stands for. The film's clapper by default; a series, an album or a
  /// person passes its own, or it reads as a movie that lost its poster.
  final IconData fallbackIcon;

  const ContentCard({
    super.key,
    required this.imageUrl,
    this.httpHeaders,
    this.badge,
    this.onTap,
    this.paneTag,
    this.fallbackIcon = Icons.movie_outlined,
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
      // A poster glows with its light (brand book, `shadow.poster`; the lamp
      // until the light is derived). It cast the older `level2` shadow ink.
      decoration: BoxDecoration(
        borderRadius: AppRadius.borderRadiusMd,
        boxShadow: AppElevation.poster(colorScheme),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Image
          _buildImage(),

          // Shadow ink behind the badge, so it stays legible over bright
          // artwork. Painted across the whole card and fading to nothing
          // well inside it, never in a box the size of the badge: that box
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
            // Held to the card's width, at its top right: a badge whose
            // word is longer than the poster is wide wraps inside it rather
            // than running off the card's other edge.
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  child: badge!,
                ),
              ),
            ),
          ],
        ],
      ),
    );

    final tile = onTap == null
        ? card
        : PressableScale(onTap: onTap, child: card);
    if (paneTag == null) return tile;
    return _PaneRing(tag: paneTag, radius: AppRadius.md, child: tile);
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

  // The plate, not the theme: the same well as MediaPosterCard's fallback.
  // This rectangle stands in for artwork, and a grid tile is the source of the
  // Hero flight into a detail page whose poster is a MediaPosterCard: painted
  // `surfaceContainer` it was a white tile in light theme that turned into a
  // dark well mid-flight. See `AppColors.plateSurface`.
  Widget _buildPlaceholder() {
    return Container(
      color: AppColors.plateSurface,
      child: Icon(fallbackIcon, color: AppColors.plateDimInk, size: 32),
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

/// Rings the poster whose title a tablet's pane is showing.
///
/// A title opened beside the list leaves the list on screen, so the list
/// says which of its tiles is open: a ring in ink a hair outside the tile,
/// never over its artwork, and the tile scrolled into view when the list
/// reflowed into the phone's column under it. [tag] is the tile's hero tag,
/// unique on its screen and carried by the title's location, so the ring
/// marks the tile that was tapped and not every tile of the same title.
class _PaneRing extends StatefulWidget {
  const _PaneRing({
    required this.tag,
    required this.radius,
    required this.child,
  });

  /// The tile's hero tag, or null for a tile that opens no title.
  final String? tag;

  /// The tile's corner radius, which the ring follows.
  final double radius;

  final Widget child;

  @override
  State<_PaneRing> createState() => _PaneRingState();
}

class _PaneRingState extends State<_PaneRing> {
  bool _selected = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _read();
  }

  @override
  void didUpdateWidget(_PaneRing oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tag != widget.tag) _read();
  }

  void _read() {
    final selected =
        widget.tag != null &&
        SidePaneScope.selectedTagOf(context) == widget.tag;
    if (selected && !_selected) {
      // After the frame the list reflows in: the tile may have left the
      // viewport as the columns closed up.
      WidgetsBinding.instance.addPostFrameCallback((_) => _reveal());
    }
    _selected = selected;
  }

  /// Scrolls the tile into view if any of it is out of view.
  void _reveal() {
    if (!mounted) return;
    final tile = context.findRenderObject();
    final view = Scrollable.maybeOf(context)?.context.findRenderObject();
    if (tile is! RenderBox || view is! RenderBox || !tile.hasSize) return;
    final tileRect = tile.localToGlobal(Offset.zero) & tile.size;
    final viewRect = view.localToGlobal(Offset.zero) & view.size;
    if (viewRect.intersect(tileRect) == tileRect) return;
    Scrollable.ensureVisible(
      context,
      alignment: 0.5,
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : AppAnimation.standard,
      curve: AppAnimation.standardCurve,
    );
  }

  @override
  Widget build(BuildContext context) {
    // One shape selected or not, so the tile under it keeps its state.
    return CustomPaint(
      foregroundPainter: _selected
          ? _Ring(
              color: Theme.of(context).colorScheme.onSurface,
              radius: widget.radius,
            )
          : null,
      child: widget.child,
    );
  }
}

class _Ring extends CustomPainter {
  const _Ring({required this.color, required this.radius});

  final Color color;
  final double radius;

  /// How far outside the tile the ring's centre line runs.
  static const double _gap = 3.5;

  static const double _width = 2;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        (Offset.zero & size).inflate(_gap),
        Radius.circular(radius + _gap),
      ),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = _width
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_Ring oldDelegate) =>
      color != oldDelegate.color || radius != oldDelegate.radius;
}
