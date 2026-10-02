import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/api/arr_detail_actions_mixin.dart';
import 'package:cupola/core/api/quality_profile_mixin.dart';
import 'package:cupola/core/status/arr_queue_snapshot.dart';
import 'package:cupola/core/utils/rating_display.dart';
import 'package:cupola/core/utils/snack_bar_helper.dart';
import 'package:cupola/core/utils/string_utils.dart';
import 'package:cupola/core/widgets/connection_badge.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/import/presentation/manual_import_routes.dart';
import 'package:cupola/features/music/data/lidarr_service.dart';
import 'package:cupola/features/music/domain/lidarr_status.dart';
import 'package:cupola/features/music/domain/models/lidarr_album.dart';
import 'package:cupola/features/music/domain/lidarr_queue_snapshots.dart';
import 'package:cupola/features/music/domain/models/lidarr_artist.dart';
import 'package:cupola/features/music/presentation/music_detail_provider.dart';
import 'package:cupola/features/music/presentation/music_detail_view_model.dart';
import 'package:cupola/features/music/presentation/music_provider.dart';
import 'package:cupola/features/music/presentation/widgets/music_albums_list.dart';
import 'package:cupola/features/release_search/domain/release_search_target.dart';
import 'package:cupola/features/release_search/presentation/release_search_entry.dart';
import 'package:cupola/features/release_search/presentation/widgets/release_search_status_card.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/connection_presentation.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

class MusicDetailScreen extends ConsumerStatefulWidget {
  final int artistId;
  final String heroTag;
  final LidarrArtist? initialArtist;

  /// The connection this page belongs to, from the route's `?i=`. Null falls
  /// through to the lens — see [MovieDetailScreen.instanceId] for why every
  /// source on the page has to agree with it.
  final String? instanceId;

  const MusicDetailScreen({
    super.key,
    required this.artistId,
    required this.heroTag,
    this.initialArtist,
    this.instanceId,
  });

  @override
  ConsumerState<MusicDetailScreen> createState() => _MusicDetailScreenState();
}

class _MusicDetailScreenState extends ConsumerState<MusicDetailScreen>
    with
        QualityProfileMixin<MusicDetailScreen>,
        ArrDetailActionsMixin<MusicDetailScreen> {
  final Set<int> _searchingAlbums = {};

  /// The connection resolved in the last build, for the callbacks to reuse —
  /// see [_MovieDetailScreenState] for why it is held rather than re-resolved.
  String _instanceId = '';

  /// Lidarr, bound to the connection this page belongs to. Every read and
  /// every write on this screen goes through it.
  LidarrService get _lidarr => _instanceId.isEmpty
      ? ref.read(lidarrServiceProvider)
      : ref.read(lidarrServiceForProvider(_instanceId));

  @override
  Widget build(BuildContext context) {
    final instanceId = effectiveInstanceId(
      ref,
      ServiceKey.lidarr,
      widget.instanceId,
    );
    _instanceId = instanceId;
    final connection = ref.watch(
      currentSettingsProvider.select((s) => s.instanceById(instanceId)),
    );
    final detailRef = (instanceId: instanceId, id: widget.artistId);
    final artistAsync = widget.artistId > 0
        ? ref.watch(musicDetailForProvider(detailRef))
        : const AsyncData<LidarrArtist?>(null);
    final albumsAsync = widget.artistId > 0
        ? ref.watch(musicAlbumsForProvider(detailRef))
        : const AsyncData<List<LidarrAlbum>>(<LidarrAlbum>[]);
    final artist = artistAsync.asData?.value ?? widget.initialArtist;

    if (artist == null) {
      if (artistAsync.isLoading) {
        return MediaDetailLoadingView(
          accent: ServiceKey.lidarr.accent,
          heroFallbackIcon: Icons.album_outlined,
        );
      }

      return MediaDetailPlaceholderView.error(
        error: artistAsync.asError?.error ?? 'Artist not found.',
        serviceName: 'Lidarr',
        accent: ServiceKey.lidarr.accent,
        // Recover in place. Both loads share one outage, so one retry re-runs
        // both. With no id there is no provider to re-run, so no retry is
        // offered rather than one that does nothing.
        onRetry: widget.artistId > 0
            ? () {
                ref.invalidate(musicDetailForProvider(detailRef));
                ref.invalidate(musicAlbumsForProvider(detailRef));
              }
            : null,
      );
    }

    _syncQualityProfiles(artist);

    final viewModel = MusicDetailViewModel.fromArtist(
      artist,
      // The page's own connection, never `lidarrUrl` — that is the first one.
      baseUrl: connection?.url ?? '',
      apiKey: connection?.credential ?? '',
    );
    // An empty profile name on purpose: decision 25 moves that field out of the
    // read-only grid and onto an editable row above it.
    final infoGroups = viewModel.buildInfoGroups('');

    // One fetch feeds both the artist badge and the per-album badges below,
    // unknown until it answers: a queue nobody read cannot say an album with
    // nothing on disk is not on its way. The page's own connection's queue,
    // never the lens's: the ids in it are that server's.
    final queues = lidarrQueueSnapshotsOf(
      ref.watch(lidarrQueueSnapshotsForProvider(instanceId)),
    );
    final status = lidarrArtistStatus(
      artist,
      queueEntry: queues.byArtist.entryFor(artist.id),
      queueUnknown: !queues.byArtist.isWhole,
    );

    return MediaDetailView(
      accent: ServiceKey.lidarr.accent,
      heroFallbackIcon: Icons.album_outlined,
      posterUrl: viewModel.posterUrl,
      posterHeaders: viewModel.posterHeaders,
      backdropUrl: viewModel.backdropUrl,
      title: viewModel.title,
      posterRow: _buildPosterRow(
        context,
        viewModel,
        badgeOverQueue(status, queues.byArtist),
      ),
      onRefresh: widget.artistId > 0
          ? () async {
              ref.invalidate(musicDetailForProvider(detailRef));
              ref.invalidate(musicAlbumsForProvider(detailRef));
              ref.invalidate(lidarrQueueSnapshotsForProvider(instanceId));
            }
          : null,
      body: _buildBody(
        context,
        viewModel,
        status,
        infoGroups,
        connection,
        albumsAsync,
        queues.byAlbum,
        artist.id > 0 ? artist.id : widget.artistId,
        band: _staleQueueLine(
          queues,
          instanceId,
          artistId: artist.id,
          albums: albumsAsync.value ?? const [],
        ),
      ),
    );
  }

  /// A quiet line over a queue kept stale ([ArrQueueSnapshot.isStale]) that
  /// still shows this artist or one of its albums in flight: the badges keep
  /// the downloads its last answer held, and the line says how old they are,
  /// so a page that still shows them does not pass them off as current.
  Widget? _staleQueueLine(
    LidarrQueueSnapshots queues,
    String instanceId, {
    required int artistId,
    required List<LidarrAlbum> albums,
  }) {
    final shown =
        queues.byArtist.entryFor(artistId) != null ||
        albums.any((album) => queues.byAlbum.entryFor(album.id) != null);
    if (!queues.byArtist.isStale || !shown) return null;
    final name = ref.watch(
      currentSettingsProvider.select(
        (s) => s.connectionTitle(instanceId, ServiceKey.lidarr),
      ),
    );
    return InlineErrorRetry(
      message: sectionFailureMessage(
        ServiceKey.lidarr,
        queues.byArtist.error,
        subject: "$name's queue",
        consequence:
            'the downloads shown are as they were '
            '${queueReadingAge(queues.byArtist)}',
      ),
      error: queues.byArtist.error,
      service: ServiceKey.lidarr,
      instanceId: instanceId,
      onRetry: () =>
          ref.invalidate(lidarrQueueSnapshotsForProvider(instanceId)),
    );
  }

  void _syncQualityProfiles(LidarrArtist artist) {
    if (artist.id <= 0 || artist.path?.isNotEmpty != true) {
      return;
    }

    ensureQualityProfiles(
      profileId: artist.qualityProfileId,
      fetchProfiles: () => _lidarr.getQualityProfiles(),
      // The record itself, so a read that came back empty is asked again when
      // a Retry or a pull brings a fresh one, not once and never again.
      record: artist,
    );
  }

  /// The hero chip slot: how much of the manifest exists. Lidarr already did
  /// this by accident, which is why it is the case the other six variants were
  /// generalised onto.
  List<Widget> _buildTags(MusicDetailViewModel viewModel) {
    return [
      if (viewModel.albumCountLabel != null)
        TagChip(
          text: viewModel.albumCountLabel!,
          color: ServiceKey.lidarr.accent,
        ),
      if (viewModel.trackCountLabel != null)
        TagChip(
          text: viewModel.trackCountLabel!,
          color: ServiceKey.lidarr.accent,
        ),
    ];
  }

  /// The connection's name, as a badge, or null while [service] has one.
  Widget? _connectionBadge(ServiceKey service) {
    final name = ref.watch(connectionNameProvider(_instanceId));
    return name == null
        ? null
        : ConnectionBadge(label: name, accent: service.accent);
  }

  Widget _buildPosterRow(
    BuildContext context,
    MusicDetailViewModel viewModel,
    MediaStatusInfo? status,
  ) {
    return MediaDetailPosterRow.circular(
      statusBadge: status == null ? null : StatusBadge.animated(info: status),
      title: viewModel.title,
      // The counts are the chip slot's one meaning, so they are stated there and
      // not also in the metadata line, which used to carry the identical pair.
      metadataItems: const [],
      tags: [
        ..._buildTags(viewModel),
        // Which connection this page reads, once there are two: a page opened
        // from the 4K's row is the 4K's artist, and the tab bar that carries the
        // lens is covered by the page.
        ?_connectionBadge(ServiceKey.lidarr),
      ],
      posterCard: MediaPosterCard.circular(
        heroTag: widget.heroTag,
        imageUrl: viewModel.posterUrl,
        imageHeaders: viewModel.posterHeaders,
        fallbackIcon: Icons.album_outlined,
      ),
    );
  }

  MediaDetailBody _buildBody(
    BuildContext context,
    MusicDetailViewModel viewModel,
    MediaStatusInfo status,
    List<MediaInfoGroup> infoGroups,
    ServiceInstance? connection,
    AsyncValue<List<LidarrAlbum>> albumsAsync,
    ArrQueueSnapshot albumQueue,
    int artistId, {
    Widget? band,
  }) {
    final accent = ServiceKey.lidarr.accent;

    // Decision 25 — the profile is edited where it is read, not from the deck's
    // ⋯ menu. The write already exists and asks first, because changing a
    // profile can start an upgrade search that cannot be called back.
    //
    // **This is the only field that ships.** Metadata profile, root folder
    // and tags are drawn on the board and every one needs a write this
    // client does not have — a generic read-modify-PUT for the first, `GET
    // /api/v1/tag` for the rest — and a picker with nothing behind it is a
    // control that fails in the user's hand.
    final profileRow = viewModel.isInLibrary && qualityProfiles.isNotEmpty
        ? MediaDetailValueRow<int>(
            label: 'Quality profile',
            value: currentProfileId,
            options: qualityProfileOptions(qualityProfiles),
            onChanged: (profileId) =>
                _updateProfile(profileId, mediaTitle: viewModel.title),
            accent: accent,
            hint: 'Changes it on Lidarr',
          )
        : null;
    final tracks = viewModel.trackCount;

    return MediaDetailBody(
      // Lidarr's column. The wide track is the discography and the search strip
      // — the only two things on this page that are about doing something — and
      // everything an artist *is* stands in the 380 column. `related` is empty
      // here (there is no cast and no collection for a musician), so the side
      // track is the encyclopaedia and nothing else.
      sideTrack: const {'Overview', 'Details', 'Scores', 'Genres'},
      // The stale queue's line, in the slot the Radarr and Sonarr pages give
      // theirs.
      band: band,
      deck: viewModel.isInLibrary
          ? LibraryDetailActions(
              service: ServiceKey.lidarr,
              status: status,
              mediaTitle: viewModel.title,
              isMonitored: viewModel.isMonitored,
              partialSummary: tracks > 0
                  ? '${viewModel.trackFileCount} of $tracks tracks on disk.'
                  : null,
              isBusy: isAutoSearching || isUpdatingMonitoredState || isDeleting,
              isConfirmed: isAutoSearchConfirmed,
              onSearch: () => _triggerSearch(context),
              onInteractiveSearch: () =>
                  _showInteractiveSearch(context, title: viewModel.title),
              onImport: openManualImportCallback(
                context,
                ServiceKey.lidarr,
                artistId,
                instanceId: _instanceId,
              ),
              // Every in-flight pipeline state promotes 'Open queue' only if the
              // host actually has a route for it; without this the most common
              // transient state on a real page degraded to a sentence. Pushed, not
              // gone: checking on a download should leave the title behind you.
              onOpenQueue: () => context.push('/activity/music'),
              onMonitoredChanged: (monitored) => _updateMonitoredState(
                context,
                artistId: artistId,
                monitored: monitored,
              ),
              onDelete: () => _confirmDelete(context, title: viewModel.title),
            )
          // See the Radarr screen: no add path from this view, so an untracked
          // artist gets a sentence instead of a CTA that apologises.
          : const MediaDetailUnavailableSection(
              message:
                  'Lidarr is not tracking this artist, so there is nothing to '
                  'manage here yet. Add it in Lidarr.',
            ),
      // Region 3 — the manifest, and the whole reason to open an artist page.
      // Albums used to be handed to the view as a sliver while the genres stayed
      // a content section, and the old spine emitted every content section before
      // every sliver — so the albums rendered dead last, after the genre chips.
      // In a named region that is structurally unreachable.
      operate: [
        if (viewModel.isInLibrary)
          // The list builds slivers and the two non-list states build boxes, so
          // the state picks the slot shape. Keeping the list in a `.lazy` slot is
          // what preserves its laziness *and* lands it mid-page.
          albumsAsync.when(
            // The project's own loading and failure vocabulary, the way the
            // Bazarr screens already use it: album-shaped shimmer rows while the
            // list is on its way, and a named failure with a retry when it does
            // not arrive.
            loading: () => MediaDetailSlot.box(
              label: 'Albums',
              count: _albumsCount(viewModel),
              child: ShimmerList(itemCount: 4, itemHeight: 64),
            ),
            error: (error, stackTrace) => MediaDetailSlot.box(
              label: 'Albums',
              count: _albumsCount(viewModel),
              child: AppErrorState.compact(
                error: error,
                serviceName: 'Lidarr',
                service: ServiceKey.lidarr,
                instanceId: _instanceId,
                onRetry: () => ref.invalidate(
                  musicAlbumsForProvider((
                    instanceId: _instanceId,
                    id: widget.artistId,
                  )),
                ),
              ),
            ),
            data: (albums) => MediaDetailSlot.lazy(
              label: 'Albums',
              count: _albumsCount(viewModel),
              leadingBox: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                child: ReleaseSearchStatusCard(
                  // Stamped: target equality includes the connection, so an
                  // unstamped one matches no running job and the card stays
                  // blank for the whole search.
                  target: ReleaseSearchTarget.artist(
                    artistId: widget.artistId,
                    label: truncateTitle(viewModel.title),
                  ).stampedWith(_instanceId),
                ),
              ),
              sliver: MusicAlbumsList(
                albums: albums,
                lidarrService: _lidarr,
                baseUrl: connection?.url ?? '',
                apiKey: connection?.credential ?? '',
                onSearchAlbum: (albumId) => _searchAlbum(context, albumId),
                onInteractiveSearchAlbum: (albumId) => _interactiveSearchAlbum(
                  context,
                  albumId,
                  title: viewModel.title,
                ),
                searchingAlbums: _searchingAlbums,
                albumQueue: albumQueue,
              ),
            ),
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
            // See the Radarr screen. Lidarr's single-source payload is badged
            // `MB`, which is MusicBrainz — and it announced itself to a screen
            // reader as a vote count in Italian.
            child: RatingChipsRow(
              ratings: legibleRatings(viewModel.ratings),
              accent: accent,
            ),
          ),
        if (viewModel.genres.isNotEmpty)
          MediaDetailSlot.box(
            // Not 'Tags' — these are genres, and a Lidarr tag is a different
            // thing the user configured on their server.
            label: 'Genres',
            child: MediaChipSection.neutral(values: viewModel.genres),
          ),
      ],
      // Lidarr has no cast and no collections.
      related: const [],
    );
  }

  /// `9 albums · 100 of 120 tracks` — the gap the manifest exists to render.
  String? _albumsCount(MusicDetailViewModel viewModel) {
    final parts = <String>[
      if (viewModel.albumCount > 0)
        '${viewModel.albumCount} '
            '${viewModel.albumCount == 1 ? 'album' : 'albums'}',
      if (viewModel.trackCount > 0)
        '${viewModel.trackFileCount} of ${viewModel.trackCount} tracks',
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }

  Future<void> _updateMonitoredState(
    BuildContext context, {
    required int artistId,
    required bool monitored,
  }) {
    return setMonitored(
      context: context,
      serviceName: 'Lidarr',
      subject: 'artist',
      monitored: monitored,
      write: () => ref
          .read(lidarrServiceProvider)
          .updateArtistMonitored(artistId, monitored),
      invalidate: [
        musicDetailForProvider((instanceId: _instanceId, id: artistId)),
        musicProvider,
      ],
    );
  }

  Future<void> _updateProfile(int profileId, {required String mediaTitle}) {
    return changeProfile(
      profileId: profileId,
      mediaTitle: mediaTitle,
      serviceName: 'Lidarr',
      consequence: 'upgrades across every monitored album',
      write: () => ref
          .read(lidarrServiceProvider)
          .updateArtistProfile(widget.artistId, profileId),
      invalidate: [musicProvider],
    );
  }

  Future<void> _triggerSearch(BuildContext context) {
    return triggerSearch(
      context: context,
      serviceName: 'Lidarr',
      // "<Service> is searching <what>", naming the scope: this covers every
      // monitored album, not just the one the user was looking at.
      successMessage: 'Lidarr is searching for every monitored album',
      search: () => _lidarr.searchArtist(widget.artistId),
    );
  }

  Future<void> _showInteractiveSearch(
    BuildContext context, {
    required String title,
  }) async {
    // The sheet heading already says "Releases"; this is its subtitle. Capped
    // because that subtitle has no maxLines.
    await showReleaseSearch(
      context,
      ref,
      ReleaseSearchTarget.artist(
        artistId: widget.artistId,
        label: truncateTitle(title),
      ).stampedWith(_instanceId),
    );
  }

  Future<void> _searchAlbum(BuildContext context, int albumId) async {
    HapticFeedback.selectionClick();
    setState(() => _searchingAlbums.add(albumId));
    try {
      final lidarrService = _lidarr;
      await lidarrService.searchAlbums([albumId]);
      if (!context.mounted) return;
      SnackBarHelper.success(context, 'Lidarr is searching this album');
    } catch (e) {
      if (!context.mounted) return;
      SnackBarHelper.error(
        context,
        "Could not start a search for this album.",
        detail: e,
      );
    } finally {
      if (mounted) setState(() => _searchingAlbums.remove(albumId));
    }
  }

  Future<void> _interactiveSearchAlbum(
    BuildContext context,
    int albumId, {
    required String title,
  }) async {
    // "Album Releases" under a heading reading "Releases" named neither the
    // artist nor the scope. Same shape as the artist-wide sheet.
    //
    // artistId travels with it so an album can be recognised as covered by an
    // artist-wide search that may already be running.
    await showReleaseSearch(
      context,
      ref,
      ReleaseSearchTarget.album(
        albumId: albumId,
        artistId: widget.artistId,
        label: '${truncateTitle(title)} · one album',
      ).stampedWith(_instanceId),
    );
  }

  Future<void> _confirmDelete(BuildContext context, {required String title}) {
    return confirmDelete(
      context: context,
      serviceName: 'Lidarr',
      subject: 'artist',
      title: title,
      mediaType: DeleteMediaType.artist,
      write: (deleteFiles, addExclusion) => ref
          .read(lidarrServiceProvider)
          .deleteArtist(
            widget.artistId,
            deleteFiles: deleteFiles,
            addImportListExclusion: addExclusion,
          ),
    );
  }
}
