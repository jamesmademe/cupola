@Tags(['e2e'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/api/api_client.dart';
import 'package:cupola/features/bazarr/data/bazarr_service.dart';
import 'package:cupola/features/discover/data/seerr_service.dart';
import 'package:cupola/features/dockge/data/dockge_client.dart';
import 'package:cupola/features/dockge/data/dockge_service.dart';
import 'package:cupola/features/jellyfin/data/jellyfin_client.dart';
import 'package:cupola/features/movies/data/radarr_service.dart';
import 'package:cupola/features/nzbget/data/nzbget_client.dart';
import 'package:cupola/features/npm/data/npm_client.dart';
import 'package:cupola/features/plex/data/plex_client.dart';
import 'package:cupola/features/prowlarr/data/prowlarr_service.dart';
import 'package:cupola/features/qbittorrent/data/qbittorrent_client.dart';
import 'package:cupola/features/qbittorrent/data/qbittorrent_service.dart';
import 'package:cupola/features/readarr/data/readarr_service.dart';
import 'package:cupola/features/sabnzbd/data/sabnzbd_client.dart';
import 'package:cupola/features/series/data/sonarr_service.dart';
import 'package:cupola/features/transmission/data/transmission_client.dart';
import 'package:cupola/features/truenas/data/truenas_service.dart';
import 'package:cupola/features/truenas/data/truenas_ws_client.dart';
import 'package:cupola/features/unraid/data/unraid_client.dart';
import 'package:cupola/features/music/data/lidarr_service.dart';

/// Disposable transport smoke for the full macOS/OrbStack laboratory.
///
/// The bootstrap writes the generated Seerr/Jellyfin values to a chmod-600
/// file. Pass its path with CUPOLA_MACLAB_CREDENTIALS_FILE; fixed passwords and
/// API keys are intentionally kept in that file too, rather than in Git.
///
/// This suite proves service reachability, authentication and the first typed
/// read used by Cupola. It is not the native visual/integration suite: a green
/// result here does not prove that a route draws the right screen.
void main() {
  final credentials = _loadCredentials();

  test('Seerr REST + session', () async {
    final client = ApiClient(
      baseUrl: 'http://127.0.0.1:5055',
      apiKey: credentials['CUPOLA_MACLAB_SEERR_API_KEY']!,
    );
    addTearDown(client.close);
    final service = SeerrService(client);
    final me = await client.get('/api/v1/auth/me');
    expect(me.data, isA<Map>());
    expect((await service.getRequests()), isA<List>());
  });

  test('Radarr REST + movie parser', () async {
    final client = _arr('http://127.0.0.1:7878');
    addTearDown(client.close);
    final service = RadarrService(client);
    final status = await client.get('/api/v3/system/status');
    expect(status.data, isA<Map>());
    expect(await service.getMoviesOrThrow(), isA<List>());
    expect(await service.getQueue(), isA<List>());
  });

  test('Sonarr REST + series parser', () async {
    final client = _arr('http://127.0.0.1:8989');
    addTearDown(client.close);
    final service = SonarrService(client);
    final status = await client.get('/api/v3/system/status');
    expect(status.data, isA<Map>());
    expect(await service.getSeriesOrThrow(), isA<List>());
    expect(await service.getQueue(), isA<List>());
  });

  test('Lidarr REST + artist parser', () async {
    final client = _arr('http://127.0.0.1:8686');
    addTearDown(client.close);
    final service = LidarrService(client);
    final status = await client.get('/api/v1/system/status');
    expect(status.data, isA<Map>());
    expect(await service.getArtistsOrThrow(), isA<List>());
    expect(await service.getQueue(), isA<List>());
  });

  test('Readarr REST + author parser', () async {
    final client = _arr('http://127.0.0.1:8787');
    addTearDown(client.close);
    final service = ReadarrService(client);
    final status = await client.get('/api/v1/system/status');
    expect(status.data, isA<Map>());
    expect(await service.getAuthorsOrThrow(), isA<List>());
    expect(await service.getQueue(), isA<List>());
  });

  test('Prowlarr REST + indexer parser', () async {
    final client = _arr('http://127.0.0.1:9696');
    addTearDown(client.close);
    final service = ProwlarrService(client);
    final status = await client.get('/api/v1/system/status');
    expect(status.data, isA<Map>());
    expect(await service.getHealth(), isA<List>());
    expect(await service.getIndexers(), isA<List>());
  });

  test('Bazarr REST + badges parser', () async {
    final client = _arr('http://127.0.0.1:6767');
    addTearDown(client.close);
    final service = BazarrService(client);
    final badges = await service.getBadges();
    expect(badges, isNotNull);
    expect((await service.getSeries()).data, isA<List>());
    expect((await service.getMovies()).data, isA<List>());
  });

  test('qBittorrent form auth + torrent parser', () async {
    final client = QbittorrentClient(
      url: 'http://127.0.0.1:8080',
      username: credentials['CUPOLA_MACLAB_QBITTORRENT_USERNAME'],
      password: credentials['CUPOLA_MACLAB_QBITTORRENT_PASSWORD'],
    );
    addTearDown(client.close);
    final service = QbittorrentService(client);
    expect(await service.authenticate(), isTrue);
    expect(await service.getVersion(), isNotEmpty);
    expect(await service.getTorrents(), isA<List>());
    expect((await service.getTransferInfo()).dlSpeed, greaterThanOrEqualTo(0));
  });

  test('Transmission RPC auth + CSRF handshake', () async {
    final client = TransmissionClient(
      url: 'http://127.0.0.1:9091',
      username: credentials['CUPOLA_MACLAB_TRANSMISSION_USERNAME'],
      password: credentials['CUPOLA_MACLAB_TRANSMISSION_PASSWORD'],
    );
    addTearDown(client.close);
    expect(await client.testConnection(), isTrue);
    expect(await client.version(), isNotEmpty);
    expect(await client.torrents(), isA<List>());
  });

  test('SABnzbd query auth + queue parser', () async {
    final client = SabnzbdClient(
      url: 'http://127.0.0.1:8082',
      apiKey: 'test-key',
    );
    addTearDown(client.close);
    expect(await client.getVersion(), isNotEmpty);
    expect((await client.getQueue()).slots, isA<List>());
    expect((await client.getServerStats()).total, greaterThanOrEqualTo(0));
  });

  test('NZBGet Basic auth + positional JSON-RPC', () async {
    final client = NzbgetClient(
      url: 'http://127.0.0.1:6789',
      username: credentials['CUPOLA_MACLAB_NZBGET_USERNAME'],
      password: credentials['CUPOLA_MACLAB_NZBGET_PASSWORD'],
    );
    addTearDown(client.close);
    expect(await client.testConnection(), isTrue);
    expect(await client.version(), isNotEmpty);
    expect(await client.status(), isNotNull);
    expect(await client.listGroups(), isA<List>());
  });

  test('Jellyfin token auth + library parser', () async {
    final client = JellyfinClient(
      baseUrl: 'http://127.0.0.1:8096',
      apiKey: credentials['CUPOLA_MACLAB_JELLYFIN_TOKEN']!,
      userId: credentials['CUPOLA_MACLAB_JELLYFIN_USER_ID']!,
      deviceName: 'Cupola MacLab E2E',
      deviceId: 'cupola-maclab-e2e',
    );
    addTearDown(client.close);
    expect(await client.verifyCredential(), isTrue);
    expect(await client.probeVersion(), isNotEmpty);
    expect(await client.getLibraries(), isA<List>());
    expect(await client.getSessions(), isA<List>());
  });

  test('Plex token auth + identity parser', () async {
    final client = PlexClient(
      url: 'http://127.0.0.1:32400',
      token: credentials['CUPOLA_MACLAB_PLEX_TOKEN']!,
      clientIdentifier: 'cupola-maclab-e2e',
    );
    addTearDown(client.close);
    expect(await client.verifyCredential(), isTrue);
    expect(await client.probeVersion(), isNotEmpty);
    expect(await client.getIdentity(), isNotNull);
    expect(await client.getLibraries(), isA<List>());
  });

  test('Dockge Socket.IO login + stack list', () async {
    final client = DockgeClient(
      baseUrl: 'http://127.0.0.1:5001',
      username: credentials['CUPOLA_MACLAB_DOCKGE_USERNAME'],
      password: credentials['CUPOLA_MACLAB_DOCKGE_PASSWORD'],
    );
    addTearDown(client.close);
    final service = DockgeService(client);
    // Dockge installations may omit the optional version field while still
    // accepting the authenticated Socket.IO session.
    await service.fetchVersion();
    expect(await service.fetchStacks(), isA<List>());
  });

  test('Nginx Proxy Manager login + proxy host parser', () async {
    final client = NpmClient(
      url: 'http://127.0.0.1:8181',
      identity: credentials['CUPOLA_MACLAB_NPM_USERNAME'],
      secret: credentials['CUPOLA_MACLAB_NPM_PASSWORD'],
    );
    addTearDown(client.close);
    expect(await client.testConnection(), isTrue);
    expect(await client.version(), isNotEmpty);
    expect(await client.proxyHosts(), isA<List>());
    expect(await client.auditLog(), isA<List>());
  });

  test('TrueNAS WebSocket JSON-RPC + dashboard parser', () async {
    final client = TrueNasWsClient(
      baseUrl: 'ws://127.0.0.1:8460',
      apiKey: 'test-key',
    );
    addTearDown(client.close);
    final service = TrueNasService(client);
    expect(await service.ping(), isTrue);
    final dashboard = await service.loadDashboard();
    expect(dashboard.system.hostname, isNotEmpty);
    expect(dashboard.pools, isA<List>());
  });

  test('Unraid GraphQL + dashboard parsers', () async {
    final client = UnraidClient(
      url: 'http://127.0.0.1:8480',
      apiKey: 'test-key',
    );
    addTearDown(client.close);
    expect(await client.testConnection(), isTrue);
    expect((await client.getArray()).state, isNotEmpty);
    expect(await client.getDockerContainers(), isA<List>());
    expect(await client.getNotifications(), isNotNull);
  });

  test('wrong credentials are rejected by every auth transport', () async {
    final apiKeyCases = <Map<String, String>>[
      {
        'name': 'Seerr',
        'url': 'http://127.0.0.1:5055',
        'path': '/api/v1/auth/me',
      },
      {
        'name': 'Radarr',
        'url': 'http://127.0.0.1:7878',
        'path': '/api/v3/system/status',
      },
      {
        'name': 'Sonarr',
        'url': 'http://127.0.0.1:8989',
        'path': '/api/v3/system/status',
      },
      {
        'name': 'Lidarr',
        'url': 'http://127.0.0.1:8686',
        'path': '/api/v1/system/status',
      },
      {
        'name': 'Readarr',
        'url': 'http://127.0.0.1:8787',
        'path': '/api/v1/system/status',
      },
      {
        'name': 'Prowlarr',
        'url': 'http://127.0.0.1:9696',
        'path': '/api/v1/system/status',
      },
      {'name': 'Bazarr', 'url': 'http://127.0.0.1:6767', 'path': '/api/badges'},
    ];
    for (final item in apiKeyCases) {
      final client = ApiClient(baseUrl: item['url']!, apiKey: 'wrong-key');
      addTearDown(client.close);
      await expectLater(
        client.get(item['path']!),
        throwsA(anything),
        reason: item['name'],
      );
    }

    final qbit = QbittorrentClient(
      url: 'http://127.0.0.1:8080',
      username: credentials['CUPOLA_MACLAB_QBITTORRENT_USERNAME'],
      password: 'wrong-password',
    );
    addTearDown(qbit.close);
    expect(await qbit.authenticate(), isFalse, reason: 'qBittorrent');

    final transmission = TransmissionClient(
      url: 'http://127.0.0.1:9091',
      username: credentials['CUPOLA_MACLAB_TRANSMISSION_USERNAME'],
      password: 'wrong-password',
    );
    addTearDown(transmission.close);
    await expectLater(
      transmission.testConnection(),
      throwsA(anything),
      reason: 'Transmission',
    );

    final sabnzbd = SabnzbdClient(
      url: 'http://127.0.0.1:8082',
      apiKey: 'wrong-key',
    );
    addTearDown(sabnzbd.close);
    await expectLater(
      sabnzbd.testConnection(),
      throwsA(anything),
      reason: 'SABnzbd',
    );

    final nzbget = NzbgetClient(
      url: 'http://127.0.0.1:6789',
      username: credentials['CUPOLA_MACLAB_NZBGET_USERNAME'],
      password: 'wrong-password',
    );
    addTearDown(nzbget.close);
    await expectLater(
      nzbget.testConnection(),
      throwsA(anything),
      reason: 'NZBGet',
    );

    final jellyfin = JellyfinClient(
      baseUrl: 'http://127.0.0.1:8096',
      apiKey: 'wrong-token',
      userId: credentials['CUPOLA_MACLAB_JELLYFIN_USER_ID']!,
      deviceName: 'Cupola MacLab invalid-auth probe',
      deviceId: 'cupola-maclab-invalid-auth',
    );
    addTearDown(jellyfin.close);
    expect(await jellyfin.verifyCredential(), isFalse, reason: 'Jellyfin');

    final dockge = DockgeClient(
      baseUrl: 'http://127.0.0.1:5001',
      username: credentials['CUPOLA_MACLAB_DOCKGE_USERNAME'],
      password: 'wrong-password',
    );
    addTearDown(dockge.close);
    await expectLater(dockge.ping(), throwsA(anything), reason: 'Dockge');

    final npm = NpmClient(
      url: 'http://127.0.0.1:8181',
      identity: credentials['CUPOLA_MACLAB_NPM_USERNAME'],
      secret: 'wrong-password',
    );
    addTearDown(npm.close);
    await expectLater(
      npm.testConnection(),
      throwsA(anything),
      reason: 'Nginx Proxy Manager',
    );

    final truenas = TrueNasWsClient(
      baseUrl: 'ws://127.0.0.1:8460',
      apiKey: 'wrong-key',
    );
    addTearDown(truenas.close);
    await expectLater(
      TrueNasService(truenas).ping(),
      throwsA(anything),
      reason: 'TrueNAS',
    );

    final unraid = UnraidClient(
      url: 'http://127.0.0.1:8480',
      apiKey: 'wrong-key',
    );
    addTearDown(unraid.close);
    await expectLater(
      unraid.testConnection(),
      throwsA(anything),
      reason: 'Unraid',
    );
  });

  test('Plex wrong-token probe is explicit when auth is disabled', () async {
    final client = PlexClient(
      url: 'http://127.0.0.1:32400',
      token: 'wrong-token',
      clientIdentifier: 'cupola-maclab-invalid-auth',
    );
    addTearDown(client.close);
    final accepted = await client.verifyCredential();
    if (accepted) {
      markTestSkipped(
        'The disposable Plex container is running with local authentication '
        'disabled; a wrong token cannot be rejected. Use a claimed/authenticated '
        'Plex server to verify token rejection.',
      );
      return;
    }
    expect(accepted, isFalse, reason: 'Plex');
  });
}

ApiClient _arr(String baseUrl) =>
    ApiClient(baseUrl: baseUrl, apiKey: 'test-key');

Map<String, String> _loadCredentials() {
  final path = Platform.environment['CUPOLA_MACLAB_CREDENTIALS_FILE'];
  if (path == null || path.isEmpty) {
    fail(
      'CUPOLA_MACLAB_CREDENTIALS_FILE must point to the bootstrap output '
      '(.ai/scratch/zz_maclab/state/credentials.env)',
    );
  }
  final file = File(path);
  if (!file.existsSync()) fail('Missing maclab credentials file: $path');
  final values = <String, String>{};
  for (final line in file.readAsLinesSync()) {
    if (line.isEmpty || line.startsWith('#')) continue;
    final separator = line.indexOf('=');
    if (separator <= 0) continue;
    values[line.substring(0, separator)] = line.substring(separator + 1);
  }
  return values;
}
