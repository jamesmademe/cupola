/// The four download clients on the fake network: qBittorrent, Transmission,
/// SABnzbd and NZBGet.
///
/// Rows come from `WorldDownloads`, so a torrent here and its row in the
/// Radarr or Sonarr queue share the download id the Dashboard joins on.
library;

import 'package:cupola/demo/world/fixtures.dart';
import 'package:cupola/demo/world/profile_network.dart';
import 'package:cupola/demo/world/service_fakes.dart';
import 'package:cupola/demo/world/world.dart';

List<WorldDownload> _rowsOf(ServerContext c, String client) => [
  for (final d in c.downloads)
    if (d.client == client) d,
];

// === qBittorrent ===========================================================

/// qBittorrent's WebUI: form login, `SID` cookie, then the v2 API.
///
/// A refused sign-in is `200 Fails.` on the login route: the ≤ 5.0 spelling
/// the client is written against, and `403` everywhere else, which is what an
/// unauthenticated WebUI answers.
class QbittorrentFake extends ServiceFake {
  const QbittorrentFake();

  static const _login = '/api/v2/auth/login';

  @override
  bool isWrite(NetworkRequest request) =>
      request.method == 'POST' && request.path != _login;

  @override
  NetworkReply refuseKey(NetworkRequest request) => request.path == _login
      ? NetworkReply.text('Fails.')
      : NetworkReply.text('Forbidden', status: 403);

  @override
  NetworkReply refuseWrite(NetworkRequest request) =>
      NetworkReply.text('Forbidden', status: 403);

  static String _state(WorldDownload d) => switch (d.state) {
    DownloadState.downloading => 'downloading',
    DownloadState.stuck => 'stalledDL',
    DownloadState.queued => 'queuedDL',
    DownloadState.importBlocked || DownloadState.seeding => 'stalledUP',
    DownloadState.stopped => 'stoppedUP',
    DownloadState.failed => 'error',
    DownloadState.missingFiles => 'missingFiles',
    DownloadState.heldByClient || DownloadState.paused => 'stoppedDL',
  };

  static JsonMap torrent(ServerContext c, WorldDownload d) {
    final now = c.now.millisecondsSinceEpoch ~/ 1000;
    final stuck = d.state == DownloadState.stuck;
    return {
      'hash': d.id.toLowerCase(),
      'name': d.release,
      'state': _state(d),
      'progress': d.progress,
      'size': d.size,
      'total_size': d.size,
      'amount_left': d.sizeLeft,
      'downloaded': d.size - d.sizeLeft,
      'completed': d.size - d.sizeLeft,
      'uploaded': d.progress == 1 ? d.size * 2 : 0,
      'dlspeed': d.speed,
      'upspeed': d.state == DownloadState.seeding ? 120000 : 0,
      'eta': d.eta?.inSeconds ?? 8640000,
      'ratio': d.release.startsWith('Sintel') ? 2.4 : 1.1,
      'category': switch (d.arr) {
        WorldIds.radarr || WorldIds.radarr4k => 'radarr',
        WorldIds.sonarr || WorldIds.sonarrAnime => 'tv-sonarr',
        _ => '',
      },
      'tags': '',
      'save_path': '/mnt/tank/downloads/',
      'content_path': '/mnt/tank/downloads/${d.release}',
      'added_on': now - 3 * 3600,
      'completion_on': d.progress == 1 ? now - 3600 : -1,
      'last_activity': stuck ? now - 3 * 3600 : now - 5,
      'num_seeds': d.peers ?? (stuck ? 0 : 12),
      'num_complete': stuck ? 0 : 40,
      'num_leechs': 3,
      'num_incomplete': 5,
      'priority': 1,
      'force_start': false,
      'tracker': 'https://tracker.example.net/announce',
      'magnet_uri': 'magnet:?xt=urn:btih:${d.id.toLowerCase()}',
    };
  }

  @override
  NetworkReply? answer(NetworkRequest r, ServerContext c) {
    final rows = _rowsOf(c, 'qbittorrent');
    switch ((r.method, r.path)) {
      case ('POST', _login):
        return NetworkReply.text(
          'Ok.',
          headers: {
            'set-cookie': ['SID=world-session; HttpOnly; path=/'],
          },
        );
      case ('GET', '/api/v2/app/version'):
        return NetworkReply.text('v4.6.7');
      case ('GET', '/api/v2/app/webapiVersion'):
        return NetworkReply.text('2.9.3');
      case ('GET', '/api/v2/app/preferences'):
        return NetworkReply.json({
          'dl_limit': 0,
          'up_limit': 0,
          'alt_dl_limit': 5 * 1024 * 1024,
          'alt_up_limit': 1024 * 1024,
          'save_path': '/mnt/tank/downloads/',
        });
      case ('GET', '/api/v2/torrents/info'):
        final hashes = r.query['hashes']?.split('|').toSet();
        return NetworkReply.json([
          for (final d in rows)
            if (hashes == null || hashes.contains(d.id.toLowerCase()))
              torrent(c, d),
        ]);
      case ('GET', '/api/v2/transfer/info'):
        return NetworkReply.json({
          'dl_info_speed': rows.fold<int>(0, (sum, d) => sum + d.speed),
          'up_info_speed': 1153433,
          'dl_info_data': 42000000000,
          'up_info_data': 77000000000,
          'dl_rate_limit': 0,
          'up_rate_limit': 0,
          'connection_status': 'connected',
          'dht_nodes': 380,
        });
      case ('GET', '/api/v2/transfer/speedLimitsMode'):
        return NetworkReply.text('0');
      case ('GET', '/api/v2/sync/maindata'):
        return NetworkReply.json({
          'rid': 1,
          'full_update': true,
          'torrents': {for (final d in rows) d.id.toLowerCase(): torrent(c, d)},
          // What a real server_state carries: the session's figures under the
          // same keys `/transfer/info` uses, and the ones it leaves out.
          'server_state': {
            'dl_info_speed': rows.fold<int>(0, (sum, d) => sum + d.speed),
            'up_info_speed': 1153433,
            'dl_info_data': 42000000000,
            'up_info_data': 77000000000,
            'dl_rate_limit': 0,
            'up_rate_limit': 0,
            'dht_nodes': 380,
            'free_space_on_disk': 13634000000000,
            'alltime_dl': 9000000000000,
            'alltime_ul': 16560000000000,
            'global_ratio': '1.84',
            'use_alt_speed_limits': false,
            'connection_status': 'connected',
          },
        });
      case ('GET', '/api/v2/torrents/properties'):
        return NetworkReply.json({
          'save_path': '/mnt/tank/downloads/',
          'total_size': 0,
          'seeds': 0,
          'peers': 0,
        });
      case ('GET', '/api/v2/torrents/files'):
      case ('GET', '/api/v2/torrents/trackers'):
        return NetworkReply.json(const <Object?>[]);
      case ('GET', '/api/v2/rss/items'):
        return NetworkReply.json(_rssItems(c, withData: r.query['withData']));
      case ('GET', '/api/v2/rss/rules'):
        return NetworkReply.json(_rssRules(c));
      case ('GET', '/api/v2/torrents/categories'):
        return NetworkReply.json({
          'radarr': {'name': 'radarr', 'savePath': ''},
          'tv-sonarr': {'name': 'tv-sonarr', 'savePath': ''},
        });
      case ('GET', '/api/v2/torrents/tags'):
        return NetworkReply.json(const <Object?>[]);
    }
    if (r.method == 'POST') {
      _write(r, c, rows);
      return NetworkReply.text('Ok.');
    }
    return null;
  }

  static const _rssFeedUrl = 'https://feeds.example.net/open-movies.xml';

  /// The one feed the household follows, as `rss/items` sends it: the feed
  /// is a leaf with its `url`, and with `withData=true` its articles, one
  /// of them already read. Without `withData` a leaf is the bare URL, which
  /// is what an older WebUI sends and what the app reads without a count.
  static JsonMap _rssItems(ServerContext c, {String? withData}) {
    if (withData != 'true') return {'Open Movies': _rssFeedUrl};
    JsonMap article(
      String id,
      String title,
      Duration age, {
      bool read = false,
    }) => {
      'id': id,
      'title': title,
      'date': c.ago(age),
      'description': '$title, released by the Open Movies feed.',
      'torrentURL': 'https://feeds.example.net/torrent/$id.torrent',
      'isRead': read,
    };
    return {
      'Open Movies': {
        'uid': '{6b1f3a52-0c7e-4d0b-9a55-2f0c4a7e91d3}',
        'url': _rssFeedUrl,
        'title': 'Open Movies',
        'lastBuildDate': c.ago(const Duration(minutes: 40)),
        'isLoading': false,
        'hasError': false,
        'articles': [
          article(
            'tears-of-steel-1080p',
            'Tears.of.Steel.2012.1080p.BluRay',
            const Duration(hours: 5),
          ),
          article(
            'spring-1080p',
            'Spring.2014.1080p.BluRay',
            const Duration(days: 1, hours: 2),
            read: true,
          ),
          article(
            'charge-1080p',
            'Charge.2022.1080p.WEB',
            const Duration(days: 2, hours: 7),
            read: true,
          ),
          article(
            'coffee-run-720p',
            'Coffee.Run.2020.720p.WEB',
            const Duration(days: 3),
          ),
        ],
      },
    };
  }

  /// The rule that sends what the feed carries at 1080p to Radarr's
  /// category, as `rss/rules` sends it.
  static JsonMap _rssRules(ServerContext c) => {
    'Open Movies 1080p': {
      'enabled': true,
      'mustContain': '1080p',
      'mustNotContain': 'CAM|HDTS|TELESYNC',
      'useRegex': true,
      'episodeFilter': '',
      'smartFilter': false,
      'previouslyMatchedEpisodes': const <Object?>[],
      'affectedFeeds': const [_rssFeedUrl],
      'ignoreDays': 0,
      'lastMatch': c.ago(const Duration(days: 1, hours: 2)),
      'addPaused': null,
      'assignedCategory': 'radarr',
      'savePath': '',
    },
  };

  /// What a write does to a living world: pause, resume, delete. The rest
  /// (tags, limits, a recheck) is answered and changes nothing the world
  /// draws.
  static void _write(
    NetworkRequest r,
    ServerContext c,
    List<WorldDownload> rows,
  ) {
    final life = c.life;
    if (life == null) return;
    final named = r.form['hashes'] ?? '';
    final hashes = named == 'all'
        ? [for (final d in rows) d.id]
        : named.split('|').where((h) => h.isNotEmpty).toList();
    final act = switch (r.path) {
      '/api/v2/torrents/stop' || '/api/v2/torrents/pause' => life.pause,
      '/api/v2/torrents/start' || '/api/v2/torrents/resume' => life.resume,
      '/api/v2/torrents/delete' => life.remove,
      _ => null,
    };
    if (act == null) return;
    hashes.forEach(act);
  }
}

// === Transmission ==========================================================

/// Transmission's RPC: HTTP Basic, then the `409` session-id handshake.
///
/// The credential is checked before the session id, as the daemon does, so a
/// wrong password is a `401` and never reaches the handshake.
class TransmissionFake extends ServiceFake {
  const TransmissionFake();

  static const sessionId = 'world-transmission-session';

  static const _reads = {
    'session-get',
    'session-stats',
    'torrent-get',
    'free-space',
    'port-test',
  };

  String _method(NetworkRequest r) {
    final body = r.json;
    return body is Map ? '${body['method']}' : '';
  }

  /// Transmission's `status`: 0 stopped, 3 queued to download, 4
  /// downloading, 6 seeding. A local error stops the torrent.
  static int _status(WorldDownload d) => switch (d.state) {
    DownloadState.downloading || DownloadState.stuck => 4,
    DownloadState.queued => 3,
    DownloadState.importBlocked || DownloadState.seeding => 6,
    DownloadState.stopped ||
    DownloadState.failed ||
    DownloadState.missingFiles ||
    DownloadState.heldByClient ||
    DownloadState.paused => 0,
  };

  static bool _localError(WorldDownload d) =>
      d.state == DownloadState.failed || d.state == DownloadState.missingFiles;

  @override
  bool isWrite(NetworkRequest request) => !_reads.contains(_method(request));

  @override
  NetworkReply refuseKey(NetworkRequest request) =>
      NetworkReply.text('<h1>401: Unauthorized</h1>', status: 401);

  @override
  NetworkReply? gate(NetworkRequest request, ServerContext context) {
    final refused = super.gate(request, context);
    if (refused != null) return refused;
    if (request.headers['x-transmission-session-id'] != sessionId) {
      return NetworkReply.text(
        '<h1>409: Conflict</h1>',
        status: 409,
        headers: {
          'X-Transmission-Session-Id': [sessionId],
        },
      );
    }
    return null;
  }

  @override
  NetworkReply? answer(NetworkRequest r, ServerContext c) {
    final body = r.json;
    final tag = body is Map ? body['tag'] : null;
    NetworkReply ok(Map<String, Object?> arguments) => NetworkReply.json({
      'result': 'success',
      'arguments': arguments,
      'tag': ?tag,
    });
    final rows = _rowsOf(c, 'transmission');
    switch (_method(r)) {
      case 'session-get':
        return ok({
          'version': '4.0.6 (38c1649)',
          'rpc-version': 17,
          'rpc-version-minimum': 14,
          'download-dir': '/mnt/tank/downloads',
          'speed-limit-down-enabled': false,
          'speed-limit-up-enabled': false,
          'alt-speed-enabled': false,
        });
      case 'session-stats':
        return ok({
          'downloadSpeed': rows.fold<int>(0, (sum, d) => sum + d.speed),
          'uploadSpeed': 0,
          'activeTorrentCount': rows.length,
          'pausedTorrentCount': 0,
          'torrentCount': rows.length,
        });
      case 'torrent-get':
        final now = c.now.millisecondsSinceEpoch ~/ 1000;
        return ok({
          'torrents': [
            for (final (i, d) in rows.indexed)
              {
                'id': i + 1,
                'hashString': d.id.toLowerCase(),
                'name': d.release,
                'status': _status(d),
                'percentDone': d.progress,
                'totalSize': d.size,
                'sizeWhenDone': d.size,
                'leftUntilDone': d.sizeLeft,
                'rateDownload': d.speed,
                'rateUpload': 0,
                'eta': d.eta?.inSeconds ?? -1,
                'uploadRatio': 0.0,
                // A local error, in the daemon's own words for missing data.
                'error': _localError(d) ? 3 : 0,
                'errorString': _localError(d)
                    ? 'No data found! Ensure your drives are connected or use '
                          '"Set Location". To re-download, remove the torrent '
                          'and re-add it.'
                    : '',
                'addedDate': now - 3600,
                'activityDate': d.state == DownloadState.stuck
                    ? now - 3 * 3600
                    : now - 5,
                'downloadDir': '/mnt/tank/downloads',
                'labels': const ['sonarr'],
                'peersConnected': 8,
                'peersSendingToUs':
                    d.peers ?? (d.state == DownloadState.stuck ? 0 : 6),
                'isStalled': d.state == DownloadState.stuck,
                'isFinished': false,
              },
          ],
        });
      case 'free-space':
        return ok({
          'path': '/mnt/tank/downloads',
          'size-bytes': 12400000000000,
        });
    }
    _write(r, c, rows);
    return ok(const {});
  }

  /// What a write does to a living world: start, stop, remove, named by the
  /// torrents' ids in `torrent-get` (their place in the list) or by hash.
  void _write(NetworkRequest r, ServerContext c, List<WorldDownload> rows) {
    final life = c.life;
    final body = r.json;
    if (life == null || body is! Map) return;
    final arguments = body['arguments'];
    final ids = arguments is Map ? arguments['ids'] : null;
    final named = <String>[
      if (ids is List)
        for (final id in ids)
          if (id is int && id >= 1 && id <= rows.length)
            rows[id - 1].id
          else if (id is String)
            id,
      if (ids == null)
        for (final d in rows) d.id,
    ];
    final act = switch (_method(r)) {
      'torrent-stop' => life.pause,
      'torrent-start' || 'torrent-start-now' => life.resume,
      'torrent-remove' => life.remove,
      _ => null,
    };
    if (act == null) return;
    named.forEach(act);
  }
}

// === SABnzbd ===============================================================

/// SABnzbd's `/api?mode=…` surface. A wrong key is a `200` with
/// `{"status": false, "error": "API Key Incorrect"}`; `mode=version` needs no
/// key at all, which is why the Dashboard's probe reads a one-slot queue
/// before it asks for the version.
class SabnzbdFake extends ServiceFake {
  const SabnzbdFake();

  static const _reads = {
    'version',
    'queue',
    'history',
    'server_stats',
    'get_cats',
    'get_config',
    'fullstatus',
    'warnings',
    'status',
  };

  String _mode(NetworkRequest r) => r.query['mode'] ?? '';

  @override
  bool isPublic(NetworkRequest request) => _mode(request) == 'version';

  // `mode=queue&name=delete` and friends change things; a bare queue reads.
  @override
  bool isWrite(NetworkRequest request) =>
      !_reads.contains(_mode(request)) || request.query.containsKey('name');

  @override
  NetworkReply refuseKey(NetworkRequest request) =>
      NetworkReply.json({'status': false, 'error': 'API Key Incorrect'});

  // SABnzbd has no read-only full key; the NZB key it can hand out is refused
  // on every full-API call, reads included, in the same words.
  @override
  NetworkReply refuseWrite(NetworkRequest request) => refuseKey(request);

  @override
  NetworkReply? answer(NetworkRequest r, ServerContext c) {
    final rows = _rowsOf(c, 'sabnzbd');
    final mbLeft = rows.fold<double>(0, (s, d) => s + d.sizeLeft / 1048576);
    // A full disk stops the queue as a pause does, and nothing moves.
    final diskFull = c.profile.fullDisks.contains(c.server.id);
    final paused = diskFull || c.pausedQueues.contains(c.server.id);
    final speed = paused ? 0 : rows.fold<int>(0, (s, d) => s + d.speed);
    switch (_mode(r)) {
      case 'version':
        return NetworkReply.json({'version': '4.3.3'});
      case 'queue':
        if (r.query.containsKey('name')) {
          _writeJob(r, c);
          return NetworkReply.json({'status': true});
        }
        return NetworkReply.json({
          'queue': {
            'paused': paused,
            'status': paused ? 'Paused' : 'Downloading',
            'pause_int': '0',
            'kbpersec': (speed / 1024).toStringAsFixed(1),
            'speed': '${(speed / 1048576).toStringAsFixed(1)} M',
            'mbleft': mbLeft.toStringAsFixed(1),
            'mb': rows
                .fold<double>(0, (s, d) => s + d.size / 1048576)
                .toStringAsFixed(1),
            'timeleft': '0:12:00',
            'diskspace1': diskFull ? '0.42' : '12400.00',
            'diskspacetotal1': '43600.00',
            'noofslots': rows.length,
            'noofslots_total': rows.length,
            'slots': [
              for (final (i, d) in rows.indexed)
                {
                  'index': i,
                  'nzo_id': d.id,
                  'filename': d.release,
                  'status': switch (d.state) {
                    DownloadState.queued => 'Queued',
                    DownloadState.heldByClient ||
                    DownloadState.paused => 'Paused',
                    // With the downloader paused, a slot reports its job's
                    // own status (`api.py`, `build_queue`): queued.
                    _ => paused ? 'Queued' : 'Downloading',
                  },
                  'labels': [
                    if (d.state == DownloadState.heldByClient) 'ENCRYPTED',
                  ],
                  'percentage': '${(d.progress * 100).round()}',
                  'cat': 'movies',
                  'priority': 'Normal',
                  'timeleft': d.eta == null
                      ? '0:00:00'
                      : '0:${d.eta!.inMinutes.toString().padLeft(2, '0')}:00',
                  'mb': (d.size / 1048576).toStringAsFixed(1),
                  'mbleft': (d.sizeLeft / 1048576).toStringAsFixed(1),
                },
            ],
          },
        });
      case 'history':
        if (r.query.containsKey('name')) {
          return NetworkReply.json({'status': true});
        }
        return NetworkReply.json({
          'history': {
            'noofslots': 1,
            'total_size': '42.0 G',
            'slots': [
              {
                'nzo_id': 'SABnzbd_nzo_spring4k',
                'name': 'Spring.2019.2160p.UHD.BluRay',
                'status': 'Completed',
                'category': 'movies',
                'bytes': 7400000000,
                'completed':
                    c.now
                        .subtract(const Duration(hours: 2, minutes: 1))
                        .millisecondsSinceEpoch ~/
                    1000,
                'fail_message': '',
              },
            ],
          },
        });
      case 'server_stats':
        return NetworkReply.json({
          ...jsonFixtureMap('sabnzbd/server_stats.json'),
          'servers': {
            'news.northwind.example': {
              'total': 4000000000000,
              'day': 30000000000,
            },
            'eu.harbornews.example': {
              'total': 1400000000000,
              'day': 12000000000,
            },
          },
        });
      case 'get_cats':
        return NetworkReply.json({
          'categories': ['*', 'movies', 'tv', 'music'],
        });
      case 'fullstatus':
      case 'status':
        return NetworkReply.json({
          'status': {
            'servers': [
              {'servername': 'news.northwind.example', 'serveractive': true},
              {'servername': 'eu.harbornews.example', 'serveractive': true},
            ],
          },
        });
      case 'warnings':
        return NetworkReply.json({'warnings': const <Object?>[]});
      case 'pause' || 'resume':
        c.life?.setQueuePaused(c.server.id, paused: _mode(r) == 'pause');
    }
    return NetworkReply.json({'status': true});
  }

  /// What `mode=queue&name=…&value=<nzo_id>` does to a living world.
  void _writeJob(NetworkRequest r, ServerContext c) {
    final life = c.life;
    final job = r.query['value'];
    if (life == null || job == null) return;
    switch (r.query['name']) {
      case 'pause':
        life.pause(job);
      case 'resume':
        life.resume(job);
      case 'delete':
        life.remove(job);
    }
  }
}

// === NZBGet (World B) ======================================================

/// NZBGet's JSON-RPC at `/jsonrpc`, behind HTTP Basic.
class NzbgetFake extends ServiceFake {
  const NzbgetFake();

  static const _reads = {
    'version',
    'status',
    'listgroups',
    'history',
    'config',
    'log',
    'servervolumes',
  };

  String _method(NetworkRequest r) {
    final body = r.json;
    return body is Map ? '${body['method']}' : '';
  }

  @override
  bool isWrite(NetworkRequest request) => !_reads.contains(_method(request));

  @override
  NetworkReply refuseKey(NetworkRequest request) => const NetworkReply(401);

  @override
  NetworkReply? answer(NetworkRequest r, ServerContext c) {
    final body = r.json;
    final id = body is Map ? body['id'] : null;
    NetworkReply result(Object? value) =>
        NetworkReply.json({'version': '1.1', 'id': id, 'result': value});
    final rows = _rowsOf(c, 'nzbget');
    final diskFull = c.profile.fullDisks.contains(c.server.id);
    final paused = diskFull || c.pausedQueues.contains(c.server.id);
    return switch (_method(r)) {
      'version' => result(
        jsonFixture('nzbget/version.json')['result'] ?? '24.3',
      ),
      'status' => result(
        rows.isEmpty
            ? _ownStatus(diskFull: diskFull, paused: paused)
            : status(rows, diskFull: diskFull, paused: paused),
      ),
      'listgroups' => result(
        rows.isEmpty
            ? _ownGroups(paused: paused)
            : [
                for (final (i, d) in rows.indexed)
                  group(d, nzbId: i + 1, paused: paused),
              ],
      ),
      'history' => result(_history(c)),
      'config' => result(_config),
      'log' => result(_log(c)),
      _ => result(_write(r, c, rows)),
    };
  }

  // The world holds no download for NZBGet, so its own screens would be
  // empty. What it moves lives here, not in `WorldDownloads`: a download
  // there is counted across the Dashboard and the arr queues, and the
  // household's Sonarr and Radarr never sent these. One is moving, one waits.
  static const _ownJobs = [
    (
      id: 3,
      name: 'Tears.of.Steel.2012.1080p.BluRay',
      sizeMb: 4200,
      leftMb: 1500,
    ),
    (id: 4, name: 'Coffee.Run.2020.1080p.WEB', sizeMb: 1400, leftMb: 1400),
  ];

  static List<JsonMap> _ownGroups({required bool paused}) => [
    for (final (i, job) in _ownJobs.indexed)
      {
        'NZBID': job.id,
        'NZBName': job.name,
        // A paused queue holds the moving job as queued, as it does a row
        // of the world's.
        'Status': i == 0 && !paused ? 'DOWNLOADING' : 'QUEUED',
        'Category': 'movies',
        'FileSizeMB': job.sizeMb,
        'RemainingSizeMB': job.leftMb,
        'Health': 1000,
        'CriticalHealth': 898,
        'Parameters': const <Object?>[],
      },
  ];

  /// `status` for the jobs above: the fixture's 2 MiB/s on the one moving,
  /// and what is left of both.
  static JsonMap _ownStatus({required bool diskFull, required bool paused}) {
    final base = status(const [], diskFull: diskFull, paused: paused);
    return {
      ...base,
      'RemainingSizeMB': _ownJobs.fold<int>(0, (sum, j) => sum + j.leftMb),
      if (paused) 'DownloadRate': 0,
    };
  }

  /// `history`: what arrived, and one release that lost more articles than
  /// its pars could repair, which the queue's Coffee Run is the retry of.
  static List<JsonMap> _history(ServerContext c) {
    int at(Duration age) => c.now.subtract(age).millisecondsSinceEpoch ~/ 1000;
    JsonMap entry(int id, String name, String status, Duration age) => {
      'ID': id,
      'NZBID': id,
      'Name': name,
      'NZBName': name,
      'Status': status,
      'Category': 'movies',
      'HistoryTime': at(age),
    };
    return [
      entry(
        2,
        'Coffee.Run.2020.720p.WEB',
        'FAILURE/HEALTH',
        const Duration(hours: 6),
      ),
      entry(
        1,
        'Spring.2014.1080p.BluRay',
        'SUCCESS/ALL',
        const Duration(days: 1, hours: 2),
      ),
      entry(
        0,
        'Charge.2022.1080p.WEB',
        'SUCCESS/ALL',
        const Duration(days: 2, hours: 7),
      ),
    ];
  }

  /// `config`, cut to what the screens read: the one RSS feed the household
  /// follows. The real answer is every option; the client keeps `FeedN.*`.
  static const _config = [
    {'Name': 'MainDir', 'Value': '/downloads'},
    {'Name': 'Feed1.Name', 'Value': 'Open Movies (usenet)'},
    {'Name': 'Feed1.URL', 'Value': 'https://indexer.example.net/rss?t=2000'},
    {'Name': 'Feed1.Filter', 'Value': 'Accept: 1080p'},
    {'Name': 'Feed1.Interval', 'Value': '15'},
    {'Name': 'Feed1.Backlog', 'Value': 'no'},
    {'Name': 'Feed1.PauseNzb', 'Value': 'no'},
    {'Name': 'Feed1.Category', 'Value': 'movies'},
    {'Name': 'Feed1.Priority', 'Value': '0'},
  ];

  /// `log`: the screen log, oldest first, the way the daemon keeps it.
  static List<JsonMap> _log(ServerContext c) {
    int at(Duration age) => c.now.subtract(age).millisecondsSinceEpoch ~/ 1000;
    JsonMap line(int id, String kind, Duration age, String text) => {
      'ID': id,
      'Kind': kind,
      'Time': at(age),
      'Text': text,
    };
    return [
      line(1, 'INFO', const Duration(hours: 9), 'nzbget 24.3 server-mode'),
      line(
        2,
        'INFO',
        const Duration(hours: 9),
        'Using config-file /config/nzbget.conf',
      ),
      line(
        3,
        'INFO',
        const Duration(days: 2, hours: 7),
        'Successfully downloaded Charge.2022.1080p.WEB',
      ),
      line(
        4,
        'INFO',
        const Duration(days: 1, hours: 2),
        'Successfully downloaded Spring.2014.1080p.BluRay',
      ),
      line(
        5,
        'WARNING',
        const Duration(hours: 6, minutes: 14),
        'Download health for Coffee.Run.2020.720p.WEB is 64.0%, below the '
            'critical health 89.8%',
      ),
      line(
        6,
        'ERROR',
        const Duration(hours: 6),
        'Failed Coffee.Run.2020.720p.WEB: not enough articles',
      ),
      line(
        7,
        'INFO',
        const Duration(minutes: 52),
        'Fetched 1 new item from feed Open Movies (usenet)',
      ),
      line(
        8,
        'INFO',
        const Duration(minutes: 31),
        'Collection Tears.of.Steel.2012.1080p.BluRay added to queue',
      ),
    ];
  }

  /// What a write does to a living world: the whole queue paused or
  /// resumed, a group paused, resumed or deleted by its `NZBID` (its place
  /// in `listgroups`). Always `true`, as NZBGet answers.
  bool _write(NetworkRequest r, ServerContext c, List<WorldDownload> rows) {
    final life = c.life;
    final body = r.json;
    if (life == null || body is! Map) return true;
    final params = body['params'];
    switch (_method(r)) {
      case 'pausedownload':
        life.setQueuePaused(c.server.id, paused: true);
      case 'resumedownload':
        life.setQueuePaused(c.server.id, paused: false);
      case 'editqueue' when params is List && params.length >= 4:
        final act = switch (params[0]) {
          'GroupPause' => life.pause,
          'GroupResume' => life.resume,
          'GroupDelete' || 'GroupFinalDelete' => life.remove,
          _ => null,
        };
        final ids = params[3];
        if (act == null || ids is! List) return true;
        for (final id in ids) {
          if (id is int && id >= 1 && id <= rows.length) act(rows[id - 1].id);
        }
    }
    return true;
  }

  /// `status`, with the rate summed over the world's NZBGet jobs. With none,
  /// the fixture as it was.
  ///
  /// A full disk pauses the download queue, as NZBGet does below its
  /// `DiskSpace` threshold, with 180 MB left on both directories.
  static JsonMap status(
    List<WorldDownload> rows, {
    bool diskFull = false,
    bool paused = false,
  }) {
    final fixture = (jsonFixtureMap('nzbget/status.json')['result'] as Map)
        .cast<String, Object?>();
    if (rows.isEmpty && !paused) return fixture;
    final rate = paused ? 0 : rows.fold<int>(0, (sum, d) => sum + d.speed);
    return {
      ...fixture,
      'DownloadRate': rate,
      'DownloadRateLo': rate,
      'DownloadRateHi': 0,
      'RemainingSizeMB': rows.fold<int>(0, (s, d) => s + d.sizeLeft ~/ _mib),
      'DownloadPaused': paused,
      'FreeDiskSpaceMB': diskFull ? 180 : 3200000,
      'FreeInterDiskSpaceMB': diskFull ? 180 : 3200000,
      'ResumeTime': 0,
      'QuotaReached': false,
    };
  }

  static const _mib = 1024 * 1024;

  /// One `listgroups` entry. An arr tags the NZB it sends with `drone=<id>`
  /// and records that id as its queue row's `downloadId`.
  ///
  /// A job in [DownloadState.failed] has lost more articles than its pars
  /// can repair; one in [DownloadState.heldByClient] is the same, paused by
  /// NZBGet's health check. Under a paused queue a group reports `QUEUED`.
  static JsonMap group(
    WorldDownload d, {
    required int nzbId,
    bool paused = false,
  }) => {
    'NZBID': nzbId,
    'NZBName': d.release,
    'Status': switch (d.state) {
      DownloadState.heldByClient || DownloadState.paused => 'PAUSED',
      DownloadState.queued => 'QUEUED',
      _ => paused ? 'QUEUED' : 'DOWNLOADING',
    },
    'Category': d.arr == null ? '' : 'tv',
    'FileSizeMB': d.size ~/ _mib,
    'RemainingSizeMB': d.sizeLeft ~/ _mib,
    'Health': switch (d.state) {
      DownloadState.failed || DownloadState.heldByClient => 640,
      _ => 1000,
    },
    'CriticalHealth': 898,
    'Parameters': [
      if (d.arr != null) {'Name': 'drone', 'Value': d.id},
    ],
  };
}
