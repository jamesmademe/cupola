import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/api/arr_detail_actions_mixin.dart';
import 'package:cupola/core/api/quality_profile_mixin.dart';
import 'package:cupola/core/utils/rating_display.dart';
import 'package:cupola/core/utils/snack_bar_helper.dart';
import 'package:cupola/core/utils/string_utils.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/discover/presentation/widgets/arr_media_extras_section.dart';
import 'package:cupola/features/release_search/domain/release_search_target.dart';
import 'package:cupola/features/release_search/presentation/release_search_entry.dart';
import 'package:cupola/features/release_search/presentation/widgets/release_search_indicators.dart';
import 'package:cupola/features/release_search/presentation/widgets/release_search_status_card.dart';
import 'package:cupola/features/stream/domain/models/stream_item.dart';
import 'package:cupola/features/stream/presentation/widgets/stream_availability_slot.dart';
import 'package:cupola/features/import/presentation/manual_import_routes.dart';
import 'package:cupola/features/series/data/sonarr_service.dart';
import 'package:cupola/features/series/domain/models/sonarr_episode.dart';
import 'package:cupola/features/series/domain/models/sonarr_series.dart';
import 'package:cupola/features/series/domain/sonarr_series_type.dart';
import 'package:cupola/features/series/domain/sonarr_status.dart';
import 'package:cupola/features/series/presentation/series_detail_provider.dart';
import 'package:cupola/features/series/presentation/series_detail_view_model.dart';
import 'package:cupola/features/series/presentation/series_provider.dart';
import 'package:cupola/features/series/presentation/widgets/series_seasons_list.dart';
import 'package:cupola/features/series/presentation/widgets/series_type_row.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

class SeriesDetailScreen extends ConsumerStatefulWidget {
  final int seriesId;
  final String heroTag;
  final SonarrSeries? initialSeries;

  /// The connection this page belongs to, from the route's `?i=`. Null falls
  /// through to the lens — see [MovieDetailScreen.instanceId] for why every
  /// source on the page has to agree with it.
  final String? instanceId;

  const SeriesDetailScreen({
    super.key,
    required this.seriesId,
    required this.heroTag,
    this.initialSeries,
    this.instanceId,
  });

  @override
  ConsumerState<SeriesDetailScreen> createState() => _SeriesDetailScreenState();
}

class _SeriesDetailScreenState extends ConsumerState<SeriesDetailScreen>
    with
        QualityProfileMixin<SeriesDetailScreen>,
        ArrDetailActionsMixin<SeriesDetailScreen> {
  final Set<int> _searchingSeasons = {};
  final Set<int> _searchingEpisodes = {};

  /// A series-type write is in flight. Held on the state rather than derived
  /// from the provider because the read-modify-write takes two round trips and
  /// the detail provider does not move until both land — without this the row
  /// looks idle for the whole of it and takes a second tap.
  bool _isUpdatingSeriesType = false;

  /// The connection resolved in the last build, for the callbacks to reuse —
  /// see [_MovieDetailScreenState] for why it is held rather than re-resolved.
  String _instanceId = '';

  /// Sonarr, bound to the connection this page belongs to. Every read and
  /// every write on this screen goes through it.
  SonarrService get _sonarr => _instanceId.isEmpty
      ? ref.read(sonarrServiceProvider)
      : ref.read(sonarrServiceForProvider(_instanceId));

  @override
  Widget build(BuildContext context) {
    final instanceId = effectiveInstanceId(
      ref,
      ServiceKey.sonarr,
      widget.instanceId,
    );
    _instanceId = instanceId;
    final connection = ref.watch(
      currentSettingsProvider.select((s) => s.instanceById(instanceId)),
    );
    // Asked before either provider is read: see the movie screen. The series
    // and its episodes would both throw and both retry with backoff for a
    // condition no waiting changes.
    if (connection?.isConfigured != true) {
      return MediaDetailPlaceholderView.error(
        error: '${ServiceKey.sonarr.title} not configured',
        serviceName: ServiceKey.sonarr.title,
        accent: ServiceKey.sonarr.accent,
      );
    }
    final detailRef = (instanceId: instanceId, id: widget.seriesId);
    final seriesAsync = widget.seriesId > 0
        ? ref.watch(seriesDetailForProvider(detailRef))
        : const AsyncData<SonarrSeries?>(null);
    final episodesAsync = widget.seriesId > 0
        ? ref.watch(seriesEpisodesForProvider(detailRef))
        : const AsyncData<List<SonarrEpisode>>(<SonarrEpisode>[]);
    final series = seriesAsync.asData?.value ?? widget.initialSeries;

    if (series == null) {
      if (seriesAsync.isLoading) {
        return MediaDetailLoadingView(
          accent: ServiceKey.sonarr.accent,
          // Passed even though it has a default: without it the skeleton shows a
          // film reel and the loaded hero a television, one frame apart.
          heroFallbackIcon: Icons.tv_rounded,
        );
      }

      return MediaDetailPlaceholderView.error(
        error: seriesAsync.asError?.error ?? 'Series not found.',
        serviceName: 'Sonarr',
        accent: ServiceKey.sonarr.accent,
        // Recover in place. Both loads share one outage, so one retry re-runs
        // both. With no id there is no provider to re-run, so no retry is
        // offered rather than one that does nothing.
        onRetry: widget.seriesId > 0
            ? () {
                ref.invalidate(seriesDetailForProvider(detailRef));
                ref.invalidate(seriesEpisodesForProvider(detailRef));
              }
            : null,
      );
    }

    _syncQualityProfiles(series);

    final viewModel = SeriesDetailViewModel.fromSeries(
      series,
      // The page's own connection, never `sonarrUrl` — that is the first one.
      baseUrl: connection?.url ?? '',
      apiKey: connection?.credential ?? '',
    );
    // An empty profile name on purpose: decision 25 moves that field out of the
    // read-only grid and onto an editable row above it, and a value offered in
    // two places is a value the user has to guess about.
    final infoGroups = viewModel.buildInfoGroups(
      '',
      // Only a series Sonarr actually holds can be retyped. For anything else
      // the row stays a fact, which is what it is.
      seriesTypeControl: viewModel.isInLibrary && series.id > 0
          ? SeriesTypeRow(
              rawValue: viewModel.seriesType ?? '',
              accent: ServiceKey.sonarr.accent,
              isBusy: _isUpdatingSeriesType,
              onChanged: (type) =>
                  _updateSeriesType(context, seriesId: series.id, type: type),
            )
          : null,
    );

    // Without the queue the badge cannot tell "nothing on disk" from "being
    // downloaded right now", and every in-flight series reads as Missing.
    final queueEntry = ref
        .watch(sonarrQueueSnapshotForProvider(instanceId))
        .maybeWhen(
          data: (snapshot) => snapshot.entryFor(series.id),
          orElse: () => null,
        );
    final status = sonarrSeriesStatus(series, queueEntry: queueEntry);

    return MediaDetailView(
      accent: ServiceKey.sonarr.accent,
      // Sonarr's own page used to pass nothing here, so a backdrop-less show got
      // a film reel on the first-party page and a television on the Bazarr one.
      heroFallbackIcon: Icons.tv_rounded,
      posterUrl: viewModel.posterUrl,
      posterHeaders: viewModel.posterHeaders,
      backdropUrl: viewModel.backdropUrl,
      title: viewModel.title,
      posterRow: _buildPosterRow(context, viewModel, status),
      // Both loads share one outage, so one pull re-runs both — the same pair the
      // retry button re-runs.
      onRefresh: widget.seriesId > 0
          ? () async {
              ref.invalidate(seriesDetailForProvider(detailRef));
              ref.invalidate(seriesEpisodesForProvider(detailRef));
            }
          : null,
      body: _buildBody(
        viewModel,
        status,
        infoGroups,
        episodesAsync,
        series.id > 0 ? series.id : widget.seriesId,
        series.tmdbId,
        series.tvdbId,
      ),
    );
  }

  /// `41/48 episodes` — how much of the manifest exists, for the hero chip slot.
  String? _episodeCounter(SeriesDetailViewModel viewModel) {
    final counts = viewModel.diskCounts;
    if (counts == null) return null;
    return '${counts.onDisk}/${counts.expected} episodes';
  }

  String? _seasonCounter(SeriesDetailViewModel viewModel) {
    final seasons = viewModel.seasonCount ?? 0;
    if (seasons <= 0) return null;
    return '$seasons ${seasons == 1 ? 'season' : 'seasons'}';
  }

  void _syncQualityProfiles(SonarrSeries series) {
    if (series.id <= 0 || series.path?.isNotEmpty != true) {
      return;
    }

    ensureQualityProfiles(
      profileId: series.qualityProfileId,
      fetchProfiles: () => _sonarr.getQualityProfiles(),
    );
  }

  Widget _buildPosterRow(
    BuildContext context,
    SeriesDetailViewModel viewModel,
    MediaStatusInfo status,
  ) {
    final episodeCounter = _episodeCounter(viewModel);
    final seasonCounter = _seasonCounter(viewModel);

    return MediaDetailPosterRow(
      statusBadge: StatusBadge.animated(info: status),
      title: viewModel.title,
      // The season/episode summary moved into the chip slot below, so it is
      // stated once rather than in the metadata line and in a chip.
      metadataItems: [
        viewModel.year,
        if (viewModel.runtimeStr != null) viewModel.runtimeStr!,
      ].where((item) => item.isNotEmpty).toList(growable: false),
      // One meaning for the chip slot on every variant: how much of the manifest
      // exists. Genres moved to the catalogue block below.
      tags: [
        if (episodeCounter != null)
          TagChip(text: episodeCounter, color: ServiceKey.sonarr.accent),
        if (seasonCounter != null)
          TagChip(text: seasonCounter, color: ServiceKey.sonarr.accent),
      ],
      posterCard: MediaPosterCard(
        heroTag: widget.heroTag,
        imageUrl: viewModel.posterUrl,
        imageHeaders: viewModel.posterHeaders,
        fallbackIcon: Icons.tv_outlined,
      ),
    );
  }

  MediaDetailBody _buildBody(
    SeriesDetailViewModel viewModel,
    MediaStatusInfo status,
    List<MediaInfoGroup> infoGroups,
    AsyncValue<List<SonarrEpisode>> episodesAsync,
    int seriesId,
    int tmdbId,
    int tvdbId,
  ) {
    final accent = ServiceKey.sonarr.accent;

    // Decision 25 — the profile is edited where it is read, not from the deck's
    // ⋯ menu. The write already exists and asks first, because changing a
    // profile can start an upgrade search that cannot be called back.
    //
    // Series type is the other field that ships, and it is edited the same way
    // one cell over (`SeriesTypeRow`, in the grid). Root folder and tags are
    // drawn on the board and neither has a write here — a generic
    // read-modify-PUT for the first, `GET /api/v3/tag` for the second — and a
    // picker with nothing behind it is a control that fails in the user's hand.
    final profileRow = viewModel.isInLibrary && qualityProfiles.isNotEmpty
        ? MediaDetailValueRow<int>(
            label: 'Quality profile',
            value: currentProfileId,
            options: qualityProfileOptions(qualityProfiles),
            onChanged: (profileId) =>
                _updateProfile(profileId, mediaTitle: viewModel.title),
            accent: accent,
            hint: 'Changes it on Sonarr',
          )
        : null;
    final counts = viewModel.diskCounts;

    return MediaDetailBody(
      // Sonarr's column, and it is not Radarr's. The wide track is the season
      // table — a table is the widest thing on this page and the reason the
      // spine stopped capping tables at the reading measure — and the Overview
      // rides with it, because on a series the synopsis is a caption to the
      // manifest rather than the subject. The 380 column takes the fact grid and
      // the catalogue.
      sideTrack: const {'Details', 'Scores', 'Genres', 'Collection'},
      deck: viewModel.isInLibrary
          ? LibraryDetailActions(
              service: ServiceKey.sonarr,
              status: status,
              mediaTitle: viewModel.title,
              isMonitored: viewModel.isMonitored,
              partialSummary: counts == null
                  ? null
                  : '${counts.onDisk} of ${counts.expected} episodes on disk.',
              isBusy: isAutoSearching || isUpdatingMonitoredState || isDeleting,
              isConfirmed: isAutoSearchConfirmed,
              onSearch: () => _triggerSearch(context),
              onInteractiveSearch: () =>
                  _showInteractiveSearch(context, title: viewModel.title),
              onImport: openManualImportCallback(
                context,
                ServiceKey.sonarr,
                seriesId,
                instanceId: _instanceId,
              ),
              // Every in-flight pipeline state promotes 'Open queue' only if the
              // host actually has a route for it; without this the most common
              // transient state on a real page degraded to a sentence. Pushed, not
              // gone: checking on a download should leave the title behind you.
              onOpenQueue: () => context.push('/activity/series'),
              onMonitoredChanged: (monitored) => _updateMonitoredState(
                context,
                seriesId: seriesId,
                monitored: monitored,
              ),
              onDelete: () => _confirmDelete(context, title: viewModel.title),
            )
          // See the Radarr screen: no add path from this view, so an untracked
          // title gets a sentence instead of a CTA that apologises.
          : const MediaDetailUnavailableSection(
              message:
                  'Sonarr is not tracking this series, so there is nothing to '
                  'manage here yet. Add it in Sonarr, or request it in Seerr.',
            ),
      // Region 3 — the manifest: the episodes Sonarr expects under this title,
      // checked against what actually arrived. It sits above the synopsis
      // because prose about a show is never more operational than the list of
      // episodes you are missing.
      operate: [
        if (viewModel.isInLibrary) ...[
          MediaDetailSlot.lazy(
            label: 'Seasons',
            count: counts == null
                ? null
                : '${counts.onDisk} of ${counts.expected} on disk',
            // `# · Episode · Aired · File` is read down its columns, so the
            // reading measure that keeps prose at 720 does not apply: capping it
            // there inside a 1000pt window is a table with a 155pt margin on
            // each side and four columns fighting for what is left.
            measure: MediaDetailMeasure.track,
            // State at the point of intent: a live search for this title's
            // primary target rewrites what the action would have promised. The
            // caller owns this box's gutter — see MediaDetailSlot.leadingBox.
            leadingBox: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: ReleaseSearchStatusCard(
                target: sonarrSeasonTarget(
                  seriesId: widget.seriesId,
                  seasonNumber: null,
                  label: truncateTitle(viewModel.title),
                ),
              ),
            ),
            // A lazy sliver mid-page: a 250-episode season builds the rows on
            // screen instead of all 250 inside one box adapter.
            sliver: SeriesSeasonsList(
              seasons: viewModel.seasons,
              episodesAsync: episodesAsync,
              // State only at the granularity it was launched: a season header
              // shows its own search, an episode row its own — never each
              // other's.
              seasonIndicator: (seasonNumber) => ReleaseSearchRowChip(
                // Stamped: target equality includes the connection, so an
                // unstamped one matches no running job and the dot never
                // lights.
                target: ReleaseSearchTarget.season(
                  seriesId: widget.seriesId,
                  seasonNumber: seasonNumber,
                  label: 'Season $seasonNumber',
                ).stampedWith(_instanceId),
              ),
              episodeIndicator: (episode) => ReleaseSearchRowDot(
                target: ReleaseSearchTarget.episode(
                  episodeId: episode.id,
                  seriesId: widget.seriesId,
                  seasonNumber: episode.seasonNumber,
                  label: 'Episode ${episode.episodeNumber}',
                ).stampedWith(_instanceId),
              ),
              onSearchSeason: (seasonNumber) =>
                  _searchSeason(context, seasonNumber),
              onInteractiveSearchSeason: (seasonNumber) =>
                  _interactiveSearchSeason(
                    context,
                    seasonNumber,
                    title: viewModel.title,
                  ),
              onSearchEpisode: (episodeId) =>
                  _searchEpisode(context, episodeId),
              onInteractiveSearchEpisode: (episodeId, seasonNumber) =>
                  _interactiveSearchEpisode(
                    context,
                    episodeId,
                    seasonNumber: seasonNumber,
                    title: viewModel.title,
                  ),
              searchingSeasons: _searchingSeasons,
              searchingEpisodes: _searchingEpisodes,
              // The episodes alone, on the key the page watches them under:
              // the series above them answered, so asking for it again would
              // only repaint what is already right.
              onRetryEpisodes: () => ref.invalidate(
                seriesEpisodesForProvider((
                  instanceId: _instanceId,
                  id: widget.seriesId,
                )),
              ),
            ),
          ),
          if (viewModel.hasFiles && viewModel.path != null)
            MediaDetailSlot.box(
              label: 'Files',
              child: FileInfoSection(path: viewModel.path, accent: accent),
            ),
        ],
      ],
      synopsis: [
        if (viewModel.overview.isNotEmpty)
          MediaDetailSlot.box(
            label: 'Overview',
            child: MediaProseSection(text: viewModel.overview, accent: accent),
          ),
      ],
      reference: [
        if (infoGroups.isNotEmpty || profileRow != null)
          MediaDetailSlot.box(
            label: 'Details',
            child: AppCard.surfaceOutlined(
              child: MediaInfoCard(rows: [?profileRow], groups: infoGroups),
            ),
          ),
        if (viewModel.ratings.isNotEmpty)
          MediaDetailSlot.box(
            label: 'Scores',
            // See the Radarr screen: one legible source name per pill, and for
            // Sonarr's single-source payload it also fixes what a screen reader
            // says — the parser puts a vote count in the name field, so the pill
            // used to announce itself as "145000 voti rating 7.2".
            child: RatingChipsRow(
              ratings: legibleRatings(viewModel.ratings),
              accent: accent,
            ),
          ),
        if (viewModel.genres.isNotEmpty)
          MediaDetailSlot.box(
            // Not 'Tags' — a Sonarr tag targets release profiles and import
            // lists, and these are genres.
            label: 'Genres',
            child: MediaChipSection.neutral(values: viewModel.genres),
          ),
      ],
      // See the movie screen: labelled slots, each omitted when empty.
      related: [
        // Sonarr's own identifier is the TVDB one, so the join goes through that
        // rather than through `tmdbId`: both servers index it, and matching on a
        // title across two catalogues would be a guess.
        ...streamAvailabilitySlots(
          ref,
          accent: accent,
          tvdbId: tvdbId == 0 ? null : '$tvdbId',
          tmdbId: tmdbId == 0 ? null : '$tmdbId',
          kind: StreamItemKind.series,
          title: viewModel.title,
          year: int.tryParse(viewModel.year),
        ),
        ...arrMediaExtrasSlots(
          ref,
          tmdbId: tmdbId,
          mediaType: 'tv',
          accent: accent,
        ),
      ],
    );
  }

  Future<void> _updateMonitoredState(
    BuildContext context, {
    required int seriesId,
    required bool monitored,
  }) {
    return setMonitored(
      context: context,
      serviceName: 'Sonarr',
      subject: 'series',
      monitored: monitored,
      // `_sonarr`, not `sonarrServiceProvider`. This wrote through the lens
      // while the file above declares that every read and every write goes
      // through the page's own connection: with two Sonarrs configured, a page
      // opened for the 4K one sent its monitor flag to the other, carrying a
      // seriesId that names a different show there.
      write: () => _sonarr.updateSeriesMonitored(seriesId, monitored),
      invalidate: [
        seriesDetailForProvider((instanceId: _instanceId, id: seriesId)),
        seriesProvider,
      ],
    );
  }

  /// Writes the new series type and re-reads the page.
  ///
  /// Not routed through [ArrDetailActionsMixin]: its helpers each own one verb
  /// (monitor, profile, delete, search) and this is a fifth. The shape is the
  /// same — guard, write, confirm in words, invalidate — and the guard matters
  /// more here than elsewhere, because the write reads the whole series
  /// resource and puts it back, so two of them racing lose whichever landed
  /// first.
  Future<void> _updateSeriesType(
    BuildContext context, {
    required int seriesId,
    required SonarrSeriesType type,
  }) async {
    if (_isUpdatingSeriesType) return;
    setState(() => _isUpdatingSeriesType = true);
    try {
      await _sonarr.updateSeriesType(seriesId, type.wireValue);
      if (!context.mounted) return;
      // Names the consequence, not the field: "Series type set to Anime" says
      // what was clicked, and the user already knows that.
      SnackBarHelper.success(
        context,
        'Sonarr will number this series as ${type.label.toLowerCase()}',
      );
      ref.invalidate(
        seriesDetailForProvider((instanceId: _instanceId, id: seriesId)),
      );
      ref.invalidate(seriesProvider);
    } catch (e) {
      if (!context.mounted) return;
      SnackBarHelper.error(
        context,
        "Couldn't change the series type in Sonarr.",
        detail: e,
      );
    } finally {
      if (mounted) setState(() => _isUpdatingSeriesType = false);
    }
  }

  Future<void> _triggerSearch(BuildContext context) {
    return triggerSearch(
      context: context,
      serviceName: 'Sonarr',
      // "<Service> is searching <what>", the shape every library page uses. The
      // scope matters here more than anywhere: this one search covers every
      // monitored episode of the show.
      successMessage: 'Sonarr is searching for every monitored episode',
      search: () => _sonarr.searchSeries(widget.seriesId),
    );
  }

  Future<void> _showInteractiveSearch(
    BuildContext context, {
    required String title,
    int? seasonNumber,
  }) async {
    // The sheet titles itself "Releases" and this lands in the subtitle, so
    // "Releases for X" said it twice. Capped: the subtitle has no maxLines, and
    // a long show name plus a season suffix used to grow the header until it
    // crowded out the list.
    await showReleaseSearch(
      context,
      ref,
      sonarrSeasonTarget(
        seriesId: widget.seriesId,
        seasonNumber: seasonNumber,
        label: seasonNumber != null
            ? '${truncateTitle(title)} · Season $seasonNumber'
            : truncateTitle(title),
      ).stampedWith(_instanceId),
    );
  }

  Future<void> _searchSeason(BuildContext context, int seasonNumber) async {
    HapticFeedback.selectionClick();
    setState(() => _searchingSeasons.add(seasonNumber));
    try {
      final sonarrService = _sonarr;
      await sonarrService.searchSeason(widget.seriesId, seasonNumber);
      if (!context.mounted) return;
      SnackBarHelper.success(
        context,
        'Sonarr is searching Season $seasonNumber',
      );
    } catch (e) {
      if (!context.mounted) return;
      SnackBarHelper.error(
        context,
        "Couldn't start a search for Season $seasonNumber in Sonarr.",
        detail: e,
      );
    } finally {
      if (mounted) setState(() => _searchingSeasons.remove(seasonNumber));
    }
  }

  Future<void> _interactiveSearchSeason(
    BuildContext context,
    int seasonNumber, {
    required String title,
  }) async {
    setState(() => _searchingSeasons.add(seasonNumber));
    try {
      await _showInteractiveSearch(
        context,
        title: title,
        seasonNumber: seasonNumber,
      );
    } finally {
      if (mounted) setState(() => _searchingSeasons.remove(seasonNumber));
    }
  }

  Future<void> _searchEpisode(BuildContext context, int episodeId) async {
    HapticFeedback.selectionClick();
    setState(() => _searchingEpisodes.add(episodeId));
    try {
      final sonarrService = _sonarr;
      await sonarrService.searchEpisodes([episodeId]);
      if (!context.mounted) return;
      SnackBarHelper.success(context, 'Sonarr is searching this episode');
    } catch (e) {
      if (!context.mounted) return;
      SnackBarHelper.error(
        context,
        "Couldn't start a search for this episode.",
        detail: e,
      );
    } finally {
      if (mounted) setState(() => _searchingEpisodes.remove(episodeId));
    }
  }

  Future<void> _interactiveSearchEpisode(
    BuildContext context,
    int episodeId, {
    required String title,
    required int seasonNumber,
  }) async {
    // "Episode Releases" under a heading that already reads "Releases" named
    // neither the show nor which scope was searched. This says both, in the
    // same shape as the series and season sheets.
    //
    // seriesId and seasonNumber travel with the target so this episode can be
    // recognised as part of a season that may already be searching.
    await showReleaseSearch(
      context,
      ref,
      ReleaseSearchTarget.episode(
        episodeId: episodeId,
        seriesId: widget.seriesId,
        seasonNumber: seasonNumber,
        label: '${truncateTitle(title)} · one episode',
      ).stampedWith(_instanceId),
    );
  }

  Future<void> _updateProfile(int profileId, {required String mediaTitle}) {
    return changeProfile(
      profileId: profileId,
      mediaTitle: mediaTitle,
      serviceName: 'Sonarr',
      consequence: 'upgrades across every monitored episode',
      // See _updateMonitoredState: the page's connection, not the lens.
      write: () => _sonarr.updateSeriesProfile(widget.seriesId, profileId),
      invalidate: [seriesProvider],
    );
  }

  Future<void> _confirmDelete(BuildContext context, {required String title}) {
    return confirmDelete(
      context: context,
      serviceName: 'Sonarr',
      subject: 'series',
      title: title,
      mediaType: DeleteMediaType.series,
      // The one that made the lens bug destructive: a delete aimed at the lens
      // with this page's seriesId removes whatever holds that id over there.
      write: (deleteFiles, addExclusion) => _sonarr.deleteSeries(
        widget.seriesId,
        deleteFiles: deleteFiles,
        addImportListExclusion: addExclusion,
      ),
    );
  }
}
