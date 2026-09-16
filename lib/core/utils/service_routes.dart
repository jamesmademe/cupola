import 'package:cupola/features/prowlarr/domain/models/prowlarr_models.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

class ServiceRoutes {
  ServiceRoutes._();

  /// The app home, and the prefix every service home hangs off.
  ///
  /// `/dashboard` since the rename (decision 1): the tab, the crumb and the
  /// route all say Dashboard, one service is a *service home* at
  /// `/dashboard/{key}`, and TrueNAS keeps the word for its own console
  /// section because the app does not rename another product's furniture.
  static const dashboard = '/dashboard';

  /// Where the app used to live. Every path under it still resolves — see the
  /// rewrite in `router.dart`'s top-level redirect — because a bookmark, a
  /// deep link or a restored session from before the rename must not 404.
  static const legacyServices = '/services';

  static const seerr = '$dashboard/seerr';
  static const radarr = '$dashboard/radarr';
  static const sonarr = '$dashboard/sonarr';
  static const lidarr = '$dashboard/lidarr';
  static const qbittorrent = '$dashboard/qbittorrent';
  static const bazarr = '$dashboard/bazarr';
  static const truenas = '$dashboard/truenas';
  static const dockge = '$dashboard/dockge';
  static const prowlarr = '$dashboard/prowlarr';
  static const readarr = '$dashboard/readarr';
  static const sabnzbd = '$dashboard/sabnzbd';
  static const nzbget = '$dashboard/nzbget';
  static const unraid = '$dashboard/unraid';
  static const jellyfin = '$dashboard/jellyfin';
  static const plex = '$dashboard/plex';

  /// The two the file was missing. Both services shipped with their callers
  /// building `'/services/transmission'` and `'/services/npm'` by hand, which
  /// is how a single source of truth stops being one — and `npm` is precisely
  /// the segment that is *not* derivable from the enum name, so a hand-built
  /// path is a spelling nobody checks.
  static const transmission = '$dashboard/transmission';
  static const nginxProxyManager = '$dashboard/npm';

  /// The home of any service, by key.
  ///
  /// Every call site that wanted this built the path by hand instead, because
  /// there was nothing to call. Going through [ServiceKey.routeParam] keeps the
  /// one irregular segment — Nginx Proxy Manager's `npm` — spelled in exactly
  /// one place.
  static String forService(ServiceKey service) =>
      '$dashboard/${service.routeParam}';

  // ── Stream sections ───────────────────────────────────────────────────────
  //
  // Both media servers share one route shape because both APIs are uniform in
  // the way the arrs are not: a Jellyfin `BaseItemDto` and a Plex `Metadata`
  // describe a movie, a series, a season and an episode with the same fields, so
  // **one** recursive item route covers the whole tree where Radarr, Sonarr and
  // Lidarr each needed their own screen.
  static const jellyfinLibraries = '$jellyfin/library';
  static const jellyfinItemBase = '$jellyfin/item';
  static const plexLibraries = '$plex/library';
  static const plexItemBase = '$plex/item';

  /// One library's browse route, e.g. `/services/jellyfin/library/f137a2dd`.
  ///
  /// The id travels as a path segment and the display name as a query parameter,
  /// following [seerrGenre]: a deep link has to resolve from the path alone, but
  /// a caller that already knows the name can spare the destination a fetch
  /// before its first frame.
  static String jellyfinLibrary(String id, {String? title}) =>
      _streamLibrary(jellyfinLibraries, id, title);
  static String plexLibrary(String id, {String? title}) =>
      _streamLibrary(plexLibraries, id, title);

  static String _streamLibrary(String base, String id, String? title) {
    final route = '$base/$id';
    final name = title?.trim() ?? '';
    return name.isEmpty ? route : _withQuery(route, {'title': name});
  }

  /// One item at any depth of the tree — film, show, season or episode.
  ///
  /// Jellyfin ids are GUIDs and a Plex `ratingKey` is documented as an opaque
  /// string that only *often* looks numeric, so neither can go through
  /// `RouteUtils.safeIntParam`. Both are single path segments containing no `/`,
  /// which is why this stays a path route rather than taking
  /// [truenasDataset]'s query-parameter escape hatch.
  static String jellyfinItem(String id) => '$jellyfinItemBase/$id';
  static String plexItem(String id) => '$plexItemBase/$id';

  // ── TrueNAS sections ──────────────────────────────────────────────────────
  static const truenasDashboard = '$truenas/dashboard';
  static const truenasStorage = '$truenas/storage';
  static const truenasPoolBase = '$truenasStorage/pool';
  static const truenasDatasets = '$truenas/datasets';
  static const truenasDatasetDetail = '$truenasDatasets/detail';
  static const truenasShares = '$truenas/shares';
  static const truenasDataProtection = '$truenas/data-protection';
  static const truenasContainers = '$truenas/containers';
  static const truenasContainerBase = '$truenasContainers/instance';
  static const truenasVms = '$truenas/vms';
  static const truenasVmBase = '$truenasVms/instance';
  static const truenasApps = '$truenas/apps';
  static const truenasAppBase = '$truenasApps/app';
  static const truenasReporting = '$truenas/reporting';
  static const truenasSystem = '$truenas/system';

  /// Pool detail, e.g. `/services/truenas/storage/pool/tank`.
  static String truenasPool(String name) => '$truenasPoolBase/$name';

  /// Dataset detail. ZFS ids contain `/`, so the id travels as a query
  /// parameter rather than a path segment.
  static String truenasDataset(String id) =>
      _withQuery(truenasDatasetDetail, {'id': id});

  /// Container/VM instance detail (Incus instance name is a single segment).
  static String truenasContainer(String id) => '$truenasContainerBase/$id';
  static String truenasVm(String id) => '$truenasVmBase/$id';

  /// Installed app detail by app name.
  static String truenasApp(String name) => '$truenasAppBase/$name';

  /// A System sub-section, e.g. `/services/truenas/system/network`.
  static String truenasSystemSection(String section) =>
      '$truenasSystem/$section';

  static const seerrRequests = '$seerr/requests';
  static const seerrMoviesAll = '$seerr/movies/all';
  static const seerrTvAll = '$seerr/tv/all';
  static const seerrTrendingAll = '$seerr/trending/all';
  static const seerrGenreBase = '$seerr/genre';
  static const seerrPersonBase = '$seerr/person';
  static const seerrCollectionBase = '$seerr/collection';

  /// Person (cast member) detail page, e.g. `/services/seerr/person/287`.
  static String seerrPerson(int id, {String? heroTag, String? posterUrl}) {
    return _withQuery('$seerrPersonBase/$id', {
      'heroTag': heroTag,
      'posterUrl': posterUrl,
    });
  }

  /// Movie collection detail page, e.g. `/services/seerr/collection/10`.
  static String seerrCollection(int id, {String? heroTag}) {
    return _withQuery('$seerrCollectionBase/$id', {'heroTag': heroTag});
  }

  /// See-all for a single genre row, e.g. `/services/seerr/genre/movie/28?title=Action`.
  static String seerrGenre({
    required String mediaType,
    required int genreId,
    String? title,
  }) {
    final normalizedMediaType = mediaType == 'tv' ? 'tv' : 'movie';
    return _withQuery('$seerrGenreBase/$normalizedMediaType/$genreId', {
      'title': title,
    });
  }

  // ── The \*arr family, under the tab model ─────────────────────────────────
  //
  // Spelled as literals rather than composed from `ServiceTab.segment`: an enum
  // instance's field is not a compile-time constant in Dart and these have to
  // stay `const`. A test ties each one to its tab so the two cannot drift.
  //
  // The four share a bar exactly, so they share these spellings exactly: a user
  // who has learned where Radarr's library lives has learned where Sonarr's
  // does, and a reader comparing two of these blocks should find nothing to
  // compare.
  static const radarrOverview = '$radarr/overview';
  static const radarrLibrary = '$radarr/library';

  /// The film, inside the Library tab's branch.
  static const radarrMovieBase = '$radarrLibrary/movie';

  static const sonarrOverview = '$sonarr/overview';
  static const sonarrLibrary = '$sonarr/library';

  /// The show, inside the Library tab's branch — the same move as the film and
  /// for the same reason: a detail pushed *inside* its tab survives a switch
  /// away from Sonarr and keeps its Hero flight, because the list it flew from
  /// and the page it flew to share one Navigator.
  static const sonarrSeriesBase = '$sonarrLibrary/series';

  static const lidarrOverview = '$lidarr/overview';
  static const lidarrLibrary = '$lidarr/library';

  /// The artist, inside the Library tab's branch. The tab is drawn as one
  /// segmented view of Artists and Albums (decision 24), but an album has no
  /// route of its own to give: `getAllAlbums()` does not exist on
  /// `LidarrService`, so there is one record type here and not two.
  static const lidarrArtistBase = '$lidarrLibrary/artist';

  // ── The download clients, under the tab model ────────────────────────────
  //
  // Literals for the reason the \*arr block gives: an enum instance's field is
  // not a compile-time constant in Dart and these have to stay `const`, so
  // nothing the analyzer sees ties a spelling to its tab. A test does, one per
  // service.
  //
  // The four do **not** share a bar the way the four \*arr do — qBittorrent has
  // RSS where Transmission has Labels and Session, and the two Usenet clients
  // carry History — so there is no shared list to factor out here. What they do
  // share is the shape: Overview first, the queue that was the whole service
  // second, and the job detail pushed inside that Queue branch.
  static const qbittorrentOverview = '$qbittorrent/overview';
  static const qbittorrentQueue = '$qbittorrent/queue';
  static const qbittorrentRss = '$qbittorrent/rss';

  /// The torrent, inside the Queue tab's branch.
  ///
  /// It used to hang off the service root, which was the only place it could
  /// hang from when the service was one page. Inside the branch it survives a
  /// switch away from qBittorrent and back, and the row it was pushed from is
  /// still under it on the same Navigator.
  static const qbittorrentTorrentBase = '$qbittorrentQueue/torrent';

  /// Transmission has no detail route to move, and that absence is the shape
  /// rather than an omission: the torrent list is expandable rows and there has
  /// never been a page to push, so Queue is a leaf branch.
  static const transmissionOverview = '$transmission/overview';
  static const transmissionQueue = '$transmission/queue';
  static const transmissionLabels = '$transmission/labels';
  static const transmissionSession = '$transmission/session';

  /// SABnzbd and NZBGet both keep a History tab, and neither has a job detail:
  /// a queue slot and a history slot are each one row that expands, so both
  /// Queue branches are leaves like Transmission's.
  static const sabnzbdOverview = '$sabnzbd/overview';
  static const sabnzbdQueue = '$sabnzbd/queue';
  static const sabnzbdHistory = '$sabnzbd/history';
  static const sabnzbdServers = '$sabnzbd/servers';

  /// NZBGet carries the widest bar of the four: five tabs, because the daemon
  /// keeps its feeds and its log as first-class things the other three do not
  /// have.
  static const nzbgetOverview = '$nzbget/overview';
  static const nzbgetQueue = '$nzbget/queue';
  static const nzbgetHistory = '$nzbget/history';
  static const nzbgetFeeds = '$nzbget/feeds';
  static const nzbgetMessages = '$nzbget/messages';

  static const bazarrWanted = '$bazarr/wanted';
  static const bazarrLibrary = '$bazarr/library';
  static const bazarrSeriesBase = '$bazarr/series';
  static const bazarrMovieBase = '$bazarr/movie';

  // ── Prowlarr ──────────────────────────────────────────────────────────────
  static const prowlarrLibrary = '$prowlarr/library';
  static const prowlarrIndexerBase = '$prowlarr/indexer';
  static const prowlarrSettings = '$prowlarr/settings';
  static const prowlarrSyncProfiles = '$prowlarrSettings/sync-profiles';
  static const prowlarrTags = '$prowlarrSettings/tags';

  /// Indexer detail, e.g. `/services/prowlarr/indexer/3`.
  static String prowlarrIndexer(int id) => '$prowlarrIndexerBase/$id';

  /// One of the field-driven settings sections, e.g.
  /// `/services/prowlarr/settings/apps`.
  static String prowlarrSettingsSection(ProwlarrProviderKind kind) =>
      '$prowlarrSettings/${kind.routeSegment}';

  // ── Readarr, under the tab model ──────────────────────────────────────────
  //
  // Literals, like the other three arrs, and tied to their tabs by a test.
  // `readarrLibrary` predates the model and needed no change: the author list
  // was already a page at `/dashboard/readarr/library`, which is exactly where
  // the Library tab's root mounts — so every link that ever pointed at it still
  // points at it, this time at a tab rather than at a pushed page.
  static const readarrOverview = '$readarr/overview';
  static const readarrLibrary = '$readarr/library';

  // ── Dockge ────────────────────────────────────────────────────────────────
  static const dockgeStackBase = '$dockge/stack';
  static const dockgeNewStack = '$dockge/new';

  /// Stack detail, e.g. `/services/dockge/stack/immich`.
  static String dockgeStack(String name) => '$dockgeStackBase/$name';

  /// Compose editor for a stack, e.g. `/services/dockge/stack/immich/edit`.
  static String dockgeStackEdit(String name) => '$dockgeStackBase/$name/edit';

  /// ## `i`: which connection a detail page belongs to
  ///
  /// Every detail route below takes an optional `?i=<instanceId>`. Absent — the
  /// shape every link in the app had before there could be two of a service —
  /// means "whichever one this service is being read through", so nothing that
  /// does not care has to say anything.
  ///
  /// A **query** rather than a path segment, and the difference is a hundred
  /// lines: `state.uri` is the whole URI at every level of nesting, so a nested
  /// route reads it without being told, while `pathParameters` is a map
  /// accumulated down the tree and a new segment would have to be declared on
  /// every one of the descendants under it. It is also not `extra`: go_router
  /// replaces a non-JSON-encodable extra with null, silently, when it
  /// serialises the match list for state restoration — a vector that survives
  /// normal use and evaporates when the OS kills the app is the worst of the
  /// three options.
  static String radarrMovie(int id, {String? heroTag, String? instanceId}) {
    return _withQuery('$radarrMovieBase/$id', {
      'heroTag': heroTag,
      'i': instanceId,
    });
  }

  static String sonarrSeries(int id, {String? heroTag, String? instanceId}) {
    return _withQuery('$sonarrSeriesBase/$id', {
      'heroTag': heroTag,
      'i': instanceId,
    });
  }

  static String lidarrArtist(int id, {String? heroTag, String? instanceId}) {
    return _withQuery('$lidarrArtistBase/$id', {
      'heroTag': heroTag,
      'i': instanceId,
    });
  }

  static String qbittorrentTorrent(String hash) {
    return '$qbittorrentTorrentBase/$hash';
  }

  /// No `i` on the two Bazarr routes, and that is the honest shape rather than
  /// an omission: a Bazarr row's id is a **third** server's (`radarrId` /
  /// `sonarrSeriesId`), so the connection that matters at the destination is an
  /// arr's, which nothing on the row knows. They briefly took an `instanceId`
  /// that no caller passed and no route read.
  static String bazarrSeries(int sonarrSeriesId, {String? heroTag}) {
    return _withQuery('$bazarrSeriesBase/$sonarrSeriesId', {
      'heroTag': heroTag,
    });
  }

  static String bazarrMovie(int radarrId, {String? heroTag}) {
    return _withQuery('$bazarrMovieBase/$radarrId', {'heroTag': heroTag});
  }

  /// Likewise no `i`: Discover resolves through the lens end to end, so a
  /// connection in the URL would be a claim the page cannot honour. The day
  /// `_discoverDetailPage` reads one, this is where it goes back.
  static String seerrDetail({
    required String mediaType,
    required int id,
    String? heroTag,
    String? posterUrl,
  }) {
    final normalizedMediaType = mediaType == 'tv' ? 'tv' : 'movie';
    return _withQuery('$seerr/$normalizedMediaType/$id', {
      'heroTag': heroTag,
      'posterUrl': posterUrl,
    });
  }

  /// App settings, and the per-service page under it.
  ///
  /// Three widgets were interpolating the per-service settings path by hand —
  /// the not-configured leaf, the cross-service toast and the capability
  /// toast — which is exactly the kind of string that survives a route rename
  /// by silently 404ing in the one state nobody screenshots.
  static const settings = '/settings';
  static const settingsConnections = '$settings/connections';

  /// Where the fix lives for a service that is not set up, or whose credential
  /// is too narrow: its own settings page, where its setup note is printed.
  static String settingsFor(ServiceKey service) =>
      '$settings/service/${service.routeParam}';

  static String _withQuery(String path, Map<String, String?> queryParameters) {
    final values = {
      for (final entry in queryParameters.entries)
        if (entry.value != null && entry.value!.isNotEmpty)
          entry.key: entry.value!,
    };

    if (values.isEmpty) {
      return path;
    }

    return Uri(path: path, queryParameters: values).toString();
  }
}
