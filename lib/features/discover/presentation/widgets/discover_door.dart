import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/network/pinned_image_cache.dart';
import 'package:cupola/core/text_scale.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/artwork_decode.dart';
import 'package:cupola/core/widgets/pressable_scale.dart';

/// A way into the catalogue: one of the atrium's six doors, or a tile of an
/// index (a genre, a network, a studio, a mood, a language, a decade).
///
/// Lit by artwork when there is some: a poster decoded a couple of dozen
/// pixels wide and laid over the whole door, which is a blur that costs
/// nothing to draw, with one or two posters leaning out of its corner. A door
/// with no artwork is the room's door fill, and its name carries it. The
/// door grows with the reading size up to the compact ceiling; it never
/// clips its words.
class DiscoverDoor extends StatelessWidget {
  /// One of the atrium's six: the name and a line under it, with posters,
  /// names or nothing in the corner.
  const DiscoverDoor.lobby({
    super.key,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.lightUrl,
    this.posterUrls = const [],
    this.names = const [],
  }) : _index = false;

  /// A tile of an index: the name alone, in the display face, at the foot
  /// of a lit tile or at the head of a plain one.
  const DiscoverDoor.index({
    super.key,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.lightUrl,
    this.posterUrls = const [],
  }) : names = const [],
       _index = true;

  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  /// The artwork the door is lit by, decoded tiny.
  final String? lightUrl;

  /// Up to two posters leaning out of the corner.
  final List<String> posterUrls;

  /// A few names stacked in the corner, fading: the networks a door leads
  /// to.
  final List<String> names;

  final bool _index;

  /// The reading size past which a door drops its corner (the posters, the
  /// names) and the atrium lays its doors two to a row.
  static const double largeTextScale = 1.3;

  /// The lit door's height at the reading size the user chose (to the
  /// compact ceiling).
  static const double _litHeight = 104;

  /// A plain index tile's.
  static const double _plainHeight = 92;

  static const double _posterWidth = 38;

  /// How far the light's picture is blurred, in logical pixels.
  static const double _blur = 18;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    final scaler = TextScaleMetrics.clampedScalerOf(context);
    final lit = lightUrl != null;
    final minHeight = lit || !_index ? _litHeight : _plainHeight;
    // At a large reading size the words take the door: the posters and the
    // stacked names are decoration, and they would sit on the name.
    final decorated = scaler.scale(1) <= largeTextScale;

    final words = MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: scaler),
      child: _words(context),
    );

    return PressableScale(
      onTap: onTap,
      semanticLabel: subtitle == null ? title : '$title, $subtitle',
      excludeChildSemantics: true,
      child: Container(
        constraints: BoxConstraints(minHeight: minHeight),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: room.door,
          borderRadius: BorderRadius.circular(AppRadius.door),
          border: Border.all(color: room.hair),
        ),
        child: Stack(
          // A lit tile of an index sets its name at the foot, under the
          // leaning poster; everything else at the head, where the eye
          // starts. The words are the one child in the flow, so the door is
          // as tall as they need and never less than [minHeight].
          alignment: lit && _index
              ? AlignmentDirectional.bottomStart
              : AlignmentDirectional.topStart,
          children: [
            if (lit)
              Positioned.fill(
                child: Opacity(
                  opacity: _index ? 0.6 : 0.55,
                  // Decoded at the smallest rung on purpose and blurred:
                  // the light of the picture, not the picture.
                  child: ImageFiltered(
                    imageFilter: ui.ImageFilter.blur(
                      sigmaX: _blur,
                      sigmaY: _blur,
                      tileMode: TileMode.clamp,
                    ),
                    child: ArtworkDecodeBox(
                      box: const Size.square(1),
                      builder: (context, decode) => CachedNetworkImage(
                        imageUrl: lightUrl!,
                        cacheManager: pinnedImageCacheFor(lightUrl),
                        memCacheWidth: decode.width,
                        memCacheHeight: decode.height,
                        fit: BoxFit.cover,
                        fadeInDuration: Duration.zero,
                        errorWidget: (_, _, _) => const SizedBox.shrink(),
                      ),
                    ),
                  ),
                ),
              ),
            // A light picture under a name in ink: the foot of a lit index
            // tile darkens toward the door's own fill, so the name reads on
            // any backdrop.
            if (lit && _index)
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        room.door.withValues(alpha: 0),
                        room.door.withValues(alpha: 0.72),
                      ],
                      stops: const [0.35, 1],
                    ),
                  ),
                ),
              ),
            if (decorated) ..._corner(context),
            Padding(
              padding: EdgeInsets.fromLTRB(
                AppSpacing.md,
                // Room above a lit tile's name for the poster leaning in.
                lit && _index ? AppSpacing.xxl : AppSpacing.md,
                AppSpacing.md,
                AppSpacing.md,
              ),
              child: words,
            ),
          ],
        ),
      ),
    );
  }

  Widget _words(BuildContext context) {
    final dim = CupolaThemeColors.of(context).dimText;
    final ink = CupolaRoom.of(context).ink;
    if (_index) {
      final name = Text(
        title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: AppType.section.copyWith(color: ink),
      );
      final line = subtitle == null
          ? null
          : Text(
              subtitle!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppType.caption.copyWith(color: dim),
            );
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [name, ?line],
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppType.row.copyWith(color: ink),
        ),
        if (subtitle != null)
          Text(
            subtitle!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppType.caption.copyWith(color: dim),
          ),
      ],
    );
  }

  List<Widget> _corner(BuildContext context) {
    final room = CupolaRoom.of(context);
    if (names.isNotEmpty) {
      return [
        Positioned(
          right: AppSpacing.md,
          bottom: AppSpacing.sm,
          child: ExcludeSemantics(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < names.length && i < 3; i++)
                  Opacity(
                    opacity: 1 - i * 0.28,
                    child: Text(
                      names[i],
                      maxLines: 1,
                      style: AppType.label.copyWith(color: room.inkSecondary),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ];
    }
    if (posterUrls.isEmpty) return const [];
    if (_index) {
      return [
        Positioned(
          right: AppSpacing.md,
          top: -AppSpacing.md,
          child: _LeaningPoster(url: posterUrls.first, turns: 8),
        ),
      ];
    }
    return [
      if (posterUrls.length > 1)
        Positioned(
          right: 30,
          bottom: -AppSpacing.md,
          child: _LeaningPoster(url: posterUrls[1], turns: -8),
        ),
      Positioned(
        right: AppSpacing.sm,
        bottom: -AppSpacing.sm,
        child: _LeaningPoster(url: posterUrls.first, turns: 6),
      ),
    ];
  }
}

/// A small poster leaning out of a door's corner, [turns] degrees off true.
class _LeaningPoster extends StatelessWidget {
  const _LeaningPoster({required this.url, required this.turns});

  final String url;
  final double turns;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Transform.rotate(
      angle: turns * math.pi / 180,
      child: Container(
        width: DiscoverDoor._posterWidth,
        height: DiscoverDoor._posterWidth * 3 / 2,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.thumb),
          color: AppColors.plateSurface,
          boxShadow: [
            BoxShadow(
              color: colorScheme.shadow.withValues(alpha: 0.6),
              blurRadius: 16,
              offset: const Offset(0, 8),
              spreadRadius: -6,
            ),
          ],
        ),
        child: ArtworkDecodeBox(
          box: const Size(
            DiscoverDoor._posterWidth,
            DiscoverDoor._posterWidth * 3 / 2,
          ),
          builder: (context, decode) => CachedNetworkImage(
            imageUrl: url,
            cacheManager: pinnedImageCacheFor(url),
            memCacheWidth: decode.width,
            memCacheHeight: decode.height,
            fit: BoxFit.cover,
            errorWidget: (_, _, _) => const SizedBox.shrink(),
          ),
        ),
      ),
    );
  }
}
