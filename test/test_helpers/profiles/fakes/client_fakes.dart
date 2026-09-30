/// The four download clients on the fake network: qBittorrent, Transmission,
/// SABnzbd and NZBGet.
///
/// Rows come from `WorldDownloads`, so a torrent here and its row in the
/// Radarr or Sonarr queue share the download id the Dashboard joins on.
library;

import '../../fixtures.dart';
import '../profile_network.dart';
import '../service_fakes.dart';
import '../world.dart';

List<WorldDownload> _rowsOf(ServerContext c, String client) => [
  for (final d in WorldDownloads.all)
    if (d.client == client) d,
];

// === qBittorrent ===========================================================

/// qBittorrent's WebUI: form login, `SID` cookie, then the v2 API.
///
/// A refused sign-in is `200 Fails.` on the login route — the ≤ 5.0 spelling
/// the client is written against — and `403` everywhere else, which is what an
/// unauthenticated WebUI answers.
class QbittorrentFake extends ServiceFake {
  const QbittorrentFake();

  static const _login = '/api/v2/auth/login';

  @override
  bool isWrite(NetworkRequest r) => r.method == 'POST' && r.path != _login;

  @override
  NetworkReply refuseKey(NetworkRequest r) => r.path == _login
      ? NetworkReply.text('Fails.')
      : NetworkReply.text('Forbidden', status: 403);

  @override
  NetworkReply refuseWrite(NetworkRequest r) =>
      NetworkReply.text('Forbidden', status: 403);

  static String _state(WorldDownload d) => switch (d.state) {
    DownloadState.downloading => 'downloading',
    DownloadState.stuck => 'stalledDL',
    DownloadState.queued => 'queuedDL',
    DownloadState.importBlocked || DownloadState.seeding => 'stalledUP',
    DownloadState.stopped => 'stoppedUP',
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
      'num_seeds': stuck ? 0 : 12,
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
          'server_state': {
            'dl_info_speed': rows.fold<int>(0, (sum, d) => sum + d.speed),
            'up_info_speed': 1153433,
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
        return NetworkReply.json(const <String, Object?>{});
      case ('GET', '/api/v2/rss/rules'):
        return NetworkReply.json(const <String, Object?>{});
      case ('GET', '/api/v2/torrents/categories'):
        return NetworkReply.json({
          'radarr': {'name': 'radarr', 'savePath': ''},
          'tv-sonarr': {'name': 'tv-sonarr', 'savePath': ''},
        });
      case ('GET', '/api/v2/torrents/tags'):
        return NetworkReply.json(const <Object?>[]);
    }
    if (r.method == 'POST') return NetworkReply.text('Ok.');
    return null;
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

  @override
  bool isWrite(NetworkRequest r) => !_reads.contains(_method(r));

  @override
  NetworkReply refuseKey(NetworkRequest r) =>
      NetworkReply.text('<h1>401: Unauthorized</h1>', status: 401);

  @override
  NetworkReply? gate(NetworkRequest r, ServerContext c) {
    final refused = super.gate(r, c);
    if (refused != null) return refused;
    if (r.headers['x-transmission-session-id'] != sessionId) {
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
        return ok({
          'torrents': [
            for (final (i, d) in rows.indexed)
              {
                'id': i + 1,
                'hashString': d.id.toLowerCase(),
                'name': d.release,
                'status': 4,
                'percentDone': d.progress,
                'totalSize': d.size,
                'sizeWhenDone': d.size,
                'leftUntilDone': d.sizeLeft,
                'rateDownload': d.speed,
                'rateUpload': 0,
                'eta': d.eta?.inSeconds ?? -1,
                'uploadRatio': 0.0,
                'error': 0,
                'errorString': '',
                'addedDate': c.now.millisecondsSinceEpoch ~/ 1000 - 3600,
                'downloadDir': '/mnt/tank/downloads',
                'labels': const ['sonarr'],
                'peersConnected': 8,
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
    return ok(const {});
  }
}

// === SABnzbd ===============================================================

/// SABnzbd's `/api?mode=…` surface. A wrong key is a `200` with
/// `{"status": false, "error": "API Key Incorrect"}`; `mode=version` needs no
/// key at all, which is why the Dashboard's probe reads a SABnzbd with a bad
/// key as online.
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
  bool isPublic(NetworkRequest r) => _mode(r) == 'version';

  // `mode=queue&name=delete` and friends change things; a bare queue reads.
  @override
  bool isWrite(NetworkRequest r) =>
      !_reads.contains(_mode(r)) || r.query.containsKey('name');

  @override
  NetworkReply refuseKey(NetworkRequest r) =>
      NetworkReply.json({'status': false, 'error': 'API Key Incorrect'});

  // SABnzbd has no read-only full key; the NZB key it can hand out is refused
  // on every full-API call, reads included, in the same words.
  @override
  NetworkReply refuseWrite(NetworkRequest r) => refuseKey(r);

  @override
  NetworkReply? answer(NetworkRequest r, ServerContext c) {
    final rows = _rowsOf(c, 'sabnzbd');
    final mbLeft = rows.fold<double>(0, (s, d) => s + d.sizeLeft / 1048576);
    final speed = rows.fold<int>(0, (s, d) => s + d.speed);
    switch (_mode(r)) {
      case 'version':
        return NetworkReply.json({'version': '4.3.3'});
      case 'queue':
        if (r.query.containsKey('name')) {
          return NetworkReply.json({'status': true});
        }
        return NetworkReply.json({
          'queue': {
            'paused': false,
            'status': 'Downloading',
            'kbpersec': (speed / 1024).toStringAsFixed(1),
            'speed': '${(speed / 1048576).toStringAsFixed(1)} M',
            'mbleft': mbLeft.toStringAsFixed(1),
            'mb': rows
                .fold<double>(0, (s, d) => s + d.size / 1048576)
                .toStringAsFixed(1),
            'timeleft': '0:12:00',
            'diskspace1': '12400.00',
            'diskspacetotal1': '43600.00',
            'noofslots': rows.length,
            'noofslots_total': rows.length,
            'slots': [
              for (final (i, d) in rows.indexed)
                {
                  'index': i,
                  'nzo_id': d.id,
                  'filename': d.release,
                  'status': d.state == DownloadState.queued
                      ? 'Queued'
                      : 'Downloading',
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
    }
    return NetworkReply.json({'status': true});
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
  bool isWrite(NetworkRequest r) => !_reads.contains(_method(r));

  @override
  NetworkReply refuseKey(NetworkRequest r) => const NetworkReply(401);

  @override
  NetworkReply? answer(NetworkRequest r, ServerContext c) {
    final body = r.json;
    final id = body is Map ? body['id'] : null;
    NetworkReply result(Object? value) =>
        NetworkReply.json({'version': '1.1', 'id': id, 'result': value});
    return switch (_method(r)) {
      'version' => result(
        jsonFixture('nzbget/version.json')['result'] ?? '24.3',
      ),
      'status' => result(jsonFixtureMap('nzbget/status.json')['result']),
      'listgroups' => result(const <Object?>[]),
      'history' => result(const <Object?>[]),
      _ => result(true),
    };
  }
}
