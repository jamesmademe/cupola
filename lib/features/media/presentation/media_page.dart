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
import 'package:cupola/features/discover/domain/seerr_request_gate.dart';
import 'package:cupola/features/discover/presentation/seerr_request_words.dart';
import 'package:cupola/features/discover/presentation/discover_detail_view_model.dart';
import 'package:cupola/features/discover/presentation/widgets/request_bottom_sheet.dart';
import 'package:cupola/core/capability/role_gate.dart';
import 'package:cupola/features/discover/domain/seerr_grant.dart';
import 'package:cupola/features/media/domain/media_key.dart';
import 'package:cupola/features/media/domain/media_lead.dart';
import 'package:cupola/features/media/domain/media_row_view.dart';
import 'package:cupola/features/media/domain/media_rows.dart';
import 'package:cupola/features/movies/data/radarr_service.dart';
import 'package:cupola/features/movies/domain/models/radarr_movie.dart';
import 'package:cupola/features/media/domain/media_removal.dart';
import 'package:cupola/features/media/presentation/media_parts.dart';
import 'package:cupola/features/media/presentation/media_add_sheet.dart';
import 'package:cupola/features/media/presentation/media_copy_panel_card.dart';
import 'package:cupola/features/media/presentation/media_identity.dart';
import 'package:cupola/features/media/presentation/media_sources_provider.dart';
import 'package:cupola/features/discover/data/seerr_service.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/media/presentation/media_manage_summaries.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
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

  /// Watchlist as the user just set it, and when: it stands until Seerr
  /// answers after that.
  ({bool on, DateTime at})? _watchlisted;

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

  /// Adds the film to the Radarr chosen in the sheet, then reads
  /// every Radarr again: the row and the lead change with the answer.
  Future<void> _add(
    MediaLeadAdd lead,
    List<MediaRow> rows,
    MediaIdentity? identity,
    TitleLight? light,
  ) async {
    final tmdbId = mediaKey.tmdbId;
    final arrs = [
      for (final row in rows)
        if (row is MediaConnectionRow && row.service == lead.arr) row,
    ];
    if (tmdbId == null || arrs.isEmpty) return;
    final settings = ref.read(currentSettingsProvider);
    String name(ServiceInstance connection) =>
        settings.connectionTitle(connection.id, connection.service);
    final added = await showMediaAddSheet(
      context,
      tmdbId: tmdbId,
      connections: [for (final row in arrs) row.connection],
      name: name,
      title: identity?.title ?? '',
      year: identity?.year,
      light: light,
    );
    if (added == null || !mounted) return;
    SnackBarHelper.success(context, 'Added to ${name(added)}');
    for (final row in arrs) {
      retryMediaRow(ref, mediaKey, row);
    }
  }

  /// What Request says and may do through [lead]'s Seerr: the title's state
  /// there, read as that Seerr numbers it, and what this account may ask.
  /// Null until that Seerr has answered.
  _Request? _requestOf(MediaLeadRequest lead, List<MediaRow> rows) {
    final seerr = lead.seerr;
    MediaSeerrRecord? record;
    for (final row in rows) {
      if (row case MediaConnectionRow(
        :final connection,
        reading: MediaReadingAnswered(:final answer),
      ) when connection.id == seerr.id) {
        if (answer.value case final MediaSeerrRecord answered) {
          record = answered;
        }
      }
    }
    if (record == null) return null;
    final kind = mediaKey.isMovie ? SeerrMediaKind.movie : SeerrMediaKind.tv;
    final roleGate = ref.watch(roleGateProvider(seerr.id));
    // An account is offered 4K when it may ask for it; the key, when Seerr
    // has a 4K server for the kind.
    final has4k = roleGate.grant?.isApiKey == false
        ? roleGate.offers4k(kind)
        : record.arrServers?.any((server) => server.is4k) ?? false;
    final gate = seerrRequestGate(
      record.mediaInfo,
      isMovie: mediaKey.isMovie,
      seasons: mediaKey.isMovie
          ? const []
          : DiscoverDetailViewModel.fromResponse(record.details).seasons,
      numbering: ref.watch(mediaSeerrNumberingProvider(seerr.id)).value,
      has4kServer: has4k,
    );
    final arr = mediaKey.isMovie ? ServiceKey.radarr : ServiceKey.sonarr;
    final words = seerrRequestWords(
      gate,
      namesSeerr: roleGate.namesService(ServiceKey.seerr),
      namesArr: roleGate.namesService(arr),
      arrName: arr.title,
    );
    return (
      gate: gate,
      words: words,
      verdict: words.open ? roleGate.requestAction(kind) : const Live(),
    );
  }

  /// Opens the request sheet, then reads Seerr again.
  void _request(
    _Request request,
    MediaIdentity? identity,
    List<MediaRow> rows,
  ) {
    final tmdbId = mediaKey.tmdbId;
    if (tmdbId == null) return;
    AppBottomSheet.show<void>(
      context: context,
      title:
          'Request ${identity?.title ?? (mediaKey.isMovie ? 'movie' : 'series')}',
      subtitle: identity?.metaLine,
      builder: (_) => RequestBottomSheet(
        mediaId: tmdbId,
        mediaType: mediaKey.isMovie ? 'movie' : 'tv',
        copies: request.gate.copies,
        title: identity?.title,
        onRequestComplete: () {
          if (!mounted) return;
          SnackBarHelper.success(context, 'Request submitted');
          for (final row in rows) {
            if (row.service == ServiceKey.seerr) {
              retryMediaRow(ref, mediaKey, row);
            }
          }
        },
      ),
    );
  }

  /// Whether the title is on the watchlist of the user [seerrId] acts as,
  /// as that Seerr answered; null until it has.
  static ({bool on, DateTime at})? _onWatchlist(
    List<MediaRow> rows,
    String seerrId,
  ) {
    for (final row in rows) {
      if (row case MediaConnectionRow(
        :final connection,
        reading: MediaReadingAnswered(:final answer),
      ) when connection.id == seerrId) {
        if (answer.value case final MediaSeerrRecord record) {
          return (on: record.details['onUserWatchlist'] == true, at: answer.at);
        }
      }
    }
    return null;
  }

  /// Puts the title on that watchlist or takes it off: shown at once, then
  /// written, then Seerr read again; put back when the write failed.
  Future<void> _toggleWatchlist(
    String seerrId,
    bool on,
    MediaIdentity? identity,
    List<MediaRow> rows,
  ) async {
    final tmdbId = mediaKey.tmdbId;
    if (tmdbId == null) return;
    final mediaType = mediaKey.isMovie ? 'movie' : 'tv';
    setState(() => _watchlisted = (on: !on, at: DateTime.now()));
    final seerr = ref.read(seerrServiceForProvider(seerrId));
    try {
      if (on) {
        await seerr.removeFromWatchlist(tmdbId: tmdbId, mediaType: mediaType);
      } else {
        await seerr.addToWatchlist(
          tmdbId: tmdbId,
          mediaType: mediaType,
          title: identity?.title ?? '',
        );
      }
      if (!mounted) return;
      SnackBarHelper.success(
        context,
        on ? 'Taken off your watchlist' : 'On your watchlist',
      );
      for (final row in rows) {
        if (row.service == ServiceKey.seerr) retryMediaRow(ref, mediaKey, row);
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _watchlisted = null);
      SnackBarHelper.error(
        context,
        on
            ? 'Could not take it off your watchlist'
            : 'Could not put it on your watchlist',
        detail: error,
      );
    }
  }

  /// The film [connectionId]'s Radarr holds, when it answered with one.
  static RadarrMovie? _radarrMovieOf(List<MediaRow> rows, String connectionId) {
    for (final row in rows) {
      if (row case MediaConnectionRow(
        :final connection,
        reading: MediaReadingAnswered(:final answer),
      ) when connection.id == connectionId) {
        if (answer.value case MediaRadarrCopy(:final movie?)) return movie;
      }
    }
    return null;
  }

  /// Reads every Radarr and Sonarr again, after something here changed what
  /// they hold.
  void _readArrsAgain(List<MediaRow> rows) {
    for (final row in rows) {
      if (row.service == ServiceKey.radarr ||
          row.service == ServiceKey.sonarr) {
        retryMediaRow(ref, mediaKey, row);
      }
    }
  }

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
    // The requester reads the players' rows only.
    final shown = [
      for (final row in rows)
        if (audience == Audience.operator ||
            row.service == ServiceKey.jellyfin ||
            row.service == ServiceKey.plex)
          row,
    ];
    final views = [
      for (final row in shown)
        if (mediaRowView(
              row,
              title: (connection) =>
                  settings.connectionTitle(connection.id, connection.service),
              now: DateTime.now(),
            )
            case final view?)
          _ServerRow(view, onTap: _wayOf(row, view)),
    ];
    final request = lead is MediaLeadRequest ? _requestOf(lead, rows) : null;
    // Watchlist is Seerr's, kept for the user the connection acts as: no
    // Seerr, no Watchlist.
    final watchlistSeerr = _recommender(settings);
    final answeredWatchlist = watchlistSeerr == null
        ? null
        : _onWatchlist(rows, watchlistSeerr);
    final chosen = _watchlisted;
    final watchlisted =
        chosen != null &&
            (answeredWatchlist == null ||
                !answeredWatchlist.at.isAfter(chosen.at))
        ? chosen.on
        : answeredWatchlist?.on;
    // Under the buttons, what a request means now: why there is none to make,
    // what one would add, or for the requester, that the title is not there.
    final requestLine = request == null
        ? null
        : request.words.reason ??
              request.verdict.reason ??
              request.words.adds ??
              (audience == Audience.requester
                  ? 'Not on the server yet.'
                  : null);
    // Manage is the operator's, and only when there is something to manage.
    final manage = audience == Audience.operator
        ? _manage(rows, settings)
        : const <Widget>[];
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
              // A Radarr copy that needs something says so where the lead
              // stands, and what can be done.
              if (lead case MediaLeadCopy(
                :final connection,
                :final status,
              ) when _radarrMovieOf(rows, connection.id) != null)
                MediaCopyPanelCard(
                  connection: connection,
                  name: settings.connectionTitle(
                    connection.id,
                    connection.service,
                  ),
                  movie: _radarrMovieOf(rows, connection.id)!,
                  status: status,
                  onChanged: () => _readArrsAgain(rows),
                )
              else
                _LeadBar(
                  lead: lead,
                  light: light,
                  onPlay: (lead) => _play(
                    lead,
                    settings.connectionTitle(
                      lead.server.id,
                      lead.server.service,
                    ),
                  ),
                  onTrailer: identity?.videos.isNotEmpty ?? false
                      ? () =>
                            DiscoverVideosButton.show(context, identity!.videos)
                      : null,
                  onManage: _toManage,
                  watchlist: watchlistSeerr == null || watchlisted == null
                      ? null
                      : (
                          on: watchlisted,
                          onTap: () => _toggleWatchlist(
                            watchlistSeerr,
                            watchlisted,
                            identity,
                            rows,
                          ),
                        ),
                  request: request,
                  onRequest: request == null
                      ? null
                      : () => _request(request, identity, rows),
                  // A series is added with its seasons, not drawn here yet.
                  onAdd: mediaKey.isMovie
                      ? (lead) => _add(lead, rows, identity, light)
                      : null,
                  hasTrailer: identity?.videos.isNotEmpty ?? false,
                  showManage: manage.isNotEmpty,
                  serverName: (lead) => settings.connectionTitle(
                    lead.server.id,
                    lead.server.service,
                  ),
                ),
              if (requestLine != null) ...[
                const SizedBox(height: AppSpacing.md),
                _StateLine(
                  requestLine,
                  tone: switch (request?.gate.state) {
                    SeerrRequestState.waitingForApproval ||
                    SeerrRequestState.onItsWay => StatusTone.info,
                    SeerrRequestState.failed => StatusTone.warning,
                    SeerrRequestState.available => StatusTone.success,
                    SeerrRequestState.blocklisted => StatusTone.neutral,
                    // Not there yet: the backlog's ring.
                    _ => null,
                  },
                ),
              ],
            ];
            final serve = <Widget>[
              // The requester's line already says the title is not there, or
              // where her request stands: the players' rows would repeat it.
              if (views.isNotEmpty &&
                  !(audience == Audience.requester && requestLine != null)) ...[
                _Heading('On your server', trailing: _servicesCount(shown)),
                MediaGroup(children: views),
              ],
              ...manage,
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
    final held = [
      for (final row in rows)
        if (row case MediaConnectionRow(
          :final connection,
          reading: MediaReadingAnswered(:final answer),
        ))
          if (answer.value case MediaRadarrCopy(:final movie?))
            (
              name: settings.connectionTitle(connection.id, connection.service),
              target: (connection: connection, movie: movie),
            ),
    ];
    final title = MediaIdentity.of(rows)?.title ?? '';
    void remove(_RadarrHeld copy) => _remove(
      copy,
      title: title,
      keeping: [
        for (final other in held)
          if (other.target != copy && other.target.movie.hasFile) other.name,
      ],
    );
    return [
      _Heading('Manage', key: _manageKey),
      MediaGroup(
        children: [
          _ManageRow(
            title: 'Files & quality',
            summary: summaries.files,
            body: (context) => _Files(
              rows: rows,
              settings: settings,
              onChanged: () => _readArrsAgain(rows),
            ),
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
                ? (context) => _CopyChoices<ReleaseSearchTarget>(
                    verb: 'Search releases on',
                    copies: searches,
                    onChoose: (target) =>
                        showReleaseSearch(context, ref, target),
                  )
                : null,
          ),
          if (held case [final copy])
            _ManageRow(
              title: 'Remove from ${copy.name}',
              summary: copy.target.movie.monitored
                  ? 'Stops ${copy.name} looking for it'
                  : 'Stops ${copy.name} tracking it',
              onTap: () => remove(copy.target),
            )
          else if (held.isNotEmpty)
            _ManageRow(
              title: 'Remove a copy',
              summary: _names([for (final copy in held) copy.name]),
              body: (context) => _CopyChoices<_RadarrHeld>(
                verb: 'Remove from',
                copies: held,
                onChoose: remove,
              ),
            ),
        ],
      ),
    ];
  }

  /// `Radarr`, `Radarr and Radarr 4K`, `A, B and C`.
  static String _names(List<String> names) => switch (names) {
    [] => '',
    [final one] => one,
    _ => '${names.take(names.length - 1).join(', ')} and ${names.last}',
  };

  /// Removes [copy] from its Radarr, after the question removing asks: what
  /// it takes, whether its files go, whether Radarr may add it again. Then
  /// every Radarr is read again.
  Future<void> _remove(
    _RadarrHeld copy, {
    required String title,
    required List<String> keeping,
  }) async {
    final name = ref
        .read(currentSettingsProvider)
        .connectionTitle(copy.connection.id, copy.connection.service);
    final removal = mediaRemoval(
      title: title,
      name: name,
      sizeOnDisk: copy.movie.sizeOnDisk,
      monitored: copy.movie.monitored,
      keeping: keeping,
    );
    final result = await showAppConfirmDialog(
      context: context,
      title: removal.title,
      message: removal.message,
      icon: Icons.delete_outline_rounded,
      cancelLabel: 'Keep it',
      confirmLabel: removal.confirm(deleteFiles: false, exclude: false),
      confirmLabelFor: (checked) => removal.confirm(
        deleteFiles: checked('files'),
        exclude: checked('exclude'),
      ),
      options: [
        if (removal.filesLabel case final label?)
          AppConfirmOption(
            key: 'files',
            label: label,
            subtitle: 'Its folder on your server. This cannot be undone.',
          ),
        AppConfirmOption(
          key: 'exclude',
          label: "Don't add it again",
          subtitle: "Keeps $name's import lists from bringing it back",
        ),
      ],
    );
    if (!result.confirmed || !mounted) return;
    try {
      await ref
          .read(radarrServiceForProvider(copy.connection.id))
          .deleteMovie(
            copy.movie.id,
            deleteFiles: result.option('files'),
            addImportExclusion: result.option('exclude'),
          );
      if (!mounted) return;
      SnackBarHelper.success(context, 'Removed from $name');
      for (final row in ref.read(mediaRowsProvider(mediaKey))) {
        if (row.service == ServiceKey.radarr) {
          retryMediaRow(ref, mediaKey, row);
        }
      }
    } catch (error) {
      if (!mounted) return;
      SnackBarHelper.error(
        context,
        'Could not remove $title from $name',
        detail: error,
      );
    }
  }
}

/// A film one Radarr holds: the connection, and its record there.
typedef _RadarrHeld = ({ServiceInstance connection, RadarrMovie movie});

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
    this.watchlist,
    this.request,
    this.onRequest,
    this.onAdd,
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

  /// Whether the title is on the watchlist, and the toggle; null without a
  /// Seerr that has answered.
  final ({bool on, VoidCallback onTap})? watchlist;

  /// What Request says and may do, when it leads.
  final _Request? request;

  /// Opens the request sheet, when a request can be made.
  final VoidCallback? onRequest;

  /// Opens the add sheet, for an Add that leads.
  final void Function(MediaLeadAdd lead)? onAdd;
  final bool hasTrailer;
  final bool showManage;
  final String Function(MediaLeadPlay lead) serverName;

  @override
  Widget build(BuildContext context) {
    final label = switch (lead) {
      MediaLeadPlay(:final resume) =>
        '${resume ? 'Resume' : 'Play'} on ${serverName(lead as MediaLeadPlay)}',
      MediaLeadAdd(:final arr) => 'Add to ${arr.title}',
      MediaLeadRequest() => request?.words.label ?? 'Request',
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
    final leadStyle = mediaLeadStyle(context, light);
    final watchlist = this.watchlist;
    final secondaries = <(String, IconData, VoidCallback?, String?)>[
      if (hasTrailer && !trailerLeads)
        ('Trailer', Icons.smart_display_outlined, onTrailer, null),
      // The watchlist of the user the Seerr connection acts as
      // (F-seerr-actas): the glyph fills while the title is on it.
      if (watchlist != null)
        (
          'Watchlist',
          watchlist.on ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
          watchlist.onTap,
          // Heard as a state, since the glyph alone shows it.
          watchlist.on ? 'On your watchlist' : null,
        ),
      if (showManage) ('Manage', Icons.tune_rounded, onManage, null),
    ];
    final onLead = switch (lead) {
      final MediaLeadPlay play => () => onPlay(play),
      final MediaLeadAdd add when onAdd != null => () => onAdd!(add),
      MediaLeadRequest() when request?.words.open ?? false => onRequest,
      _ => null,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (lead is MediaLeadWaiting)
          const ShimmerPlaceholder(height: DesignTokens.sizeButtonL)
        else if (label != null && label.isNotEmpty)
          // An account that may not ask for this kind keeps Request, dimmed
          // and tappable, and is told why.
          if (lead is MediaLeadRequest &&
              (request?.words.open ?? false) &&
              onRequest != null)
            RoleGatedAction.builder(
              verdict: request!.verdict,
              onTap: onRequest!,
              builder: (context, onPressed, annotate) => FilledButton(
                onPressed: onPressed,
                style: leadStyle,
                child: Row(
                  children: [
                    Expanded(child: annotate(Text(label))),
                    const Icon(Icons.add_rounded, size: 20),
                  ],
                ),
              ),
            )
          else
            FilledButton(
              onPressed: onLead,
              style: leadStyle,
              child: Row(
                children: [
                  Expanded(child: Text(label)),
                  Icon(switch (lead) {
                    MediaLeadPlay() => Icons.play_arrow_rounded,
                    MediaLeadAdd() => Icons.add_rounded,
                    MediaLeadRequest() when !(request?.words.open ?? true) =>
                      request!.words.icon,
                    MediaLeadRequest() => Icons.add_rounded,
                    _ => Icons.arrow_forward_rounded,
                  }, size: 20),
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
          for (final (index, (text, icon, onPressed, spoken))
              in secondaries.indexed) ...[
            if (index > 0) const SizedBox(height: AppSpacing.sm),
            OutlinedButton.icon(
              onPressed: onPressed,
              icon: Icon(icon, size: 17),
              label: Text(text, semanticsLabel: spoken),
            ),
          ]
        else
          Row(
            children: [
              for (final (index, (text, icon, onPressed, spoken))
                  in secondaries.indexed) ...[
                if (index > 0) const SizedBox(width: AppSpacing.row),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onPressed,
                    icon: Icon(icon, size: 17),
                    label: Text(
                      text,
                      semanticsLabel: spoken,
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
  const _Files({
    required this.rows,
    required this.settings,
    required this.onChanged,
  });

  final List<MediaRow> rows;
  final SettingsModel settings;

  /// Told after a copy's profile or monitoring changed.
  final VoidCallback onChanged;

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
            (
              connection: connection,
              movie: movie,
              file: movie.movieFile,
              folder: movie.path,
            ),
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
          _CopyControls(
            connection: copy.connection,
            name: settings.connectionTitle(
              copy.connection.id,
              copy.connection.service,
            ),
            movie: copy.movie,
            onChanged: onChanged,
          ),
        ],
      ],
    );
  }
}

/// What a copy's arr does about it, edited where it is read: its quality
/// profile and whether it is monitored, in the words the add sheet uses.
/// A change shows at once and is written to the arr; [onChanged] then reads
/// the copy again, and a write that failed puts the old value back.
class _CopyControls extends ConsumerStatefulWidget {
  const _CopyControls({
    required this.connection,
    required this.name,
    required this.movie,
    required this.onChanged,
  });

  final ServiceInstance connection;
  final String name;
  final RadarrMovie movie;
  final VoidCallback onChanged;

  @override
  ConsumerState<_CopyControls> createState() => _CopyControlsState();
}

class _CopyControlsState extends ConsumerState<_CopyControls> {
  /// What the user chose, until the copy read again says so.
  int? _profileId;
  bool? _monitored;

  @override
  void didUpdateWidget(_CopyControls old) {
    super.didUpdateWidget(old);
    if (old.movie != widget.movie) {
      _profileId = null;
      _monitored = null;
    }
  }

  Future<void> _write(
    Future<void> Function() write,
    VoidCallback undo,
    String failure,
  ) async {
    try {
      await write();
      widget.onChanged();
    } catch (error) {
      if (!mounted) return;
      setState(undo);
      SnackBarHelper.error(context, failure, detail: error);
    }
  }

  Future<void> _pickProfile(Map<int, String> profiles, int current) async {
    final picked = await showMediaValueSheet<int>(
      context,
      title: 'Quality profile',
      value: current,
      currentLabel: profiles[current] ?? '',
      options: [
        for (final MapEntry(:key, :value) in profiles.entries)
          MediaDetailValueOption(value: key, label: value),
      ],
    );
    if (picked == null || picked.value == current || !mounted) return;
    setState(() => _profileId = picked.value);
    await _write(
      () => ref
          .read(radarrServiceForProvider(widget.connection.id))
          .updateMovieProfile(widget.movie.id, picked.value),
      () => _profileId = null,
      'Could not change the profile in ${widget.name}',
    );
  }

  Future<void> _setMonitored(bool value) async {
    setState(() => _monitored = value);
    await _write(
      () => ref
          .read(radarrServiceForProvider(widget.connection.id))
          .updateMovieMonitored(widget.movie.id, value),
      () => _monitored = null,
      value
          ? 'Could not monitor it in ${widget.name}'
          : 'Could not stop monitoring it in ${widget.name}',
    );
  }

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    final profiles =
        ref.watch(mediaRadarrProfilesProvider(widget.connection.id)).value ??
        const <int, String>{};
    final profileId = _profileId ?? widget.movie.qualityProfileId;
    final profile = profiles[profileId];
    final monitored = _monitored ?? widget.movie.monitored;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Unnamed until Radarr has said what its profiles are called.
        if (profile != null)
          MediaValueRow(
            label: 'Quality profile',
            value: Text(
              profile,
              textAlign: TextAlign.end,
              style: AppType.meta.copyWith(color: room.inkSecondary),
            ),
            onTap: profiles.length > 1 && profileId != null
                ? () => _pickProfile(profiles, profileId)
                : null,
          ),
        MediaSwitchRow(
          label: 'Monitor',
          detail: monitored
              ? 'Grabs it and upgrades it to ${profile ?? 'its profile'}'
              : '${widget.name} lists it and never looks for it',
          value: monitored,
          onChanged: _setMonitored,
        ),
      ],
    );
  }
}

/// A section open on the copies it can act on: one row per copy, each named
/// for what it does there (`Search releases on Radarr 4K`).
class _CopyChoices<T> extends StatelessWidget {
  const _CopyChoices({
    required this.verb,
    required this.copies,
    required this.onChoose,
  });

  /// What a row does, before the connection's name: `Search releases on`.
  final String verb;
  final List<({String name, T target})> copies;
  final ValueChanged<T> onChoose;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final copy in copies)
          Semantics(
            button: true,
            label: '$verb ${copy.name}',
            excludeSemantics: true,
            child: InkWell(
              onTap: () => onChoose(copy.target),
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

/// What Request says and may do on a page: the title's state in Seerr, the
/// control's words, and what the account may ask.
typedef _Request = ({
  SeerrRequestGate gate,
  SeerrRequestWords words,
  GateVerdict verdict,
});

/// One line under the lead that says where a title stands: a 7 dot in its
/// tone, or the backlog's ring, then the sentence.
class _StateLine extends StatelessWidget {
  const _StateLine(this.text, {this.tone});

  final String text;

  /// The dot's tone; null draws the ring of something not there yet.
  final StatusTone? tone;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    final tone = this.tone;
    final color = tone == null
        ? room.inkTertiary
        : statusToneColor(Theme.of(context).colorScheme, tone);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: tone == null ? null : color,
              border: tone == null
                  ? Border.all(color: color, width: 1.4)
                  : null,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            text,
            style: AppType.meta
                .weight(FontWeight.w400)
                .copyWith(color: room.inkSecondary),
          ),
        ),
      ],
    );
  }
}
