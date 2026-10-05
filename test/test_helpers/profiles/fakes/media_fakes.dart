/// Seerr, Jellyfin and Plex on the fake network.
library;

import 'package:cupola/features/discover/domain/seerr_permission.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import '../../fixtures.dart';
import '../config_profile.dart';
import '../profile_network.dart';
import '../service_fakes.dart';
import '../world.dart';
import 'arr_fakes.dart';
import 'seerr_sessions.dart';

// === Seerr =================================================================

/// Seerr, as whoever calls it sees it: the operator's admin key, or a
/// household member's own session.
///
/// Its settings know the Radarr and Sonarr servers the profile lists in
/// `seerrKnows` — whether or not Cupola has a connection to them, which is
/// the whole of the b case.
///
/// Who is calling, the sign-in routes, the sessions and the CSRF guard are in
/// `seerr_sessions.dart`; this class holds the world's data and the checks
/// each route makes on its own (a requester sees her own requests only).
class SeerrFake extends ServiceFake {
  const SeerrFake();

  /// The routes that want nobody, the one list [gate] reads: `/status`,
  /// `/status/appdata` and `/settings/public` (`security: []` in the API
  /// spec), every route under `/auth` but `GET /auth/me`, and whatever is
  /// not the API at all (`server/routes/index.ts`).
  @override
  bool isPublic(NetworkRequest r) {
    const v1 = '/api/v1/';
    if (!r.path.startsWith(v1)) return true;
    final route = r.path.substring(v1.length);
    if (route.startsWith('auth/')) {
      return !(r.method == 'GET' && route == 'auth/me');
    }
    return r.method == 'GET' &&
        const {'status', 'status/appdata', 'settings/public'}.contains(route);
  }

  // Seerr reads a key it does not know as nobody, and refuses nobody the way
  // `isAuthenticated` does.
  @override
  NetworkReply refuseKey(NetworkRequest r) => seerrEndpointRefused();

  @override
  NetworkReply refuseWrite(NetworkRequest r) => seerrEndpointRefused();

  /// A web page still answers in front of everything; otherwise Seerr's own
  /// middleware decides: the CSRF guard, then the key or the session, then
  /// the route's permission.
  @override
  NetworkReply? gate(NetworkRequest r, ServerContext c) {
    if (c.behaviour == ConnectionBehaviour.servesHtmlPage) {
      return super.gate(r, c);
    }
    return seerrGate(r, c, isPublic: isPublic);
  }

  @override
  NetworkReply finish(NetworkRequest r, ServerContext c, NetworkReply reply) =>
      seerrFinish(r, reply);

  // Search and discovery are GETs; every write is a POST, PUT or DELETE.

  /// User [id] as a request, an issue or the user list names them.
  static JsonMap _user(ServerContext c, int id) {
    final user =
        SeerrSetup.of(c).userById(id) ??
        WorldSeerrUsers.household.firstWhere((u) => u.id == id);
    return {
      'id': id,
      'displayName': user.displayName,
      'username': user.displayName.toLowerCase(),
      'email': user.email,
      'permissions': user.permissions,
      'userType': user.kind.wire,
      'avatar': '/avatarproxy/$id',
      'requestCount': id == 1 ? 0 : 20,
    };
  }

  /// `(request id, title, requester, request status, age, is4k)`.
  ///
  /// Request status: 1 pending, 2 approved, 3 declined. The media's own
  /// status comes from [_mediaStatus], so a request and the title's page
  /// never disagree.
  static const _requests = [
    (1, WorldTitles.charge, 2, 1, Duration(hours: 2), false),
    (2, WorldTitles.metropolis, 3, 1, Duration(days: 1), false),
    (3, WorldTitles.spriteFright, 2, 2, Duration(days: 20), false),
    (4, WorldTitles.coffeeRun, 3, 2, Duration(days: 5), false),
    (5, WorldTitles.sintel, 2, 2, Duration(days: 9), false),
    (6, WorldTitles.tearsOfSteel, 2, 2, Duration(days: 30), true),
    (7, WorldTitles.cosmosLaundromat, 2, 2, Duration(days: 60), false),
    // A series' next season, asked for and waiting.
    (8, WorldTitles.nightShift, 3, 1, Duration(hours: 5), false),
  ];

  /// What Seerr knows of each title: `(status, status4k)`, Seerr's media
  /// status — 1 unknown, 2 pending, 3 processing, 4 partially available,
  /// 5 available. Null for a title Seerr has no media row for.
  static (int, int)? _mediaStatus(WorldTitle t) => switch (t.key) {
    'spriteFright' || 'bigBuckBunny' => (3, 1),
    'coffeeRun' => (5, 1),
    'sintel' || 'elephantsDream' => (5, 3),
    'tearsOfSteel' => (5, 5),
    'spring' => (1, 5),
    'charge' || 'metropolis' => (2, 1),
    'cosmosLaundromat' || 'nightShift' => (4, 1),
    _ => null,
  };

  /// The collection every Blender film belongs to: 5 of 8 on the server,
  /// 2 on the way, 1 requested.
  static const collectionId = 90101;
  static const collectionName = 'Blender Open Movies';
  static const collectionParts = [
    WorldTitles.elephantsDream,
    WorldTitles.bigBuckBunny,
    WorldTitles.sintel,
    WorldTitles.tearsOfSteel,
    WorldTitles.spring,
    WorldTitles.coffeeRun,
    WorldTitles.spriteFright,
    WorldTitles.charge,
  ];

  /// Ian Hubert: director, 3 of 4 on the server.
  static const personId = 90001;
  static const personName = 'Ian Hubert';
  static const personCredits = [
    WorldTitles.tearsOfSteel,
    WorldTitles.elephantsDream,
    WorldTitles.sintel,
    WorldTitles.charge,
  ];

  static List<SeerrKnownServer> _known(ServerContext c, ServiceKey kind) => [
    for (final s in c.profile.seerrKnows)
      if (s.service == kind) s,
  ];

  /// Seerr's id for the server a title of this kind and resolution goes to.
  static int? _serverFor(ServerContext c, WorldTitle t, bool is4k) {
    final kind = t.isSeries ? ServiceKey.sonarr : ServiceKey.radarr;
    final servers = _known(c, kind).where((s) => s.is4k == is4k).toList();
    if (servers.isEmpty) return null;
    return (servers.where((s) => s.isDefault).firstOrNull ?? servers.first)
        .seerrId;
  }

  static JsonMap? _media(ServerContext c, WorldTitle t) {
    final status = _mediaStatus(t);
    if (status == null) return null;
    final (hd, uhd) = status;
    final hdId = t.isSeries
        ? SonarrFake.idOf(t)
        : RadarrFake.idOf(t, is4k: false);
    final uhdId = t.isSeries ? null : RadarrFake.idOf(t, is4k: true);
    return {
      'id': t.tmdbId,
      'tmdbId': t.tmdbId,
      if (t.tvdbId != null) 'tvdbId': t.tvdbId,
      'mediaType': t.isSeries ? 'tv' : 'movie',
      'status': hd,
      'status4k': uhd,
      'serviceId': hdId == null ? null : _serverFor(c, t, false),
      'serviceId4k': uhdId == null ? null : _serverFor(c, t, true),
      'externalServiceId': hdId,
      'externalServiceId4k': uhdId,
      'externalServiceSlug': t.slug,
      // Seerr's link to the title in the player it is set up with, once it
      // is there, whole or in part.
      if (hd == 4 || hd == 5)
        'mediaUrl': '${WorldHosts.jellyfin}/web/#/details?id=jf-${t.key}',
      // A series' seasons, each with its own status. Cosmos Laundromat: the
      // first on the server, the second in part. Night Shift: the first on
      // the server, the second asked for by nobody, the third waiting.
      if (t.isSeries)
        'seasons': [
          {'seasonNumber': 1, 'status': hd >= 4 ? 5 : hd, 'status4k': 1},
          {
            'seasonNumber': 2,
            'status': t == WorldTitles.nightShift ? 1 : hd,
            'status4k': 1,
          },
        ],
      'downloadStatus': [
        for (final d in WorldDownloads.all)
          if (d.title == t &&
              (d.arr == WorldIds.radarr || d.arr == WorldIds.sonarr) &&
              d.state != DownloadState.importBlocked)
            _downloadStatus(c, d),
      ],
      'downloadStatus4k': [
        for (final d in WorldDownloads.all)
          if (d.title == t && d.arr == WorldIds.radarr4k) _downloadStatus(c, d),
      ],
      'createdAt': c.ago(const Duration(days: 60)),
      'updatedAt': c.ago(const Duration(hours: 1)),
      // Seerr's own: every request for the title, as `/movie/:id` sends it.
      'requests': [
        for (final row in _requests)
          if (row.$2 == t) _requestRecord(c, row),
      ],
    };
  }

  static JsonMap _downloadStatus(ServerContext c, WorldDownload d) => {
    'externalId': d.title == null
        ? null
        : d.title!.isSeries
        ? SonarrFake.idOf(d.title!)
        : RadarrFake.idOf(d.title!, is4k: d.arr == WorldIds.radarr4k),
    'mediaType': d.title?.isSeries == true ? 'tv' : 'movie',
    'size': d.size,
    'sizeLeft': d.sizeLeft,
    'status': switch (d.state) {
      DownloadState.queued => 'queued',
      DownloadState.stuck => 'warning',
      _ => 'downloading',
    },
    if (d.eta != null)
      'timeLeft': '00:${d.eta!.inMinutes.toString().padLeft(2, '0')}:00',
    if (d.eta != null) 'estimatedCompletionTime': c.ahead(d.eta!),
    'title': d.release,
    'downloadId': d.id.toUpperCase(),
  };

  static JsonMap _request(
    ServerContext c,
    (int, WorldTitle, int, int, Duration, bool) row,
  ) => {..._requestRecord(c, row), 'media': _media(c, row.$2)};

  /// A request without its media, as the title's own record lists it.
  static JsonMap _requestRecord(
    ServerContext c,
    (int, WorldTitle, int, int, Duration, bool) row,
  ) {
    final (id, title, by, status, age, is4k) = row;
    return {
      'id': id,
      'status': status,
      'type': title.isSeries ? 'tv' : 'movie',
      'is4k': is4k,
      'serverId': _serverFor(c, title, is4k),
      'profileId': 1,
      'profileName': is4k ? 'Ultra-HD' : 'HD-1080p',
      'rootFolder': is4k ? '/mnt/tank/media/films-4k' : '/mnt/tank/media/films',
      'createdAt': c.ago(age),
      'updatedAt': c.ago(age),
      'canRemove': true,
      'requestedBy': _user(c, by),
      if (status != 1) 'modifiedBy': _user(c, 1),
      // A waiting request asks for the season nobody has asked for yet.
      'seasons': !title.isSeries
          ? const <Object?>[]
          : status == 1
          ? [
              {'id': 3, 'seasonNumber': 3, 'status': 1},
            ]
          : [
              {'id': 1, 'seasonNumber': 1, 'status': 5},
              {'id': 2, 'seasonNumber': 2, 'status': 3},
            ],
    };
  }

  static JsonMap _details(ServerContext c, WorldTitle t) {
    final media = _media(c, t);
    return {
      'id': t.tmdbId,
      if (t.isSeries) 'name': t.title else 'title': t.title,
      if (t.isSeries)
        'firstAirDate': '${t.year}-05-01'
      else
        'releaseDate': '${t.year}-04-10',
      'overview': 'A Blender open ${t.isSeries ? 'series' : 'movie'}.',
      'voteAverage': 7.4,
      'genres': const [
        {'id': 16, 'name': 'Animation'},
      ],
      'externalIds': {
        if (t.imdbId != null) 'imdbId': t.imdbId,
        if (t.tvdbId != null) 'tvdbId': t.tvdbId,
      },
      if (t.imdbId != null) 'imdbId': t.imdbId,
      if (t.isSeries) 'numberOfSeasons': 3,
      if (t.isSeries) 'status': 'Returning Series',
      // The third season's premiere, as TMDB dates it: a day, no hour.
      if (t == WorldTitles.cosmosLaundromat)
        'nextEpisodeToAir': {
          'name': 'Episode 1',
          'airDate': c.ahead(const Duration(days: 3)).substring(0, 10),
          'seasonNumber': 3,
          'episodeNumber': 1,
        },
      if (t.isSeries)
        'seasons': [
          for (var s = 1; s <= 3; s++)
            {'id': s, 'seasonNumber': s, 'episodeCount': s == 3 ? 8 : 10},
        ],
      if (collectionParts.contains(t))
        'collection': {'id': collectionId, 'name': collectionName},
      'watchProviders': [
        {
          'iso_3166_1': 'IT',
          'flatrate': [
            {'id': 8, 'name': 'Netflix'},
            {'id': 119, 'name': 'Prime Video'},
          ],
          'buy': [
            {'id': 2, 'name': 'Apple TV'},
          ],
        },
        {
          'iso_3166_1': 'US',
          'flatrate': [
            {'id': 15, 'name': 'Hulu'},
          ],
        },
      ],
      if (!t.isSeries) ...{
        'releases': {
          'results': [
            {
              'iso_3166_1': 'IT',
              'release_dates': [
                {'type': 3, 'release_date': '${t.year}-09-26T00:00:00.000Z'},
                {'type': 4, 'release_date': '${t.year}-11-12T00:00:00.000Z'},
              ],
            },
          ],
        },
      },
      'credits': {
        'cast': const <Object?>[],
        'crew': [
          if (personCredits.contains(t))
            {
              'id': personId,
              'name': personName,
              'job': 'Director',
              'department': 'Directing',
            },
        ],
      },
      'relatedVideos': const <Object?>[],
      'mediaInfo': ?media,
    };
  }

  static JsonMap _credit(ServerContext c, WorldTitle t) => {
    'id': t.tmdbId,
    'mediaType': t.isSeries ? 'tv' : 'movie',
    if (t.isSeries) 'name': t.title else 'title': t.title,
    if (!t.isSeries) 'releaseDate': '${t.year}-04-10',
    'job': 'Director',
    'department': 'Directing',
    'voteAverage': 7.4,
    'mediaInfo': ?_media(c, t),
  };

  static JsonMap _page(NetworkRequest r, List<JsonMap> items) {
    final take = int.tryParse(r.query['take'] ?? '') ?? 20;
    final skip = int.tryParse(r.query['skip'] ?? '') ?? 0;
    final start = skip.clamp(0, items.length);
    final end = (start + take).clamp(0, items.length);
    return {
      'pageInfo': {
        'pages': (items.length / take).ceil(),
        'pageSize': take,
        'results': items.length,
        'page': take == 0 ? 1 : skip ~/ take + 1,
      },
      'results': items.sublist(start, end),
    };
  }

  /// A person among the trending titles, as TMDB's `/trending/all` sends one
  /// through Seerr: `mediaType: person`, a name and what she is known for.
  static const JsonMap _trendingPerson = {
    'id': 1234567,
    'mediaType': 'person',
    'name': 'Elena Varga',
    'profilePath': null,
    'adult': false,
    'popularity': 88.2,
    'knownFor': <Object?>[],
  };

  static JsonMap _discoverPage(List<WorldTitle> titles) => {
    'page': 1,
    'totalPages': 1,
    'totalResults': titles.length,
    'results': [
      for (final t in titles)
        {
          'id': t.tmdbId,
          'mediaType': t.isSeries ? 'tv' : 'movie',
          if (t.isSeries) 'name': t.title else 'title': t.title,
          if (!t.isSeries) 'releaseDate': '${t.year}-04-10',
          'voteAverage': 7.4,
        },
    ],
  };

  /// One server as `GET /settings/radarr|sonarr` sends it: Seerr's
  /// `RadarrSettings` or `SonarrSettings` (`server/lib/settings/index.ts`),
  /// the key in the clear, as the route returns `settings.radarr` whole.
  ///
  /// The address is where Seerr reaches the server: its container under
  /// `withDockerHostnames`, and then `externalUrl` holds the address a
  /// browser opens it at, as an admin of such a stack sets it.
  static JsonMap _knownSettings(SeerrKnownServer s, ServerContext c) {
    final docker = c.profile.dockerHostnames && s.containerUrl != null;
    final uri = s.seenBySeerr(dockerHostnames: docker);
    return {
      'id': s.seerrId,
      'name': s.name,
      'hostname': uri.host,
      'port': uri.port,
      'apiKey': s.apiKey,
      'useSsl': uri.scheme == 'https',
      'baseUrl': '',
      'activeProfileId': s.activeProfileId,
      'activeProfileName': s.activeProfileName,
      'activeDirectory': s.activeDirectory,
      'tags': const <Object?>[],
      'is4k': s.is4k,
      'isDefault': s.isDefault,
      'externalUrl': docker ? s.url : '',
      'syncEnabled': true,
      'preventSearch': false,
      'tagRequests': false,
      'overrideRule': const <Object?>[],
      if (s.service == ServiceKey.radarr) 'minimumAvailability': 'released',
      if (s.service == ServiceKey.sonarr) ...{
        'seriesType': 'standard',
        'animeSeriesType': 'anime',
        'activeAnimeProfileId': s.activeProfileId,
        'enableSeasonFolders': true,
        'monitorNewItems': 'all',
      },
    };
  }

  static JsonMap _knownService(SeerrKnownServer s) => {
    'id': s.seerrId,
    'name': s.name,
    'is4k': s.is4k,
    'isDefault': s.isDefault,
    'activeDirectory': s.activeDirectory,
    'activeProfileId': s.activeProfileId,
    'activeTags': const <Object?>[],
  };

  @override
  NetworkReply? answer(NetworkRequest r, ServerContext c) {
    final auth = seerrAuthAnswer(r, c) ?? seerrUserSettingsAnswer(r, c);
    if (auth != null) return auth;
    final path = r.path;
    final setup = SeerrSetup.of(c);
    // The gate let nobody through to a route that wants a caller; the
    // public routes do not read it.
    final caller = seerrCallerOf(r, c);
    final everyone = caller?.seesEveryone ?? false;
    if (r.method == 'GET') {
      switch (path) {
        case '/api/v1/status':
          return NetworkReply.json({
            'version': setup.release.version,
            'commitTag': setup.release.commitTag,
            'updateAvailable': false,
            'commitsBehind': 0,
            'restartRequired': false,
          });
        case '/api/v1/settings/public':
          return NetworkReply.json(setup.publicSettings);
        case '/api/v1/request':
          // `request.ts:147-162`: without MANAGE_REQUESTS or REQUEST_VIEW the
          // list filters itself to the caller's own.
          final requestedBy = int.tryParse(r.query['requestedBy'] ?? '');
          if (!everyone &&
              requestedBy != null &&
              requestedBy != caller?.user.id) {
            return seerrError(
              403,
              "You do not have permission to view this user's requests.",
            );
          }
          final by = everyone ? requestedBy : caller?.user.id;
          final rows = [
            for (final row in _requests)
              if (by == null || row.$3 == by) _request(c, row),
          ];
          final filter = r.query['filter'];
          int? mediaStatus(JsonMap q) =>
              (q['media'] as JsonMap?)?['status'] as int?;
          // The status of the copy the request asked for: a 4K request
          // reads the title's 4K status, as Seerr's own filter does.
          int? requestedStatus(JsonMap q) =>
              (q['media'] as JsonMap?)?[q['is4k'] == true
                      ? 'status4k'
                      : 'status']
                  as int?;
          final filtered = switch (filter) {
            'pending' => rows.where((q) => q['status'] == 1).toList(),
            'approved' => rows.where((q) => q['status'] == 2).toList(),
            // Seerr's own reading: approved, and the title not yet
            // available (unknown, pending, processing, partly available).
            'processing' =>
              rows
                  .where(
                    (q) =>
                        q['status'] == 2 &&
                        const {null, 1, 2, 3, 4}.contains(requestedStatus(q)),
                  )
                  .toList(),
            'available' => rows.where((q) => mediaStatus(q) == 5).toList(),
            'failed' => rows.where((q) => q['status'] == 4).toList(),
            _ => rows,
          };
          return NetworkReply.json(_page(r, filtered));
        case '/api/v1/request/count':
          final pending = _requests.where((q) => q.$4 == 1).length;
          return NetworkReply.json({
            'total': _requests.length,
            'movie': _requests.where((q) => !q.$2.isSeries).length,
            'tv': _requests.where((q) => q.$2.isSeries).length,
            'pending': pending,
            'approved': _requests.length - pending,
            'declined': 0,
            'processing': _requests
                .where((q) => _mediaStatus(q.$2)?.$1 == 3)
                .length,
            'available': _requests
                .where((q) => _mediaStatus(q.$2)?.$1 == 5)
                .length,
          });
        case '/api/v1/user':
          // `user/index.ts:160-163`: the email only for MANAGE_USERS.
          final full = caller?.has(SeerrPermission.manageUsers) ?? false;
          return NetworkReply.json(
            _page(r, [
              for (final u in setup.users)
                if (full) _user(c, u.id) else _user(c, u.id)..remove('email'),
            ]),
          );
        case '/api/v1/issue':
          return NetworkReply.json(
            _page(r, [
              {
                'id': 1,
                'issueType': 2,
                'status': 1,
                'problemSeason': 0,
                'problemEpisode': 0,
                'createdAt': c.ago(const Duration(days: 3)),
                'updatedAt': c.ago(const Duration(days: 2)),
                'createdBy': _user(c, 2),
                'media': _media(c, WorldTitles.tearsOfSteel),
                'comments': [
                  {
                    'id': 1,
                    'message': 'Audio drifts out of sync after about 8 minutes',
                    'user': _user(c, 2),
                    'createdAt': c.ago(const Duration(days: 3)),
                  },
                  {
                    'id': 2,
                    'message': 'Which device?',
                    'user': _user(c, 1),
                    'createdAt': c.ago(const Duration(days: 2, hours: 5)),
                  },
                  {
                    'id': 3,
                    'message': 'Living room TV',
                    'user': _user(c, 2),
                    'createdAt': c.ago(const Duration(days: 2)),
                  },
                ],
              },
            ]),
          );
        case '/api/v1/issue/count':
          return NetworkReply.json({
            'total': 1,
            'video': 0,
            'audio': 1,
            'subtitles': 0,
            'others': 0,
            'open': 1,
            'closed': 0,
          });
        case '/api/v1/settings/radarr':
          return NetworkReply.json([
            for (final s in _known(c, ServiceKey.radarr)) _knownSettings(s, c),
          ]);
        case '/api/v1/settings/sonarr':
          return NetworkReply.json([
            for (final s in _known(c, ServiceKey.sonarr)) _knownSettings(s, c),
          ]);
        case '/api/v1/service/radarr':
          return NetworkReply.json([
            for (final s in _known(c, ServiceKey.radarr)) _knownService(s),
          ]);
        case '/api/v1/service/sonarr':
          return NetworkReply.json([
            for (final s in _known(c, ServiceKey.sonarr)) _knownService(s),
          ]);
        case '/api/v1/discover/trending':
          // TMDB's trending, which Seerr relays, mixes people in with the
          // titles: one leads the list, as she does when she is in the news.
          final page = _discoverPage([
            for (final t in WorldTitles.all)
              if (!t.isSeries) t,
          ]);
          return NetworkReply.json({
            ...page,
            'results': [_trendingPerson, ...page['results']! as List],
          });
        case '/api/v1/discover/movies':
        case '/api/v1/discover/movies/upcoming':
          return NetworkReply.json(
            _discoverPage([
              for (final t in WorldTitles.all)
                if (!t.isSeries) t,
            ]),
          );
        case '/api/v1/discover/tv':
        case '/api/v1/discover/tv/upcoming':
          return NetworkReply.json(
            _discoverPage([
              for (final t in WorldTitles.all)
                if (t.isSeries) t,
            ]),
          );
        case '/api/v1/search':
          final query = (r.query['query'] ?? '').toLowerCase();
          return NetworkReply.json(
            _discoverPage([
              for (final t in WorldTitles.all)
                if (query.isNotEmpty && t.title.toLowerCase().contains(query))
                  t,
            ]),
          );
        // The rail's own route, as Seerr 3.4.1 answers it: each genre with
        // the backdrops of a few of its titles. `/genres/{movie,tv}` exists
        // too, but nothing in the app reads it.
        case '/api/v1/discover/genreslider/movie':
        case '/api/v1/discover/genreslider/tv':
          return NetworkReply.json(const [
            {
              'id': 16,
              'name': 'Animation',
              'backdrops': ['/animation-1.jpg', '/animation-2.jpg'],
            },
          ]);
      }
      final service = RegExp(
        r'^/api/v1/service/(radarr|sonarr)/(\d+)$',
      ).firstMatch(path);
      if (service != null) {
        final kind = service.group(1)!;
        final id = int.parse(service.group(2)!);
        final known = _known(
          c,
          kind == 'radarr' ? ServiceKey.radarr : ServiceKey.sonarr,
        ).where((s) => s.seerrId == id).firstOrNull;
        if (known == null) {
          return NetworkReply.json({'message': 'Not found'}, status: 404);
        }
        return NetworkReply.json({
          'server': _knownService(known),
          'profiles': [
            {'id': known.activeProfileId, 'name': known.activeProfileName},
          ],
          'rootFolders': [
            {
              'id': 1,
              'path': known.activeDirectory,
              'freeSpace': 12400000000000,
            },
          ],
          'tags': const <Object?>[],
        });
      }
      final quota = RegExp(r'^/api/v1/user/(\d+)/quota$').firstMatch(path);
      if (quota != null && caller != null) {
        final id = int.parse(quota.group(1)!);
        // `user/index.ts:804-834`: one's own, or MANAGE_USERS and
        // MANAGE_REQUESTS for anybody's.
        if (id != caller.user.id &&
            !(caller.has(SeerrPermission.manageUsers) &&
                caller.has(SeerrPermission.manageRequests))) {
          return seerrError(
            403,
            "You do not have permission to view this user's request limits.",
          );
        }
        final user = setup.userById(id);
        // Upstream relays TypeORM's own "could not find" sentence here; only
        // the 404 is modelled.
        if (user == null) return seerrError(404, 'User not found.');
        return NetworkReply.json(seerrQuotaOf(user, full: setup.quotaReached));
      }
      final one = RegExp(r'^/api/v1/request/(\d+)$').firstMatch(path);
      if (one != null) {
        final id = int.parse(one.group(1)!);
        final row = _requests.where((q) => q.$1 == id).firstOrNull;
        if (row == null) {
          return NetworkReply.json({
            'message': 'Request not found.',
          }, status: 404);
        }
        // `request.ts:434-463`.
        if (!everyone && row.$3 != caller?.user.id) {
          return seerrError(
            403,
            'You do not have permission to view this request.',
          );
        }
        return NetworkReply.json(_request(c, row));
      }
      // A season as TMDB keeps it: Cosmos Laundromat's votes, a few of the
      // second season's from fewer than twenty people, the third not out.
      final season = RegExp(
        r'^/api/v1/tv/(\d+)/season/(\d+)$',
      ).firstMatch(path);
      if (season != null) {
        final number = int.parse(season.group(2)!);
        final votes = switch (number) {
          1 => const [7.2, 7.5, 7.9, 8.1, 7.4, 8.3, 7.0, 7.7, 8.0, 8.6],
          2 => const [8.2, 8.4, 8.1, 7.6, 7.9, 8.9, 7.3, 8.0, 8.5, 8.7],
          _ => const <double>[0, 0, 0, 0, 0, 0, 0, 0],
        };
        return NetworkReply.json({
          'id': number,
          'seasonNumber': number,
          'episodes': [
            for (final (i, vote) in votes.indexed)
              {
                'id': number * 100 + i + 1,
                'seasonNumber': number,
                'episodeNumber': i + 1,
                'name': switch ((number, i + 1)) {
                  (2, 3) => 'The Second Cycle',
                  (2, 6) => 'The Seventh Cycle',
                  _ => 'Episode ${i + 1}',
                },
                'airDate':
                    '2025-0${number + 1}-${(i + 1).toString().padLeft(2, '0')}',
                'overview': number == 2 && i == 2
                    ? 'Franck wakes up in the second life Tachyon sold him.'
                    : '',
                // No still: a picture needs the disk cache tests have not got.
                'voteAverage': vote,
                'voteCount': vote == 0
                    ? 0
                    : number == 2 && const {4, 6, 7, 8}.contains(i)
                    ? 12
                    : number == 2 && i == 5
                    ? 31
                    : 37,
              },
          ],
        });
      }
      // Rotten Tomatoes' word on a series, which TMDB's record lacks.
      if (RegExp(r'^/api/v1/tv/\d+/ratings$').hasMatch(path)) {
        return NetworkReply.json({
          'title': WorldTitles.cosmosLaundromat.title,
          'criticsScore': 88,
          'criticsRating': 'Fresh',
        });
      }
      final detail = RegExp(r'^/api/v1/(movie|tv)/(\d+)$').firstMatch(path);
      if (detail != null) {
        final id = int.parse(detail.group(2)!);
        final title = WorldTitles.all
            .where(
              (t) => t.tmdbId == id && t.isSeries == (detail.group(1) == 'tv'),
            )
            .firstOrNull;
        if (title == null) {
          return NetworkReply.json({'message': 'Not found'}, status: 404);
        }
        return NetworkReply.json(_details(c, title));
      }
      if (path == '/api/v1/person/$personId') {
        return NetworkReply.json({
          'id': personId,
          'name': personName,
          'knownForDepartment': 'Directing',
          'biography': 'Director of Blender open movies.',
          'placeOfBirth': 'Seattle, Washington, USA',
        });
      }
      if (path == '/api/v1/person/$personId/combined_credits') {
        return NetworkReply.json({
          'id': personId,
          'cast': const <Object?>[],
          'crew': [for (final t in personCredits) _credit(c, t)],
        });
      }
      if (path == '/api/v1/collection/$collectionId') {
        return NetworkReply.json({
          'id': collectionId,
          'name': collectionName,
          'overview': 'The open movies of the Blender Studio.',
          'parts': [
            for (final t in collectionParts)
              {
                'id': t.tmdbId,
                'mediaType': 'movie',
                'title': t.title,
                'releaseDate': '${t.year}-04-10',
                'voteAverage': 7.4,
                'mediaInfo': ?_media(c, t),
              },
          ],
        });
      }
      final rail = RegExp(
        r'^/api/v1/(movie|tv)/\d+/(recommendations|similar)$',
      ).firstMatch(path);
      if (rail != null) return NetworkReply.json(_discoverPage(const []));
      if (path.startsWith('/api/v1/discover/')) {
        return NetworkReply.json(_discoverPage(const []));
      }
    }
    // An edit before an approval, as Seerr's route takes it: only a request
    // still waiting, `mediaType` required, and a series with its seasons.
    final edit = RegExp(r'^/api/v1/request/(\d+)$').firstMatch(path);
    if (r.method == 'PUT' && edit != null) {
      final id = int.parse(edit.group(1)!);
      final row = _requests.where((q) => q.$1 == id).firstOrNull;
      if (row == null) {
        return NetworkReply.json({
          'message': 'Request not found.',
        }, status: 404);
      }
      // `request.ts:484-494`: one's own, and a series or REQUEST_ADVANCED; or
      // MANAGE_REQUESTS.
      final mine = row.$3 == caller?.user.id;
      final advanced = caller?.has(SeerrPermission.requestAdvanced) ?? false;
      if (!(caller?.has(SeerrPermission.manageRequests) ?? false) &&
          !(mine && (row.$2.isSeries || advanced))) {
        return seerrError(
          403,
          'You do not have permission to modify this request.',
        );
      }
      if (row.$4 != 1) {
        return NetworkReply.json({
          'message': 'Only pending requests can be modified.',
        }, status: 409);
      }
      final body = r.json;
      if (body is! Map || body['mediaType'] == null) {
        return NetworkReply.json({
          'message': "request/body must have required property 'mediaType'",
        }, status: 400);
      }
      final seasons = body['seasons'];
      if (body['mediaType'] == 'tv' && (seasons is! List || seasons.isEmpty)) {
        return NetworkReply.json({
          'message':
              'Missing seasons. If you want to cancel a series request, use '
              'the DELETE method.',
        }, status: 500);
      }
      return NetworkReply.json({
        ..._request(c, row),
        'serverId': body['serverId'],
        'profileId': body['profileId'],
        'rootFolder': body['rootFolder'],
      });
    }
    if (r.method == 'POST' &&
        RegExp(r'^/api/v1/request/\d+/(approve|decline)$').hasMatch(path)) {
      final id = int.parse(path.split('/')[4]);
      final row = _requests.where((q) => q.$1 == id).firstOrNull;
      if (row == null) {
        return NetworkReply.json({'message': 'Not found'}, status: 404);
      }
      return NetworkReply.json(_request(c, row));
    }
    // A title put on the watchlist: Seerr answers with the item. The world
    // keeps no watchlist.
    if (r.method == 'POST' && path == '/api/v1/watchlist') {
      final body = r.json;
      return NetworkReply.json({
        if (body is Map) ...body.cast<String, Object?>(),
        'ratingKey': '',
      }, status: 201);
    }
    if (r.method == 'POST' && path == '/api/v1/request') {
      // The operator's answer is the world's first row, as it always was:
      // the request sheet's tests read it.
      if (caller == null || caller.byKey) {
        return NetworkReply.json(_request(c, _requests.first), status: 201);
      }
      return _newRequest(r, c, caller, setup);
    }
    final cancel = RegExp(r'^/api/v1/request/(\d+)$').firstMatch(path);
    if (r.method == 'DELETE' && cancel != null && caller != null) {
      final id = int.parse(cancel.group(1)!);
      final row = _requests.where((q) => q.$1 == id).firstOrNull;
      if (row == null) return seerrError(404, 'Request not found.');
      // `request.ts:706-737`: a 401, not a 403, for a request that is not
      // one's own or no longer waits.
      if (!caller.has(SeerrPermission.manageRequests) &&
          (row.$3 != caller.user.id || row.$4 != 1)) {
        return seerrError(
          401,
          'You do not have permission to delete this request.',
        );
      }
      return const NetworkReply(204);
    }
    // `issue.ts:326-372`: past the route's MANAGE_ISSUES or CREATE_ISSUES
    // (`_needOf` in `seerr_sessions.dart`), anybody else's issue wants MANAGE_ISSUES, else a 401.
    // The world has one issue, Anna's.
    final status = RegExp(
      r'^/api/v1/issue/(\d+)/(open|resolved)$',
    ).firstMatch(path);
    if (r.method == 'POST' && status != null) {
      if (status.group(1) != '1') return seerrError(404, 'Issue not found.');
      if (caller != null &&
          !caller.byKey &&
          !caller.has(SeerrPermission.manageIssues) &&
          caller.user.id != WorldSeerrUsers.anna.id) {
        return seerrError(
          401,
          'You do not have permission to modify this issue.',
        );
      }
      return NetworkReply.json({
        'id': 1,
        'status': status.group(2) == 'resolved' ? 2 : 1,
      });
    }
    if (r.method == 'DELETE' && path.startsWith('/api/v1/')) {
      return const NetworkReply(204);
    }
    return null;
  }

  /// `POST /api/v1/request` by a household member's own account: the
  /// permission and quota checks of `MediaRequest.request`, then a request of
  /// theirs, waiting unless the account is auto-approved.
  static NetworkReply _newRequest(
    NetworkRequest r,
    ServerContext c,
    SeerrCaller caller,
    SeerrSetup setup,
  ) {
    final json = r.json;
    final body = json is Map ? json : const <String, Object?>{};
    final kind = body['mediaType'];
    final is4k = body['is4k'] == true;
    final refusal = seerrRequestRefusal(
      caller,
      kind: kind is String ? kind : null,
      is4k: is4k,
      ignoreQuota: body['ignoreQuota'] == true,
      quotaReached: setup.quotaReached,
    );
    if (refusal != null) return refusal;
    final series = kind == 'tv';
    final title =
        WorldTitles.all
            .where((t) => t.tmdbId == body['mediaId'] && t.isSeries == series)
            .firstOrNull ??
        WorldTitles.all.firstWhere((t) => t.isSeries == series);
    final approved = seerrAutoApproves(caller, movie: !series, is4k: is4k);
    return NetworkReply.json(
      _request(c, (
        100 + c.network.requestsTo(c.server.id).length,
        title,
        caller.user.id,
        approved ? 2 : 1,
        Duration.zero,
        is4k,
      )),
      status: 201,
    );
  }
}

// === Jellyfin ==============================================================

/// Jellyfin with three users; the operator is "this is me".
///
/// [ConnectionBehaviour.readOnly] models a non-admin user's token — the P2+J
/// variant, Anna signing in with her own account: admin reads (other users,
/// devices, tasks, the activity log, the full system info) are refused, and
/// only her own sessions are listed.
class JellyfinFake extends ServiceFake {
  const JellyfinFake();

  static const operatorId = '0a1b2c3d4e5f60718293a4b5c6d7e8f9';
  static const annaId = '1a1b2c3d4e5f60718293a4b5c6d7e8f9';
  static const lucaId = '2a1b2c3d4e5f60718293a4b5c6d7e8f9';
  static const serverId = '9f2c1b7e4a3d4f0e8b6c5a1d2e3f4a5b';

  @override
  bool isPublic(NetworkRequest r) =>
      r.method == 'GET' &&
      (r.path == '/System/Info/Public' || r.path == '/System/Ping');

  @override
  NetworkReply refuseKey(NetworkRequest r) => const NetworkReply(401);

  @override
  bool isAdminRead(NetworkRequest r) =>
      r.method == 'GET' &&
      (r.path == '/System/Info' ||
          r.path == '/Users' ||
          r.path == '/Devices' ||
          r.path == '/ScheduledTasks' ||
          r.path == '/System/ActivityLog/Entries' ||
          r.path == '/Library/VirtualFolders');

  // Playback reporting and session commands are POSTs a non-admin may send
  // for its own sessions, so only the admin writes count here.
  @override
  bool isWrite(NetworkRequest r) =>
      r.method != 'GET' &&
      (r.path.startsWith('/Library/') ||
          r.path.startsWith('/ScheduledTasks/') ||
          r.path.startsWith('/Items/') && r.path.endsWith('/Refresh'));

  static JsonMap _item(ServerContext c, WorldTitle t, {String? type}) {
    final unverified = c.profile.unverifiedMatches.contains(t.key);
    return {
      'Name': t.title,
      'Id': 'jf-${t.key}',
      'ServerId': serverId,
      'Type': type ?? (t.isSeries ? 'Series' : 'Movie'),
      'ProductionYear': t.year,
      'RunTimeTicks': 7200000000,
      // Case f: the item is there, but under another TMDB id, so the app's
      // own match refuses it.
      'ProviderIds': {
        'Tmdb': unverified ? '${t.tmdbId + 1000000}' : '${t.tmdbId}',
        if (t.imdbId != null && !unverified) 'Imdb': t.imdbId,
        if (t.tvdbId != null) 'Tvdb': '${t.tvdbId}',
      },
      'UserData': {
        'Played': t == WorldTitles.tearsOfSteel,
        'PlaybackPositionTicks': 0,
        'IsFavorite': false,
      },
      'ImageTags': const <String, Object?>{},
      'DateCreated': c.ago(const Duration(days: 30)),
      // The picture: Tears of Steel is the household's 4K HDR copy.
      if (!t.isSeries)
        'MediaStreams': [
          if (t == WorldTitles.tearsOfSteel)
            {
              'Type': 'Video',
              'Width': 3840,
              'Height': 1714,
              'VideoRange': 'HDR',
              'VideoRangeType': 'HDR10',
            }
          else
            {
              'Type': 'Video',
              'Width': 1920,
              'Height': 1080,
              'VideoRange': 'SDR',
              'VideoRangeType': 'SDR',
            },
          {'Type': 'Audio', 'Language': 'eng'},
        ],
    };
  }

  static List<WorldTitle> _library() => const [
    WorldTitles.coffeeRun,
    WorldTitles.sintel,
    WorldTitles.tearsOfSteel,
    WorldTitles.elephantsDream,
    WorldTitles.spring,
    WorldTitles.cosmosLaundromat,
  ];

  static JsonMap _user(String id, String name, {required bool admin}) => {
    'Id': id,
    'Name': name,
    'ServerId': serverId,
    'HasPassword': true,
    'Policy': {'IsAdministrator': admin, 'IsDisabled': false},
    'LastActivityDate': '2026-09-29T18:40:00.0000000Z',
  };

  JsonMap _session(ServerContext c) => {
    'Id': 'session-anna-livingroom',
    'UserId': annaId,
    'UserName': WorldPeople.anna,
    'Client': 'Jellyfin Android TV',
    'DeviceName': 'Living room TV',
    'DeviceId': 'living-room-tv',
    'DeviceType': 'TV',
    'IsActive': true,
    'SupportsMediaControl': true,
    'SupportsRemoteControl': true,
    'LastActivityDate': c.ago(const Duration(minutes: 1)),
    'PlayState': {
      'PositionTicks': 18000000000,
      'IsPaused': false,
      'PlayMethod': 'DirectPlay',
      'CanSeek': true,
    },
    'NowPlayingItem': {
      ..._item(c, WorldTitles.sintel),
      'RunTimeTicks': 40800000000,
    },
  };

  @override
  NetworkReply? answer(NetworkRequest r, ServerContext c) {
    if (r.method != 'GET') return const NetworkReply(204);
    final path = r.path;
    switch (path) {
      case '/System/Info/Public':
        return NetworkReply.json({
          ...jsonFixtureMap('jellyfin/system_info_public.json'),
          'LocalAddress': WorldHosts.jellyfin,
          'ServerName': 'nas',
        });
      case '/System/Info':
        return NetworkReply.json({
          ...jsonFixtureMap('jellyfin/system_info_public.json'),
          'LocalAddress': WorldHosts.jellyfin,
          'ServerName': 'nas',
          'HasPendingRestart': false,
          'HasUpdateAvailable': false,
        });
      case '/System/Ping':
        return NetworkReply.text('Jellyfin Server');
      case '/Users':
        return NetworkReply.json([
          _user(operatorId, 'Operator', admin: true),
          _user(annaId, WorldPeople.anna, admin: false),
          _user(lucaId, WorldPeople.luca, admin: false),
        ]);
      case '/Users/Me':
        return NetworkReply.json(
          c.behaviour == ConnectionBehaviour.readOnly
              ? _user(annaId, WorldPeople.anna, admin: false)
              : _user(operatorId, 'Operator', admin: true),
        );
      case '/Sessions':
        return NetworkReply.json([_session(c)]);
      case '/Library/VirtualFolders':
        return NetworkReply.json([
          for (final (name, type) in const [
            ('Films', 'movies'),
            ('Films 4K', 'movies'),
            ('Series', 'tvshows'),
            ('Music', 'music'),
          ])
            {
              'Name': name,
              'CollectionType': type,
              'ItemId': 'lib-${name.toLowerCase().replaceAll(' ', '-')}',
              'Locations': ['/mnt/tank/media/${name.toLowerCase()}'],
            },
        ]);
      case '/Items/Counts':
        return NetworkReply.json({
          'MovieCount': 461,
          'SeriesCount': 86,
          'EpisodeCount': 2914,
          'AlbumCount': 1240,
          'SongCount': 14000,
        });
      case '/ScheduledTasks':
        return NetworkReply.json([
          {
            'Name': 'Scan media library',
            'State': 'Running',
            'CurrentProgressPercentage': 42.0,
            'Id': 'task-scan',
            'Category': 'Library',
            'Key': 'RefreshLibrary',
          },
        ]);
      case '/System/ActivityLog/Entries':
        return NetworkReply.json({
          'Items': [
            {
              'Id': 1,
              'Name': 'Anna started Sintel on Living room TV',
              'Type': 'VideoPlayback',
              'Date': c.ago(const Duration(minutes: 38)),
              'Severity': 'Information',
            },
            {
              'Id': 2,
              'Name': 'Coffee Run added to Films',
              'Type': 'ItemAdded',
              'Date': c.ago(const Duration(hours: 2, minutes: 13)),
              'Severity': 'Information',
            },
          ],
          'TotalRecordCount': 2,
        });
      case '/Devices':
        return NetworkReply.json({
          'Items': const <Object?>[],
          'TotalRecordCount': 7,
        });
      case '/Items':
      case '/Search/Hints':
        final ids =
            r.query['AnyProviderIdEquals'] ?? r.query['anyProviderIdEquals'];
        final term = (r.query['searchTerm'] ?? r.query['SearchTerm'] ?? '')
            .toLowerCase();
        final items = [
          for (final t in _library())
            if (_wanted(t, ids, term)) _item(c, t),
        ];
        return NetworkReply.json({
          'Items': items,
          'TotalRecordCount': items.length,
          'StartIndex': 0,
        });
      case '/Shows/NextUp':
        return NetworkReply.json({
          'Items': const <Object?>[],
          'TotalRecordCount': 0,
        });
    }
    // A series' episodes, with the household viewer's watch state: Cosmos
    // Laundromat's first season and the three of the second on the server,
    // two of them watched and the third part-way.
    final episodes = RegExp(
      r'^/Shows/jf-([A-Za-z0-9]+)/Episodes$',
    ).firstMatch(path);
    if (episodes != null) {
      final cosmos = episodes.group(1) == WorldTitles.cosmosLaundromat.key;
      JsonMap episode(int season, int number, {double played = 1}) => {
        ..._item(c, WorldTitles.cosmosLaundromat, type: 'Episode'),
        'Id': 'jf-cosmos-s${season}e$number',
        'Name': season == 2 && number == 3
            ? 'The Second Cycle'
            : 'Episode $number',
        'SeriesName': WorldTitles.cosmosLaundromat.title,
        'SeriesId': 'jf-cosmosLaundromat',
        'ParentIndexNumber': season,
        'IndexNumber': number,
        'RunTimeTicks': 12000000000,
        'UserData': {
          'Played': played >= 1,
          'PlaybackPositionTicks': played > 0 && played < 1
              ? (12000000000 * played).round()
              : 0,
          if (played > 0 && played < 1) 'PlayedPercentage': played * 100,
        },
      };
      final items = cosmos
          ? [
              for (var e = 1; e <= 10; e++) episode(1, e),
              episode(2, 1),
              episode(2, 2),
              episode(2, 3, played: 0.75),
            ]
          : const <JsonMap>[];
      return NetworkReply.json({
        'Items': items,
        'TotalRecordCount': items.length,
      });
    }
    if (RegExp(r'^/Users/[^/]+/Items/Resume$').hasMatch(path) ||
        path == '/UserItems/Resume') {
      return NetworkReply.json({
        'Items': [
          {
            ..._item(c, WorldTitles.cosmosLaundromat, type: 'Episode'),
            'Id': 'jf-cosmos-s02e03',
            'Name': 'The Second Cycle',
            'SeriesName': WorldTitles.cosmosLaundromat.title,
            'SeriesId': 'jf-cosmosLaundromat',
            'ParentIndexNumber': 2,
            'IndexNumber': 3,
            'RunTimeTicks': 12000000000,
            'UserData': {
              'Played': false,
              'PlaybackPositionTicks': 9000000000,
              'PlayedPercentage': 75.0,
            },
          },
        ],
        'TotalRecordCount': 1,
      });
    }
    if (RegExp(r'^/Users/[^/]+/Items/Latest$').hasMatch(path) ||
        path == '/Items/Latest') {
      return NetworkReply.json([_item(c, WorldTitles.coffeeRun)]);
    }
    final one = RegExp(
      r'^/(?:Users/[^/]+/)?Items/jf-([A-Za-z0-9]+)$',
    ).firstMatch(path);
    if (one != null) {
      final title = WorldTitles.all
          .where((t) => t.key == one.group(1))
          .firstOrNull;
      if (title != null) return NetworkReply.json(_item(c, title));
    }
    return null;
  }

  static bool _wanted(WorldTitle t, String? ids, String term) {
    if (term.isNotEmpty) return t.title.toLowerCase().contains(term);
    if (ids == null || ids.isEmpty) return true;
    // Jellyfin matches any of the listed provider ids; the fake answers with
    // the item whatever id it holds, so the app's own check decides — which
    // is what case f needs.
    return ids.contains('${t.tmdbId}') ||
        (t.imdbId != null && ids.contains(t.imdbId!)) ||
        (t.tvdbId != null && ids.contains('${t.tvdbId}'));
  }
}

// === Plex ==================================================================

/// Plex, owner token by default.
///
/// [ConnectionBehaviour.readOnly] models a shared, non-owner token (P6):
/// `/status/sessions` — what Stop needs — is refused, the library reads.
class PlexFake extends ServiceFake {
  const PlexFake();

  @override
  bool isPublic(NetworkRequest r) => r.method == 'GET' && r.path == '/identity';

  @override
  NetworkReply refuseKey(NetworkRequest r) => NetworkReply.text(
    '<html><head><title>Unauthorized</title></head></html>',
    status: 401,
  );

  @override
  bool isAdminRead(NetworkRequest r) =>
      r.method == 'GET' &&
      (r.path == '/status/sessions' || r.path == '/statistics/bandwidth');

  // A shared user's token is refused the owner's routes the way a bad token
  // is refused everything: 401, Plex's only word for it.
  @override
  NetworkReply refuseWrite(NetworkRequest r) => refuseKey(r);

  static JsonMap _metadata(ServerContext c, WorldTitle t, int key) {
    final unverified = c.profile.unverifiedMatches.contains(t.key);
    return {
      'ratingKey': '$key',
      'key': '/library/metadata/$key',
      'guid': 'plex://${t.isSeries ? 'show' : 'movie'}/${t.key}',
      'type': t.isSeries ? 'show' : 'movie',
      'title': t.title,
      'year': t.year,
      'addedAt':
          c.now.subtract(const Duration(days: 30)).millisecondsSinceEpoch ~/
          1000,
      'Guid': [
        {'id': 'tmdb://${unverified ? t.tmdbId + 1000000 : t.tmdbId}'},
        if (t.imdbId != null && !unverified) {'id': 'imdb://${t.imdbId}'},
        if (t.tvdbId != null) {'id': 'tvdb://${t.tvdbId}'},
      ],
    };
  }

  static const _library = [
    WorldTitles.coffeeRun,
    WorldTitles.sintel,
    WorldTitles.tearsOfSteel,
    WorldTitles.elephantsDream,
    WorldTitles.spring,
  ];

  @override
  NetworkReply? answer(NetworkRequest r, ServerContext c) {
    if (r.method != 'GET') return const NetworkReply(200);
    switch (r.path) {
      case '/identity':
        return NetworkReply.json(jsonFixtureMap('plex/identity.json'));
      case '/':
        return NetworkReply.json(jsonFixtureMap('plex/capabilities.json'));
      case '/status/sessions':
        return NetworkReply.json(jsonFixtureMap('plex/sessions_idle.json'));
      case '/library/sections':
        return NetworkReply.json(jsonFixtureMap('plex/library_sections.json'));
      case '/hubs/continueWatching':
      case '/hubs/home/continueWatching':
        return NetworkReply.json({
          'MediaContainer': {'size': 0, 'Hub': const <Object?>[]},
        });
      case '/library/onDeck':
      case '/library/recentlyAdded':
        return NetworkReply.json({
          'MediaContainer': {'size': 0, 'Metadata': const <Object?>[]},
        });
      case '/hubs/search':
      case '/library/all':
        // Plex ignores provider filters (P6's f): it answers the whole
        // library and leaves the match to the client.
        return NetworkReply.json({
          'MediaContainer': {
            'size': _library.length,
            'Metadata': [
              for (final (i, t) in _library.indexed) _metadata(c, t, 100 + i),
            ],
          },
        });
    }
    if (RegExp(r'^/library/sections/\d+/all$').hasMatch(r.path)) {
      return NetworkReply.json({
        'MediaContainer': {
          'size': _library.length,
          'totalSize': _library.length,
          'offset': 0,
          'Metadata': [
            for (final (i, t) in _library.indexed) _metadata(c, t, 100 + i),
          ],
        },
      });
    }
    return null;
  }
}
