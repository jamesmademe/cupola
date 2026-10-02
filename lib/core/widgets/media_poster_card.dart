import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'package:cupola/core/app_elevation.dart';
import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/network/pinned_image_cache.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/artwork_decode.dart';

/// A reusable poster card for media detail screens.
///
/// Consolidates the previously duplicated poster card widgets
/// (`_MoviePosterCard`, `_SeriesPosterCard`, `_MusicPosterCard`,
/// `_DiscoverPosterCard`) into a single shared component.
///
/// The card fills its parent constraints — wrap in a [SizedBox] to
/// control dimensions externally (e.g. from [MediaDetailPosterRow]).
class MediaPosterCard extends StatelessWidget {
  final String heroTag;
  final String? imageUrl;
  final Map<String, String>? imageHeaders;
  final IconData fallbackIcon;
  final BorderRadius? borderRadius;

  /// Private because the public name is taken by the [MediaPosterCard.circular]
  /// constructor — the same shape `MediaChildTile._stacked` uses.
  final bool _circular;

  /// The rectangular poster: rounded corners on [borderRadius].
  const MediaPosterCard({
    super.key,
    required this.heroTag,
    this.imageUrl,
    this.imageHeaders,
    this.fallbackIcon = Icons.movie_outlined,
    this.borderRadius,
  }) : _circular = false;

  /// The circular artist/person treatment.
  ///
  /// Takes no [borderRadius]: a [ClipOval] has no corners to round, so the
  /// rectangular constructor's parameter would be silently discarded here.
  const MediaPosterCard.circular({
    super.key,
    required this.heroTag,
    this.imageUrl,
    this.imageHeaders,
    this.fallbackIcon = Icons.movie_outlined,
  }) : borderRadius = null,
       _circular = true;

  /// Whether poster Heroes also fly during the interactive swipe-back
  /// gesture (iOS Photos behaviour). Shared by every Hero source that flies
  /// into a detail page, so the whole flight family toggles in one place —
  /// flip to false if the interactive flight proves flaky on device.
  static const bool flightOnUserGestures = true;

  static const _fallbackIconSize = 48.0;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final hasImage = imageUrl != null && imageUrl!.isNotEmpty;
    final effectiveBorderRadius = borderRadius ?? AppRadius.borderRadiusMd;
    // The plate, not the theme. This rectangle stands in for artwork, and
    // artwork is not palette — a missing poster painted `surfaceContainer`
    // renders as a white hole in a light-theme grid, and then flips to a dark
    // photograph the moment the real image lands. Pinned to the plate tokens it
    // is the same well in both themes and the arriving image replaces like with
    // like. See `AppColors.plateSurface`.
    Widget fallback() => Container(
      color: AppColors.plateSurface,
      child: Center(
        child: Icon(
          fallbackIcon,
          size: _fallbackIconSize,
          color: AppColors.plateDimInk,
        ),
      ),
    );

    // Decoded at the size of the box it fills ([ArtworkCacheSize]), or of
    // [decodeBox] when the box is a flight's and keeps changing.
    Widget image({Size? decodeBox}) => hasImage
        ? ArtworkDecodeBox(
            box: decodeBox,
            builder: (context, decode) => CachedNetworkImage(
              imageUrl: imageUrl!,
              httpHeaders: imageHeaders,
              cacheManager: pinnedImageCacheFor(imageUrl),
              memCacheWidth: decode.width,
              memCacheHeight: decode.height,
              fit: BoxFit.cover,
              // No cross-fade: keeps the Hero flight crisp when the poster is
              // already cached from the source grid/carousel.
              fadeInDuration: Duration.zero,
              fadeOutDuration: Duration.zero,
              placeholderFadeInDuration: Duration.zero,
              errorWidget: (context, url, error) => fallback(),
            ),
          )
        : fallback();
    Widget clippedImage({Size? decodeBox}) => _circular
        ? ClipOval(child: image(decodeBox: decodeBox))
        : ClipRRect(
            borderRadius: effectiveBorderRadius,
            child: image(decodeBox: decodeBox),
          );

    Widget content(List<BoxShadow> shadow, {Size? decodeBox}) {
      Widget child = DecoratedBox(
        decoration: BoxDecoration(
          shape: _circular ? BoxShape.circle : BoxShape.rectangle,
          borderRadius: _circular ? null : effectiveBorderRadius,
          boxShadow: shadow,
        ),
        child: clippedImage(decodeBox: decodeBox),
      );
      if (hasImage) {
        child = Stack(
          fit: StackFit.expand,
          children: [
            child,
            Opacity(opacity: 0, child: fallback()),
          ],
        );
      }
      return child;
    }

    // Match ContentCard's resting elevation so the shared-element flight
    // doesn't "pop" a different shadow mid-transition.
    final heroChild = content(AppElevation.level2(colorScheme));

    return Hero(
      tag: heroTag,
      transitionOnUserGestures: flightOnUserGestures,
      flightShuttleBuilder:
          (flightContext, animation, direction, fromContext, toContext) {
            // The picture is decoded at the size it is drawn at, so the hero
            // a flight leaves and the one it lands on hold two decodes of it.
            // The shuttle draws the one already on screen, at the size of the
            // hero it leaves, so it never waits on a decode; the one it lands
            // on is decoded while it flies, so the landing does not either.
            final fromBox = _laidOutSize(fromContext);
            _decodeAhead(flightContext, _laidOutSize(toContext));
            if (MediaQuery.disableAnimationsOf(flightContext)) {
              return Material(
                type: MaterialType.transparency,
                child: content(
                  AppElevation.level2(colorScheme),
                  decodeBox: fromBox,
                ),
              );
            }
            // "Pick up / set down": the shadow deepens to level3 mid-flight
            // and settles back to level2, so the poster reads as physically
            // lifted off one surface and placed on the other. Symmetric, so
            // push and pop flights both work.
            return AnimatedBuilder(
              animation: animation,
              builder: (context, _) {
                final lift = 1 - (2 * animation.value - 1).abs();
                final scheme = Theme.of(flightContext).colorScheme;
                final shadow = BoxShadow.lerpList(
                  AppElevation.level2(scheme),
                  AppElevation.level3(scheme),
                  Curves.easeOut.transform(lift),
                )!;
                return Material(
                  type: MaterialType.transparency,
                  child: content(shadow, decodeBox: fromBox),
                );
              },
            );
          },
      child: Material(type: MaterialType.transparency, child: heroChild),
    );
  }

  /// The size [context]'s hero was laid out at, or null before it was.
  static Size? _laidOutSize(BuildContext context) {
    final box = context.findRenderObject();
    return box is RenderBox && box.hasSize ? box.size : null;
  }

  /// Starts decoding this card's picture for [box], so a hero that lands on
  /// it finds it ready. A picture that does not load is the landing card's
  /// to say so, in its fallback; nothing is reported here.
  void _decodeAhead(BuildContext context, Size? box) {
    final url = imageUrl;
    if (box == null || url == null || url.isEmpty) return;
    final decode = artworkCacheSize(
      box,
      MediaQuery.devicePixelRatioOf(context),
    );
    precacheImage(
      decode.resize(
        CachedNetworkImageProvider(
          url,
          headers: imageHeaders,
          cacheManager: pinnedImageCacheFor(url),
        ),
      ),
      context,
      onError: (_, _) {},
    );
  }
}
