import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/api/arr_detail_actions_mixin.dart';
import 'package:cupola/core/api/quality_profile_mixin.dart';
import 'package:cupola/core/utils/rating_display.dart';
import 'package:cupola/core/utils/string_utils.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/discover/presentation/widgets/arr_media_extras_section.dart';
import 'package:cupola/features/release_search/domain/release_search_target.dart';
import 'package:cupola/features/release_search/presentation/release_search_entry.dart';
import 'package:cupola/features/release_search/presentation/widgets/release_search_status_card.dart';
import 'package:cupola/features/stream/presentation/widgets/stream_availability_slot.dart';
import 'package:cupola/features/import/presentation/manual_import_routes.dart';
import 'package:cupola/features/movies/data/radarr_service.dart';
import 'package:cupola/features/movies/domain/models/radarr_movie.dart';
import 'package:cupola/features/movies/domain/radarr_status.dart';
import 'package:cupola/features/movies/presentation/movie_detail_provider.dart';
import 'package:cupola/features/movies/presentation/movie_detail_view_model.dart';
import 'package:cupola/features/movies/presentation/movies_provider.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// Detail screen for a Radarr movie with M3 styling.
class MovieDetailScreen extends ConsumerStatefulWidget {
  final int movieId;
  final String heroTag;
  final RadarrMovie? initialMovie;

  /// The connection this page belongs to, from the route's `?i=`.
  ///
  /// Null for every link that does not name one, which is all of them outside
  /// a multi-connection search — and then the page reads through the lens, as
  /// it always did.
  ///
  /// **Load-bearing for the whole page, not just the fetch.** A page shown for
  /// one Radarr while its queue badge, its quality profile and its poster came
  /// from another is worse than a page that failed to load: every part of it
  /// looks right. So the id resolved here is the one every source below is
  /// keyed on.
  final String? instanceId;

  const MovieDetailScreen({
    super.key,
    required this.movieId,
    required this.heroTag,
    this.initialMovie,
    this.instanceId,
  });

  @override
  ConsumerState<MovieDetailScreen> createState() => _MovieDetailScreenState();
}

class _MovieDetailScreenState extends ConsumerState<MovieDetailScreen>
    with
        QualityProfileMixin<MovieDetailScreen>,
        ArrDetailActionsMixin<MovieDetailScreen> {
  /// The connection resolved in the last build, for the callbacks to reuse.
  ///
  /// Held rather than re-resolved, because `effectiveInstanceId` watches the
  /// lens and a callback is not a build. The two can only disagree between a
  /// lens move and the frame that follows it, and a write is dispatched from a
  /// frame the user is looking at.
  String _instanceId = '';

  /// Radarr, bound to the connection this page belongs to.
  ///
  /// Every read AND every write on this screen goes through it. Reading through
  /// the lens instead is how a page opened for one server sends its "search for
  /// this movie" to another — with a `movieId` that names a different film
  /// there.
  RadarrService get _radarr => _instanceId.isEmpty
      ? ref.read(radarrServiceProvider)
      : ref.read(radarrServiceForProvider(_instanceId));

  @override
  Widget build(BuildContext context) {
    final instanceId = effectiveInstanceId(
      ref,
      ServiceKey.radarr,
      widget.instanceId,
    );
    _instanceId = instanceId;
    final connection = ref.watch(
      currentSettingsProvider.select((s) => s.instanceById(instanceId)),
    );
    final item = (instanceId: instanceId, id: widget.movieId);
    final movieAsync = widget.movieId > 0
        ? ref.watch(movieDetailForProvider(item))
        : const AsyncData<RadarrMovie?>(null);
    final movie = movieAsync.asData?.value ?? widget.initialMovie;

    if (movie == null) {
      if (movieAsync.isLoading) {
        return MediaDetailLoadingView(
          accent: ServiceKey.radarr.accent,
          heroFallbackIcon: Icons.movie_outlined,
        );
      }

      return MediaDetailPlaceholderView.error(
        error: movieAsync.asError?.error ?? 'Movie not found.',
        serviceName: 'Radarr',
        accent: ServiceKey.radarr.accent,
        // Recover in place. With no id there is no provider to re-run, so the
        // retry is withheld rather than offered and doing nothing.
        onRetry: widget.movieId > 0
            ? () => ref.invalidate(movieDetailForProvider(item))
            : null,
      );
    }

    _syncQualityProfiles(movie);

    // The connection this page is bound to, not `settings.radarrUrl` — that
    // resolves to the FIRST Radarr, so a poster served by the arr rather than
    // by TMDB was fetched from one server with another's key.
    final viewModel = MovieDetailViewModel.fromMovie(
      movie,
      baseUrl: connection?.url ?? '',
      apiKey: connection?.credential ?? '',
    );
    // An empty profile name on purpose, which drops the read-only `Profile`
    // cell from the grid: decision 25 moves that field to an editable row above
    // it, and a value offered twice is a value the user has to guess about.
    final infoGroups = viewModel.buildInfoGroups('');

    // Without the queue the badge cannot tell "nothing on disk" from "being
    // downloaded right now", and every in-flight movie reads as Missing.
    final queueEntry = ref
        .watch(radarrQueueSnapshotForProvider(instanceId))
        .maybeWhen(
          data: (snapshot) => snapshot.entryFor(movie.id),
          orElse: () => null,
        );
    final status = radarrMovieStatus(movie, queueEntry: queueEntry);

    return MediaDetailView(
      accent: ServiceKey.radarr.accent,
      heroFallbackIcon: Icons.movie_outlined,
      posterUrl: viewModel.posterUrl,
      posterHeaders: viewModel.posterHeaders,
      backdropUrl: viewModel.backdropUrl,
      title: viewModel.title,
      posterRow: _buildPosterRow(context, viewModel, status),
      // The same load the retry button re-runs, on the gesture the hero was
      // already accepting and doing nothing with.
      onRefresh: widget.movieId > 0
          ? () async => ref.invalidate(movieDetailForProvider(item))
          : null,
      body: _buildBody(
        viewModel,
        status,
        infoGroups,
        movie.id > 0 ? movie.id : widget.movieId,
        movie.tmdbId,
      ),
    );
  }

  void _syncQualityProfiles(RadarrMovie movie) {
    if (movie.id <= 0 || movie.path?.isNotEmpty != true) {
      return;
    }

    ensureQualityProfiles(
      profileId: movie.qualityProfileId,
      fetchProfiles: () => _radarr.getQualityProfiles(),
    );
  }

  Widget _buildPosterRow(
    BuildContext context,
    MovieDetailViewModel viewModel,
    MediaStatusInfo status,
  ) {
    return MediaDetailPosterRow(
      statusBadge: StatusBadge.animated(info: status),
      title: viewModel.title,
      metadataItems: viewModel.metadataItems,
      // The hero's chip slot has one meaning on every variant: how much of the
      // manifest exists. Genres moved to the catalogue block below, where they
      // now appear exactly once instead of in the hero *and* in a section
      // mislabelled "Tags".
      tags: [
        TagChip(
          text: viewModel.hasFile ? '1 file' : 'No file',
          color: ServiceKey.radarr.accent,
        ),
      ],
      posterCard: MediaPosterCard(
        heroTag: widget.heroTag,
        imageUrl: viewModel.posterUrl,
        imageHeaders: viewModel.posterHeaders,
        fallbackIcon: Icons.movie_outlined,
      ),
    );
  }

  MediaDetailBody _buildBody(
    MovieDetailViewModel viewModel,
    MediaStatusInfo status,
    List<MediaInfoGroup> infoGroups,
    int movieId,
    int tmdbId,
  ) {
    final accent = ServiceKey.radarr.accent;

    // Decision 25 — the profile is edited where it is read, not from the deck's
    // ⋯ menu. The write already exists and asks first, because changing a
    // profile can start an upgrade search that cannot be called back.
    //
    // **This is the only field that ships.** Root folder, minimum
    // availability and tags are drawn on the board and every one needs a
    // write this client does not have — a generic read-modify-PUT for the
    // first, `GET /api/v3/tag` for the rest — and a picker with nothing
    // behind it is a control that fails in the user's hand.
    final profileRow = viewModel.isInLibrary && qualityProfiles.isNotEmpty
        ? MediaDetailValueRow<int>(
            label: 'Quality profile',
            value: currentProfileId,
            options: qualityProfileOptions(qualityProfiles),
            onChanged: (profileId) =>
                _updateProfile(profileId, mediaTitle: viewModel.title),
            accent: accent,
            hint: 'Changes it on Radarr',
          )
        : null;

    return MediaDetailBody(
      // Radarr's own column, not a shared one. The wide track carries what the
      // server is doing about this film — the file, whether a media server can
      // already play it, the search strip — and the 380 column carries what the
      // film *is*: the overview, the fact grid, the scores and genres, the rest
      // of its collection. Cast stays wide: faces at 380 are four to a row and
      // the rail exists to be scrolled.
      sideTrack: const {
        'Overview',
        'Details',
        'Scores',
        'Genres',
        'Collection',
      },
      deck: viewModel.isInLibrary
          ? LibraryDetailActions(
              service: ServiceKey.radarr,
              status: status,
              mediaTitle: viewModel.title,
              isMonitored: viewModel.isMonitored,
              // One flag, mapped from whichever per-action flag can be in flight
              // on this page: only one action is ever promoted.
              isBusy: isAutoSearching || isUpdatingMonitoredState || isDeleting,
              isConfirmed: isAutoSearchConfirmed,
              onSearch: () => _triggerSearch(context),
              onInteractiveSearch: () =>
                  _showInteractiveSearch(context, title: viewModel.title),
              onImport: openManualImportCallback(
                context,
                ServiceKey.radarr,
                movieId,
              ),
              // Every in-flight pipeline state promotes 'Open queue' only if the
              // host actually has a route for it; without this the most common
              // transient state on a real page degraded to a sentence. Pushed, not
              // gone: checking on a download should leave the title behind you.
              onOpenQueue: () => context.push('/activity/movies'),
              onMonitoredChanged: (monitored) => _updateMonitoredState(
                context,
                movieId: movieId,
                monitored: monitored,
              ),
              onDelete: () => _confirmDelete(context, title: viewModel.title),
            )
          // No add path exists from this view, so an untracked title falls
          // through to a sentence rather than to the full-width accent CTA whose
          // only behaviour was a snackbar saying it is not available.
          : const MediaDetailUnavailableSection(
              message:
                  'Radarr is not tracking this movie, so there is nothing to '
                  'manage here yet. Add it in Radarr, or request it in Seerr.',
            ),
      // Region 3 — the manifest. A movie has no child records, so the manifest
      // is the file, and the path a self-hoster actually hunts for lives here
      // rather than at the bottom of an encyclopaedic grid.
      operate: [
        if (viewModel.isInLibrary)
          MediaDetailSlot.box(
            child: ReleaseSearchStatusCard(
              // Stamped with the page's own connection: the job the card is
              // looking for was started against this server, and target
              // equality now includes it — an unstamped target matches nothing
              // and the card stays blank for the whole search.
              target: ReleaseSearchTarget.movie(
                movieId: widget.movieId,
                label: truncateTitle(viewModel.title),
              ).stampedWith(_instanceId),
            ),
          ),
        if (viewModel.isInLibrary)
          MediaDetailSlot.box(
            label: 'File',
            child: viewModel.hasFile && viewModel.path != null
                ? FileInfoSection(
                    path: viewModel.path,
                    filename: viewModel.filename,
                    accent: accent,
                  )
                // One footprint in both states: the region does not jump when a
                // file arrives, and the hint spends its two lines suggesting the
                // route the promoted "Automatic search" button does not cover.
                : FileInfoSection.missing(accent: accent),
          ),
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
            // Through `legibleRatings` so a pill names its source the way the
            // source names itself. Radarr's keys arrive as `metacritic`,
            // `rottenTomatoes`, `trakt` and the parser badges them `MC`, `RO`,
            // `TR` — abbreviations that appear nowhere else in the app and are
            // not what anyone calls those sites.
            child: RatingChipsRow(
              ratings: legibleRatings(viewModel.ratings),
              accent: accent,
            ),
          ),
        if (viewModel.genres.isNotEmpty)
          MediaDetailSlot.box(
            // Not 'Tags': in this domain a tag is a Radarr concept that targets
            // release profiles and import lists, so calling genres tags
            // asserted something false about the user's server.
            label: 'Genres',
            child: MediaChipSection.neutral(values: viewModel.genres),
          ),
      ],
      // One `CAST` slot and one `COLLECTION` slot, each labelled by the spine and
      // each omitted when Seerr has nothing for it — rather than one
      // undifferentiated extras section that drew its own headings.
      related: [
        // "On Jellyfin · 34 min in" — the pipeline closing. Radarr answers "do I
        // own it"; only a media server knows whether anyone can play it and where
        // they stopped. Omitted entirely when there is nothing to say, so it never
        // leaves a labelled region over empty air.
        ...streamAvailabilitySlots(
          ref,
          accent: accent,
          tmdbId: tmdbId == 0 ? null : '$tmdbId',
        ),
        ...arrMediaExtrasSlots(
          ref,
          tmdbId: tmdbId,
          mediaType: 'movie',
          accent: accent,
        ),
      ],
    );
  }

  Future<void> _updateMonitoredState(
    BuildContext context, {
    required int movieId,
    required bool monitored,
  }) {
    return setMonitored(
      context: context,
      serviceName: 'Radarr',
      subject: 'movie',
      monitored: monitored,
      write: () => _radarr.updateMovieMonitored(movieId, monitored),
      // The page's own connection, not the lens: invalidating the lens-keyed
      // family would refresh a page nobody is looking at and leave this one
      // showing the state it had before the write.
      invalidate: [
        movieDetailForProvider((instanceId: _instanceId, id: movieId)),
        moviesProvider,
      ],
    );
  }

  Future<void> _updateProfile(int profileId, {required String mediaTitle}) {
    return changeProfile(
      profileId: profileId,
      mediaTitle: mediaTitle,
      serviceName: 'Radarr',
      consequence: 'an upgrade',
      write: () => _radarr.updateMovieProfile(widget.movieId, profileId),
      invalidate: [moviesProvider],
    );
  }

  Future<void> _confirmDelete(BuildContext context, {required String title}) {
    return confirmDelete(
      context: context,
      serviceName: 'Radarr',
      subject: 'movie',
      title: title,
      mediaType: DeleteMediaType.movie,
      write: (deleteFiles, addExclusion) => _radarr.deleteMovie(
        widget.movieId,
        deleteFiles: deleteFiles,
        addImportExclusion: addExclusion,
      ),
    );
  }

  Future<void> _triggerSearch(BuildContext context) {
    return triggerSearch(
      context: context,
      serviceName: 'Radarr',
      // One shape for every search confirmation on every library page:
      // "<Service> is searching <what>". The old set drifted between "Search
      // started", "Search started for entire series" and "Album search
      // started", which read as three different features.
      successMessage: 'Radarr is searching for this movie',
      search: () => _radarr.searchMovie(widget.movieId),
    );
  }

  Future<void> _showInteractiveSearch(
    BuildContext context, {
    required String title,
  }) async {
    // The sheet's own heading is already "Releases" and this string lands in
    // the subtitle beneath it, so "Releases for X" printed the word twice.
    // Capped because the subtitle Text has no maxLines: a long title used to
    // grow the header until it ate the list it was introducing.
    await showReleaseSearch(
      context,
      ref,
      ReleaseSearchTarget.movie(
        movieId: widget.movieId,
        label: truncateTitle(title),
      ).stampedWith(_instanceId),
    );
  }
}
