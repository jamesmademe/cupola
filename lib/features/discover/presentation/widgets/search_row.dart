import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/network/pinned_image_cache.dart';
import 'package:cupola/core/text_scale.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/artwork_decode.dart';
import 'package:cupola/core/widgets/media_poster_card.dart';
import 'package:cupola/core/widgets/pressable_scale.dart';
import 'package:cupola/core/widgets/status_badge.dart';

/// One row of a search by kind, and of the atrium's people: a
/// title with its poster, what it is and where it stands, or a person with
/// their face and what they are known for.
///
/// Flat on the page, no card: the section heading above groups the rows.
/// The row is one control that speaks one sentence; a title the operator may
/// add carries a second control at its end, the plus, which names what it
/// adds and where.
class SearchRow extends StatelessWidget {
  /// A movie or a series: [poster] (empty for none, drawn as the title's
  /// initials), [meta] (`Movie · 1996 · TMDB 8.0`), and where it stands,
  /// when there is something to say.
  const SearchRow.title({
    super.key,
    required this.title,
    required this.meta,
    this.status,
    String poster = '',
    this.posterHeaders,
    this.heroTag,
    required this.onTap,
    this.onAdd,
    this.addLabel,
    this.padding = EdgeInsets.zero,
  }) : imageUrl = poster,
       _person = false,
       assert(onAdd == null || addLabel != null, 'a plus names what it adds');

  /// A person: their [face] (empty for none, drawn as their initials) and
  /// one line under the name.
  const SearchRow.person({
    super.key,
    required String name,
    required String line,
    String face = '',
    required this.onTap,
    this.padding = EdgeInsets.zero,
  }) : title = name,
       meta = line,
       imageUrl = face,
       status = null,
       posterHeaders = null,
       heroTag = null,
       onAdd = null,
       addLabel = null,
       _person = true;

  final String title;
  final String meta;

  /// Where the title stands, as a dot in its tone and a word.
  final ({String label, StatusTone tone})? status;

  final String imageUrl;
  final Map<String, String>? posterHeaders;

  /// The poster flies into the title's page under this tag; null for none.
  final String? heroTag;

  final VoidCallback onTap;

  /// The plus: adds the title to its arr. Null where there is no add to
  /// honour, and then there is no plus at all.
  final VoidCallback? onAdd;

  /// What the plus says to a screen reader: `Add Cosmic Voyage to Radarr`.
  final String? addLabel;

  /// Around the row, beside the list's own gutter: none in a search, the
  /// slab's inset among the atrium's people.
  final EdgeInsetsGeometry padding;

  final bool _person;

  /// The row's floor: a 2:3 poster 66 tall and 8 above and below it.
  static const double minHeight = 76;

  static const Size _poster = Size(44, 66);
  static const double _face = 44;
  static const double _dot = 7;

  /// Up to two initials, for a title or a person with no picture.
  static String initialsOf(String name) => name
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .take(2)
      .map((part) => part.characters.first.toUpperCase())
      .join();

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final status = this.status;
    final spoken = [meta, ?status?.label].where((s) => s.isNotEmpty).join(', ');

    final row = PressableScale(
      onTap: onTap,
      semanticLabel: title,
      semanticValue: spoken,
      excludeChildSemantics: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: minHeight),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          child: Row(
            children: [
              _person ? _faceOf(room) : _posterOf(room),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.row.copyWith(color: room.ink),
                    ),
                    if (meta.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        meta,
                        maxLines: _person ? 2 : 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppType.meta.copyWith(color: room.inkSecondary),
                      ),
                    ],
                    if (status != null) ...[
                      const SizedBox(height: AppSpacing.xxs),
                      Row(
                        children: [
                          Container(
                            width: _dot,
                            height: _dot,
                            decoration: BoxDecoration(
                              color: statusToneColor(colorScheme, status.tone),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.s),
                          Flexible(
                            child: Text(
                              status.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppType.caption
                                  .weight(FontWeight.w600)
                                  .copyWith(color: room.inkSecondary),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              if (_person) ...[
                const SizedBox(width: AppSpacing.sm),
                Icon(Icons.chevron_right_rounded, color: room.inkSecondary),
              ],
            ],
          ),
        ),
      ),
    );

    final onAdd = this.onAdd;
    return Padding(
      padding: padding,
      child: onAdd == null
          ? row
          : Row(
              children: [
                Expanded(child: row),
                const SizedBox(width: AppSpacing.sm),
                _AddButton(onTap: onAdd, label: addLabel!),
              ],
            ),
    );
  }

  Widget _posterOf(CupolaRoom room) {
    final plate = Container(
      width: _poster.width,
      height: _poster.height,
      clipBehavior: Clip.antiAlias,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: room.fillQuiet,
        borderRadius: BorderRadius.circular(AppRadius.thumb),
        border: imageUrl.isEmpty ? Border.all(color: room.hair) : null,
      ),
      child: imageUrl.isEmpty
          ? _initials(room)
          : ArtworkDecodeBox(
              box: _poster,
              builder: (context, decode) => CachedNetworkImage(
                imageUrl: imageUrl,
                httpHeaders: posterHeaders,
                cacheManager: pinnedImageCacheFor(imageUrl),
                memCacheWidth: decode.width,
                memCacheHeight: decode.height,
                width: _poster.width,
                height: _poster.height,
                fit: BoxFit.cover,
                errorWidget: (_, _, _) => _initials(room),
              ),
            ),
    );
    final tag = heroTag;
    if (tag == null || imageUrl.isEmpty) return plate;
    return Hero(
      tag: tag,
      transitionOnUserGestures: MediaPosterCard.flightOnUserGestures,
      child: plate,
    );
  }

  Widget _faceOf(CupolaRoom room) => Container(
    width: _face,
    height: _face,
    clipBehavior: Clip.antiAlias,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: room.fillQuiet,
      shape: BoxShape.circle,
      border: Border.all(color: room.hair),
    ),
    child: imageUrl.isEmpty
        ? _initials(room)
        : ArtworkDecodeBox(
            box: const Size.square(_face),
            builder: (context, decode) => CachedNetworkImage(
              imageUrl: imageUrl,
              cacheManager: pinnedImageCacheFor(imageUrl),
              memCacheWidth: decode.width,
              memCacheHeight: decode.height,
              width: _face,
              height: _face,
              fit: BoxFit.cover,
              errorWidget: (_, _, _) => _initials(room),
            ),
          ),
  );

  /// The initials stop at the compact tiles' ceiling: past it two letters
  /// fill a 44pt plate edge to edge.
  Widget _initials(CupolaRoom room) => Builder(
    builder: (context) => Text(
      initialsOf(title),
      textScaler: TextScaleMetrics.clampedScalerOf(context),
      style: AppType.label.copyWith(color: room.ink),
    ),
  );
}

/// The plus at a row's end: a 44 disc in the room's quiet fill.
class _AddButton extends StatelessWidget {
  const _AddButton({required this.onTap, required this.label});

  final VoidCallback onTap;
  final String label;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    return PressableScale(
      onTap: onTap,
      semanticLabel: label,
      excludeChildSemantics: true,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: room.fillQuiet,
          shape: BoxShape.circle,
          border: Border.all(color: room.hair),
        ),
        child: Icon(Icons.add_rounded, size: 20, color: room.ink),
      ),
    );
  }
}
