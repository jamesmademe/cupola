import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:cupola/core/app_breakpoints.dart';
import 'package:cupola/core/app_elevation.dart';
import 'package:cupola/core/app_gradients.dart';
import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/generated/design_tokens.g.dart';
import 'package:cupola/core/capability/audience.dart';
import 'package:cupola/core/capability/role_gate_provider.dart';
import 'package:cupola/core/network/pinned_image_cache.dart';
import 'package:cupola/features/media/domain/quality_words.dart';
import 'package:cupola/features/media/domain/media_reading.dart';
import 'package:cupola/features/media/domain/media_copies.dart';
import 'package:cupola/core/utils/byte_format.dart';
import 'package:cupola/core/models/arr_media_file.dart';
import 'package:cupola/core/status/media_action.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/title_light.dart';
import 'package:cupola/core/utils/dynamic_map_utils.dart';
import 'package:cupola/core/utils/image_utils.dart';
import 'package:cupola/core/utils/string_utils.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/core/utils/snack_bar_helper.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/discover/presentation/widgets/discover_videos_button.dart';
import 'package:cupola/features/bazarr/presentation/widgets/bazarr_detail_sections.dart';
import 'package:cupola/features/plex/presentation/plex_provider.dart';
import 'package:cupola/features/release_search/domain/release_search_target.dart';
import 'package:cupola/features/release_search/presentation/release_search_entry.dart';
import 'package:cupola/features/stream/domain/stream_web_url.dart';
import 'package:cupola/features/activity/domain/global_activity_status.dart';
import 'package:cupola/features/discover/presentation/widgets/discover_carousel.dart';
import 'package:cupola/features/discover/presentation/widgets/discover_cast_list.dart';
import 'package:cupola/features/discover/domain/models/discover_detail_model.dart';
import 'package:cupola/features/media/domain/media_collection.dart';
import 'package:cupola/features/media/domain/media_key.dart';
import 'package:cupola/features/media/domain/media_lead.dart';
import 'package:cupola/features/media/domain/media_row_view.dart';
import 'package:cupola/features/media/domain/media_rows.dart';
import 'package:cupola/features/media/presentation/media_identity.dart';
import 'package:cupola/features/media/presentation/media_sources_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/media/presentation/media_manage_summaries.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';

/// The canonical Media page: one title, the same page from every entry
/// point.
///
/// Four layers, top to bottom: who the title is (artwork, title, scores), the
/// one action that leads, what every connection holds ("On your server"),
/// and the operator's sections, closed. [focus] is the connection the page
/// was opened from: its copy leads when it needs something.
class MediaPage extends ConsumerStatefulWidget {
  const MediaPage({
    super.key,
    required this.mediaKey,
    this.focus,
    this.heroTag,
    this.posterUrl,
  });

  final MediaKey mediaKey;
  final String? focus;

  /// The tag of the tile the page was opened from: its poster flies here.
  final String? heroTag;

  /// The poster that tile drew, standing in until the page has read who the
  /// title is, so the flight lands on a picture rather than a shimmer.
  final String? posterUrl;

  @override
  ConsumerState<MediaPage> createState() => _MediaPageState();
}

class _MediaPageState extends ConsumerState<MediaPage> {
  /// Where Manage scrolls to.
  final _manageKey = GlobalKey();

  /// The artwork the page has drawn: the title light is read from one of
  /// these only.
  final _drawn = <String>{};

  void _artDrawn(String url) {
    if (_drawn.contains(url)) return;
    // After the frame that drew it: a setState inside an image builder would
    // rebuild the tree that is being built.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _drawn.add(url));
    });
  }

  MediaKey get mediaKey => widget.mediaKey;
  String? get focus => widget.focus;

  /// Plays [lead] in its server's own client, at the item.
  Future<void> _play(MediaLeadPlay lead, String serverName) async {
    final server = lead.server;
    final machineId = server.service == ServiceKey.plex
        ? ref
              .read(plexCapabilitiesForProvider(server.id))
              .value
              ?.machineIdentifier
        : null;
    final target = streamItemWebUrl(
      service: server.service,
      baseUrl: server.url,
      itemId: lead.item.id,
      plexMachineId: machineId,
    );
    final opened =
        target != null &&
        await launchUrl(target, mode: LaunchMode.externalApplication);
    if (!opened && mounted) {
      SnackBarHelper.error(context, 'Could not open $serverName');
    }
  }

  /// The Seerr "More like this" is read through: the first one set up, while
  /// the title has a TMDB id.
  String? _recommender(SettingsModel settings) {
    if (mediaKey.tmdbId == null) return null;
    return settings
        .instancesOf(ServiceKey.seerr)
        .where((instance) => instance.isConfigured)
        .firstOrNull
        ?.id;
  }

  /// Where [view]'s one way forward leads, for [row]: a setup form, the
  /// connection asked again, or its own form for the remedy a failure names.
  VoidCallback? _wayOf(MediaRow row, MediaRowView view) => switch (view.way) {
    null => null,
    MediaRowWay.setUp ||
    MediaRowWay.add => () => context.go(ServiceRoutes.setUp(row.service)),
    MediaRowWay.retry => () => retryMediaRow(ref, mediaKey, row),
    MediaRowWay.fix => () => context.go(
      ServiceRoutes.settingsForConnection(row.service, view.connectionId ?? ''),
    ),
  };

  void _toManage() {
    final target = _manageKey.currentContext;
    if (target == null) return;
    Scrollable.ensureVisible(
      target,
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final rows = ref.watch(mediaRowsProvider(mediaKey));
    final audience = ref.watch(audienceProvider);
    final settings = ref.watch(currentSettingsProvider);
    final identity = MediaIdentity.of(rows);
    final lead = resolveMediaLead(rows, audience: audience, focus: focus);
    final views = [
      for (final row in rows)
        if (audience == Audience.operator ||
            row.service == ServiceKey.jellyfin ||
            row.service == ServiceKey.plex)
          if (mediaRowView(
                row,
                title: (connection) =>
                    settings.connectionTitle(connection.id, connection.service),
                now: DateTime.now(),
              )
              case final view?)
            _ServerRow(view, onTap: _wayOf(row, view)),
    ];
    final room = CupolaRoom.of(context);
    final scheme = Theme.of(context).colorScheme;
    final top = MediaQuery.paddingOf(context).top;
    // The one image that lights the room: the backdrop, else the poster. Until
    // it is read, and for artwork with too little chroma, the lamp.
    // It is read once the page has drawn that picture: it comes from the same
    // cache then, and a picture that never arrives leaves the lamp on.
    final lightSource = identity?.backdropUrl ?? identity?.posterUrl;
    final lit = _drawn.contains(lightSource) ? lightSource : null;
    final light = lit == null ? null : ref.watch(titleLightProvider(lit)).value;

    return Scaffold(
      backgroundColor: room.ground,
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: AppGradients.ambientBackground(
            scheme,
            accent: light?.light,
          ),
        ),
        child: LayoutBuilder(
          builder: (context, box) {
            // The page's own width, not the window's: in a tablet's detail
            // pane it is a phone's column, full screen it takes two tracks.
            final column = (box.maxWidth - 2 * AppSpacing.lg).clamp(
              0.0,
              AppBreakpoints.contentWell,
            );
            final gutter = (box.maxWidth - column) / 2;
            final head = <Widget>[
              const Align(alignment: Alignment.centerLeft, child: _BackPlate()),
              const SizedBox(height: AppSpacing.md),
              _Hero(
                onArtDrawn: _artDrawn,
                backdropHeight: (column / 2.6).clamp(214, 420),
                identity: identity,
                kind: mediaKey.kind,
                heroTag: widget.heroTag,
                posterUrl: widget.posterUrl,
                waiting:
                    identity == null &&
                    rows.any(
                      (row) =>
                          row is MediaConnectionRow &&
                          row.reading is MediaReadingWaiting,
                    ),
                marks: mediaFormatMarks(rows),
                light: light,
              ),
            ];
            final act = <Widget>[
              const SizedBox(height: AppSpacing.lg),
              _Scores(
                scores: mediaScoresOf(rows, identity),
                showMetacritic: audience == Audience.operator,
              ),
              const SizedBox(height: AppSpacing.slabY),
              _LeadBar(
                lead: lead,
                light: light,
                onPlay: (lead) => _play(
                  lead,
                  settings.connectionTitle(lead.server.id, lead.server.service),
                ),
                onTrailer: identity?.videos.isNotEmpty ?? false
                    ? () => DiscoverVideosButton.show(context, identity!.videos)
                    : null,
                onManage: _toManage,
                hasTrailer: identity?.videos.isNotEmpty ?? false,
                showManage: audience == Audience.operator,
                serverName: (lead) => settings.connectionTitle(
                  lead.server.id,
                  lead.server.service,
                ),
              ),
            ];
            final serve = <Widget>[
              if (views.isNotEmpty) ...[
                _Heading('On your server', trailing: _servicesCount(rows)),
                _RowsCard(children: views),
              ],
              if (audience == Audience.operator) ..._manage(rows, settings),
            ];
            final reference = <Widget>[
              if ((identity?.overview ?? '').isNotEmpty) ...[
                const SizedBox(height: AppSpacing.section),
                Text(
                  identity!.overview,
                  style: AppType.body.copyWith(color: room.ink),
                ),
              ],
              if ((identity?.creditsLine ?? '').isNotEmpty) ...[
                const SizedBox(height: AppSpacing.md),
                Text(
                  identity!.creditsLine,
                  style: AppType.meta.copyWith(color: room.inkSecondary),
                ),
              ],
              if (identity?.cast.isNotEmpty ?? false) ...[
                const _Heading('Cast'),
                DiscoverCastList(
                  cast: identity!.cast,
                  padding: EdgeInsets.zero,
                ),
              ],
              if (identity?.collection case final collection?) ...[
                const SizedBox(height: AppSpacing.section),
                _CollectionBand(
                  collection: collection,
                  held: switch (_recommender(settings)) {
                    final seerr? =>
                      ref
                          .watch(
                            mediaCollectionHeldProvider((
                              connectionId: seerr,
                              collectionId: collection.id,
                            )),
                          )
                          .value,
                    null => null,
                  },
                ),
              ],
            ];
            final more = <Widget>[
              if (_recommender(settings) case final seerr?) ...[
                const SizedBox(height: AppSpacing.section),
                DiscoverCarousel(
                  title: 'More like this',
                  sectionId: 'media-more-like-this',
                  forcedMediaType: mediaKey.isMovie ? 'movie' : 'tv',
                  items: ref.watch(
                    mediaRecommendationsProvider((
                      key: mediaKey,
                      connectionId: seerr,
                    )),
                  ),
                ),
              ],
            ];
            return CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    gutter,
                    top + AppSpacing.md,
                    gutter,
                    // Clear of the floating bar, which grows with the
                    // reading size; where there is none, a margin.
                    math.max(
                      AppSpacing.xxxl,
                      FloatingNavBarMetrics.getScrollViewBottomPadding(context),
                    ),
                  ),
                  sliver: SliverList.list(
                    children: [
                      ...head,
                      if (box.maxWidth >= AppBreakpoints.touchRail)
                        // Two tracks: who the title is and what to do with it
                        // on the left, the servers and Manage beside it.
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [...act, ...reference],
                              ),
                            ),
                            const SizedBox(width: AppSpacing.xl),
                            SizedBox(
                              width: _sideTrack,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: serve,
                              ),
                            ),
                          ],
                        )
                      else ...[
                        ...act,
                        ...serve,
                        ...reference,
                      ],
                      ...more,
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// `4 services`: the services the rows speak for, each once.
  String _servicesCount(List<MediaRow> rows) {
    final services = {
      for (final row in rows)
        if (row is MediaConnectionRow) row.service,
    };
    return services.length == 1 ? '1 service' : '${services.length} services';
  }

  /// The operator's sections, closed: each says what it holds in one line
  /// ([mediaManageSummaries]).
  List<Widget> _manage(List<MediaRow> rows, SettingsModel settings) {
    final summaries = mediaManageSummaries(
      rows,
      title: (connection) =>
          settings.connectionTitle(connection.id, connection.service),
    );
    if (summaries == null) return const [];
    final searches = [
      for (final row in rows)
        if (row case MediaConnectionRow(
          :final connection,
          reading: MediaReadingAnswered(:final answer),
        ))
          if (answer.value case MediaRadarrCopy(:final movie?))
            (
              name: settings.connectionTitle(connection.id, connection.service),
              target: ReleaseSearchTarget.movie(
                movieId: movie.id,
                label: truncateTitle(movie.title),
              ).stampedWith(connection.id),
            ),
    ];
    return [
      _Heading('Manage', key: _manageKey),
      _RowsCard(
        children: [
          _ManageRow(
            title: 'Files & quality',
            summary: summaries.files,
            body: (context) => _Files(rows: rows, settings: settings),
          ),
          _ManageRow(
            title: 'History',
            summary: summaries.history,
            body: (context) => _History(rows: rows, settings: settings),
          ),
          if (summaries.subtitles case final subtitles?)
            _ManageRow(
              title: 'Subtitles',
              summary: subtitles,
              body: (context) => _Subtitles(rows: rows, settings: settings),
            ),
          _ManageRow(
            title: 'Search releases',
            summary: summaries.search,
            // One copy: the row is the way in. More: it opens on the copies,
            // and the search goes to the one chosen.
            onTap: searches.length == 1
                ? () => showReleaseSearch(context, ref, searches.single.target)
                : null,
            body: searches.length > 1
                ? (context) => _SearchCopies(
                    copies: searches,
                    onSearch: (target) =>
                        showReleaseSearch(context, ref, target),
                  )
                : null,
          ),
        ],
      ),
    ];
  }
}

/// The back control: a 44 plate at rest over the room.
class _BackPlate extends StatelessWidget {
  const _BackPlate();

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    return Semantics(
      button: true,
      label: MaterialLocalizations.of(context).backButtonTooltip,
      child: PressableScale(
        onTap: () => Navigator.of(context).maybePop(),
        child: Container(
          width: DesignTokens.sizeTouch,
          height: DesignTokens.sizeTouch,
          decoration: BoxDecoration(
            color: room.fillControl,
            borderRadius: BorderRadius.circular(AppRadius.control),
            border: Border.all(color: room.edge),
          ),
          child: Icon(Icons.chevron_left_rounded, size: 26, color: room.ink),
        ),
      ),
    );
  }
}

/// Past 1.4 times the reading size the page stacks what sits side by side:
/// the answer `SectionHeader` and `MediaChildList` give at the same threshold.
bool _stacked(BuildContext context) =>
    MediaQuery.textScalerOf(context).scale(14) > 14 * 1.4;

/// Artwork, poster and title: the backdrop in a slab, the poster rising out
/// of its foot, the title beside the poster, then the meta line.
class _Hero extends StatelessWidget {
  const _Hero({
    required this.identity,
    required this.kind,
    required this.waiting,
    required this.marks,
    required this.onArtDrawn,
    required this.backdropHeight,
    this.heroTag,
    this.posterUrl,
    this.light,
  });

  /// See [MediaPage.heroTag] and [MediaPage.posterUrl].
  final String? heroTag;
  final String? posterUrl;

  /// The slab's height: 214 on the phone, growing with the page's width.
  final double backdropHeight;

  /// Told when the backdrop or the poster has been drawn.
  final ValueChanged<String> onArtDrawn;

  final MediaIdentity? identity;
  final MediaKind kind;

  /// Nobody has said who the title is yet: the artwork shimmers rather than
  /// standing in.
  final bool waiting;

  final List<String> marks;

  /// The title's light, or null for the lamp.
  final TitleLight? light;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    final scheme = Theme.of(context).colorScheme;
    final identity = this.identity;
    // The poster grows with the slab, up to half again its phone size.
    final scale = (backdropHeight / 214).clamp(1.0, 1.5);
    final posterWidth = 88.0 * scale;
    final posterHeight = 132.0 * scale;
    final rise = 52.0 * scale;

    final stacked = _stacked(context);
    final backdrop = Container(
      height: backdropHeight,
      decoration: BoxDecoration(
        color: room.raised,
        borderRadius: BorderRadius.circular(AppRadius.slab),
        boxShadow: AppElevation.hero(scheme, light: light?.light),
      ),
      clipBehavior: Clip.antiAlias,
      child: switch ((identity?.backdropUrl, identity?.posterUrl)) {
        _ when waiting => const ShimmerPlaceholder(height: double.infinity),
        (final String backdrop, _) when backdrop.isNotEmpty => _Artwork(
          url: backdrop,
          onDrawn: onArtDrawn,
          fallback: _Plate(kind: kind, well: true),
        ),
        // No backdrop: the poster, veiled, so the slab is still the title's.
        // Decoded once, at the poster's box.
        (_, final String poster) when poster.isNotEmpty => _Artwork.veiled(
          url: poster,
          decodeBox: Size(posterWidth, posterHeight),
          onDrawn: onArtDrawn,
          fallback: _Plate(kind: kind, well: true),
        ),
        _ => _Plate(kind: kind, well: true),
      },
    );
    // The tile's poster stands in until the title's own is known.
    final posterArt = (identity?.posterUrl ?? '').isNotEmpty
        ? identity!.posterUrl
        : posterUrl;
    Widget poster = Container(
      width: posterWidth,
      height: posterHeight,
      decoration: BoxDecoration(
        color: room.raised,
        borderRadius: BorderRadius.circular(AppRadius.poster),
        // Artwork is not palette: the plate's line in both rooms.
        border: Border.all(color: AppColors.plateOutline),
        boxShadow: AppElevation.poster(scheme, light: light?.light),
      ),
      clipBehavior: Clip.antiAlias,
      child: waiting && (posterArt ?? '').isEmpty
          ? const ShimmerPlaceholder(height: double.infinity)
          : _Artwork(
              url: posterArt,
              decodeBox: Size(posterWidth, posterHeight),
              onDrawn: onArtDrawn,
              fallback: _Plate(kind: kind),
            ),
    );
    if (heroTag case final tag?) {
      poster = Hero(
        tag: tag,
        transitionOnUserGestures: MediaPosterCard.flightOnUserGestures,
        child: poster,
      );
    }
    final title = Semantics(
      header: true,
      child: Text(
        identity?.title ?? '',
        maxLines: stacked ? 3 : 2,
        overflow: TextOverflow.ellipsis,
        style: AppType.media.copyWith(color: room.ink),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // The poster rises [rise] into the artwork, and the title beside it
        // sizes the hero: a title on two lines pushes the meta line down
        // rather than running over it.
        Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: backdropHeight,
              child: backdrop,
            ),
            Padding(
              padding: EdgeInsets.only(top: backdropHeight - rise),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  poster,
                  if (!stacked) ...[
                    const SizedBox(width: AppSpacing.slabY),
                    Expanded(
                      child: Padding(
                        // Clear of the artwork: the title starts under it.
                        padding: EdgeInsets.only(top: rise + AppSpacing.md),
                        child: title,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        // At a large reading size the title takes the whole width.
        if (stacked) ...[const SizedBox(height: AppSpacing.md), title],
        const SizedBox(height: AppSpacing.md),
        Wrap(
          spacing: AppSpacing.s,
          runSpacing: AppSpacing.xs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              identity?.metaLine ?? '',
              style: AppType.label
                  .weight(FontWeight.w400)
                  .copyWith(color: room.inkSecondary),
            ),
            for (final mark in marks) _Mark(mark),
          ],
        ),
      ],
    );
  }
}

class _Mark extends StatelessWidget {
  const _Mark(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s,
        vertical: 1,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: room.inkTertiary),
      ),
      child: Text(
        text,
        style: AppType.micro.copyWith(color: room.inkSecondary),
      ),
    );
  }
}

class _Artwork extends StatelessWidget {
  const _Artwork({
    required this.url,
    required this.fallback,
    this.decodeBox,
    this.onDrawn,
  }) : veiled = false,
       opacity = 1;

  /// [url] blurred and dimmed over the plate's well: a poster standing in
  /// for a backdrop.
  const _Artwork.veiled({
    required this.url,
    required this.fallback,
    this.decodeBox,
    this.onDrawn,
    this.opacity = 0.72,
  }) : veiled = true;

  final String? url;

  /// What stands in when there is no picture, or it cannot be fetched.
  final Widget fallback;

  /// The box the picture is decoded for, when it is not the one it fills.
  final Size? decodeBox;

  final bool veiled;

  /// How much of the veiled picture shows over the well: less under words.
  final double opacity;

  /// Told once the picture is drawn, with its address.
  final ValueChanged<String>? onDrawn;

  @override
  Widget build(BuildContext context) {
    final url = this.url;
    if (url == null || url.isEmpty) return fallback;
    final picture = ArtworkDecodeBox(
      box: decodeBox,
      builder: (context, decode) => CachedNetworkImage(
        imageUrl: url,
        cacheManager: pinnedImageCacheFor(url),
        memCacheWidth: decode.width,
        memCacheHeight: decode.height,
        fit: BoxFit.cover,
        imageBuilder: (context, image) {
          onDrawn?.call(url);
          return Image(image: image, fit: BoxFit.cover);
        },
        placeholder: (context, url) =>
            const ShimmerPlaceholder(height: double.infinity),
        errorWidget: (context, url, error) => fallback,
      ),
    );
    if (!veiled) return picture;
    return ColoredBox(
      color: AppColors.plateWell,
      child: Opacity(
        opacity: opacity,
        child: ImageFiltered(
          imageFilter: ui.ImageFilter.blur(
            sigmaX: 24,
            sigmaY: 24,
            tileMode: TileMode.clamp,
          ),
          child: SizedBox.expand(child: picture),
        ),
      ),
    );
  }
}

/// The side track's width when the page takes two: the servers and Manage,
/// drawn for the phone's column and a little more.
const double _sideTrack = 380;

/// The collection the title belongs to, in one slab over its own artwork,
/// veiled: its name, and how much of it the household holds. Taps
/// into the collection.
class _CollectionBand extends StatelessWidget {
  const _CollectionBand({required this.collection, required this.held});

  final CollectionInfo collection;

  /// Null until Seerr has counted it, and when it could not: then the band
  /// names what it is and states no figure.
  final MediaCollectionHeld? held;

  @override
  Widget build(BuildContext context) {
    final count = held;
    final words = count == null
        ? 'Collection'
        : '${count.held} of ${count.total} on your server';
    final art = collection.backdropPath ?? collection.posterPath;
    return PressableScale(
      onTap: () => context.push(
        ServiceRoutes.seerrCollection(
          collection.id,
          heroTag: 'collection_${collection.id}',
        ),
      ),
      semanticLabel: '${collection.name}, $words',
      excludeChildSemantics: true,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.slab),
        child: DecoratedBox(
          position: DecorationPosition.foreground,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.slab),
            border: Border.all(color: AppColors.plateOutline),
          ),
          child: Stack(
            children: [
              Positioned.fill(
                child: _Artwork.veiled(
                  url: ImageUtils.buildTmdbPosterUrl(art, size: 'w300'),
                  fallback: const ColoredBox(color: AppColors.plateSurface),
                  // Blurred: a small decode carries it.
                  decodeBox: const Size(120, 68),
                  opacity: 0.56,
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            collection.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: AppType.feature.copyWith(
                              color: AppColors.plateInk,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          Text(
                            words,
                            style: AppType.label
                                .weight(FontWeight.w600)
                                .copyWith(color: AppColors.plateInk),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    const Icon(
                      Icons.chevron_right_rounded,
                      size: 24,
                      color: AppColors.plateInk,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Missing artwork's stand-in: the plate, dark in both rooms (brand book,
/// *Plates*), with the kind of title it stands for.
class _Plate extends StatelessWidget {
  const _Plate({required this.kind, this.well = false});

  final MediaKind kind;

  /// The backdrop's letterboxed well rather than a poster's plate.
  final bool well;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: ColoredBox(
        color: well ? AppColors.plateWell : AppColors.plateSurface,
        child: Center(
          child: Icon(
            kind == MediaKind.movie ? Icons.movie_outlined : Icons.tv_outlined,
            size: well ? 40 : 28,
            color: AppColors.plateDimInk,
          ),
        ),
      ),
    );
  }
}

/// The four scores in one slab, each with its source; a source with no
/// figure reads `—`.
class _Scores extends StatelessWidget {
  const _Scores({required this.scores, required this.showMetacritic});

  final MediaScores scores;

  /// The requester never sees Metacritic: Seerr has none.
  final bool showMetacritic;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    String figure(num? value, {bool decimal = true}) => value == null
        ? '—'
        : decimal
        ? value.toStringAsFixed(1)
        : '$value';
    Widget line(List<(String, String)> cells) => _ScoresLine(cells);
    final cells = [
      ('TMDB', figure(scores.tmdb)),
      ('IMDb', figure(scores.imdb)),
      ('Rotten Tomatoes', figure(scores.rottenTomatoes, decimal: false)),
      if (showMetacritic)
        ('Metacritic', figure(scores.metacritic, decimal: false)),
    ];
    return Container(
      padding: const EdgeInsets.all(AppSpacing.xs),
      decoration: BoxDecoration(
        color: room.fillQuiet,
        borderRadius: BorderRadius.circular(AppRadius.door),
        border: Border.all(color: room.hair),
      ),
      child: _stacked(context)
          // At a large reading size, two to a line.
          ? Column(
              children: [
                line(cells.take(2).toList()),
                Divider(height: 1, color: room.hair),
                line(cells.skip(2).toList()),
              ],
            )
          : line(cells),
    );
  }
}

class _ScoresLine extends StatelessWidget {
  const _ScoresLine(this.cells);

  final List<(String, String)> cells;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    return IntrinsicHeight(
      child: Row(
        children: [
          for (final (index, cell) in cells.indexed) ...[
            if (index > 0) VerticalDivider(width: 1, color: room.hair),
            Expanded(
              child: Semantics(
                label: '${cell.$1}: ${cell.$2 == '—' ? 'no score' : cell.$2}',
                excludeSemantics: true,
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.row),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(
                        cell.$2,
                        style: AppType.figure.copyWith(color: room.ink),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        cell.$1,
                        style: AppType.micro
                            .weight(FontWeight.w400)
                            .copyWith(color: room.inkTertiary),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The one action that leads, and the three beside it: Trailer, Watchlist,
/// Manage.
class _LeadBar extends StatelessWidget {
  const _LeadBar({
    required this.lead,
    required this.onPlay,
    required this.onTrailer,
    required this.onManage,
    this.light,
    required this.hasTrailer,
    required this.showManage,
    required this.serverName,
  });

  final MediaLead lead;

  /// The title's light: the lead takes its tinted fill. Null, the ink.
  final TitleLight? light;
  final void Function(MediaLeadPlay lead) onPlay;
  final VoidCallback? onTrailer;
  final VoidCallback onManage;
  final bool hasTrailer;
  final bool showManage;
  final String Function(MediaLeadPlay lead) serverName;

  @override
  Widget build(BuildContext context) {
    final label = switch (lead) {
      MediaLeadPlay(:final resume) =>
        '${resume ? 'Resume' : 'Play'} on ${serverName(lead as MediaLeadPlay)}',
      MediaLeadAdd(:final arr) => 'Add to ${arr.title}',
      MediaLeadRequest() => 'Request',
      MediaLeadCopy(:final status, :final connection) => resolveMediaAction(
        status,
        const MediaActionCapabilities(
          canSearch: true,
          canInteractiveSearch: true,
          canOpenQueue: true,
        ),
        serviceName: connection.service.title,
      ).label,
      MediaLeadTrailer() || MediaLeadNone() || MediaLeadWaiting() => null,
    };
    final trailerLeads = lead is MediaLeadTrailer;
    // Lit by the title: the tinted fill under its ink in the dark room, the
    // tinted primary under white in the day room. Unlit, the ink.
    final light = this.light;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final leadStyle = light == null
        ? AppTheme.primaryButtonStyle(context)
        : AppTheme.primaryButtonStyle(context).copyWith(
            backgroundColor: WidgetStatePropertyAll(
              dark ? light.actionFill : light.dayPrimary,
            ),
            foregroundColor: WidgetStatePropertyAll(
              dark ? light.actionInk : const Color(0xFFFFFFFF),
            ),
            iconColor: WidgetStatePropertyAll(
              dark ? light.actionInk : const Color(0xFFFFFFFF),
            ),
          );
    // Watchlist is wired with the account the Seerr connection acts as
    // (F-seerr-actas): until then it has no way to keep its promise.
    final secondaries = <(String, IconData, VoidCallback?)>[
      if (hasTrailer && !trailerLeads)
        ('Trailer', Icons.smart_display_outlined, onTrailer),
      ('Watchlist', Icons.bookmark_border_rounded, null),
      if (showManage) ('Manage', Icons.tune_rounded, onManage),
    ];
    final onLead = switch (lead) {
      final MediaLeadPlay play => () => onPlay(play),
      // Add, Request and a copy's own action open the operator's and the
      // requester's flows from the page: lots M5 and M6.
      _ => null,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (lead is MediaLeadWaiting)
          const ShimmerPlaceholder(height: DesignTokens.sizeButtonL)
        else if (label != null && label.isNotEmpty)
          FilledButton(
            onPressed: onLead,
            style: leadStyle,
            child: Row(
              children: [
                Expanded(child: Text(label)),
                Icon(
                  lead is MediaLeadPlay
                      ? Icons.play_arrow_rounded
                      : Icons.arrow_forward_rounded,
                  size: 20,
                ),
              ],
            ),
          )
        else if (trailerLeads)
          FilledButton.icon(
            onPressed: onTrailer,
            style: leadStyle,
            icon: const Icon(Icons.smart_display_outlined, size: 20),
            label: const Text('Trailer'),
          ),
        const SizedBox(height: AppSpacing.row),
        // At a large reading size, one to a line: three side by side cut
        // their words.
        if (_stacked(context))
          for (final (index, (text, icon, onPressed))
              in secondaries.indexed) ...[
            if (index > 0) const SizedBox(height: AppSpacing.sm),
            OutlinedButton.icon(
              onPressed: onPressed,
              icon: Icon(icon, size: 17),
              label: Text(text),
            ),
          ]
        else
          Row(
            children: [
              for (final (index, (text, icon, onPressed))
                  in secondaries.indexed) ...[
                if (index > 0) const SizedBox(width: AppSpacing.row),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onPressed,
                    icon: Icon(icon, size: 17),
                    label: Text(
                      text,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
            ],
          ),
      ],
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text, {super.key, this.trailing});

  final String text;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    return Padding(
      padding: const EdgeInsets.only(
        top: AppSpacing.section,
        bottom: AppSpacing.md,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Text(
                text,
                style: AppType.section.copyWith(color: room.ink),
              ),
            ),
          ),
          if (trailing != null)
            Text(
              trailing!,
              style: AppType.meta.copyWith(color: room.inkTertiary),
            ),
        ],
      ),
    );
  }
}

/// A group of rows on one slab, divided by hairlines.
class _RowsCard extends StatelessWidget {
  const _RowsCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    final items = children;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.slabY),
      decoration: BoxDecoration(
        color: room.fillQuiet,
        borderRadius: BorderRadius.circular(AppRadius.group),
        border: Border.all(color: room.hair),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (index, item) in items.indexed) ...[
            if (index > 0) Divider(height: 1, color: room.hair),
            item,
          ],
        ],
      ),
    );
  }
}

/// One row of "On your server", in the shape its case takes
/// ([MediaRowShape]): the connection on the left, a fixed 92; what it holds;
/// on the right the state, or the row's one way forward. A row with a way
/// forward is tapped whole, and speaks one sentence.
class _ServerRow extends StatelessWidget {
  const _ServerRow(this.view, {this.onTap});

  final MediaRowView view;

  /// The row's one way forward ([MediaRowView.way]).
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    final stacked = _stacked(context);
    final content = Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.row),
      child: view.shape == MediaRowShape.notSetUp
          ? _notSetUp(room, stacked: stacked)
          : _reading(context, room, stacked: stacked),
    );
    final onTap = this.onTap;
    if (onTap == null) {
      return Semantics(
        container: true,
        label: view.spoken,
        excludeSemantics: true,
        child: content,
      );
    }
    return PressableScale(
      onTap: onTap,
      semanticLabel: view.spoken,
      excludeChildSemantics: true,
      child: content,
    );
  }

  /// Case a, dimmed and still the way in: the name, `Not
  /// set up` and what it would bring, and the pill that names the service.
  Widget _notSetUp(CupolaRoom room, {required bool stacked}) {
    final name = Text(
      view.name,
      style: AppType.row.copyWith(color: room.ink.withValues(alpha: 0.55)),
    );
    final state = Text(
      view.state,
      style: AppType.meta
          .weight(FontWeight.w600)
          .copyWith(color: room.inkSecondary.withValues(alpha: 0.72)),
    );
    final reason = Text(
      view.detail,
      style: AppType.caption
          .weight(FontWeight.w400)
          .copyWith(color: room.inkTertiary),
    );
    if (stacked) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          name,
          state,
          if (view.detail.isNotEmpty) reason,
          if (view.action case final action?) ...[
            const SizedBox(height: AppSpacing.sm),
            _SetUpPill(action),
          ],
        ],
      );
    }
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  SizedBox(width: 92, child: name),
                  const SizedBox(width: AppSpacing.row),
                  Expanded(child: state),
                ],
              ),
              if (view.detail.isNotEmpty) ...[
                const SizedBox(height: 2),
                reason,
              ],
            ],
          ),
        ),
        if (view.action case final action?) ...[
          const SizedBox(width: AppSpacing.row),
          _SetUpPill(action),
        ],
      ],
    );
  }

  Widget _reading(
    BuildContext context,
    CupolaRoom room, {
    required bool stacked,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final tone = statusToneColor(scheme, view.tone, surface: room.ground);
    final waiting = view.state.isEmpty;
    final secondary = AppType.meta
        .weight(FontWeight.w400)
        .copyWith(color: room.inkTertiary);
    final stateStyle = AppType.meta
        .weight(FontWeight.w600)
        .copyWith(color: room.inkSecondary);

    Widget state() => ConstrainedBox(
      // The state takes its own width, up to a third of the row: the detail
      // gets the rest, and a long state wraps inside its own column.
      constraints: const BoxConstraints(maxWidth: 150),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: view.hollow ? null : tone,
              border: view.hollow
                  ? Border.all(color: room.inkSecondary, width: 1.5)
                  : null,
            ),
          ),
          const SizedBox(width: AppSpacing.s),
          Flexible(child: Text(view.state, style: stateStyle)),
        ],
      ),
    );

    final middle = switch (view.shape) {
      _ when waiting => const Align(
        alignment: Alignment.centerLeft,
        child: ShimmerPlaceholder(width: 120, height: 12),
      ),
      MediaRowShape.failed => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(view.state, style: stateStyle.copyWith(color: tone)),
          if (view.detail.isNotEmpty) Text(view.detail, style: secondary),
        ],
      ),
      _ => Text(view.detail, style: secondary),
    };

    final trailing = switch (view.shape) {
      _ when waiting => null,
      MediaRowShape.failed => Text(
        view.action ?? '',
        style: AppType.label.copyWith(color: room.ink),
      ),
      _ => state(),
    };

    final name = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(view.name, style: AppType.row.copyWith(color: room.ink)),
        if (view.via case final via?)
          Text(via, style: AppType.caption.copyWith(color: room.inkTertiary)),
      ],
    );
    final add = view.shape == MediaRowShape.claim && view.action != null
        ? Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: Row(
              children: [
                Icon(Icons.add_rounded, size: 18, color: room.ink),
                const SizedBox(width: AppSpacing.s),
                Expanded(
                  child: Text(
                    view.action!,
                    style: AppType.label.copyWith(color: room.ink),
                  ),
                ),
              ],
            ),
          )
        : null;
    // At a large reading size each part takes the whole width, one under
    // the other: the name, what it holds, its state or its way forward.
    if (stacked) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          name,
          if (waiting ||
              view.detail.isNotEmpty ||
              view.shape == MediaRowShape.failed) ...[
            const SizedBox(height: AppSpacing.xs),
            middle,
          ],
          if (trailing != null) ...[
            const SizedBox(height: AppSpacing.xs),
            trailing,
          ],
          ?add,
        ],
      );
    }
    return Column(
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 36),
          child: Row(
            children: [
              SizedBox(width: 92, child: name),
              const SizedBox(width: AppSpacing.row),
              Expanded(child: middle),
              if (trailing != null) ...[
                const SizedBox(width: AppSpacing.row),
                trailing,
              ],
            ],
          ),
        ),
        ?add,
      ],
    );
  }
}

/// `+ Set up Seerr`: the quiet pill a row that is not set up ends with. The
/// row around it is the target; the pill names where it leads.
class _SetUpPill extends StatelessWidget {
  const _SetUpPill(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    final ink = room.inkSecondary.withValues(alpha: 0.8);
    return Container(
      constraints: const BoxConstraints(minHeight: 36),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.row),
      decoration: BoxDecoration(
        color: room.fillControl,
        borderRadius: BorderRadius.circular(AppRadius.chip),
        border: Border.all(color: room.edge),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.add_rounded, size: 16, color: ink),
          const SizedBox(width: AppSpacing.xs),
          Text(
            label,
            style: AppType.meta.weight(FontWeight.w600).copyWith(color: ink),
          ),
        ],
      ),
    );
  }
}

/// A closed operator section: its title and what it holds in one line,
/// opening on [body] when there is one. Its content is built when it opens:
/// a section nobody opens reads nothing.
class _ManageRow extends StatefulWidget {
  const _ManageRow({
    required this.title,
    required this.summary,
    this.body,
    this.onTap,
  }) : assert(body == null || onTap == null, 'a section opens or acts');

  final String title;
  final String summary;
  final WidgetBuilder? body;

  /// What the row does instead of opening, when it leads straight there.
  final VoidCallback? onTap;

  @override
  State<_ManageRow> createState() => _ManageRowState();
}

class _ManageRowState extends State<_ManageRow> {
  var _open = false;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    final body = widget.body;
    final header = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 60),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.title,
                  style: AppType.row.copyWith(color: room.ink),
                ),
                if (widget.summary.isNotEmpty)
                  Text(
                    widget.summary,
                    style: AppType.meta
                        .weight(FontWeight.w400)
                        .copyWith(color: room.inkTertiary),
                  ),
              ],
            ),
          ),
          if (widget.onTap != null)
            Icon(
              Icons.chevron_right_rounded,
              size: 18,
              color: room.inkTertiary,
            ),
          if (body != null)
            AnimatedRotation(
              turns: _open ? 0.5 : 0,
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 220),
              child: Icon(
                Icons.expand_more_rounded,
                size: 18,
                color: room.inkTertiary,
              ),
            ),
        ],
      ),
    );
    if (widget.onTap case final onTap?) {
      return Semantics(
        button: true,
        child: InkWell(onTap: onTap, child: header),
      );
    }
    if (body == null) return header;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          button: true,
          expanded: _open,
          child: InkWell(
            onTap: () => setState(() => _open = !_open),
            child: header,
          ),
        ),
        if (_open)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.slabY),
            child: body(context),
          ),
      ],
    );
  }
}

/// Files & quality, open: every copy under its connection's name, its file
/// as the service records it, or the row a copy with nothing on disk keeps.
class _Files extends StatelessWidget {
  const _Files({required this.rows, required this.settings});

  final List<MediaRow> rows;
  final SettingsModel settings;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    final copies = [
      for (final row in rows)
        if (row case MediaConnectionRow(
          :final connection,
          reading: MediaReadingAnswered(:final answer),
        ))
          if (answer.value case MediaRadarrCopy(:final movie?))
            (connection: connection, file: movie.movieFile, folder: movie.path),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final copy in copies) ...[
          Padding(
            padding: const EdgeInsets.only(
              top: AppSpacing.sm,
              bottom: AppSpacing.xs,
            ),
            child: Text(
              [
                settings.connectionTitle(
                  copy.connection.id,
                  copy.connection.service,
                ),
                if (copy.file?.qualityName case final quality?
                    when quality.isNotEmpty)
                  qualityWords(quality),
                if (copy.file?.size case final size? when size > 0)
                  formatBytes(size),
              ].join(' · '),
              style: AppType.label.copyWith(color: room.inkSecondary),
            ),
          ),
          switch (copy.file) {
            ArrMediaFile(:final fileName?) => FileInfoSection.file(
              fileName: fileName,
              releasedAs: copy.file!.releasedAs,
              path: copy.folder,
            ),
            _ => const FileInfoSection.missing(),
          },
        ],
      ],
    );
  }
}

/// Search releases, open on more than one copy: each copy a row that sends
/// the search to its own connection.
class _SearchCopies extends StatelessWidget {
  const _SearchCopies({required this.copies, required this.onSearch});

  final List<({String name, ReleaseSearchTarget target})> copies;
  final ValueChanged<ReleaseSearchTarget> onSearch;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final copy in copies)
          Semantics(
            button: true,
            label: 'Search releases on ${copy.name}',
            excludeSemantics: true,
            child: InkWell(
              onTap: () => onSearch(copy.target),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  minHeight: DesignTokens.sizeTouch,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        copy.name,
                        style: AppType.label.copyWith(color: room.inkSecondary),
                      ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 18,
                      color: room.inkTertiary,
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Subtitles, open: each Bazarr's languages for the movie, the ones on disk
/// and the ones it is still looking for.
class _Subtitles extends StatelessWidget {
  const _Subtitles({required this.rows, required this.settings});

  final List<MediaRow> rows;
  final SettingsModel settings;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    final copies = [
      for (final row in rows)
        if (row case MediaConnectionRow(
          :final connection,
          reading: MediaReadingAnswered(:final answer),
        ))
          if (answer.value case MediaBazarrCopy(:final movie?))
            (connection: connection, movie: movie),
    ];
    Widget label(String text) => Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm, bottom: AppSpacing.s),
      child: Text(
        text,
        style: AppType.label.copyWith(color: room.inkSecondary),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final copy in copies) ...[
          if (copies.length > 1)
            label(
              settings.connectionTitle(
                copy.connection.id,
                copy.connection.service,
              ),
            ),
          if (copy.movie.presentLanguages.isNotEmpty) ...[
            label('On disk'),
            BazarrSubtitleLanguageWrap(languages: copy.movie.presentLanguages),
          ],
          if (copy.movie.missingLanguages.isNotEmpty) ...[
            label('Wanted'),
            BazarrSubtitleLanguageWrap(languages: copy.movie.missingLanguages),
          ],
        ],
      ],
    );
  }
}

/// History, open: each Radarr copy's own events, newest first, read when the
/// section opens.
class _History extends ConsumerWidget {
  const _History({required this.rows, required this.settings});

  final List<MediaRow> rows;
  final SettingsModel settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final room = CupolaRoom.of(context);
    final scheme = Theme.of(context).colorScheme;
    final copies = [
      for (final row in rows)
        if (row case MediaConnectionRow(
          :final connection,
          reading: MediaReadingAnswered(:final answer),
        ))
          if (answer.value case MediaRadarrCopy(:final movie?))
            (connection: connection, movieId: movie.id),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final copy in copies) ...[
          Padding(
            padding: const EdgeInsets.only(
              top: AppSpacing.sm,
              bottom: AppSpacing.xs,
            ),
            child: Text(
              settings.connectionTitle(
                copy.connection.id,
                copy.connection.service,
              ),
              style: AppType.label.copyWith(color: room.inkSecondary),
            ),
          ),
          switch (ref.watch(
            mediaRadarrHistoryProvider((
              connectionId: copy.connection.id,
              movieId: copy.movieId,
            )),
          )) {
            AsyncValue(:final value?) when value.isEmpty => Text(
              'Nothing in its history yet',
              style: AppType.meta.copyWith(color: room.inkTertiary),
            ),
            AsyncValue(:final value?) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final record in value.take(8))
                  _HistoryLine(record: record, scheme: scheme),
              ],
            ),
            AsyncValue(:final error?) => InlineErrorRetry(
              message: 'Could not read the history',
              error: error,
              service: copy.connection.service,
              instanceId: copy.connection.id,
              onRetry: () => ref.invalidate(
                mediaRadarrHistoryProvider((
                  connectionId: copy.connection.id,
                  movieId: copy.movieId,
                )),
              ),
            ),
            _ => const ShimmerPlaceholder(height: 36),
          },
        ],
      ],
    );
  }
}

/// One event: its word in its tone, the release's quality, the day.
class _HistoryLine extends StatelessWidget {
  const _HistoryLine({required this.record, required this.scheme});

  final Map<String, dynamic> record;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    final event = '${record['eventType'] ?? ''}';
    final quality = mapOrNull(
      mapOrNull(record['quality'])?['quality'],
    )?['name'];
    final date = '${record['date'] ?? ''}';
    final words = [
      historyEventLabel(event),
      if (quality is String && quality.isNotEmpty) qualityWords(quality),
      if (date.isNotEmpty) formatShortDate(date),
    ];
    return Semantics(
      container: true,
      label: words.join('. '),
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Row(
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: statusToneColor(
                  scheme,
                  historyEventTone(event),
                  surface: room.ground,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                words.join(' · '),
                style: AppType.meta
                    .weight(FontWeight.w400)
                    .copyWith(color: room.inkSecondary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
