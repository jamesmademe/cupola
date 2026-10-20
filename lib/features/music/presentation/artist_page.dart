import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:cupola/core/api/arr_detail_actions_mixin.dart';
import 'package:cupola/core/api/quality_profile_mixin.dart';
import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/generated/design_tokens.g.dart';
import 'package:cupola/core/status/arr_queue_snapshot.dart';
import 'package:cupola/core/status/lexicon.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/title_light.dart';
import 'package:cupola/core/utils/dot_separator.dart';
import 'package:cupola/core/utils/image_utils.dart';
import 'package:cupola/core/utils/snack_bar_helper.dart';
import 'package:cupola/core/utils/string_utils.dart';
import 'package:cupola/core/utils/url_utils.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/import/presentation/manual_import_routes.dart';
import 'package:cupola/features/media/domain/media_removal.dart';
import 'package:cupola/features/media/presentation/media_parts.dart';
import 'package:cupola/features/media/presentation/shelf_page.dart';
import 'package:cupola/features/music/data/lidarr_service.dart';
import 'package:cupola/features/music/domain/artist_shelf.dart';
import 'package:cupola/features/music/domain/lidarr_queue_snapshots.dart';
import 'package:cupola/features/music/domain/models/lidarr_album.dart';
import 'package:cupola/features/music/domain/models/lidarr_artist.dart';
import 'package:cupola/features/music/presentation/artist_page_providers.dart';
import 'package:cupola/features/music/presentation/music_provider.dart';
import 'package:cupola/features/release_search/domain/release_search_target.dart';
import 'package:cupola/features/release_search/presentation/release_search_entry.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/data/connection_reach_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/connection_presentation.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// An artist on one Lidarr: who they are, what of theirs is on disk, what is
/// on its way, and what Lidarr does for them.
///
/// Under the name, the albums in the four places they can be ([ArtistShelf]):
/// announced, wanted, on disk, left alone. Each album opens on its tracks.
/// Then the artist's settings on that Lidarr, and the way to it.
class ArtistPage extends ConsumerStatefulWidget {
  const ArtistPage({
    super.key,
    required this.artistId,
    this.instanceId,
    this.initialArtist,
    this.heroTag,
  });

  final int artistId;

  /// The connection this page belongs to, from the route's `?i=`; null
  /// falls through to the lens. Every read and every write on the page goes
  /// to it.
  final String? instanceId;

  /// The library's record, standing in while the page reads its own.
  final LidarrArtist? initialArtist;

  /// The tag of the tile the page was opened from.
  final String? heroTag;

  @override
  ConsumerState<ArtistPage> createState() => _ArtistPageState();
}

class _ArtistPageState extends ConsumerState<ArtistPage>
    with QualityProfileMixin<ArtistPage>, ArrDetailActionsMixin<ArtistPage> {
  /// Where Manage scrolls to.
  final _detailsKey = GlobalKey();

  /// The pictures the page has drawn: the room's light is read from one of
  /// these only.
  final _drawn = <String>{};

  /// The albums a search was just asked for, until Lidarr takes it.
  final _searching = <int>{};

  /// Whether the albums Lidarr leaves alone are shown.
  var _showUnmonitored = false;

  /// What the switches were just set to, standing until the artist is read
  /// again: [_setOn] is the record they were set over.
  bool? _monitoredSet;
  String? _newItemsSet;
  LidarrArtist? _setOn;
  var _savingNewItems = false;

  /// The connection resolved in the last build, for the callbacks to reuse:
  /// a write after an await goes to the connection the page showed even if
  /// the lens moved meanwhile.
  String _instanceId = '';

  LidarrService get _lidarr => _instanceId.isEmpty
      ? ref.read(lidarrServiceProvider)
      : ref.read(lidarrServiceForProvider(_instanceId));

  LidarrRecordRef get _record => (instanceId: _instanceId, id: widget.artistId);

  void _artDrawn(String url) {
    if (_drawn.contains(url)) return;
    // After the frame that drew it: a setState inside an image builder would
    // rebuild the tree that is being built.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _drawn.add(url));
    });
  }

  void _readAgain() {
    ref.invalidate(lidarrArtistProvider(_record));
    ref.invalidate(lidarrArtistAlbumsProvider(_record));
    ref.invalidate(lidarrQueueSnapshotsForProvider(_instanceId));
  }

  @override
  Widget build(BuildContext context) {
    _instanceId = effectiveInstanceId(
      ref,
      ServiceKey.lidarr,
      widget.instanceId,
    );
    final connection = ref.watch(
      currentSettingsProvider.select((s) => s.instanceById(_instanceId)),
    );
    // Where the connection is reached now: its artwork is fetched there.
    final reachedAt =
        ref.watch(connectionReachProvider(_instanceId))?.url ?? '';
    // Not set up: nothing to read, and a read that throws would only fail.
    if (connection == null || !connection.isConfigured) {
      return Scaffold(
        backgroundColor: CupolaRoom.of(context).ground,
        body: NotConfiguredPlaceholder.forService(ServiceKey.lidarr),
      );
    }
    final name = ref.watch(
      currentSettingsProvider.select(
        (s) => s.connectionTitle(_instanceId, ServiceKey.lidarr),
      ),
    );
    final artistAsync = ref.watch(lidarrArtistProvider(_record));
    final artist = artistAsync.value ?? widget.initialArtist;
    if (artist == null) {
      return ShelfPage(
        name: '',
        summary: '',
        heroTag: widget.heroTag,
        slivers: [
          if (artistAsync.error case final error?)
            SliverFillRemaining(
              hasScrollBody: false,
              child: AppErrorState(
                error: error,
                service: ServiceKey.lidarr,
                instanceId: _instanceId,
                onRetry: _readAgain,
              ),
            )
          else
            const SliverToBoxAdapter(child: _Waiting()),
        ],
      );
    }
    if (!identical(artist, _setOn)) {
      _monitoredSet = null;
      _newItemsSet = null;
    }
    ensureQualityProfiles(
      profileId: artist.qualityProfileId,
      fetchProfiles: () => _lidarr.getQualityProfiles(),
      // The record itself, so a read that came back empty is asked again
      // when a Retry or a pull brings a fresh one.
      record: artist,
    );

    final now = DateTime.now();
    final albumsAsync = ref.watch(lidarrArtistAlbumsProvider(_record));
    final albums = albumsAsync.value;
    final shelf = albums == null ? null : ArtistShelf.of(albums, now: now);
    // The page's own connection's queue: the ids in it are that server's.
    final queues = lidarrQueueSnapshotsOf(
      ref.watch(lidarrQueueSnapshotsForProvider(_instanceId)),
    );
    ShelfArt? artOf(List<dynamic> images, List<String> types) {
      final source = ImageUtils.extractPosterUrl(
        images,
        baseUrl: reachedAt,
        apiKey: connection.credential,
        coverTypes: types,
      );
      return source.url.isEmpty
          ? null
          : (url: source.url, headers: source.headers);
    }

    ShelfArt? coverOf(LidarrAlbum album) => artOf(album.images, ['cover']);
    final photo = artOf(artist.images, ['poster']);
    final covers = [
      for (final album in shelf?.covers ?? const <LidarrAlbum>[])
        if (coverOf(album) case final art?) (album: album, art: art),
    ];
    // The room is lit by the first cover the page has drawn, else the photo.
    final lightSource = [
      for (final cover in covers) cover.art.url,
      ?photo?.url,
    ].where(_drawn.contains).firstOrNull;
    final light = lightSource == null
        ? null
        : ref.watch(titleLightProvider(lightSource)).value;
    final monitored = _monitoredSet ?? artist.monitored;

    final room = CupolaRoom.of(context);
    Widget section(String title, {String? trailing}) =>
        SliverToBoxAdapter(child: MediaHeading(title, trailing: trailing));
    Widget row(LidarrAlbum album) => _AlbumRow(
      key: ValueKey(('album', album.id)),
      album: album,
      cover: coverOf(album),
      light: light,
      state: albumState(album, queue: queues.byAlbum, now: now),
      detail: albumIsComing(album, now: now) && album.monitored
          ? "$name looks for it once it's out"
          : null,
      record: (instanceId: _instanceId, id: album.id),
      searching: _searching.contains(album.id),
      onSearch: albumIsComing(album, now: now)
          ? null
          : () => _searchAlbum(album, name: name),
      onSearchReleases: albumIsComing(album, now: now)
          ? null
          : () => _searchReleases(album, artist: artist),
      now: now,
    );
    Widget group(List<LidarrAlbum> albums) => ShelfSliverGroup(
      itemCount: albums.length,
      itemBuilder: (context, index) => row(albums[index]),
    );

    return ShelfPage(
      name: artist.artistName,
      summary: shelf?.summary ?? '',
      photo: photo,
      light: light,
      heroTag: widget.heroTag,
      moreLabel: 'More actions for ${artist.artistName}',
      onMore: (plate) => _more(artist, name: name, plate: plate),
      onRefresh: () async => _readAgain(),
      slivers: [
        if (covers.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xl),
              child: ExcludeSemantics(
                child: _Covers(
                  covers: covers,
                  light: light,
                  onDrawn: _artDrawn,
                ),
              ),
            ),
          ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(top: AppSpacing.lg),
            child: _Actions(
              searching: isAutoSearching,
              onSearch: () => triggerSearch(
                context: context,
                serviceName: name,
                successMessage: '$name is searching for every monitored album',
                search: () => _lidarr.searchArtist(widget.artistId),
              ),
              onManage: _toDetails,
            ),
          ),
        ),
        if (_staleQueueLine(queues, name, artist: artist, albums: albums)
            case final line?)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(top: AppSpacing.md),
              child: line,
            ),
          ),
        ...switch (albumsAsync) {
          AsyncValue(:final error?) when albums == null => [
            section('Albums'),
            SliverToBoxAdapter(
              child: AppErrorState.compact(
                error: error,
                service: ServiceKey.lidarr,
                instanceId: _instanceId,
                onRetry: () =>
                    ref.invalidate(lidarrArtistAlbumsProvider(_record)),
              ),
            ),
          ],
          _ when shelf == null => [
            section('Albums'),
            SliverToBoxAdapter(
              child: ShimmerList(itemCount: 3, itemHeight: 64),
            ),
          ],
          _ when albums!.isEmpty => [
            section('Albums'),
            SliverToBoxAdapter(
              child: Text(
                '$name knows of no albums by this artist yet. It looks '
                'again on its next refresh.',
                style: AppType.body.copyWith(color: room.inkSecondary),
              ),
            ),
          ],
          _ => [
            if (shelf.coming.isNotEmpty) ...[
              section('Coming'),
              group(shelf.coming),
            ],
            if (shelf.wanted.isNotEmpty) ...[
              section(
                StateWord.wanted.label,
                trailing: _albumCount(shelf.wanted.length),
              ),
              group(shelf.wanted),
            ],
            if (shelf.onDisk.isNotEmpty) ...[
              section('On disk', trailing: _albumCount(shelf.onDisk.length)),
              group(shelf.onDisk),
            ],
            if (shelf.unmonitored.isNotEmpty) ...[
              section(
                'Unmonitored',
                trailing: _albumCount(shelf.unmonitored.length),
              ),
              if (_showUnmonitored)
                group(shelf.unmonitored)
              else
                SliverToBoxAdapter(
                  child: MediaGroup(
                    children: [
                      MediaLinkRow(
                        label: 'Show them',
                        detail: '$name is not looking for these',
                        onTap: () => setState(() => _showUnmonitored = true),
                      ),
                    ],
                  ),
                ),
            ],
          ],
        },
        SliverToBoxAdapter(child: MediaHeading('Details', key: _detailsKey)),
        SliverToBoxAdapter(
          child: MediaGroup(
            children: [
              MediaSwitchRow(
                label: 'Monitored',
                detail: '$name keeps these albums up to date',
                value: monitored,
                onChanged: isUpdatingMonitoredState
                    ? null
                    : (on) => _setMonitored(artist, on, name: name),
              ),
              if (artist.monitorNewItems case final newItems?)
                MediaSwitchRow(
                  label: 'Monitor new albums',
                  detail:
                      'New releases are added and searched for on '
                      'their own',
                  value: (_newItemsSet ?? newItems) != 'none',
                  onChanged: _savingNewItems
                      ? null
                      : (on) => _setNewItems(artist, on, name: name),
                ),
              if (qualityProfiles.isNotEmpty)
                MediaValueRow(
                  label: 'Quality profile',
                  value: Text(
                    currentProfileName ?? '',
                    textAlign: TextAlign.end,
                    style: AppType.meta.copyWith(color: room.inkSecondary),
                  ),
                  onTap: qualityProfiles.length > 1
                      ? () => _pickProfile(artist, name: name)
                      : null,
                ),
              if (artist.path case final path? when path.isNotEmpty)
                ShelfFolderRow(path: path),
            ],
          ),
        ),
        if (artist.foreignArtistId.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xl),
              child: ShelfOpenIn(
                name: name,
                onTap: () => _openInLidarr(connection, artist, name: name),
              ),
            ),
          ),
      ],
    );
  }

  static String _albumCount(int count) =>
      '$count ${count == 1 ? 'album' : 'albums'}';

  void _toDetails() {
    final target = _detailsKey.currentContext;
    if (target == null) return;
    Scrollable.ensureVisible(
      target,
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
    );
  }

  /// A quiet line over a queue kept stale ([ArrQueueSnapshot.isStale]) that
  /// still shows this artist or one of its albums in flight: the albums keep
  /// the downloads its last answer held, and the line says how old they are.
  Widget? _staleQueueLine(
    LidarrQueueSnapshots queues,
    String name, {
    required LidarrArtist artist,
    required List<LidarrAlbum>? albums,
  }) {
    final shown =
        queues.byArtist.entryFor(artist.id) != null ||
        (albums ?? const []).any(
          (album) => queues.byAlbum.entryFor(album.id) != null,
        );
    if (!queues.byArtist.isStale || !shown) return null;
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
      instanceId: _instanceId,
      onRetry: () =>
          ref.invalidate(lidarrQueueSnapshotsForProvider(_instanceId)),
    );
  }

  Future<void> _setMonitored(
    LidarrArtist artist,
    bool on, {
    required String name,
  }) async {
    var written = false;
    await setMonitored(
      context: context,
      serviceName: name,
      subject: 'artist',
      monitored: on,
      write: () async {
        await _lidarr.updateArtistMonitored(artist.id, on);
        written = true;
      },
      invalidate: [lidarrArtistProvider(_record), musicProvider],
    );
    if (written && mounted) {
      setState(() {
        _setOn = ref.read(lidarrArtistProvider(_record)).value ?? artist;
        _monitoredSet = on;
      });
    }
  }

  Future<void> _setNewItems(
    LidarrArtist artist,
    bool on, {
    required String name,
  }) async {
    final value = on ? 'all' : 'none';
    setState(() => _savingNewItems = true);
    try {
      await _lidarr.updateArtistMonitorNewItems(artist.id, value);
      if (!mounted) return;
      setState(() {
        _setOn = artist;
        _newItemsSet = value;
      });
      ref.invalidate(lidarrArtistProvider(_record));
      SnackBarHelper.success(
        context,
        on
            ? '$name adds new albums by ${artist.artistName}'
            : '$name no longer adds new albums by ${artist.artistName}',
      );
    } catch (error) {
      if (!mounted) return;
      SnackBarHelper.error(
        context,
        'Could not change new albums in $name.',
        detail: error,
      );
    } finally {
      if (mounted) setState(() => _savingNewItems = false);
    }
  }

  Future<void> _pickProfile(LidarrArtist artist, {required String name}) async {
    final picked = await showMediaValueSheet<int>(
      context,
      title: 'Quality profile',
      value: currentProfileId,
      currentLabel: currentProfileName ?? '',
      options: qualityProfileOptions(qualityProfiles),
    );
    if (picked == null || !mounted) return;
    await changeProfile(
      profileId: picked.value,
      mediaTitle: artist.artistName,
      serviceName: name,
      consequence: 'upgrades across every monitored album',
      write: () => _lidarr.updateArtistProfile(artist.id, picked.value),
      invalidate: [lidarrArtistProvider(_record), musicProvider],
    );
  }

  Future<void> _searchAlbum(LidarrAlbum album, {required String name}) async {
    HapticFeedback.selectionClick();
    setState(() => _searching.add(album.id));
    try {
      await _lidarr.searchAlbums([album.id]);
      if (!mounted) return;
      SnackBarHelper.success(context, '$name is searching for ${album.title}');
    } catch (error) {
      if (!mounted) return;
      SnackBarHelper.error(
        context,
        'Could not start a search for ${album.title}.',
        detail: error,
      );
    } finally {
      if (mounted) setState(() => _searching.remove(album.id));
    }
  }

  Future<void> _searchReleases(
    LidarrAlbum album, {
    required LidarrArtist artist,
  }) => showReleaseSearch(
    context,
    ref,
    // The artist travels with it, so the album is known to be covered by an
    // artist-wide search that may already be running.
    ReleaseSearchTarget.album(
      albumId: album.id,
      artistId: artist.id,
      label:
          '${truncateTitle(artist.artistName)}\u00A0· ${truncateTitle(album.title)}',
    ).stampedWith(_instanceId),
  );

  void _more(
    LidarrArtist artist, {
    required String name,
    required BuildContext plate,
  }) {
    final import = openManualImportCallback(
      context,
      ServiceKey.lidarr,
      artist.id,
      instanceId: _instanceId,
    );
    showMediaDetailActions(
      context,
      anchor: plate,
      accent: ServiceKey.lidarr.accent,
      title: artist.artistName,
      actions: [
        MediaOverflowAction(
          label: 'Search releases',
          icon: Icons.manage_search_rounded,
          onInvoke: () => showReleaseSearch(
            context,
            ref,
            ReleaseSearchTarget.artist(
              artistId: artist.id,
              label: truncateTitle(artist.artistName),
            ).stampedWith(_instanceId),
          ),
        ),
        if (import != null)
          MediaOverflowAction(
            label: 'Import files',
            icon: Icons.drive_folder_upload_outlined,
            onInvoke: import,
          ),
        MediaOverflowAction.destructive(
          label: 'Remove from $name',
          icon: Icons.delete_outline_rounded,
          onInvoke: () => _remove(artist, name: name),
        ),
      ],
    );
  }

  /// Removes the artist from this Lidarr, after the question removing asks:
  /// what it takes, whether the files go, whether Lidarr may add them again.
  Future<void> _remove(LidarrArtist artist, {required String name}) async {
    final removal = mediaRemoval(
      title: artist.artistName,
      name: name,
      sizeOnDisk: artist.sizeOnDisk,
      monitored: artist.monitored,
      works: 'albums',
    );
    final result = await showAppConfirmDialog(
      context: context,
      title: removal.title,
      message: removal.message,
      icon: Icons.delete_outline_rounded,
      cancelLabel: 'Keep them',
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
            subtitle: 'Their folder on your server. This cannot be undone.',
          ),
        AppConfirmOption(
          key: 'exclude',
          label: "Don't add them again",
          subtitle: "Keeps $name's import lists from bringing them back",
        ),
      ],
    );
    if (!result.confirmed || !mounted) return;
    try {
      await _lidarr.deleteArtist(
        artist.id,
        deleteFiles: result.option('files'),
        addImportListExclusion: result.option('exclude'),
      );
      if (!mounted) return;
      SnackBarHelper.success(context, 'Removed from $name');
      ref.invalidate(musicProvider);
      context.pop();
    } catch (error) {
      if (!mounted) return;
      SnackBarHelper.error(
        context,
        'Could not remove ${artist.artistName} from $name',
        detail: error,
      );
    }
  }

  Future<void> _openInLidarr(
    ServiceInstance connection,
    LidarrArtist artist, {
    required String name,
  }) async {
    // Lidarr's own page at the address it is reached at now: away from home,
    // the one at home would not open.
    final base = ref.read(connectionReachProvider(connection.id))?.url ?? '';
    final target = Uri.tryParse(
      UrlUtils.buildUrl(base, '/artist/${artist.foreignArtistId}'),
    );
    final opened =
        target != null &&
        await launchUrl(target, mode: LaunchMode.externalApplication);
    if (!opened && mounted) {
      SnackBarHelper.error(context, 'Could not open $name');
    }
  }
}

/// Search albums and Manage, side by side; one to a line at a large reading
/// size, where side by side they cut their words.
class _Actions extends StatelessWidget {
  const _Actions({
    required this.searching,
    required this.onSearch,
    required this.onManage,
  });

  final bool searching;
  final VoidCallback onSearch;
  final VoidCallback onManage;

  @override
  Widget build(BuildContext context) {
    final buttons = [
      OutlinedButton.icon(
        onPressed: searching ? null : onSearch,
        icon: const Icon(Icons.search_rounded, size: 17),
        label: const Text(
          'Search albums',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      OutlinedButton.icon(
        onPressed: onManage,
        icon: const Icon(Icons.tune_rounded, size: 17),
        label: const Text(
          'Manage',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    ];
    if (mediaStacked(context)) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          buttons[0],
          const SizedBox(height: AppSpacing.sm),
          buttons[1],
        ],
      );
    }
    return Row(
      children: [
        Expanded(child: buttons[0]),
        const SizedBox(width: AppSpacing.row),
        Expanded(child: buttons[1]),
      ],
    );
  }
}

/// The page while it reads the artist: the disc's place and two lines.
class _Waiting extends StatelessWidget {
  const _Waiting();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.only(top: AppSpacing.xl),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ShimmerPlaceholder(height: 110),
        SizedBox(height: AppSpacing.lg),
        ShimmerPlaceholder(height: DesignTokens.sizeTouch),
        SizedBox(height: AppSpacing.section),
        ShimmerPlaceholder(height: 220),
      ],
    ),
  );
}

/// The largest a cover under the name grows, in a wide window.
const double _coverMax = 160;

/// Up to three covers under the name, the shelf at a glance.
class _Covers extends StatelessWidget {
  const _Covers({
    required this.covers,
    required this.light,
    required this.onDrawn,
  });

  final List<({LidarrAlbum album, ShelfArt art})> covers;
  final TitleLight? light;
  final ValueChanged<String> onDrawn;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        const gap = AppSpacing.row;
        // Three to the column, never bigger than a cover needs to be read.
        final side = ((box.maxWidth - 2 * gap) / 3).clamp(0.0, _coverMax);
        return Row(
          children: [
            for (final (index, cover) in covers.indexed) ...[
              if (index > 0) const SizedBox(width: gap),
              ShelfCover(
                art: cover.art,
                size: Size.square(side),
                radius: AppRadius.poster,
                light: light,
                onDrawn: onDrawn,
                fallback: const _AlbumPlate(),
              ),
            ],
          ],
        );
      },
    );
  }
}

/// An album without a cover: the plate and a disc, dark in both rooms.
class _AlbumPlate extends StatelessWidget {
  const _AlbumPlate();

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: AppColors.plateWell,
    child: Center(
      // Artwork is not palette: the plate's own ink, in both rooms.
      child: Icon(Icons.album_outlined, size: 24, color: AppColors.plateDimInk),
    ),
  );
}

/// One album: its cover, its title, its facts and where it stands. Opens on
/// its tracks, and on the searches an album that is out can ask for.
class _AlbumRow extends StatelessWidget {
  const _AlbumRow({
    super.key,
    required this.album,
    required this.cover,
    required this.light,
    required this.state,
    required this.detail,
    required this.record,
    required this.searching,
    required this.onSearch,
    required this.onSearchReleases,
    required this.now,
  });

  final LidarrAlbum album;
  final ShelfArt? cover;
  final TitleLight? light;
  final ShelfState? state;
  final String? detail;
  final LidarrRecordRef record;
  final bool searching;
  final VoidCallback? onSearch;
  final VoidCallback? onSearchReleases;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final coming = albumIsComing(album, now: now);
    final complete =
        album.trackFileCount > 0 && album.trackFileCount >= album.trackCount;
    return ShelfWorkRow(
      cover: ShelfCover(
        art: cover,
        size: const Size.square(64),
        light: light,
        fallback: const _AlbumPlate(),
      ),
      title: album.title,
      // An album not out yet says when, and nothing else: its tracks and
      // length are Lidarr's guess.
      facts: coming ? null : albumFacts(album).join(dotSeparator),
      state: state,
      detail: detail,
      spoken: [
        album.title,
        if (!coming) ...albumSpokenFacts(album),
        ?state?.word,
        ?detail,
      ].join(', '),
      body: (context) => AlbumTracks(
        album: album,
        record: record,
        searching: searching,
        // A complete album asks for nothing; one with a gap, or none on disk,
        // can be searched for.
        onSearch: complete ? null : onSearch,
        onSearchReleases: onSearchReleases,
      ),
    );
  }
}

/// An album's tracks, read when it opens: number, title, length, and the
/// tracks not on disk quieter when some are. Under them how many are on
/// disk, and the searches.
class AlbumTracks extends ConsumerWidget {
  const AlbumTracks({
    super.key,
    required this.album,
    required this.record,
    required this.searching,
    required this.onSearch,
    required this.onSearchReleases,
  });

  final LidarrAlbum album;
  final LidarrRecordRef record;
  final bool searching;
  final VoidCallback? onSearch;
  final VoidCallback? onSearchReleases;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final room = CupolaRoom.of(context);
    final tracks = ref.watch(lidarrAlbumTracksProvider(record));
    final partial = album.trackFileCount > 0;
    final summary = album.trackCount > 0
        ? '${album.trackFileCount} of ${album.trackCount} tracks on disk'
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        switch (tracks) {
          AsyncValue(:final value?) when value.isEmpty => Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            child: Text(
              'Lidarr lists no tracks for this album.',
              style: AppType.meta.copyWith(color: room.inkTertiary),
            ),
          ),
          AsyncValue(:final value?) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (index, track) in value.indexed) ...[
                if (index > 0) Divider(height: 1, color: room.hair),
                Semantics(
                  container: true,
                  excludeSemantics: true,
                  label: [
                    'Track ${track.displayTrackNumber}',
                    track.title,
                    if (track.duration > 0) track.formattedDuration,
                    track.hasFile ? 'on disk' : 'not on disk',
                  ].join(', '),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      minHeight: DesignTokens.sizeTouch,
                    ),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 28,
                          child: Text(
                            track.displayTrackNumber,
                            style: AppType.meta
                                .weight(FontWeight.w600)
                                .copyWith(color: room.inkTertiary),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.row),
                        Expanded(
                          child: Text(
                            track.title,
                            style: AppType.label
                                .weight(FontWeight.w500)
                                .copyWith(
                                  color: partial && !track.hasFile
                                      ? room.inkTertiary
                                      : room.ink,
                                ),
                          ),
                        ),
                        if (track.duration > 0) ...[
                          const SizedBox(width: AppSpacing.row),
                          Text(
                            track.formattedDuration,
                            style: AppType.meta.copyWith(
                              color: room.inkTertiary,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
          AsyncValue(:final error?) => InlineErrorRetry(
            message: sectionFailureMessage(
              ServiceKey.lidarr,
              error,
              consequence: 'the tracks are not shown',
            ),
            error: error,
            service: ServiceKey.lidarr,
            instanceId: record.instanceId,
            onRetry: () => ref.invalidate(lidarrAlbumTracksProvider(record)),
          ),
          _ => const ShimmerList(itemCount: 3, itemHeight: 36),
        },
        if (summary != null) ...[
          const SizedBox(height: AppSpacing.s),
          Text(
            summary,
            style: AppType.caption.copyWith(color: room.inkTertiary),
          ),
        ],
        if (onSearch != null) ...[
          const SizedBox(height: AppSpacing.md),
          FilledButton.icon(
            onPressed: searching ? null : onSearch,
            icon: const Icon(Icons.search_rounded, size: 18),
            label: const Text('Search for this album'),
          ),
        ],
        if (onSearchReleases != null)
          TextButton(
            onPressed: onSearchReleases,
            child: const Text('Search releases'),
          ),
      ],
    );
  }
}
