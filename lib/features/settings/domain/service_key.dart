import 'package:flutter/material.dart';

import 'package:cupola/core/theme.dart';
import 'package:cupola/features/truenas/domain/truenas_version.dart';

enum ServiceKey {
  seerr,
  radarr,
  sonarr,
  lidarr,
  qbittorrent,
  transmission,
  bazarr,
  truenas,
  dockge,
  prowlarr,
  readarr,
  sabnzbd,
  nzbget,
  unraid,
  nginxProxyManager,
  jellyfin,
  plex,
}

/// High-level grouping used to organise services across the app.
///
/// Cupola started as a media companion but is growing into a homelab hub, so
/// services are grouped by the kind of job they do. This enum is the single
/// source of truth for that grouping — the Home dashboard, Settings and the
/// onboarding flow all read from it, so a new service only needs a [domain]
/// assignment in one place.
enum ServiceDomain {
  media(label: 'Media'),
  downloads(label: 'Downloads'),

  /// Media servers — the only services in the app that know about *people*.
  ///
  /// Every other domain answers questions about objects: is this film owned,
  /// grabbed, subtitled, on disk. A media server is the only source of
  /// subject-and-time state — who is watching, where they stopped, what is next
  /// for them, what nobody has played. That is why this is its own domain and
  /// not more Media, and it is the guard against re-rendering Radarr's library
  /// under a second name.
  ///
  /// Ordered between [downloads] and [infrastructure] deliberately: the bands
  /// then read as the pipeline they are — catalogue, acquire, watch, and the box
  /// it all runs on.
  stream(label: 'Stream'),
  infrastructure(label: 'Infrastructure');

  const ServiceDomain({required this.label});

  final String label;

  /// The configured services belonging to this domain, in declaration order.
  List<ServiceKey> get services =>
      ServiceKey.values.where((s) => s.domain == this).toList(growable: false);
}

extension ServiceKeyExtension on ServiceKey {
  /// Which [ServiceDomain] this service belongs to. See [ServiceDomain].
  ServiceDomain get domain => switch (this) {
    ServiceKey.seerr ||
    ServiceKey.radarr ||
    ServiceKey.sonarr ||
    ServiceKey.lidarr ||
    ServiceKey.bazarr ||
    ServiceKey.readarr => ServiceDomain.media,
    ServiceKey.qbittorrent ||
    ServiceKey.transmission ||
    ServiceKey.prowlarr ||
    ServiceKey.sabnzbd ||
    ServiceKey.nzbget => ServiceDomain.downloads,
    ServiceKey.jellyfin || ServiceKey.plex => ServiceDomain.stream,
    ServiceKey.truenas ||
    ServiceKey.dockge ||
    ServiceKey.unraid ||
    // A reverse proxy is not a download client that happens to run on the
    // box: it is the box's front door. Every other service in the app is
    // usually reached *through* it, which is exactly why it belongs beside
    // the NAS and the container manager rather than anywhere else.
    ServiceKey.nginxProxyManager => ServiceDomain.infrastructure,
  };

  /// Whether tapping this service opens a full multi-screen console (with its
  /// own inner navigation) rather than a single detail screen. Heavy services
  /// like TrueNAS and Dockge are effectively sub-apps.
  bool get isFullConsole =>
      this == ServiceKey.truenas || this == ServiceKey.dockge;

  String get title => switch (this) {
    ServiceKey.seerr => 'Seerr',
    ServiceKey.radarr => 'Radarr',
    ServiceKey.sonarr => 'Sonarr',
    ServiceKey.lidarr => 'Lidarr',
    ServiceKey.qbittorrent => 'qBittorrent',
    ServiceKey.transmission => 'Transmission',
    ServiceKey.nginxProxyManager => 'Nginx Proxy Manager',
    ServiceKey.bazarr => 'Bazarr',
    ServiceKey.truenas => 'TrueNAS',
    ServiceKey.dockge => 'Dockge',
    ServiceKey.prowlarr => 'Prowlarr',
    ServiceKey.readarr => 'Readarr',
    ServiceKey.sabnzbd => 'SABnzbd',
    ServiceKey.nzbget => 'NZBGet',
    ServiceKey.unraid => 'Unraid',
    ServiceKey.jellyfin => 'Jellyfin',
    ServiceKey.plex => 'Plex',
  };

  IconData get icon => switch (this) {
    ServiceKey.seerr => Icons.search_rounded,
    ServiceKey.radarr => Icons.movie_rounded,
    ServiceKey.sonarr => Icons.tv_rounded,
    ServiceKey.lidarr => Icons.music_note_rounded,
    ServiceKey.qbittorrent => Icons.download_rounded,
    // Told apart from the three download clients by *direction*, not detail:
    // theirs are all one-way arrows into the box, and a BitTorrent daemon is
    // the one client in the group that is equally busy sending. The paired
    // arrows survive the 18pt matrix glyph where a restyled download arrow
    // would read as a second qBittorrent.
    ServiceKey.transmission => Icons.swap_vert_rounded,
    // A reverse proxy is a fork in the road — one address in, many services
    // out. Distinct at glyph size from TrueNAS's drive stack, Dockge's
    // layers and Unraid's board.
    ServiceKey.nginxProxyManager => Icons.alt_route_rounded,
    ServiceKey.bazarr => Icons.subtitles_rounded,
    ServiceKey.truenas => Icons.storage_rounded,
    ServiceKey.dockge => Icons.layers_rounded,
    ServiceKey.prowlarr => Icons.travel_explore_rounded,
    ServiceKey.readarr => Icons.menu_book_rounded,
    ServiceKey.sabnzbd => Icons.cloud_download_rounded,
    ServiceKey.nzbget => Icons.cloud_sync_rounded,
    ServiceKey.unraid => Icons.developer_board_rounded,
    // The two media servers do the same job, so they are told apart by
    // *silhouette* rather than by detail: a circle against a rounded
    // rectangle survives the 18pt glyph on an expanded matrix cell and the
    // 32pt one on a folded card, where two screen-shaped glyphs would not.
    // Neither may be `live_tv_rounded` — that is a TV outline with signal
    // arcs and collides with Sonarr's `tv_rounded` at cell size.
    ServiceKey.jellyfin => Icons.play_circle_rounded,
    ServiceKey.plex => Icons.smart_display_rounded,
  };

  Color get accent => switch (this) {
    ServiceKey.seerr => AppColors.seerr,
    ServiceKey.radarr => AppColors.radarr,
    ServiceKey.sonarr => AppColors.sonarr,
    ServiceKey.lidarr => AppColors.lidarr,
    ServiceKey.qbittorrent => AppColors.qbittorrent,
    ServiceKey.transmission => AppColors.transmission,
    ServiceKey.nginxProxyManager => AppColors.nginxProxyManager,
    ServiceKey.bazarr => AppColors.bazarr,
    ServiceKey.truenas => AppColors.truenas,
    ServiceKey.dockge => AppColors.dockge,
    ServiceKey.prowlarr => AppColors.prowlarr,
    ServiceKey.readarr => AppColors.readarr,
    ServiceKey.sabnzbd => AppColors.sabnzbd,
    ServiceKey.nzbget => AppColors.nzbget,
    ServiceKey.unraid => AppColors.unraid,
    ServiceKey.jellyfin => AppColors.jellyfin,
    ServiceKey.plex => AppColors.plex,
  };

  /// Whether this service authenticates with a single API key rather than a
  /// username and password.
  ///
  /// **The one place the app decides that.** Persistence, the settings form and
  /// the verifier all read this rather than re-deriving "is it one of these
  /// three" — the three-way check used to be spelled out in five files, so the
  /// next credential-authenticated service could be added to four of them and
  /// leave storage and the UI disagreeing about which fields even exist.
  ///
  /// Written as an exhaustive `switch` on purpose: a `!=` chain would silently
  /// class a newly added service as API-key authenticated, whereas this makes
  /// the compiler ask.
  bool get usesApiKey => switch (this) {
    ServiceKey.qbittorrent ||
    ServiceKey.dockge ||
    ServiceKey.nzbget ||
    // HTTP Basic, straight from `rpc-username`/`rpc-password`. Transmission
    // mints no key of any kind.
    ServiceKey.transmission ||
    // Nginx Proxy Manager has **no long-lived API key at all**: the only
    // credential it accepts is the account's own email and password, which
    // `POST /api/tokens` exchanges for a short-lived bearer token. That is a
    // property of the server, not a shortcut taken here — see [setupNote]
    // for what it means for the user.
    ServiceKey.nginxProxyManager => false,
    ServiceKey.seerr ||
    ServiceKey.radarr ||
    ServiceKey.sonarr ||
    ServiceKey.lidarr ||
    ServiceKey.bazarr ||
    ServiceKey.truenas ||
    ServiceKey.prowlarr ||
    ServiceKey.readarr ||
    ServiceKey.sabnzbd ||
    ServiceKey.unraid ||
    ServiceKey.jellyfin ||
    ServiceKey.plex => true,
  };

  /// Whether the library this service serves has to be entered through a chosen
  /// person, so the settings screen offers a viewer picker once it connects.
  ///
  /// True for Jellyfin alone, and structurally rather than by preference: a
  /// Jellyfin API key authenticates as an administrator with **no user
  /// attached**, so every user-scoped question (resume positions, next up,
  /// unplayed) needs a `userId` supplied explicitly. Plex is excluded because
  /// its token *is* its user and `/library/*` accepts no impersonation
  /// parameter — a Plex library has exactly one perspective. Expressed as a
  /// capability so the shared settings screen inserts the control the same way
  /// it decides on `SearchHeadroomCard.appliesTo`, rather than naming a
  /// `ServiceKey` inline.
  bool get needsViewerSelection => this == ServiceKey.jellyfin;

  /// The port this service listens on out of the box.
  ///
  /// Offered as a one-tap suggestion next to the address field, alongside the
  /// host carried over from the service configured before it — on a home lab one
  /// box usually runs everything on different ports, so between the two most
  /// services become a tap plus a pasted key. A suggestion only: a service
  /// behind a reverse proxy is reached on 443 with a path, and nothing here
  /// overwrites an address the user has already typed.
  int get defaultPort => switch (this) {
    ServiceKey.seerr => 5055,
    ServiceKey.radarr => 7878,
    ServiceKey.sonarr => 8989,
    ServiceKey.lidarr => 8686,
    ServiceKey.readarr => 8787,
    ServiceKey.prowlarr => 9696,
    ServiceKey.bazarr => 6767,
    ServiceKey.qbittorrent || ServiceKey.sabnzbd => 8080,
    ServiceKey.nzbget => 6789,
    ServiceKey.transmission => 9091,
    // 81, not 80 or 443. Those two are the proxy *doing its job* — the
    // hostnames it fronts. The admin interface, which is the only thing
    // carrying an API, listens separately.
    ServiceKey.nginxProxyManager => 81,
    ServiceKey.jellyfin => 8096,
    ServiceKey.plex => 32400,
    ServiceKey.dockge => 5001,
    // Both ship a TLS web UI on the standard port.
    ServiceKey.truenas || ServiceKey.unraid => 443,
  };

  /// What the credential is called in this service's own vocabulary.
  ///
  /// Plex calls its own credential a token, and the field has said so since the
  /// integration shipped; everything else keeps the wording the settings form
  /// already used, so moving the string into the registry changes where it lives
  /// and not what it says.
  String get credentialLabel =>
      this == ServiceKey.plex ? 'Plex token' : 'API Key';

  /// The word this service's secret is filed under in secure storage.
  ///
  /// The tail of `ServiceInstance.credentialStorageKey`, and the reason that
  /// key comes out byte-identical to the one an existing install already wrote:
  /// the suffix was never uniform. Three services' worth of vocabulary is
  /// already on disk — an arr files an `api_key`, qBittorrent a `password`,
  /// Plex a `token` — so this states it rather than flattening it and orphaning
  /// every stored secret.
  ///
  /// Not [credentialLabel] lowercased: that string is UI copy and may be
  /// reworded, while this one names bytes on disk and may not. They are allowed
  /// to drift, and keeping them apart is what makes that safe.
  ///
  /// Exhaustive on purpose, for the same reason [usesApiKey] is: a `!=` chain
  /// would silently file a newly added service under `api_key` and lose its
  /// secret the first time someone noticed.
  String get credentialStorageSuffix => switch (this) {
    ServiceKey.qbittorrent ||
    ServiceKey.transmission ||
    ServiceKey.nginxProxyManager ||
    ServiceKey.dockge ||
    ServiceKey.nzbget => 'password',
    ServiceKey.plex => 'token',
    ServiceKey.seerr ||
    ServiceKey.radarr ||
    ServiceKey.sonarr ||
    ServiceKey.lidarr ||
    ServiceKey.bazarr ||
    ServiceKey.truenas ||
    ServiceKey.prowlarr ||
    ServiceKey.readarr ||
    ServiceKey.sabnzbd ||
    ServiceKey.unraid ||
    ServiceKey.jellyfin => 'api_key',
  };

  /// Whether this service may hold more than one instance.
  ///
  /// True for every service, and stated as a named capability rather than left
  /// implicit because the question gets asked at a dozen call sites and the
  /// answer deserves one home. Two NAS in two houses, two Jellyfin for two
  /// households, a seedbox qBittorrent beside the one at home: none of these
  /// are stranger than 4K-and-1080p Radarr, and carving out a "singleton"
  /// class would mean defending an arbitrary line at every one of them.
  ///
  /// True means **reachable**, not merely storable. There was briefly a second
  /// flag here — `readsThroughLens` — that said no for Jellyfin, Plex and
  /// TrueNAS, whose clients were still built from the flat first-instance
  /// projections; it hid their lens badge and folded their picker cells, so a
  /// second connection of those three could be configured, probed and counted
  /// and then never opened. Their three client providers now go through
  /// `watchTransport` like everyone else, which is all that was ever missing,
  /// and the flag is gone rather than left standing at a permanent `true`.
  bool get supportsMultipleInstances => true;

  /// Whether the global search runs a **leg per connection** for this service.
  ///
  /// Narrower than [supportsMultipleInstances], and the difference is the tap
  /// rather than the query. Every service now reads through the lens, so moving
  /// it changes what any screen shows; a *section per connection*, though, is
  /// only honest if the row under it opens the server that listed it, which
  /// needs two things: a way to build
  /// a client for a named connection, and a detail route that carries and
  /// honours one. The three arrs have both. Seerr's detail path is the Discover
  /// feature, whose thirty-odd reads all resolve through the lens; Bazarr's ids
  /// are a *third* server's (`radarrId` / `sonarrSeriesId`), so its row does not
  /// even land on a Bazarr page. Both therefore search the lens and get one
  /// section, unlabelled — which is what they did before, rather than two
  /// sections with identical contents under two different names.
  ///
  /// Not contradicted by /activity fanning Seerr out over its connections: a
  /// request row opens the *requests list*, which carries `?i=` and honours it,
  /// not a Discover media page. The line here is drawn by the destination, and
  /// Seerr's search destination is still the lens-bound one.
  bool get searchesPerConnection => switch (this) {
    ServiceKey.radarr || ServiceKey.sonarr || ServiceKey.lidarr => true,
    _ => false,
  };

  /// What the *non-secret* half of a credential pair is called.
  ///
  /// The sibling of [credentialLabel], and it exists for one service: Nginx
  /// Proxy Manager authenticates on an account's **email**, and its
  /// `POST /api/tokens` rejects a bare username outright. Labelling that field
  /// "Username" would be an invitation to fail the login and then blame the
  /// password. Every other credential service really does want a username.
  String get usernameLabel =>
      this == ServiceKey.nginxProxyManager ? 'Email' : 'Username';

  /// Where the credential lives inside *this service's* own interface.
  ///
  /// A breadcrumb rather than prose, shown under the field it explains. Null for
  /// the services that authenticate with the web-UI login the user already
  /// knows, since there is nothing to go and find.
  String? get credentialPath => switch (this) {
    ServiceKey.radarr ||
    ServiceKey.sonarr ||
    ServiceKey.lidarr ||
    ServiceKey.readarr ||
    ServiceKey.prowlarr ||
    ServiceKey.bazarr ||
    ServiceKey.seerr => 'Settings → General → API Key',
    ServiceKey.sabnzbd => 'Config → General → API Key',
    ServiceKey.jellyfin => 'Dashboard → Advanced → API Keys',
    ServiceKey.truenas => 'Credentials → API Keys',
    ServiceKey.unraid => 'Settings → Management Access → Developer Options',
    ServiceKey.plex => 'any item → Get Info → View XML → copy X-Plex-Token',
    // Web-UI login: the user already has these.
    ServiceKey.qbittorrent ||
    ServiceKey.dockge ||
    ServiceKey.nzbget ||
    ServiceKey.transmission ||
    ServiceKey.nginxProxyManager => null,
  };

  /// Setup guidance shown above the address field, for the services where the
  /// API needs turning on first or the project itself carries a caveat worth
  /// stating before anything is typed.
  ///
  /// Registry data rather than an if-chain inside the shared settings screen,
  /// for the same reason [credentialLabel], [credentialPath] and [defaultPort]
  /// live here: everything a service *says about itself* belongs next to the
  /// rest of its description, so adding a service is one entry rather than a
  /// hunt through the screens that render it. Null for the majority, which need
  /// nothing said.
  String? get setupNote => switch (this) {
    ServiceKey.truenas =>
      'Requires TrueNAS SCALE $kTrueNasMinVersion or newer. Create an '
          'API key under Credentials → Local Users, and use the https:// '
          'address of the web UI.',
    ServiceKey.unraid =>
      'Enable the Unraid API first: Settings → Management Access → '
          'Developer Options → turn on the GraphQL sandbox, then create an '
          'API key under API Keys. Without this the endpoint will not '
          'respond.',
    // Readarr development stopped upstream. Saying so here is the honest
    // thing: the integration works against the last released API, but the
    // user should know they are pointing at a project that will not receive
    // fixes.
    ServiceKey.readarr =>
      'Readarr development has stopped upstream. Cupola targets its '
          'last released API, so existing instances keep working, but expect '
          'no new server-side fixes.',
    ServiceKey.jellyfin =>
      'Create an API key under Dashboard → Advanced → API Keys. The '
          'key authenticates as an administrator but carries no user of its '
          'own, so pick whose watch state to read below once the connection '
          'works.',
    // Naming the *kind* of token matters more than naming the place. Plex has
    // two, and the modern one is a dead end here: a JWT expires after seven
    // days and can only be refreshed through plex.tv, which Cupola never
    // calls. Saying so up front beats a week of working software.
    ServiceKey.plex =>
      'Open any item in Plex Web, choose Get Info → View XML, and copy '
          'the X-Plex-Token from the address bar. Cupola never contacts '
          'plex.tv, so it needs a long-lived device token, not a temporary '
          'one beginning "eyJ".',
    // The single most common reason a Transmission daemon is reachable in a
    // browser and not from a phone, and it is worth saying before the address
    // is typed rather than after a mystifying 403.
    ServiceKey.transmission =>
      'Use the same username and password the Transmission web '
          'interface asks for, and check that this device is allowed: '
          '`rpc-whitelist` defaults to 127.0.0.1 only, so a phone on the same '
          'network is refused until the range is widened. Note that '
          'Transmission has one all-or-nothing credential and it can set the '
          'script it runs when a download finishes, treat it as a login to '
          'the machine itself, and do not reuse a password from anywhere '
          'else.',
    // Says the uncomfortable thing plainly, because the user cannot choose
    // otherwise and deserves to know what they are handing over.
    ServiceKey.nginxProxyManager =>
      'Nginx Proxy Manager issues no API key, the only credential it '
          'accepts is an account login, which Cupola exchanges for a '
          'short-lived token it keeps in memory and never writes to disk. '
          'Create a dedicated user for Cupola rather than using your admin '
          'account, and point this at the admin interface (port 81 by '
          'default), not at a hostname the proxy serves.',
    ServiceKey.seerr ||
    ServiceKey.radarr ||
    ServiceKey.sonarr ||
    ServiceKey.lidarr ||
    ServiceKey.qbittorrent ||
    ServiceKey.bazarr ||
    ServiceKey.dockge ||
    ServiceKey.prowlarr ||
    ServiceKey.sabnzbd ||
    ServiceKey.nzbget => null,
  };

  /// The same caveats as [setupNote], said in the onboarding walk's voice: a
  /// sentence or two under the fields, for the services where something has to
  /// be true before the connection is worth testing.
  ///
  /// A second getter rather than a reuse of [setupNote] because the walk says
  /// less on purpose — its address field already prints the default port and
  /// its credential field the breadcrumb, so what is left to say is the caveat
  /// itself. It lives here for the reason [setupNote] does: what a service says
  /// about itself belongs beside the rest of its description, so a new service
  /// is one entry in this file rather than a hunt through the screens that
  /// render it. The walk used to carry its own copy of this list, and TrueNAS
  /// was missing from it — the version requirement was stated in Settings and
  /// nowhere in the flow that actually asks for the address.
  String? get walkNote => switch (this) {
    // Said before the test, not after: an older TrueNAS can connect and then
    // leave whole sections empty, which reads as a broken app rather than an
    // unsupported server.
    ServiceKey.truenas =>
      'Cupola supports TrueNAS SCALE $kTrueNasMinVersion or newer. An older '
          'release may connect and still leave whole sections empty.',
    ServiceKey.readarr =>
      'Readarr development has stopped upstream. Existing instances keep '
          'working against its last released API, but expect no new '
          'server-side fixes.',
    ServiceKey.unraid =>
      'Enable the Unraid API first, under Settings → Management Access → '
          'Developer Options. The endpoint stays silent until it is on.',
    ServiceKey.jellyfin =>
      'The key signs in as an administrator but carries no user of its '
          'own, so pick whose watch state to read in Settings afterwards.',
    ServiceKey.plex =>
      'It must be a long-lived device token: one beginning "eyJ" expires '
          'in 7 days and Cupola cannot renew it without contacting plex.tv.',
    // Transmission's one all-or-nothing credential and its `rpc-whitelist`
    // default are both reasons a daemon that works in a browser refuses a
    // phone, so they are worth a line here too.
    ServiceKey.transmission =>
      'Use the same login the Transmission web interface asks for, and widen '
          '`rpc-whitelist`, it defaults to 127.0.0.1, so this device is '
          'refused until it is listed.',
    ServiceKey.nginxProxyManager =>
      'Point this at the admin interface (port 81 by default), not at a '
          'hostname the proxy serves, and use a dedicated account rather than '
          'your admin one.',
    ServiceKey.seerr ||
    ServiceKey.radarr ||
    ServiceKey.sonarr ||
    ServiceKey.lidarr ||
    ServiceKey.qbittorrent ||
    ServiceKey.bazarr ||
    ServiceKey.dockge ||
    ServiceKey.prowlarr ||
    ServiceKey.sabnzbd ||
    ServiceKey.nzbget => null,
  };

  /// Whether the global search tab fans out to this service.
  ///
  /// **Jellyfin and Plex are deliberately excluded, and this is a design
  /// decision rather than an omission.** Adding them would make the same film
  /// return in up to six sections: Radarr and Sonarr "search" is `movie/lookup`
  /// and `series/lookup` — a TMDB/TVDB lookup, not a library search — so "Dune"
  /// already produces four groups, in `Future.wait` declaration order with no
  /// relevance ranking, and `_SearchSection` renders every group including the
  /// empty ones. A Stream match is worth strictly more as a *decoration* on the
  /// Radarr/Sonarr/Seerr row that is already there — "On Jellyfin · 34 min in" —
  /// joined on `tmdbId`, which is the same move `arrMediaExtrasSlots` already
  /// makes for Seerr data inside an arr screen.
  bool get isSearchable {
    return this == ServiceKey.seerr ||
        this == ServiceKey.radarr ||
        this == ServiceKey.sonarr ||
        this == ServiceKey.lidarr ||
        this == ServiceKey.bazarr;
  }

  bool get supportsManualImport {
    return this == ServiceKey.radarr ||
        this == ServiceKey.sonarr ||
        this == ServiceKey.lidarr;
  }

  String get apiVersion => switch (this) {
    ServiceKey.seerr || ServiceKey.lidarr || ServiceKey.readarr => 'v1',
    ServiceKey.radarr || ServiceKey.sonarr => 'v3',
    ServiceKey.qbittorrent => 'WebUI',
    ServiceKey.transmission => 'RPC',
    ServiceKey.nginxProxyManager => 'API',
    ServiceKey.bazarr => 'v1',
    ServiceKey.truenas => 'v25',
    ServiceKey.dockge => 'Socket.IO',
    ServiceKey.prowlarr => 'v1',
    ServiceKey.sabnzbd => 'API',
    ServiceKey.nzbget => 'JSON-RPC',
    ServiceKey.unraid => 'GraphQL',
    ServiceKey.jellyfin => 'v10',
    ServiceKey.plex => 'v1',
  };

  /// The endpoint used to prove a service is answering.
  ///
  /// Empty for the services that verify over something other than REST —
  /// TrueNAS (WebSocket JSON-RPC), Dockge (Socket.IO), SABnzbd (query-string
  /// API), NZBGet (JSON-RPC) and Unraid (GraphQL), each handled by its own
  /// branch in the version loader and in the credential verifier.
  ///
  /// Jellyfin's and Plex's entries are **reachability probes, not credential
  /// checks**: both are anonymous endpoints, and neither server reads the
  /// `X-Api-Key` header the shared `ApiClient` sends, so a 2xx here says nothing
  /// at all about the pasted credential. That is why those two verify through
  /// their own clients first and only fall back to this table to explain a
  /// refusal — see `diagnoseCredentials`.
  String get statusEndpoint => switch (this) {
    ServiceKey.seerr => '/api/v1/status',
    ServiceKey.radarr || ServiceKey.sonarr => '/api/v3/system/status',
    ServiceKey.lidarr => '/api/v1/system/status',
    ServiceKey.qbittorrent => '/api/v2/app/version',
    ServiceKey.bazarr => '/api/system/status',
    ServiceKey.prowlarr => '/api/v1/system/status',
    ServiceKey.readarr => '/api/v1/system/status',
    // Both media-server probes are deliberately the *unauthenticated* ones, so
    // reachability separates cleanly from credentials: a 200 here with a 401
    // elsewhere means "the box is up, the token is wrong", which is the single
    // most common Stream misconfiguration and the one a generic timeout hides.
    ServiceKey.jellyfin => '/System/Info/Public',
    ServiceKey.plex => '/identity',
    // Transmission (RPC envelope + session-id handshake) and Nginx Proxy
    // Manager (token exchange) join this group for the same reason: no plain
    // GET can separate "reachable" from "authenticated" for either.
    //
    // Handled over the RPC envelope in _loadVersion; the endpoint is a POST
    // with a session-id handshake, not a GET.
    ServiceKey.transmission ||
    // Handled in _loadVersion, which reads the unauthenticated `GET /api/`
    // through the client so the token exchange is not paid for a version
    // string.
    ServiceKey.nginxProxyManager ||
    // Handled over WebSocket in _loadVersion; no REST endpoint.
    ServiceKey.truenas ||
    // Handled over Socket.IO in _loadVersion; no REST endpoint.
    ServiceKey.dockge ||
    // Handled over the query-string API in _loadVersion; no REST endpoint.
    ServiceKey.sabnzbd ||
    // Handled over JSON-RPC in _loadVersion; no REST endpoint.
    ServiceKey.nzbget ||
    // Handled over GraphQL in _loadVersion; no REST endpoint.
    ServiceKey.unraid => '',
  };

  String get itemLabel => switch (this) {
    ServiceKey.seerr => 'requests',
    ServiceKey.radarr => 'movies',
    ServiceKey.sonarr => 'series',
    ServiceKey.lidarr => 'artists',
    ServiceKey.qbittorrent || ServiceKey.transmission => 'torrents',
    // The hostnames it fronts. Not "hosts" on its own — a homelab already
    // calls the physical boxes that, and this counts neither of them.
    ServiceKey.nginxProxyManager => 'proxy hosts',
    ServiceKey.bazarr => 'subtitles',
    ServiceKey.truenas => 'pools',
    ServiceKey.dockge => 'stacks',
    ServiceKey.prowlarr => 'indexers',
    ServiceKey.readarr => 'authors',
    ServiceKey.sabnzbd => 'downloads',
    ServiceKey.nzbget => 'downloads',
    ServiceKey.unraid => 'containers',
    // The top-level thing you enumerate on a media server. Not "movies" —
    // a single Jellyfin or Plex instance mixes films, shows and music, and
    // naming one of them would both misdescribe the server and read as a
    // duplicate of Radarr's or Sonarr's own label.
    ServiceKey.jellyfin || ServiceKey.plex => 'libraries',
  };

  String get routeParam => switch (this) {
    ServiceKey.seerr => 'seerr',
    // The only service whose enum name is camelCase, and a URL is the one
    // place that shows. Every other route segment is the lowercase name the
    // user would type, so this one is spelled out rather than derived.
    ServiceKey.nginxProxyManager => 'npm',
    ServiceKey.radarr ||
    ServiceKey.sonarr ||
    ServiceKey.lidarr ||
    ServiceKey.qbittorrent ||
    ServiceKey.transmission ||
    ServiceKey.bazarr ||
    ServiceKey.truenas ||
    ServiceKey.dockge ||
    ServiceKey.prowlarr ||
    ServiceKey.readarr ||
    ServiceKey.sabnzbd ||
    ServiceKey.nzbget ||
    ServiceKey.unraid ||
    ServiceKey.jellyfin ||
    ServiceKey.plex => name,
  };

  String? extractHost(String? url) {
    final value = url?.trim() ?? '';
    if (value.isEmpty) return null;
    final parseableValue = value.contains('://') ? value : 'http://$value';

    try {
      final uri = Uri.parse(parseableValue);
      if (uri.host.isNotEmpty) {
        return uri.hasPort ? '${uri.host}:${uri.port}' : uri.host;
      }

      return uri.path.isEmpty ? null : uri.path;
    } catch (_) {
      return null;
    }
  }
}
