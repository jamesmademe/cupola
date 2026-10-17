import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:cupola/core/app_breakpoints.dart';
import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/status/lexicon.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/image_utils.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/discover/domain/collection_shelf.dart';
import 'package:cupola/features/media/presentation/shelf_page.dart';

/// How much of a collection is on the server: the headline, the strip of
/// its movies with where each stands, and the count of each kind. On the
/// collection's page under its still; in the atrium, the invitation to
/// complete it.
class CollectionTally extends StatelessWidget {
  /// The collection's own page: the headline is how much is on the server.
  const CollectionTally({super.key, required this.shelf})
    : name = null,
      onTap = null;

  /// The atrium's invitation: "Complete the collection" over the name and
  /// how much is on the server, the whole slab one button to the page.
  const CollectionTally.invitation({
    super.key,
    required this.shelf,
    required String this.name,
    required VoidCallback this.onTap,
  });

  final CollectionShelf shelf;

  /// The collection's name, on the invitation.
  final String? name;

  final VoidCallback? onTap;

  static const String invitationTitle = 'Complete the collection';

  /// The widest the strip is drawn beside the words: as the widest phone
  /// draws it ([AppBreakpoints.splitList], less the atrium's margins and the
  /// slab's padding). Its covers stop at 44 wide, so eight of them never need
  /// more; past ten movies the bars alone fill it.
  static const double stripMeasure =
      AppBreakpoints.splitList - 4 * AppSpacing.lg;

  /// The width inside the slab from which the strip goes beside the words:
  /// where the words keep at least the strip's own measure. A tablet on its
  /// side or a desktop window draws one that wide in the atrium; no phone,
  /// no tablet's list beside a title and no collection's page does.
  static const double besideFrom = 2 * stripMeasure + AppSpacing.xl;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    final scheme = Theme.of(context).colorScheme;
    final total = shelf.parts.length;
    final held = shelf.count(CollectionPartStand.onServer);
    final onTheWay = shelf.count(CollectionPartStand.onTheWay);
    final waiting = shelf.count(CollectionPartStand.waiting);
    final headline = held == total && total > 1
        ? 'All $total on your server'
        : '$held of $total on your server';
    Color tone(StatusTone t) =>
        statusToneColor(scheme, t, surface: room.fillQuiet);
    final coming = [
      if (onTheWay > 0) ('$onTheWay on the way', tone(StatusTone.info), false),
      if (waiting > 0)
        (
          '$waiting ${StateWord.waitingForApproval.label.toLowerCase()}',
          tone(StatusTone.info),
          true,
        ),
    ];
    final legend = [
      if (held > 0) ('$held on your server', tone(StatusTone.success), false),
      ...coming,
    ];
    final invitation = name;
    final sentence = [
      if (invitation != null) ...[invitationTitle, invitation],
      headline,
      for (final (words, _, _) in coming) words,
    ].join(', ');
    final heading = <Widget>[
      if (invitation == null)
        Text(headline, style: AppType.section.copyWith(color: room.ink))
      else ...[
        // The chevron is the slab's way in, as on a shelf's header.
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Flexible(
              child: Text(
                invitationTitle,
                style: AppType.section.copyWith(color: room.ink),
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: scheme.primary),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          '$invitation\u00A0· $headline',
          style: AppType.label
              .weight(FontWeight.w400)
              .copyWith(color: room.inkSecondary),
        ),
      ],
    ];
    final legendLine = legend.isEmpty
        ? null
        : Wrap(
            spacing: AppSpacing.lg,
            runSpacing: AppSpacing.xs,
            children: [
              for (final (words, color, hollow) in legend)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: hollow ? null : color,
                        border: hollow
                            ? Border.all(color: color, width: 1.2)
                            : null,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Text(
                      words,
                      style: AppType.label
                          .weight(FontWeight.w400)
                          .copyWith(color: room.inkSecondary),
                    ),
                  ],
                ),
            ],
          );
    final slab = Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: room.fillQuiet,
        borderRadius: BorderRadius.circular(AppRadius.door),
        border: Border.all(color: room.hair),
      ),
      // The phone's slab: the words, the strip under them, the legend under
      // that. Where the words keep at least the strip's own measure beside
      // it, the strip goes beside them instead, at the end of the slab.
      child: LayoutBuilder(
        builder: (context, box) {
          if (box.maxWidth >= besideFrom) {
            return Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ...heading,
                      if (legendLine != null) ...[
                        const SizedBox(height: AppSpacing.md),
                        legendLine,
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.xl),
                SizedBox(
                  width: _Strip.widthOf(shelf.parts.length),
                  child: _Strip(shelf: shelf),
                ),
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ...heading,
              const SizedBox(height: AppSpacing.md),
              _Strip(shelf: shelf),
              if (legendLine != null) ...[
                const SizedBox(height: AppSpacing.md),
                legendLine,
              ],
            ],
          );
        },
      ),
    );
    final tap = onTap;
    if (tap == null) {
      return Semantics(
        container: true,
        label: sentence,
        excludeSemantics: true,
        child: slab,
      );
    }
    return PressableScale(
      onTap: tap,
      semanticLabel: sentence,
      excludeChildSemantics: true,
      child: slab,
    );
  }
}

/// The collection's movies side by side, each over a bar in the tone of
/// where it stands: filled on the server or on its way, a ring of a bar
/// while it waits for approval, the hairline where it is neither. Past
/// [_postersUpTo] movies the covers would be too small to read and the bars
/// stand alone.
class _Strip extends StatelessWidget {
  const _Strip({required this.shelf});

  final CollectionShelf shelf;

  static const int _postersUpTo = 10;
  static const double _gap = AppSpacing.s;
  static const double _bar = 3;
  static const double _maxPoster = 44;

  /// The strip's own width beside the words: its covers at their widest,
  /// up to [CollectionTally.stripMeasure]; bars alone take the whole of it.
  static double widthOf(int parts) {
    if (parts == 0 || parts > _postersUpTo) {
      return CollectionTally.stripMeasure;
    }
    return math.min(
      CollectionTally.stripMeasure,
      parts * _maxPoster + (parts - 1) * _gap,
    );
  }

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    final scheme = Theme.of(context).colorScheme;
    final parts = shelf.parts;
    final posters = parts.length <= _postersUpTo;
    return LayoutBuilder(
      builder: (context, box) {
        final fit = (box.maxWidth - _gap * (parts.length - 1)) / parts.length;
        final width = posters ? math.min(fit, _maxPoster) : fit;
        return Row(
          children: [
            for (final (index, part) in parts.indexed) ...[
              if (index > 0) const SizedBox(width: _gap),
              SizedBox(
                width: width,
                child: Column(
                  children: [
                    if (posters) ...[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(AppRadius.thumb),
                        child: SizedBox(
                          width: width,
                          height: width * 1.5,
                          child: ShelfArtwork(
                            art: switch (ImageUtils.buildTmdbPosterUrl(
                              part.media.posterPath,
                              size: 'w92',
                            )) {
                              '' => null,
                              final url => (url: url, headers: null),
                            },
                            box: Size(width, width * 1.5),
                            fallback: ColoredBox(color: room.raised),
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                    ],
                    _barOf(part.stand, room: room, scheme: scheme),
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _barOf(
    CollectionPartStand stand, {
    required CupolaRoom room,
    required ColorScheme scheme,
  }) {
    Color tone(StatusTone t) =>
        statusToneColor(scheme, t, surface: room.fillQuiet);
    final (color, hollow) = switch (stand) {
      CollectionPartStand.onServer => (tone(StatusTone.success), false),
      CollectionPartStand.onTheWay => (tone(StatusTone.info), false),
      CollectionPartStand.waiting => (tone(StatusTone.info), true),
      CollectionPartStand.missing => (room.hair, false),
    };
    return Container(
      height: _bar,
      decoration: BoxDecoration(
        color: hollow ? null : color,
        borderRadius: BorderRadius.circular(_bar),
        border: hollow ? Border.all(color: color, width: 1) : null,
      ),
    );
  }
}
