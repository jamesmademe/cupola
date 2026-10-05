import 'package:cupola/features/media/domain/media_key.dart';
import 'package:cupola/features/prowlarr/domain/models/prowlarr_models.dart';
import 'package:cupola/features/settings/domain/connection_access.dart';
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

  // ── The media servers, under the tab model ────────────────────────────────
  //
  // Literals, like every other service's, and tied to their tabs by a test: an
  // enum instance's field is not a compile-time constant in Dart and these have
  // to stay `const`, so nothing the analyzer sees ties a spelling to
  // `ServiceTab.segment`.
  //
  // Jellyfin and Plex share one screen family and **not** one bar, which is why
  // the two blocks below are spelled out separately rather than factored into a
  // shared shape: the surfaces are written against `StreamServerClient` and take
  // the service as a parameter, but the tabs come from what each API can answer
  // — Jellyfin has users, devices and scheduled tasks, Plex has an on-deck hub,
  // its own activities and playlists — and a shared spelling would have to
  // invent a name one of them does not use.
  //
  // Both route shapes stay uniform in the way the arrs are not: a Jellyfin
  // `BaseItemDto` and a Plex `Metadata` describe a movie, a series, a season and
  // an episode with the same fields, so **one** recursive item route covers the
  // whole tree where Radarr, Sonarr and Lidarr each needed their own screen.
  static const jellyfinOverview = '$jellyfin/overview';

  /// The Libraries tab's root, **and** the base of one library's browse under
  /// it — one constant because they are one address, the way
  /// [bazarrSeriesBase] is.
  ///
  /// This one **moved**: the browse was `/dashboard/jellyfin/library/:id`, a
  /// sibling of nothing, and the tab's segment is the plural the bar draws. The
  /// old spelling still resolves; `router.dart` keeps a childless tail for it.
  static const jellyfinLibraries = '$jellyfin/libraries';

  /// The item, inside the Libraries tab's branch — the same move Radarr's film
  /// made into Library, and for the same two reasons: a detail pushed *inside*
  /// its tab survives a switch away from the service, and the poster it flew
  /// from is still under it on one Navigator, so the Hero still flies.
  ///
  /// Declared under `libraries/` and not beside it, which is also what makes
  /// the literal-before-parameter order in `router.dart` load-bearing: `item`
  /// competes with the library browse's `:id` in the same branch.
  static const jellyfinItemBase = '$jellyfinLibraries/item';

  static const jellyfinUsers = '$jellyfin/users';
  static const jellyfinDevices = '$jellyfin/devices';
  static const jellyfinTasks = '$jellyfin/tasks';
  static const jellyfinActivity = '$jellyfin/activity';

  static const plexOverview = '$plex/overview';

  /// The same two roles [jellyfinLibraries] carries, and the same move: the
  /// browse was `/dashboard/plex/library/:id` and a childless tail keeps that
  /// spelling resolving.
  static const plexLibraries = '$plex/libraries';
  static const plexItemBase = '$plexLibraries/item';

  /// `on-deck`, hyphenated, because that is how Plex writes it and the app does
  /// not rename another product's furniture — `ServiceTab.onDeck.segment` is
  /// the one tab segment that is not simply its enum name.
  static const plexOnDeck = '$plex/on-deck';
  static const plexActivities = '$plex/activities';
  static const plexDevices = '$plex/devices';
  static const plexPlaylists = '$plex/playlists';

  /// One library's browse route, e.g.
  /// `/dashboard/jellyfin/libraries/f137a2dd`.
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

  /// [jellyfinItem] or [plexItem], by [service].
  static String streamItem(ServiceKey service, String id) =>
      service == ServiceKey.jellyfin ? jellyfinItem(id) : plexItem(id);

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

  // ── Seerr, under the tab model ────────────────────────────────────────────
  //
  // Literals for the reason the \*arr block gives below: an enum instance's
  // field is not a compile-time constant in Dart and these have to stay
  // `const`, so nothing the analyzer sees ties a spelling to its tab. A test
  // does.
  //
  // Seerr carried more pre-tab link shapes than any other service — three
  // see-alls, a genre tree, two media details, a person and a collection — and
  // **every one of them moved under `discover/`**, because Discover is the tab
  // that owns them: each is reached by tapping a row of the Discover page, and
  // a page pushed inside its own tab's branch survives a switch away from Seerr
  // and keeps its Hero flight. The old spellings still resolve; `router.dart`
  // keeps one childless redirect tail per shape.
  static const seerrOverview = '$seerr/overview';

  /// Unchanged by the migration, and that is the point: the all-requests list
  /// was already a page at `/dashboard/seerr/requests`, which is exactly where
  /// the Requests tab's root mounts — so every link that ever pointed at it
  /// still points at it, this time at a tab rather than at a pushed page.
  static const seerrRequests = '$seerr/requests';
  static const seerrIssues = '$seerr/issues';
  static const seerrDiscover = '$seerr/discover';
  static const seerrUsers = '$seerr/users';

  static const seerrMoviesAll = '$seerrDiscover/movies/all';
  static const seerrTvAll = '$seerrDiscover/tv/all';
  static const seerrTrendingAll = '$seerrDiscover/trending/all';
  static const seerrGenreBase = '$seerrDiscover/genre';
  static const seerrPersonBase = '$seerrDiscover/person';
  static const seerrCollectionBase = '$seerrDiscover/collection';

  /// Person (cast member) detail page, e.g.
  /// `/dashboard/seerr/discover/person/287`.
  static String seerrPerson(int id, {String? heroTag, String? posterUrl}) {
    return _withQuery('$seerrPersonBase/$id', {
      'heroTag': heroTag,
      'posterUrl': posterUrl,
    });
  }

  /// Movie collection detail page, e.g.
  /// `/dashboard/seerr/discover/collection/10`.
  static String seerrCollection(int id, {String? heroTag}) {
    return _withQuery('$seerrCollectionBase/$id', {'heroTag': heroTag});
  }

  /// See-all for a single genre row, e.g.
  /// `/dashboard/seerr/discover/genre/movie/28?title=Action`.
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

  // ── Bazarr, under the tab model ───────────────────────────────────────────
  //
  // Literals, like every other service's, and tied to their tabs by a test.
  //
  // Bazarr is the one service whose bar names the record types themselves —
  // Series and Movies, where the \*arr say Library — so the detail spelling is
  // `<tab>/:id` and not `<tab>/<record>/:id`: `series/series/42` would be a
  // stutter nobody would type. `bazarrSeriesBase` therefore needed no change at
  // all, which is the happiest case of the migration: every link that ever
  // pointed at a Bazarr series still points at it, now at a page inside the
  // Series tab's branch rather than at a sibling of the tabs.
  static const bazarrOverview = '$bazarr/overview';
  static const bazarrWanted = '$bazarr/wanted';
  static const bazarrHistory = '$bazarr/history';
  static const bazarrProviders = '$bazarr/providers';

  /// The Series tab's root, **and** the base of the series detail under it —
  /// one constant because they are one address. Unchanged by the migration,
  /// which is the happiest case it had: every link that ever pointed at a
  /// Bazarr series still points at it, now at a page inside the Series tab's
  /// branch rather than at a sibling of the tabs.
  ///
  /// There is no `bazarrSeries` constant beside it because [bazarrSeries] is
  /// already the function that builds one.
  static const bazarrSeriesBase = '$bazarr/series';

  /// The Movies tab's root, and the base of the film detail under it. This one
  /// **did** move: it was `/dashboard/bazarr/movie/:id`, singular, a sibling of
  /// nothing. The old spelling still resolves; `router.dart` keeps a childless
  /// tail for it.
  static const bazarrMovieBase = '$bazarr/movies';

  // ── Prowlarr, under the tab model ─────────────────────────────────────────
  //
  // Literals, like every other service's, and tied to their tabs by a test.
  //
  // `library` became `indexers`, which is what the bar calls it and what the
  // page always was: a list of indexers under a heading that said Library
  // because every other service's list did. The old spelling still resolves;
  // `router.dart` keeps a childless tail for it.
  static const prowlarrOverview = '$prowlarr/overview';
  static const prowlarrIndexers = '$prowlarr/indexers';
  static const prowlarrHistory = '$prowlarr/history';
  static const prowlarrStats = '$prowlarr/stats';

  /// The indexer, inside the Indexers tab's branch — the same move the film
  /// made into Radarr's Library, and for the same reasons: a detail pushed
  /// *inside* its tab survives a switch away from Prowlarr, and the row it was
  /// pushed from is still under it on one Navigator.
  static const prowlarrIndexerBase = '$prowlarrIndexers/indexer';

  /// Prowlarr's own Settings, which is **not** a tab (decision 26): Apps,
  /// download clients, notifications and indexer proxies are sections of one
  /// field-driven page, and a fifth bar entry for a configuration screen is a
  /// bar entry nobody opens twice. It stays a page pushed from the service, so
  /// it hangs off the service node beside the shell rather than inside a
  /// branch — no one tab owns it.
  static const prowlarrSettings = '$prowlarr/settings';
  static const prowlarrSyncProfiles = '$prowlarrSettings/sync-profiles';
  static const prowlarrTags = '$prowlarrSettings/tags';

  /// Indexer detail, e.g. `/dashboard/prowlarr/indexers/indexer/3`.
  static String prowlarrIndexer(int id) => '$prowlarrIndexerBase/$id';

  /// One of the field-driven settings sections, e.g.
  /// `/dashboard/prowlarr/settings/apps`.
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

  // ── The infrastructure three, under the tab model ─────────────────────────
  //
  // Literals, like every other service's, and tied to their tabs by a test: an
  // enum instance's field is not a compile-time constant in Dart and these have
  // to stay `const`, so nothing the analyzer sees ties a spelling to
  // `ServiceTab.segment`. An earlier attempt at composing one shipped a path
  // containing a literal dollar sign that no analyzer could see.
  //
  // Three services with nothing else in common — a Compose manager, a NAS and a
  // reverse proxy — so there is no shared shape to factor out here and the
  // blocks below are spelled out one at a time. What they did share was being
  // **one page each**: every route below that is not a tab root used to hang off
  // the service root, because a one-page service had nowhere else to hang it.
  static const dockgeOverview = '$dockge/overview';
  static const dockgeStacks = '$dockge/stacks';
  static const dockgeTerminal = '$dockge/terminal';

  /// The stack, inside the Stacks tab's branch — the move Radarr's film made
  /// into Library, and for the same two reasons: a detail pushed *inside* its
  /// tab survives a switch away from Dockge and back, and the row it was pushed
  /// from is still under it on one Navigator.
  ///
  /// It was `/dashboard/dockge/stack/:name`, a sibling of nothing. The old
  /// spelling still resolves; `router.dart` keeps a childless tail for it, and
  /// a second one for the editor a segment deeper.
  static const dockgeStackBase = '$dockgeStacks/stack';

  /// The new-stack editor, inside the same branch and for the same reason: it
  /// is reached by the New button in the Stacks list's own header, so Stacks is
  /// the tab that owns it. It was `/dashboard/dockge/new`.
  static const dockgeNewStack = '$dockgeStacks/new';

  /// Stack detail, e.g. `/dashboard/dockge/stacks/stack/immich`.
  static String dockgeStack(String name) => '$dockgeStackBase/$name';

  /// Compose editor for a stack, e.g.
  /// `/dashboard/dockge/stacks/stack/immich/edit`.
  static String dockgeStackEdit(String name) => '$dockgeStackBase/$name/edit';

  /// Unraid's six, and not one of them moved: the service shipped exactly one
  /// path — its bare root — so there is no pre-tab spelling to keep resolving
  /// beyond that root, the way Transmission had none.
  static const unraidOverview = '$unraid/overview';
  static const unraidArray = '$unraid/array';
  static const unraidDocker = '$unraid/docker';
  static const unraidVms = '$unraid/vms';
  static const unraidNotifications = '$unraid/notifications';
  static const unraidShares = '$unraid/shares';

  /// Nginx Proxy Manager's five. Spelled `npm…` rather than
  /// `nginxProxyManager…` because that is what the whole feature is called —
  /// `NpmScreen`, `npmClientProvider`, `lib/features/npm/` — while
  /// [nginxProxyManager] keeps the product's full name because it is the one
  /// constant that *names the service*.
  ///
  /// Three of the five segments are hyphenated where the label has a space, and
  /// that is `ServiceTab.segment`'s job rather than a spelling invented here.
  /// Like Unraid, NPM shipped one path and there is nothing to forward.
  static const npmOverview = '$nginxProxyManager/overview';
  static const npmProxyHosts = '$nginxProxyManager/proxy-hosts';
  static const npmCertificates = '$nginxProxyManager/certificates';
  static const npmAccessLists = '$nginxProxyManager/access-lists';
  static const npmAuditLog = '$nginxProxyManager/audit-log';

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
    return _withQuery('$seerrDiscover/$normalizedMediaType/$id', {
      'heroTag': heroTag,
      'posterUrl': posterUrl,
    });
  }

  /// The two top-level tabs a title can be opened from besides the Dashboard.
  static const activity = '/activity';
  static const search = '/search';

  /// ## The one page a title has
  ///
  /// A title's page hangs off every branch that opens titles, at the title's
  /// own location (`MediaKey.location`, `/media/movie/653`): the Dashboard,
  /// Activity, Search, and every tab of the services in [mediaMountServices].
  /// One page mounted many times rather than one route at the root, for the
  /// two reasons the arr details moved inside Library: the poster's Hero flies
  /// only when the tile it left and the page it lands on share one Navigator,
  /// and a tab left and come back to still shows the title.
  ///
  /// The root mounts it once more, for the pages that sit above the tabs
  /// (`/activity/movies`, the import flow): a page pushed into a tab from one
  /// of those would open underneath it.
  static const mediaMountServices = {
    ServiceKey.seerr,
    ServiceKey.radarr,
    ServiceKey.sonarr,
    ServiceKey.jellyfin,
    ServiceKey.plex,
  };

  /// Where a title opened from [path] lands: under the service tab [path] is
  /// in when that service mounts titles, else under its top-level tab, else
  /// at the root. [path] is a location the app is at, never a redirecting
  /// one.
  static String mediaMountFor(String path) =>
      switch (Uri.parse(path).pathSegments) {
        ['dashboard', final service, final tab, ...]
            when mediaMountServices.any((s) => s.routeParam == service) =>
          '$dashboard/$service/$tab',
        ['dashboard', ...] => dashboard,
        ['activity'] || ['activity', 'media', ...] => activity,
        ['search', ...] => search,
        _ => '',
      };

  /// The page of [key], opened from the page at [from]. [focus] is the
  /// connection it was opened from (`?i=`, above): that copy leads when it
  /// needs something. [heroTag] lets the poster fly, and [posterUrl] stands
  /// in for it until the page has read who the title is.
  static String media(
    MediaKey key, {
    required String from,
    String? focus,
    String? heroTag,
    String? posterUrl,
  }) => _withQuery('${mediaMountFor(from)}${key.location}', {
    'i': focus,
    'heroTag': heroTag,
    'posterUrl': posterUrl,
  });

  /// The page of [key] for a caller with no page of its own to open it
  /// from (a row built by a provider): the root form, which
  /// [mounted] moves under the tab it is opened from.
  static String mediaRoot(
    MediaKey key, {
    String? focus,
    String? heroTag,
    String? posterUrl,
  }) => media(
    key,
    from: '',
    focus: focus,
    heroTag: heroTag,
    posterUrl: posterUrl,
  );

  /// [location] as it is opened from the page at [from]: a title's page in
  /// root form ([mediaRoot]) moves under the mount [from] is in; anything
  /// else stays as it is.
  static String mounted(String location, {required String from}) =>
      location.startsWith('/media/')
      ? '${mediaMountFor(from)}$location'
      : location;

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

  /// Where every `Set up X` goes: the service's own setup form.
  ///
  /// One destination for one verb. The matrix cell and the not-set-up leaf
  /// sent the user to the connections list, a cross-service control's toast
  /// to the form, and Streaming's empty state to the Dashboard — three places
  /// for the same tap. Every surface that says `Set up X` (the lexicon's
  /// `Lexicon.setUp`) navigates here, and nowhere else.
  static String setUp(ServiceKey service) => settingsFor(service);

  /// The settings form of one saved connection of [service] — where a
  /// too-narrow credential is replaced.
  ///
  /// Not [settingsFor]: a service can have two connections, and the fix for a
  /// read-only key on the second one has to land on the second one's form
  /// rather than on the first, which is fine. An empty [connectionId] collapses
  /// to [settingsFor].
  ///
  /// [access] opens the form on its Access row with that choice made, for a
  /// gateway's remedy (`Add a service token` lands on Cloudflare Access).
  static String settingsForConnection(
    ServiceKey service,
    String connectionId, {
    AccessKind? access,
  }) => _withQuery(settingsFor(service), {
    'i': connectionId,
    'access': access?.name,
  });

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
