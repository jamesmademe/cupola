/// The seven configuration profiles of the config inventory (P1–P7), as
/// values a test can pump.
///
/// ```dart
/// await pumpWithProfile(tester, Profiles.p6, child: const DashboardScreen());
/// ```
///
/// See `README.md` beside this file for what each profile is for.
library;

import 'package:cupola/core/utils/url_utils.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import 'config_profile.dart';
import 'fakes/media_fakes.dart';
import 'world.dart';

export 'config_profile.dart';
export 'fakes/infra_fakes.dart' show TrueNasRpcFault;
export 'profile_harness.dart';
export 'profile_network.dart';
export 'world.dart';

/// The credential a world connection is configured with, and the one Seerr's
/// settings hold for the same server.
String worldKey(String connectionId) => 'world-$connectionId-key';

ProfileConnection _api(
  String id,
  ServiceKey service,
  String url, {
  String label = '',
  String viewerId = '',
  ConnectionBehaviour behaviour = ConnectionBehaviour.answers,
  bool homeOnly = false,
}) => ProfileConnection(
  ServiceInstance(
    id: id,
    service: service,
    label: label,
    url: url,
    credential: worldKey(id),
    viewerId: viewerId,
  ),
  behaviour: behaviour,
  homeOnly: homeOnly,
);

ProfileConnection _login(
  String id,
  ServiceKey service,
  String url, {
  ConnectionBehaviour behaviour = ConnectionBehaviour.answers,
  bool homeOnly = false,
}) => ProfileConnection(
  ServiceInstance(
    id: id,
    service: service,
    url: url,
    username: 'admin',
    credential: worldKey(id),
  ),
  behaviour: behaviour,
  homeOnly: homeOnly,
);

/// The world's connections, one of each, in the brief's order.
abstract final class WorldConnections {
  static final seerr = _api(WorldIds.seerr, ServiceKey.seerr, WorldHosts.seerr);
  static final jellyfin = _api(
    WorldIds.jellyfin,
    ServiceKey.jellyfin,
    WorldHosts.jellyfin,
    viewerId: JellyfinFake.operatorId,
  );
  static final radarr = _api(
    WorldIds.radarr,
    ServiceKey.radarr,
    WorldHosts.radarr,
  );
  static final radarr4k = _api(
    WorldIds.radarr4k,
    ServiceKey.radarr,
    WorldHosts.radarr4k,
    label: '4K',
  );
  static final sonarr = _api(
    WorldIds.sonarr,
    ServiceKey.sonarr,
    WorldHosts.sonarr,
  );
  static final sonarrAnime = _api(
    WorldIds.sonarrAnime,
    ServiceKey.sonarr,
    WorldHosts.sonarrAnime,
    label: 'Anime',
  );
  static final lidarr = _api(
    WorldIds.lidarr,
    ServiceKey.lidarr,
    WorldHosts.lidarr,
  );
  static final bazarr = _api(
    WorldIds.bazarr,
    ServiceKey.bazarr,
    WorldHosts.bazarr,
  );
  static final prowlarr = _api(
    WorldIds.prowlarr,
    ServiceKey.prowlarr,
    WorldHosts.prowlarr,
  );
  static final qbittorrent = _login(
    WorldIds.qbittorrent,
    ServiceKey.qbittorrent,
    WorldHosts.qbittorrent,
  );
  static final sabnzbd = _api(
    WorldIds.sabnzbd,
    ServiceKey.sabnzbd,
    WorldHosts.sabnzbd,
  );
  static final truenas = _api(
    WorldIds.truenas,
    ServiceKey.truenas,
    WorldHosts.truenas,
  );
  static final dockge = _login(
    WorldIds.dockge,
    ServiceKey.dockge,
    WorldHosts.dockge,
  );
  static final plex = _api(WorldIds.plex, ServiceKey.plex, WorldHosts.plex);
  static final transmission = _login(
    WorldIds.transmission,
    ServiceKey.transmission,
    WorldHosts.transmission,
  );

  /// The cabin's Jellyfin, named by the user: in no profile, for a test that
  /// adds it with `ConfigProfile.withConnection` beside the unnamed one at
  /// home — two of a media server, one of them nobody named.
  static final jellyfinCabin = _api(
    WorldIds.jellyfinCabin,
    ServiceKey.jellyfin,
    WorldHosts.jellyfinCabin,
    label: 'Cabin',
    viewerId: JellyfinFake.operatorId,
  );

  /// The cabin's Seerr, named by the user: in no profile, for a test that
  /// adds it beside the unnamed one at home — two Seerr, each answering for
  /// its own requests.
  static final seerrCabin = _api(
    WorldIds.seerrCabin,
    ServiceKey.seerr,
    WorldHosts.seerrCabin,
    label: 'Cabin',
  );

  // World B, on `tower`: in no profile, for a test that adds one with
  // `ConfigProfile.withConnection` — the NPM and Unraid read-only cases.
  static final readarr = _api(
    'readarr',
    ServiceKey.readarr,
    WorldHosts.readarr,
  );
  static final nzbget = _login('nzbget', ServiceKey.nzbget, WorldHosts.nzbget);
  static final unraid = _api('unraid', ServiceKey.unraid, WorldHosts.unraid);
  static final npm = _login(
    'npm',
    ServiceKey.nginxProxyManager,
    WorldHosts.npm,
  );
}

SeerrKnownServer _knows(
  int seerrId,
  ServiceKey service,
  String name,
  String connectionId,
  String url, {
  bool is4k = false,
  bool isDefault = false,
}) => SeerrKnownServer(
  seerrId: seerrId,
  service: service,
  name: name,
  url: url,
  apiKey: worldKey(connectionId),
  is4k: is4k,
  isDefault: isDefault,
  activeProfileName: is4k ? 'Ultra-HD' : 'HD-1080p',
  activeDirectory: switch ((service, is4k, name.contains('Anime'))) {
    (ServiceKey.radarr, true, _) => '/mnt/tank/media/films-4k',
    (ServiceKey.radarr, false, _) => '/mnt/tank/media/films',
    (_, _, true) => '/mnt/tank/media/anime',
    _ => '/mnt/tank/media/series',
  },
);

/// The three self-signed origins of the brief: TrueNAS, Dockge, Radarr 4K.
final Map<String, String> _worldPins = {
  for (final (url, fill) in const [
    (WorldHosts.truenas, 'a'),
    (WorldHosts.dockge, 'b'),
    (WorldHosts.radarr4k, 'c'),
  ])
    UrlUtils.certOrigin(url)!: fill * 64,
};

abstract final class Profiles {
  /// P1 — Full household (Matt, operator). The canvas default: twelve
  /// connections, all answering, Radarr and Radarr 4K side by side.
  static final p1 = ConfigProfile(
    id: 'P1',
    title: 'Full household',
    summary:
        'Seerr, Jellyfin, Radarr, Radarr 4K, Sonarr, Lidarr, Bazarr, Prowlarr, '
        'qBittorrent, SABnzbd, TrueNAS and Dockge, all answering. Plex, '
        'Readarr, Transmission, NZBGet, Unraid and NPM not set up.',
    cases: const {
      ConfigCase.severalInstances,
      ConfigCase.notSetUp,
      ConfigCase.matchNotVerified,
    },
    connections: [
      WorldConnections.seerr,
      WorldConnections.jellyfin,
      WorldConnections.radarr,
      WorldConnections.radarr4k,
      WorldConnections.sonarr,
      WorldConnections.lidarr,
      WorldConnections.bazarr,
      WorldConnections.prowlarr,
      WorldConnections.qbittorrent,
      WorldConnections.sabnzbd,
      WorldConnections.truenas,
      WorldConnections.dockge,
    ],
    seerrKnows: [
      _knows(
        0,
        ServiceKey.radarr,
        'Radarr',
        WorldIds.radarr,
        WorldHosts.radarr,
        isDefault: true,
      ),
      _knows(
        1,
        ServiceKey.radarr,
        'Radarr 4K',
        WorldIds.radarr4k,
        WorldHosts.radarr4k,
        is4k: true,
        isDefault: true,
      ),
      _knows(
        0,
        ServiceKey.sonarr,
        'Sonarr',
        WorldIds.sonarr,
        WorldHosts.sonarr,
        isDefault: true,
      ),
    ],
    // Case f: Jellyfin filed Elephants Dream under another TMDB id.
    unverifiedMatches: const {'elephantsDream'},
    trustedCertificates: _worldPins,
  );

  /// P2 — Requester (Anna): her Seerr connection only.
  ///
  /// Only half modelled: the app signs in to Seerr with an admin API key and
  /// has no user login, so Anna's Seerr answers as the operator's does. See
  /// `ConfigProfile.seerrRequester` for the hook.
  static final p2 = ConfigProfile(
    id: 'P2',
    title: 'Requester',
    summary:
        "Anna's Seerr, nothing else. Cupola has no Seerr user login, so the "
        'requester half is a TODO hook (seerrRequester).',
    cases: const {ConfigCase.notAllowed, ConfigCase.didNotAnswer},
    connections: [WorldConnections.seerr],
    seerrRequester: const WorldSeerrUser(
      id: 2,
      displayName: WorldPeople.anna,
      permissions: 32,
    ),
  );

  /// P2+J — Anna with her own Jellyfin sign-in: a non-admin user's token in
  /// the Jellyfin slot, answering as [ConnectionBehaviour.readOnly] (no admin
  /// reads, only her own sessions).
  static final p2WithJellyfin = ConfigProfile(
    id: 'P2+J',
    title: 'Requester with Jellyfin',
    summary: "P2 plus Anna's own, non-admin Jellyfin sign-in.",
    cases: const {ConfigCase.notAllowed, ConfigCase.didNotAnswer},
    connections: [
      WorldConnections.seerr,
      ProfileConnection(
        WorldConnections.jellyfin.instance.copyWith(
          viewerId: JellyfinFake.annaId,
        ),
        behaviour: ConnectionBehaviour.readOnly,
      ),
    ],
    seerrRequester: p2.seerrRequester,
  );

  /// P3 — First day (J-HomeFresh): Radarr, Sonarr, Seerr. No download client,
  /// no media server, no Bazarr, no Prowlarr.
  static final p3 = ConfigProfile(
    id: 'P3',
    title: 'First day',
    summary: 'Radarr, Sonarr and Seerr only.',
    cases: const {ConfigCase.notSetUp},
    connections: [
      WorldConnections.radarr,
      WorldConnections.sonarr,
      WorldConnections.seerr,
    ],
    seerrKnows: [
      _knows(
        0,
        ServiceKey.radarr,
        'Radarr',
        WorldIds.radarr,
        WorldHosts.radarr,
        isDefault: true,
      ),
      _knows(
        0,
        ServiceKey.sonarr,
        'Sonarr',
        WorldIds.sonarr,
        WorldHosts.sonarr,
        isDefault: true,
      ),
    ],
  );

  /// P4 — Arr stack without Seerr, Bazarr or a media server, and two
  /// different download clients.
  static final p4 = ConfigProfile(
    id: 'P4',
    title: 'Arr stack without Seerr',
    summary:
        'Radarr, Sonarr, Lidarr, Prowlarr, qBittorrent and Transmission. No '
        'Seerr, Bazarr or media server.',
    cases: const {ConfigCase.notSetUp},
    connections: [
      WorldConnections.radarr,
      WorldConnections.sonarr,
      WorldConnections.lidarr,
      WorldConnections.prowlarr,
      WorldConnections.qbittorrent,
      WorldConnections.transmission,
    ],
  );

  /// P5 — Sonarr and Radarr known only through Seerr: Cupola has Seerr and
  /// Jellyfin, and Seerr's settings name a Radarr and a Sonarr that answer at
  /// their addresses but have no connection in Cupola.
  static final p5 = ConfigProfile(
    id: 'P5',
    title: 'Arrs only through Seerr',
    summary:
        'Seerr and Jellyfin. Seerr knows a Radarr and a Sonarr Cupola has no '
        'connection to.',
    cases: const {ConfigCase.knownThroughAnother, ConfigCase.notSetUp},
    connections: [WorldConnections.seerr, WorldConnections.jellyfin],
    seerrKnows: [
      _knows(
        0,
        ServiceKey.radarr,
        'Radarr',
        WorldIds.radarr,
        WorldHosts.radarr,
        isDefault: true,
      ),
      _knows(
        0,
        ServiceKey.sonarr,
        'Sonarr',
        WorldIds.sonarr,
        WorldHosts.sonarr,
        isDefault: true,
      ),
    ],
  );

  /// P6 — Two of a kind, Plex instead of Jellyfin: two Radarr, two Sonarr,
  /// Seerr with a default and a 4K server, Bazarr following Radarr only, a
  /// shared (non-owner) Plex token, qBittorrent and SABnzbd.
  static final p6 = ConfigProfile(
    id: 'P6',
    title: 'Two of a kind, Plex',
    summary:
        'Radarr + Radarr 4K, Sonarr + Sonarr Anime, Seerr (default and 4K), '
        'Bazarr on Radarr only, a non-owner Plex, qBittorrent and SABnzbd.',
    cases: const {
      ConfigCase.severalInstances,
      ConfigCase.matchNotVerified,
      ConfigCase.notAllowed,
    },
    connections: [
      WorldConnections.seerr,
      WorldConnections.plex.withBehaviour(ConnectionBehaviour.readOnly),
      WorldConnections.radarr,
      WorldConnections.radarr4k,
      WorldConnections.sonarr,
      WorldConnections.sonarrAnime,
      WorldConnections.bazarr,
      WorldConnections.qbittorrent,
      WorldConnections.sabnzbd,
    ],
    seerrKnows: [
      _knows(
        0,
        ServiceKey.radarr,
        'Radarr',
        WorldIds.radarr,
        WorldHosts.radarr,
        isDefault: true,
      ),
      _knows(
        1,
        ServiceKey.radarr,
        'Radarr 4K',
        WorldIds.radarr4k,
        WorldHosts.radarr4k,
        is4k: true,
        isDefault: true,
      ),
      _knows(
        0,
        ServiceKey.sonarr,
        'Sonarr',
        WorldIds.sonarr,
        WorldHosts.sonarr,
        isDefault: true,
      ),
      _knows(
        1,
        ServiceKey.sonarr,
        'Sonarr Anime',
        WorldIds.sonarrAnime,
        WorldHosts.sonarrAnime,
      ),
    ],
    unverifiedMatches: const {'elephantsDream'},
    bazarrFollows: const {ServiceKey.radarr},
    trustedCertificates: {UrlUtils.certOrigin(WorldHosts.radarr4k)!: 'c' * 64},
  );

  /// P7 — Full household, degraded and away: P1 away from home, Jellyfin and
  /// Bazarr not answering, five services home-only, qBittorrent refusing the
  /// sign-in, TrueNAS on a read-only key.
  static final p7 = ConfigProfile(
    id: 'P7',
    title: 'Full household, degraded and away',
    summary:
        'P1 away from home. Jellyfin and Bazarr do not answer; Lidarr, '
        'Prowlarr, SABnzbd, TrueNAS and Dockge are home-only; qBittorrent '
        'refuses the sign-in; the TrueNAS key is read-only.',
    cases: const {
      ConfigCase.didNotAnswer,
      ConfigCase.notAllowed,
      ConfigCase.severalInstances,
      ConfigCase.notSetUp,
    },
    place: NetworkPlace.away,
    connections: [
      for (final c in p1.connections)
        switch (c.id) {
          WorldIds.jellyfin ||
          WorldIds.bazarr => c.withBehaviour(ConnectionBehaviour.didNotAnswer),
          WorldIds.qbittorrent => c.withBehaviour(
            ConnectionBehaviour.refusesKey,
          ),
          WorldIds.truenas =>
            c.withBehaviour(ConnectionBehaviour.readOnly).withHomeOnly(true),
          WorldIds.lidarr ||
          WorldIds.prowlarr ||
          WorldIds.sabnzbd ||
          WorldIds.dockge => c.withHomeOnly(true),
          _ => c,
        },
    ],
    seerrKnows: p1.seerrKnows,
    unverifiedMatches: p1.unverifiedMatches,
    trustedCertificates: _worldPins,
  );

  static final all = [p1, p2, p2WithJellyfin, p3, p4, p5, p6, p7];
}
