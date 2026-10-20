import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'package:cupola/core/app_breakpoints.dart';
import 'package:cupola/core/app_elevation.dart';
import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/generated/design_tokens.g.dart';
import 'package:cupola/core/network/pinned_image_cache.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/room_art.dart';
import 'package:cupola/core/title_light.dart';
import 'package:cupola/core/widgets/artwork_decode.dart';
import 'package:cupola/core/widgets/floating_bottom_nav_bar.dart';
import 'package:cupola/core/widgets/media_poster_card.dart';
import 'package:cupola/core/widgets/pressable_scale.dart';
import 'package:cupola/core/widgets/shimmer_placeholder.dart';
import 'package:cupola/core/widgets/status_badge.dart';
import 'package:cupola/features/media/presentation/media_parts.dart';

/// A picture on a shelf page, and what its request carries: an arr's own
/// artwork needs its key.
typedef ShelfArt = ({String url, Map<String, String>? headers});

/// Where a work stands, as its row's state line says it: the word, its
/// tone, and whether it is the backlog's ring rather than a dot.
typedef ShelfState = ({String word, StatusTone tone, bool hollow});

/// How many of a shelf's works are on the server, of how many: the dots
/// beside the summary, one per work.
typedef ShelfTally = ({int held, int of});

/// A page about someone and their shelf: an artist and the albums, an author
/// and the books. The Media page's room without its slab: the person's
/// photo or initials, their name, what the shelf holds in one line, then the
/// sections the caller gives as slivers.
///
/// The room is lit by [light], a picture of the shelf's. The page is one
/// column, centred in a wider window and never wider than
/// [AppBreakpoints.readingWell].
class ShelfPage extends StatelessWidget {
  const ShelfPage({
    super.key,
    required this.name,
    required this.summary,
    required this.slivers,
    this.photo,
    this.role,
    this.tally,
    this.light,
    this.art,
    this.heroTag,
    this.onArtDrawn,
    this.moreLabel,
    this.onMore,
    this.onRefresh,
  }) : banner = null,
       _bannered = false;

  /// A shelf that is a set of works rather than someone's: a collection. Its
  /// [banner], a wide still, heads the page in the disc's place, the name and
  /// summary under it.
  const ShelfPage.banner({
    super.key,
    required this.name,
    required this.summary,
    required this.slivers,
    required this.banner,
    this.light,
    this.art,
    this.heroTag,
    this.onArtDrawn,
    this.onRefresh,
  }) : photo = null,
       role = null,
       tally = null,
       moreLabel = null,
       onMore = null,
       _bannered = true;

  final String name;

  /// What the person does, under their name: `Director`.
  final String? role;

  /// The dots beside [summary], when the shelf is short enough to count
  /// them out.
  final ShelfTally? tally;

  /// The still that heads a [ShelfPage.banner].
  final ShelfArt? banner;

  /// Told once the photo or the banner is drawn, with its address: the room
  /// is lit from a picture the page has drawn.
  final ValueChanged<String>? onArtDrawn;

  final bool _bannered;

  /// What the shelf holds: `3 albums on disk · 1 announced`. Empty while it
  /// is being read.
  final String summary;

  /// The person's photo; their initials without one.
  final ShelfArt? photo;

  final TitleLight? light;

  /// The picture of [light], laid over the top of the room once read.
  final RoomArt? art;

  /// The tag of the tile the page was opened from: its picture flies to the
  /// disc.
  final String? heroTag;

  /// The page's other actions, behind the plate at the top right, and what
  /// that plate says to a screen reader. [onMore] is handed the plate, so a
  /// wide window can open the actions as a menu under it.
  final String? moreLabel;
  final void Function(BuildContext plate)? onMore;

  /// A pull reads the page again.
  final Future<void> Function()? onRefresh;

  /// The sections under the name.
  final List<Widget> slivers;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    final page = LayoutBuilder(
      builder: (context, box) {
        final column = (box.maxWidth - 2 * AppSpacing.lg).clamp(
          0.0,
          AppBreakpoints.readingWell,
        );
        final gutter = (box.maxWidth - column) / 2;
        final scroll = CustomScrollView(
          physics: onRefresh == null
              ? null
              : const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                gutter,
                top + AppSpacing.md,
                gutter,
                // Clear of the floating bar, which grows with the reading
                // size; where there is none, a margin.
                math.max(
                  AppSpacing.xxxl,
                  FloatingNavBarMetrics.getScrollViewBottomPadding(context),
                ),
              ),
              sliver: SliverMainAxisGroup(
                slivers: [
                  // Back and More float here, pinned (`MediaPinnedPlates`).
                  const SliverToBoxAdapter(
                    child: SizedBox(height: MediaPinnedPlates.reserve),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.md),
                      child: _bannered
                          ? ShelfBanner(
                              name: name,
                              summary: summary,
                              banner: banner,
                              light: light,
                              heroTag: heroTag,
                              onDrawn: onArtDrawn,
                            )
                          : ShelfIdentity(
                              name: name,
                              summary: summary,
                              photo: photo,
                              role: role,
                              tally: tally,
                              light: light,
                              heroTag: heroTag,
                              onDrawn: onArtDrawn,
                            ),
                    ),
                  ),
                  ...slivers,
                ],
              ),
            ),
          ],
        );
        return MediaPinnedPlates(
          inset: gutter,
          trailing: switch (onMore) {
            final onMore? => Builder(
              builder: (plate) => MediaPlate(
                label: moreLabel ?? 'More actions',
                icon: Icons.more_horiz_rounded,
                onTap: () => onMore(plate),
              ),
            ),
            null => null,
          },
          child: onRefresh == null
              ? scroll
              : RefreshIndicator(
                  edgeOffset: top,
                  onRefresh: onRefresh!,
                  child: scroll,
                ),
        );
      },
    );
    // The room a title's page stands in, so a shelf and a title read as one
    // kind of page: lit by the shelf's picture, the clock legible over what
    // scrolls under it, and in a tablet's pane coming up from the list's side.
    return MediaRoom(light: light, art: art, child: page);
  }
}

/// The person: a 92 disc with their photo, or their initials on the room's
/// light, beside their name and what the shelf holds. At a large reading
/// size the name goes under the disc.
class ShelfIdentity extends StatelessWidget {
  const ShelfIdentity({
    super.key,
    required this.name,
    required this.summary,
    this.photo,
    this.role,
    this.tally,
    this.light,
    this.heroTag,
    this.onDrawn,
  });

  final String name;
  final String summary;
  final ShelfArt? photo;

  /// What the person does, under the name: `Director`.
  final String? role;

  /// One dot per work beside [summary], filled for each on the server; drawn
  /// only up to [ShelfTally.of] of eight, past which dots stop being
  /// countable at a glance.
  final ShelfTally? tally;
  final TitleLight? light;
  final String? heroTag;
  final ValueChanged<String>? onDrawn;

  static const double _disc = 92;

  /// The most works the dots count out.
  static const int maxDots = 8;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    final light = this.light?.light;
    final initials = shelfInitials(name);
    final stacked = mediaStacked(context);
    Widget disc = Container(
      width: _disc,
      height: _disc,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: light?.withValues(alpha: 0.18) ?? room.fillControl,
        border: Border.all(color: light?.withValues(alpha: 0.4) ?? room.edge),
      ),
      clipBehavior: Clip.antiAlias,
      child: ExcludeSemantics(
        child: ShelfArtwork(
          art: photo,
          box: const Size.square(_disc),
          onDrawn: onDrawn,
          fallback: Text(
            initials,
            style: AppType.feature.copyWith(color: room.ink),
          ),
        ),
      ),
    );
    if (heroTag case final tag?) {
      disc = Hero(
        tag: tag,
        transitionOnUserGestures: MediaPosterCard.flightOnUserGestures,
        child: disc,
      );
    }
    final words = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          header: true,
          child: Text(
            name,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            // At a large reading size the room's title role: the screen's
            // broke a long name in the middle of a word.
            style: (stacked ? AppType.room : AppType.screen).copyWith(
              color: room.ink,
            ),
          ),
        ),
        if (role case final role? when role.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            role,
            style: AppType.label
                .weight(FontWeight.w400)
                .copyWith(color: room.inkSecondary),
          ),
        ],
        if (summary.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              if (tally case final tally?
                  when tally.of > 0 && tally.of <= maxDots) ...[
                ExcludeSemantics(child: _TallyDots(tally: tally)),
                const SizedBox(width: AppSpacing.sm),
              ],
              Flexible(
                child: Text(
                  summary,
                  style: AppType.label
                      .weight(FontWeight.w400)
                      .copyWith(color: room.inkSecondary),
                ),
              ),
            ],
          ),
        ],
      ],
    );
    if (stacked) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          disc,
          const SizedBox(height: AppSpacing.md),
          words,
        ],
      );
    }
    return Row(
      children: [
        disc,
        const SizedBox(width: AppSpacing.lg),
        Expanded(child: words),
      ],
    );
  }
}

/// One dot per work, filled in the available tone for each on the server,
/// a ring in the backlog's ink for each that is not.
class _TallyDots extends StatelessWidget {
  const _TallyDots({required this.tally});

  final ShelfTally tally;

  static const double _dot = 7;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    final held = statusToneColor(
      Theme.of(context).colorScheme,
      StatusTone.success,
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < tally.of; i++)
          Padding(
            padding: EdgeInsetsDirectional.only(
              start: i == 0 ? 0 : AppSpacing.xs,
            ),
            child: Container(
              width: _dot,
              height: _dot,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: i < tally.held ? held : null,
                border: i < tally.held
                    ? null
                    : Border.all(color: room.inkTertiary, width: 1.2),
              ),
            ),
          ),
      ],
    );
  }
}

/// A collection's head: its still, wide and rounded, lit from under by the
/// room, then the name and what the collection holds. Without a still, the
/// name alone.
class ShelfBanner extends StatelessWidget {
  const ShelfBanner({
    super.key,
    required this.name,
    required this.summary,
    this.banner,
    this.light,
    this.heroTag,
    this.onDrawn,
  });

  final String name;
  final String summary;
  final ShelfArt? banner;
  final TitleLight? light;
  final String? heroTag;
  final ValueChanged<String>? onDrawn;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    final scheme = Theme.of(context).colorScheme;
    Widget? still;
    if (banner case final banner? when banner.url.isNotEmpty) {
      still = AspectRatio(
        aspectRatio: 16 / 9,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: room.raised,
            borderRadius: BorderRadius.circular(AppRadius.door),
            boxShadow: AppElevation.poster(scheme, light: light?.light),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.door),
            child: ExcludeSemantics(
              child: LayoutBuilder(
                builder: (context, box) => ShelfArtwork(
                  art: banner,
                  box: Size(box.maxWidth, box.maxWidth * 9 / 16),
                  onDrawn: onDrawn,
                  fallback: const SizedBox.expand(),
                ),
              ),
            ),
          ),
        ),
      );
      if (heroTag case final tag?) {
        still = Hero(
          tag: tag,
          transitionOnUserGestures: MediaPosterCard.flightOnUserGestures,
          child: still,
        );
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (still != null) ...[still, const SizedBox(height: AppSpacing.lg)],
        Semantics(
          header: true,
          child: Text(
            name,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: (mediaStacked(context) ? AppType.room : AppType.screen)
                .copyWith(color: room.ink),
          ),
        ),
        if (summary.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            summary,
            style: AppType.label
                .weight(FontWeight.w400)
                .copyWith(color: room.inkSecondary),
          ),
        ],
      ],
    );
  }
}

/// A name's initials, as a disc without a photo shows them: the first
/// letter of the first word and of the last, `JM` for Jan Morgenstern, one
/// letter for one word.
String shelfInitials(String name) {
  final words = [
    for (final word in name.trim().split(RegExp(r'\s+')))
      if (word.isNotEmpty &&
          RegExp(r'\p{L}|\p{N}', unicode: true).hasMatch(word))
        word,
  ];
  String first(String word) => String.fromCharCode(
    word.runes.firstWhere(
      (rune) => RegExp(
        r'\p{L}|\p{N}',
        unicode: true,
      ).hasMatch(String.fromCharCode(rune)),
    ),
  ).toUpperCase();
  return switch (words) {
    [] => '',
    [final one] => first(one),
    _ => '${first(words.first)}${first(words.last)}',
  };
}

/// A picture of the shelf's, decoded at its box, or [fallback] without one
/// and while it cannot be read. Tells [onDrawn] once it is drawn, with its
/// address: the room's light is read from a picture the page has drawn.
class ShelfArtwork extends StatelessWidget {
  const ShelfArtwork({
    super.key,
    required this.art,
    required this.fallback,
    this.box,
    this.onDrawn,
  });

  final ShelfArt? art;
  final Widget fallback;
  final Size? box;
  final ValueChanged<String>? onDrawn;

  @override
  Widget build(BuildContext context) {
    final art = this.art;
    if (art == null || art.url.isEmpty) return fallback;
    return ArtworkDecodeBox(
      box: box,
      builder: (context, decode) => CachedNetworkImage(
        imageUrl: art.url,
        httpHeaders: art.headers,
        cacheManager: pinnedImageCacheFor(art.url),
        memCacheWidth: decode.width,
        memCacheHeight: decode.height,
        fit: BoxFit.cover,
        width: box?.width,
        height: box?.height,
        imageBuilder: (context, image) {
          onDrawn?.call(art.url);
          return Image(image: image, fit: BoxFit.cover);
        },
        placeholder: (context, url) =>
            const ShimmerPlaceholder(height: double.infinity),
        errorWidget: (context, url, error) => fallback,
      ),
    );
  }
}

/// A cover: square for an album, a book's 2:3 when [book]. Its own picture
/// with the room's light under it, else [fallback] on the plate.
class ShelfCover extends StatelessWidget {
  const ShelfCover({
    super.key,
    required this.art,
    required this.size,
    required this.fallback,
    this.light,
    this.radius = AppRadius.chip,
    this.onDrawn,
    this.dashed = false,
  });

  final ShelfArt? art;
  final Size size;
  final Widget fallback;
  final TitleLight? light;
  final double radius;
  final ValueChanged<String>? onDrawn;

  /// A book not on disk yet: its edge is dashed, as the backlog's ring is
  /// hollow.
  final bool dashed;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    final scheme = Theme.of(context).colorScheme;
    final picture = SizedBox.fromSize(
      size: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: room.raised,
          borderRadius: BorderRadius.circular(radius),
          border: dashed ? null : Border.all(color: AppColors.plateOutline),
          boxShadow: AppElevation.poster(scheme, light: light?.light),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: ShelfArtwork(
            art: art,
            box: size,
            onDrawn: onDrawn,
            fallback: fallback,
          ),
        ),
      ),
    );
    if (!dashed) return picture;
    return CustomPaint(
      foregroundPainter: _DashedEdge(color: room.inkTertiary, radius: radius),
      child: picture,
    );
  }
}

class _DashedEdge extends CustomPainter {
  const _DashedEdge({required this.color, required this.radius});

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final outline = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Offset.zero & size,
          Radius.circular(radius),
        ).deflate(0.75),
      );
    const dash = 5.0;
    const gap = 4.0;
    for (final metric in outline.computeMetrics()) {
      var at = 0.0;
      while (at < metric.length) {
        canvas.drawPath(metric.extractPath(at, at + dash), paint);
        at += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedEdge oldDelegate) =>
      color != oldDelegate.color || radius != oldDelegate.radius;
}

/// One work on the shelf, in a group: its cover, its title, what it is, where
/// it stands, and a line on what happens next. Opens on [body] when it has
/// one (an album's tracks), and speaks one sentence, [spoken].
class ShelfWorkRow extends StatefulWidget {
  const ShelfWorkRow({
    super.key,
    required this.cover,
    required this.title,
    required this.spoken,
    this.facts,
    this.state,
    this.detail,
    this.body,
    this.initiallyOpen = false,
  });

  final Widget cover;
  final String title;

  /// `2010 · 5 tracks · 21 min`.
  final String? facts;
  final ShelfState? state;

  /// What happens next, quietly: `Lidarr looks for it once it's out`.
  final String? detail;

  /// The row's sentence for a screen reader, its parts silenced.
  final String spoken;

  final WidgetBuilder? body;
  final bool initiallyOpen;

  @override
  State<ShelfWorkRow> createState() => _ShelfWorkRowState();
}

class _ShelfWorkRowState extends State<ShelfWorkRow> {
  late var _open = widget.initiallyOpen;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    final body = widget.body;
    final state = widget.state;
    final header = Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      child: Row(
        children: [
          widget.cover,
          const SizedBox(width: AppSpacing.slabY),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.row.copyWith(color: room.ink),
                ),
                if (widget.facts case final facts? when facts.isNotEmpty)
                  Text(
                    facts,
                    style: AppType.meta.copyWith(color: room.inkTertiary),
                  ),
                if (state != null) ...[
                  const SizedBox(height: AppSpacing.xxs),
                  MediaStateWord(
                    state.word,
                    tone: state.tone,
                    hollow: state.hollow,
                  ),
                ],
                if (widget.detail case final detail? when detail.isNotEmpty)
                  Text(
                    detail,
                    style: AppType.meta.copyWith(color: room.inkTertiary),
                  ),
              ],
            ),
          ),
          if (body != null) ...[
            const SizedBox(width: AppSpacing.sm),
            AnimatedRotation(
              turns: _open ? 0.5 : 0,
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 320),
              curve: const Cubic(0.2, 0.8, 0.2, 1),
              child: Icon(
                Icons.expand_more_rounded,
                size: 22,
                color: room.inkSecondary,
              ),
            ),
          ],
        ],
      ),
    );
    if (body == null) {
      return Semantics(
        container: true,
        label: widget.spoken,
        excludeSemantics: true,
        child: header,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          button: true,
          expanded: _open,
          label: widget.spoken,
          excludeSemantics: true,
          child: InkWell(
            onTap: () => setState(() => _open = !_open),
            child: header,
          ),
        ),
        if (_open)
          Padding(
            // Under the words, clear of the cover.
            padding: EdgeInsetsDirectional.only(
              start: _coverWidthOf(widget.cover) + AppSpacing.slabY,
              bottom: AppSpacing.md,
            ),
            child: body(context),
          ),
      ],
    );
  }

  double _coverWidthOf(Widget cover) =>
      cover is ShelfCover ? cover.size.width : 64;
}

/// A group of works as a sliver: the room's quiet fill round rows built as
/// they scroll in, a hairline between them. [MediaGroup] for a list that
/// can be long.
class ShelfSliverGroup extends StatelessWidget {
  const ShelfSliverGroup({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
  });

  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    return DecoratedSliver(
      decoration: BoxDecoration(
        color: room.fillQuiet,
        borderRadius: BorderRadius.circular(AppRadius.group),
        border: Border.all(color: room.hair),
      ),
      sliver: SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.slabY),
        sliver: SliverList.builder(
          itemCount: itemCount,
          itemBuilder: (context, index) => index == 0
              ? itemBuilder(context, 0)
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Divider(height: 1, color: room.hair),
                    itemBuilder(context, index),
                  ],
                ),
        ),
      ),
    );
  }
}

/// Where the files live on the server: `Folder` over the path, in the mono
/// face. A path too long for the line breaks where it must.
class ShelfFolderRow extends StatelessWidget {
  const ShelfFolderRow({super.key, required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    return MergeSemantics(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Folder', style: AppType.row.copyWith(color: room.ink)),
            const SizedBox(height: AppSpacing.xs),
            Text(path, style: AppType.mono.copyWith(color: room.inkSecondary)),
          ],
        ),
      ),
    );
  }
}

/// The way to the same page in the service's own web app: `Open in Lidarr`.
class ShelfOpenIn extends StatelessWidget {
  const ShelfOpenIn({super.key, required this.name, required this.onTap});

  /// The connection's name.
  final String name;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    return Center(
      child: Semantics(
        link: true,
        child: PressableScale(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: DesignTokens.sizeTouch,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      'Open in $name',
                      style: AppType.label.copyWith(color: room.inkSecondary),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  ExcludeSemantics(
                    child: Icon(
                      Icons.open_in_new_rounded,
                      size: 18,
                      color: room.inkSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
