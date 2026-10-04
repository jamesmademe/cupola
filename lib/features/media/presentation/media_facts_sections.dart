import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/network/pinned_image_cache.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/string_utils.dart';
import 'package:cupola/core/widgets/artwork_decode.dart';
import 'package:cupola/features/discover/domain/models/discover_detail_model.dart';
import 'package:cupola/features/media/domain/media_facts.dart';
import 'package:cupola/features/media/presentation/media_parts.dart';
import 'package:cupola/features/settings/domain/regions.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';

/// The country a region code names, `Italy` for `IT`: what a heading says,
/// and what a screen reader would otherwise spell out letter by letter.
String regionName(String code) {
  final normalized = SettingsModel.normalizeRegion(code);
  return commonRegions[normalized] ?? normalized;
}

/// Where the title streams, and where it can be bought or rented, in the
/// region Settings names: one row each, the services by their logo and name.
/// Facts about the title, not controls: a row is read, never tapped.
class MediaWatchProviders extends StatelessWidget {
  const MediaWatchProviders({super.key, required this.providers});

  final WatchProviderRegion providers;

  @override
  Widget build(BuildContext context) {
    return MediaGroup(
      children: [
        if (providers.flatrate.isNotEmpty)
          _ProviderRow(label: 'Stream', entries: providers.flatrate),
        if (providers.buy.isNotEmpty)
          _ProviderRow(label: 'Buy or rent', entries: providers.buy),
      ],
    );
  }
}

class _ProviderRow extends StatelessWidget {
  const _ProviderRow({required this.label, required this.entries});

  final String label;
  final List<WatchProviderEntry> entries;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    final names = [for (final entry in entries) entry.name];
    return Semantics(
      container: true,
      // One sentence for the row: "Stream: Netflix, Prime Video".
      label: '$label: ${names.join(', ')}',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: AppType.row.copyWith(color: room.ink)),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.md,
              runSpacing: AppSpacing.sm,
              children: [
                for (final entry in entries)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _Logo(path: entry.logoPath),
                      const SizedBox(width: AppSpacing.xs),
                      Text(
                        entry.name,
                        style: AppType.meta.copyWith(color: room.inkSecondary),
                      ),
                    ],
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// A service's logo as TMDB keeps it, in a rounded square; its glyph when
/// TMDB has none.
class _Logo extends StatelessWidget {
  const _Logo({required this.path});

  final String? path;

  static const double _size = 20;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    final glyph = Icon(
      Icons.play_circle_outline_rounded,
      size: 16,
      color: room.inkTertiary,
    );
    final path = this.path;
    return SizedBox.square(
      dimension: _size,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(5),
        child: path == null || path.isEmpty
            ? glyph
            : ArtworkDecodeBox(
                box: const Size.square(_size),
                builder: (context, decode) => CachedNetworkImage(
                  imageUrl: 'https://image.tmdb.org/t/p/w92$path',
                  cacheManager: pinnedImageCacheFor(
                    'https://image.tmdb.org/t/p/w92$path',
                  ),
                  memCacheWidth: decode.width,
                  memCacheHeight: decode.height,
                  fit: BoxFit.cover,
                  errorWidget: (context, url, error) => glyph,
                ),
              ),
      ),
    );
  }
}

/// When the movie came out, or comes out: in cinemas, digitally, on disc,
/// each a row with its date.
class MediaReleaseDates extends StatelessWidget {
  const MediaReleaseDates({super.key, required this.releases});

  final MediaReleases releases;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    final rows = [
      ('In cinemas', releases.cinemas),
      ('Digital', releases.digital),
      ('Physical', releases.physical),
    ];
    return MediaGroup(
      children: [
        for (final (label, date) in rows)
          if (date != null)
            MediaValueRow(
              label: label,
              value: Text(
                // The page's one date voice: `Wed 26 Sep 2012`.
                formatShortDate(date),
                textAlign: TextAlign.end,
                style: AppType.meta.copyWith(color: room.inkSecondary),
              ),
            ),
      ],
    );
  }
}
