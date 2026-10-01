/// The fictional household the profiles live in — World A of the design
/// brief, so a test and a design board name the same things: Radarr and
/// Radarr 4K, Sprite Fright at 62 %, Big Buck Bunny stuck at 47 %, Anna and
/// Luca waiting on Seerr.
///
/// Rows are built here rather than read from `test/fixtures/` because they
/// join across services — a Radarr queue row and its qBittorrent torrent share
/// a download id, a Seerr request names the Radarr server that takes it — and
/// because their times are relative to the network's `now`, so "2 h ago"
/// renders as "2 h ago" on whatever day the suite runs. Shapes that carry no
/// title (TrueNAS `auth.me`, NPM `users/me`, Unraid `me`, Plex `/identity`)
/// come from `test/fixtures/` as they are.
library;

/// Addresses, from the brief: everything on `nas.home.arpa`, one port each.
/// The six World-B services live on `tower.home.arpa`.
abstract final class WorldHosts {
  static const radarr = 'http://nas.home.arpa:7878';
  static const radarr4k = 'https://nas.home.arpa:7879';
  static const sonarr = 'http://nas.home.arpa:8989';
  static const sonarrAnime = 'http://nas.home.arpa:8990';
  static const lidarr = 'http://nas.home.arpa:8686';
  static const prowlarr = 'http://nas.home.arpa:9696';
  static const bazarr = 'http://nas.home.arpa:6767';
  static const qbittorrent = 'http://nas.home.arpa:8080';
  static const sabnzbd = 'http://nas.home.arpa:8085';
  static const seerr = 'http://nas.home.arpa:5055';
  static const jellyfin = 'http://nas.home.arpa:8096';
  static const dockge = 'https://nas.home.arpa:5001';
  static const truenas = 'https://nas.home.arpa';
  static const plex = 'http://nas.home.arpa:32400';
  static const transmission = 'http://nas.home.arpa:9091';

  /// A second Jellyfin, at the cabin: in no profile, for a test that adds it
  /// with `ConfigProfile.withConnection` — two of a media server.
  static const jellyfinCabin = 'http://cabin.home.arpa:8096';

  /// The cabin's Seerr, likewise in no profile: two Seerr, each with its own
  /// requests.
  static const seerrCabin = 'http://cabin.home.arpa:5055';

  /// A second Lidarr beside the first, for the vinyl rips: in no profile, for
  /// a test that adds it.
  static const lidarrVinyl = 'http://nas.home.arpa:8687';

  /// A friend's Seerr, outside the household, where the operator has an
  /// account of his own. P9's second Seerr.
  static const seerrFriend = 'https://seerr.example.net';

  // World B.
  static const readarr = 'http://tower.home.arpa:8787';
  static const nzbget = 'http://tower.home.arpa:6789';
  static const unraid = 'https://tower.home.arpa';
  static const npm = 'http://tower.home.arpa:81';
}

/// Connection ids. The first of a service takes the service's own route
/// param, as `ServiceInstance.mintId` hands it out; a second takes
/// `<param>-<7 chars>`, the minted shape.
abstract final class WorldIds {
  static const radarr = 'radarr';
  static const radarr4k = 'radarr-4k00001';
  static const sonarr = 'sonarr';
  static const sonarrAnime = 'sonarr-anime01';
  static const lidarr = 'lidarr';
  static const prowlarr = 'prowlarr';
  static const bazarr = 'bazarr';
  static const qbittorrent = 'qbittorrent';
  static const sabnzbd = 'sabnzbd';
  static const seerr = 'seerr';
  static const jellyfin = 'jellyfin';
  static const dockge = 'dockge';
  static const truenas = 'truenas';
  static const plex = 'plex';
  static const transmission = 'transmission';
  static const jellyfinCabin = 'jellyfin-cabin01';
  static const seerrCabin = 'seerr-cabin001';
  static const lidarrVinyl = 'lidarr-vinyl01';
  static const seerrFriend = 'seerr-sara001';
}

/// The credential a world connection is configured with, and the one the
/// server behind it accepts: Seerr's settings hold the same for each Radarr
/// and Sonarr they know.
String worldKey(String connectionId) => 'world-$connectionId-key';

/// One film or series of the world, with the ids every service agrees on.
class WorldTitle {
  const WorldTitle({
    required this.key,
    required this.title,
    required this.year,
    required this.tmdbId,
    this.imdbId,
    this.tvdbId,
    this.isSeries = false,
  });

  /// Stable handle for a test: `spriteFright`.
  final String key;
  final String title;
  final int year;
  final int tmdbId;
  final String? imdbId;
  final int? tvdbId;
  final bool isSeries;

  String get slug => title.toLowerCase().replaceAll(RegExp('[^a-z0-9]+'), '-');
}

/// The catalogue. Ids are the world's, not claims about TMDB.
abstract final class WorldTitles {
  static const spriteFright = WorldTitle(
    key: 'spriteFright',
    title: 'Sprite Fright',
    year: 2021,
    tmdbId: 811631,
    imdbId: 'tt14852882',
  );
  static const elephantsDream = WorldTitle(
    key: 'elephantsDream',
    title: 'Elephants Dream',
    year: 2006,
    tmdbId: 9761,
    imdbId: 'tt0807840',
  );
  static const bigBuckBunny = WorldTitle(
    key: 'bigBuckBunny',
    title: 'Big Buck Bunny',
    year: 2008,
    tmdbId: 10378,
    imdbId: 'tt1254207',
  );
  static const sintel = WorldTitle(
    key: 'sintel',
    title: 'Sintel',
    year: 2010,
    tmdbId: 45745,
    imdbId: 'tt1727587',
  );
  static const tearsOfSteel = WorldTitle(
    key: 'tearsOfSteel',
    title: 'Tears of Steel',
    year: 2012,
    tmdbId: 133701,
    imdbId: 'tt2285752',
  );
  static const coffeeRun = WorldTitle(
    key: 'coffeeRun',
    title: 'Coffee Run',
    year: 2020,
    tmdbId: 730154,
  );
  static const spring = WorldTitle(
    key: 'spring',
    title: 'Spring',
    year: 2019,
    tmdbId: 593910,
  );
  static const charge = WorldTitle(
    key: 'charge',
    title: 'Charge',
    year: 2022,
    tmdbId: 1011985,
  );
  static const metropolis = WorldTitle(
    key: 'metropolis',
    title: 'Metropolis',
    year: 1927,
    tmdbId: 19,
    imdbId: 'tt0017136',
  );
  static const cosmosLaundromat = WorldTitle(
    key: 'cosmosLaundromat',
    title: 'Cosmos Laundromat',
    year: 2015,
    tmdbId: 358332,
    tvdbId: 300001,
    isSeries: true,
  );
  static const nightShift = WorldTitle(
    key: 'nightShift',
    title: 'Night Shift',
    year: 2024,
    tmdbId: 300002,
    tvdbId: 300002,
    isSeries: true,
  );
  static const agent327 = WorldTitle(
    key: 'agent327',
    title: 'Agent 327',
    year: 2017,
    tmdbId: 300003,
    tvdbId: 300003,
    isSeries: true,
  );

  static const all = [
    spriteFright,
    elephantsDream,
    bigBuckBunny,
    sintel,
    tearsOfSteel,
    coffeeRun,
    spring,
    charge,
    metropolis,
    cosmosLaundromat,
    nightShift,
    agent327,
  ];

  static WorldTitle byKey(String key) => all.firstWhere((t) => t.key == key);
}

/// The people on the Seerr side.
abstract final class WorldPeople {
  /// The operator. Seerr user 1, admin.
  static const operatorName = 'Matt';
  static const anna = 'Anna';
  static const luca = 'Luca';

  /// The friend whose Seerr the operator requests from (P9).
  static const friend = 'Sara';
}

/// Where a download is in its life.
enum DownloadState {
  downloading,
  stuck,
  queued,
  importBlocked,
  seeding,
  stopped,

  /// The client cannot read or write the data: qBittorrent's `error`,
  /// Transmission's local error. None of the world's own downloads is in this
  /// state; a test adds one with `ConfigProfile.withDownloads`.
  failed,

  /// The data is not where the client left it: qBittorrent's `missingFiles`,
  /// Transmission's local error. Added the same way as [failed].
  missingFiles,

  /// The client paused the job itself and waits on a person: a SABnzbd slot
  /// `Paused` with an `ENCRYPTED` label, an NZBGet group paused by its health
  /// check. The arr's queue calls it paused. Added the same way as [failed].
  heldByClient,

  /// Somebody paused the download, with bytes still to come: qBittorrent's
  /// `stoppedDL`, a stopped Transmission torrent, a SABnzbd slot `Paused`
  /// with no label, an NZBGet group `PAUSED`. The arr's queue calls it
  /// paused. Added the same way as [failed].
  paused,
}

/// One download of the world, as both the arr's queue and the client see it.
///
/// [id] is the join: a qBittorrent hash (lower-case in qB, upper-case in the
/// arr's `downloadId`), a SABnzbd `nzo_id`, a Transmission `hashString`.
class WorldDownload {
  const WorldDownload({
    required this.id,
    required this.release,
    required this.client,
    required this.state,
    required this.progress,
    required this.size,
    this.arr,
    this.title,
    this.season,
    this.episode,
    this.speed = 0,
    this.eta,
    this.onlyWithClient = false,
    this.peers,
  });

  final String id;
  final String release;

  /// `qbittorrent`, `sabnzbd` or `transmission` — a `ServiceKey` name.
  final String client;
  final DownloadState state;

  /// 0…1.
  final double progress;
  final int size;

  /// The arr connection whose queue carries this row (a [WorldIds] value), or
  /// null for a torrent nobody's arr grabbed.
  final String? arr;
  final WorldTitle? title;
  final int? season;
  final int? episode;

  /// Bytes per second.
  final int speed;
  final Duration? eta;

  /// Present only in a profile that configures [client]: the Transmission row
  /// P4 needs would otherwise sit in P1's Sonarr queue, where the brief has
  /// exactly five downloads in flight.
  final bool onlyWithClient;

  /// How many peers are sending it (Transmission's `peersSendingToUs`,
  /// qBittorrent's `num_seeds`), or null for the fakes' own default.
  final int? peers;

  int get sizeLeft => (size * (1 - progress)).round();
}

abstract final class WorldDownloads {
  static const _mb = 1024 * 1024;
  static const _gb = 1024 * 1024 * 1024;

  static const spriteFright = WorldDownload(
    id: 'a1f0c3d4e5f60718293a4b5c6d7e8f9012345601',
    release: 'Sprite.Fright.2021.1080p.WEB',
    client: 'qbittorrent',
    state: DownloadState.downloading,
    progress: 0.62,
    size: 2 * _gb,
    arr: WorldIds.radarr,
    title: WorldTitles.spriteFright,
    speed: (4.2 * _mb) ~/ 1,
    eta: Duration(minutes: 11),
  );

  static const bigBuckBunny = WorldDownload(
    id: 'a1f0c3d4e5f60718293a4b5c6d7e8f9012345602',
    release: 'Big.Buck.Bunny.2008.1080p.BluRay',
    client: 'qbittorrent',
    state: DownloadState.stuck,
    progress: 0.47,
    size: (2.34 * _gb) ~/ 1,
    arr: WorldIds.radarr,
    title: WorldTitles.bigBuckBunny,
  );

  static const cosmosS02E04 = WorldDownload(
    id: 'a1f0c3d4e5f60718293a4b5c6d7e8f9012345603',
    release: 'Cosmos.Laundromat.S02E04.1080p.WEB',
    client: 'qbittorrent',
    state: DownloadState.downloading,
    progress: 0.88,
    size: (1.2 * _gb) ~/ 1,
    arr: WorldIds.sonarr,
    title: WorldTitles.cosmosLaundromat,
    season: 2,
    episode: 4,
    speed: (12.1 * _mb) ~/ 1,
    eta: Duration(minutes: 1),
  );

  static const cosmosS02E05 = WorldDownload(
    id: 'a1f0c3d4e5f60718293a4b5c6d7e8f9012345604',
    release: 'Cosmos.Laundromat.S02E05.1080p.WEB',
    client: 'qbittorrent',
    state: DownloadState.downloading,
    progress: 0.09,
    size: (1.2 * _gb) ~/ 1,
    arr: WorldIds.sonarr,
    title: WorldTitles.cosmosLaundromat,
    season: 2,
    episode: 5,
    speed: (6.1 * _mb) ~/ 1,
    eta: Duration(minutes: 24),
  );

  static const elephantsDream4k = WorldDownload(
    id: 'SABnzbd_nzo_elephants4k',
    release: 'Elephants.Dream.2006.2160p.UHD.BluRay',
    client: 'sabnzbd',
    state: DownloadState.downloading,
    progress: 0.31,
    size: (9.4 * _gb) ~/ 1,
    arr: WorldIds.radarr4k,
    title: WorldTitles.elephantsDream,
    speed: 18 * _mb,
    eta: Duration(minutes: 6),
  );

  static const sintel4k = WorldDownload(
    id: 'SABnzbd_nzo_sintel4k',
    release: 'Sintel.2010.2160p.UHD.BluRay',
    client: 'sabnzbd',
    state: DownloadState.queued,
    progress: 0,
    size: (8.1 * _gb) ~/ 1,
    arr: WorldIds.radarr4k,
    title: WorldTitles.sintel,
    eta: Duration(minutes: 6),
  );

  static const sintelSeeding = WorldDownload(
    id: 'a1f0c3d4e5f60718293a4b5c6d7e8f9012345605',
    release: 'Sintel.2010.1080p.BluRay',
    client: 'qbittorrent',
    state: DownloadState.seeding,
    progress: 1,
    size: (2.2 * _gb) ~/ 1,
  );

  static const tearsOfSteelSeeding = WorldDownload(
    id: 'a1f0c3d4e5f60718293a4b5c6d7e8f9012345606',
    release: 'Tears.of.Steel.2012.1080p',
    client: 'qbittorrent',
    state: DownloadState.seeding,
    progress: 1,
    size: (1.9 * _gb) ~/ 1,
  );

  static const ubuntu = WorldDownload(
    id: 'a1f0c3d4e5f60718293a4b5c6d7e8f9012345607',
    release: 'ubuntu-24.04.1-desktop-amd64.iso',
    client: 'qbittorrent',
    state: DownloadState.stopped,
    progress: 1,
    size: (5.7 * _gb) ~/ 1,
  );

  /// P4's second client: one Sonarr grab through Transmission.
  static const nightShiftTransmission = WorldDownload(
    id: 'b2e1d4c5f6a70819304b5c6d7e8f901234567801',
    release: 'Night.Shift.S02E04.1080p.WEB',
    client: 'transmission',
    state: DownloadState.downloading,
    progress: 0.4,
    size: (1.1 * _gb) ~/ 1,
    arr: WorldIds.sonarr,
    title: WorldTitles.nightShift,
    season: 2,
    episode: 4,
    speed: 3 * _mb,
    eta: Duration(minutes: 4),
    onlyWithClient: true,
  );

  /// The 18 finished Sonarr grabs that need a manual import: 12 WEB upgrades
  /// whose names say their episode, 6 tapes whose names do not.
  static final List<WorldDownload> blockedImports = [
    for (final (i, (season, episode)) in const [
      (1, 1),
      (1, 2),
      (1, 3),
      (1, 4),
      (1, 5),
      (1, 6),
      (1, 7),
      (1, 8),
      (1, 9),
      (1, 10),
      (2, 1),
      (2, 2),
    ].indexed)
      WorldDownload(
        id: 'c3f2e5d6a7b8091a2b3c4d5e6f70819203${(40 + i).toString().padLeft(6, '0')}',
        release:
            'Kosmische.Wasserette.S${_two(season)}E${_two(episode)}.1080p.WEB',
        client: 'qbittorrent',
        state: DownloadState.importBlocked,
        progress: 1,
        size: (1.1 * _gb) ~/ 1,
        arr: WorldIds.sonarr,
        title: WorldTitles.cosmosLaundromat,
        season: season,
        episode: episode,
      ),
    for (var tape = 1; tape <= 6; tape++)
      WorldDownload(
        id: 'c3f2e5d6a7b8091a2b3c4d5e6f70819203${(60 + tape).toString().padLeft(6, '0')}',
        release: 'Laundromat.Tapes.E${_two(tape)}.720p.WEB',
        client: 'qbittorrent',
        state: DownloadState.importBlocked,
        progress: 1,
        size: (0.7 * _gb) ~/ 1,
        arr: WorldIds.sonarr,
        title: WorldTitles.cosmosLaundromat,
      ),
  ];

  static final List<WorldDownload> all = [
    spriteFright,
    bigBuckBunny,
    cosmosS02E04,
    cosmosS02E05,
    elephantsDream4k,
    sintel4k,
    sintelSeeding,
    tearsOfSteelSeeding,
    ubuntu,
    nightShiftTransmission,
    ...blockedImports,
  ];

  static String _two(int n) => n.toString().padLeft(2, '0');

  /// The raw message Sonarr attaches to every blocked import.
  static const blockedImportMessage =
      'Found matching series via grab history, but release was matched to '
      'series by ID. Automatic import is not possible. See the FAQ for '
      'details.';
}
