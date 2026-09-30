/// Each behaviour, through the app's own clients, produces the failure the
/// app's own classifiers expect of a live server — the contract the next
/// packages' fixes are tested against.
///
/// Every client here comes out of a production provider; nothing is
/// overridden but the startup settings. If one of these starts failing, the
/// fake network drifted from the wire, not the app from the fake.
library;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/capability/capability_scope.dart';
import 'package:cupola/core/capability/connection_capability.dart';
import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/features/discover/data/seerr_service.dart';
import 'package:cupola/features/dockge/data/dockge_client.dart';
import 'package:cupola/features/dockge/presentation/dockge_provider.dart';
import 'package:cupola/features/jellyfin/presentation/jellyfin_provider.dart';
import 'package:cupola/features/movies/data/radarr_service.dart';
import 'package:cupola/features/qbittorrent/data/qbittorrent_client.dart';
import 'package:cupola/features/qbittorrent/presentation/qbittorrent_provider.dart';
import 'package:cupola/features/sabnzbd/data/sabnzbd_client.dart';
import 'package:cupola/features/sabnzbd/presentation/sabnzbd_provider.dart';
import 'package:cupola/features/series/data/sonarr_service.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/stream/domain/models/stream_item.dart';
import 'package:cupola/features/truenas/data/truenas_ws_client.dart';
import 'package:cupola/features/truenas/presentation/truenas_provider.dart';

import '../../test_helpers/profiles/profiles.dart';

/// What [call] threw, classified the way the app classifies it.
Future<ServiceFailureReason> _failureOf(Future<Object?> Function() call) async {
  try {
    await call();
  } catch (error) {
    return classifyConnectionFailure(error);
  }
  fail('expected the call to fail');
}

void main() {
  group('answers', () {
    test(
      'each Radarr answers with its own library, through its own client',
      () async {
        final harness = await ProfileHarness.start(Profiles.p1);
        final container = harness.container();

        final hd = await container.read(radarrServiceProvider).getMovies();
        final uhd = await container
            .read(radarrServiceForProvider(WorldIds.radarr4k))
            .getMovies();

        expect(
          hd.map((m) => m.title),
          contains(WorldTitles.spriteFright.title),
        );
        expect(uhd.map((m) => m.title), contains(WorldTitles.spring.title));
        expect(
          uhd.map((m) => m.title),
          isNot(contains(WorldTitles.spriteFright.title)),
        );
        // Each request reached the server it was meant for, and is on record.
        expect(
          harness.network.requestsTo(WorldIds.radarr).single.path,
          '/api/v3/movie',
        );
        expect(
          harness.network.requestsTo(WorldIds.radarr4k).single.path,
          '/api/v3/movie',
        );
        expect(harness.network.unanswered, isEmpty);
      },
    );

    test('an arr queue row and its client row share the download id', () async {
      final harness = await ProfileHarness.start(Profiles.p1);
      final container = harness.container();

      final queue = await container.read(radarrServiceProvider).getQueue();
      final torrents = await container
          .read(qbittorrentServiceProvider)
          .getTorrents();
      final spriteFright = queue.cast<Map<String, dynamic>>().firstWhere(
        (row) => row['title'] == WorldDownloads.spriteFright.release,
      );

      expect(
        torrents.map((t) => t.hash.toUpperCase()),
        contains(spriteFright['downloadId']),
      );
    });

    test('every P1 connection reads online on the Dashboard probe', () async {
      final harness = await ProfileHarness.start(Profiles.p1);
      final container = harness.container(retry: (_, _) => null);

      for (final c in Profiles.p1.connections) {
        final summary = await container.read(
          instanceSummaryProvider((
            service: c.service,
            instanceId: c.id,
          )).future,
        );
        expect(summary.isOnline, isTrue, reason: c.id);
      }
      // TrueNAS and Dockge answered over their real WebSocket upgrade.
      expect(harness.network.rpcCalls.map((call) => call.$1).toSet(), {
        WorldIds.truenas,
        WorldIds.dockge,
      });
    });
  });

  group('didNotAnswer', () {
    test(
      'fails the way a dead host does, and the attempt is on record',
      () async {
        final profile = Profiles.p1.withBehaviour(
          WorldIds.radarr4k,
          ConnectionBehaviour.didNotAnswer,
        );
        final harness = await ProfileHarness.start(profile);
        final container = harness.container();

        final service = container.read(
          radarrServiceForProvider(WorldIds.radarr4k),
        );
        try {
          await service.getMoviesOrThrow();
          fail('expected a refused connection');
        } on DioException catch (error) {
          expect(error.type, DioExceptionType.connectionError);
          expect(
            classifyConnectionFailure(error),
            ServiceFailureReason.unreachable,
          );
        }
        expect(
          harness.network.requestsTo(WorldIds.radarr4k).single.dialRefused,
          isTrue,
        );
        // The other Radarr is untouched.
        expect(
          await container.read(radarrServiceProvider).getMovies(),
          isNotEmpty,
        );
      },
    );

    test(
      'a TrueNAS that does not answer fails its WebSocket dial as unreachable',
      () async {
        final harness = await ProfileHarness.start(Profiles.p7);
        final container = harness.container();

        expect(
          await _failureOf(
            () => container.read(truenasServiceProvider).getSystemInfo(),
          ),
          ServiceFailureReason.unreachable,
        );
      },
    );

    test(
      'a host nothing owns fails like a DNS miss, never the real network',
      () async {
        final harness = await ProfileHarness.start(Profiles.p1);

        expect(
          await _failureOf(() => Dio().get<Object?>('https://example.com/')),
          ServiceFailureReason.unreachable,
        );
        final attempt = harness.network.requests.single;
        expect(attempt.server, isNull);
        expect(attempt.dialRefused, isTrue);
      },
    );
  });

  group('timesOut', () {
    test('fails as a connect timeout, at once: it did not answer', () async {
      final harness = await ProfileHarness.start(
        Profiles.p3.withBehaviour(
          WorldIds.sonarr,
          ConnectionBehaviour.timesOut,
        ),
      );
      final container = harness.container();

      try {
        await container.read(sonarrServiceProvider).getSeriesOrThrow();
        fail('expected a timeout');
      } on DioException catch (error) {
        expect(error.type, DioExceptionType.connectionTimeout);
        // The connection never completed, so nothing replied at the address:
        // red, not the amber of a server reached and then slow.
        expect(
          classifyConnectionFailure(error),
          ServiceFailureReason.unreachable,
        );
      }
    });
  });

  group('refusesKey', () {
    test('an arr refuses with 401: unauthorized, not unreachable', () async {
      final harness = await ProfileHarness.start(
        Profiles.p1.withBehaviour(
          WorldIds.radarr,
          ConnectionBehaviour.refusesKey,
        ),
      );
      final container = harness.container();

      try {
        await container.read(radarrServiceProvider).getMoviesOrThrow();
        fail('expected a refusal');
      } on DioException catch (error) {
        expect(error.response?.statusCode, 401);
        expect(
          classifyConnectionFailure(error),
          ServiceFailureReason.unauthorized,
        );
      }
    });

    test(
      'qBittorrent fails as a refused sign-in, not as unreachable',
      () async {
        final harness = await ProfileHarness.start(Profiles.p7);
        final container = harness.container();

        try {
          await container.read(qbittorrentServiceProvider).getVersion();
          fail('expected a refused sign-in');
        } on QbittorrentException catch (error) {
          expect(error.reason, ServiceFailureReason.unauthorized);
          expect(error.message, contains('rejected the username or password'));
        }
        final login = harness.network.requestsTo(WorldIds.qbittorrent).first;
        expect(login.path, '/api/v2/auth/login');
        expect(login.form['username'], 'admin');
      },
    );

    test(
      'SABnzbd refuses in its 200 body, and its keyless version still answers',
      () async {
        final harness = await ProfileHarness.start(
          Profiles.p1.withBehaviour(
            WorldIds.sabnzbd,
            ConnectionBehaviour.refusesKey,
          ),
        );
        final container = harness.container();
        final client = container.read(sabnzbdClientProvider);

        expect(await client.getVersion(), isNotEmpty);
        try {
          await client.getQueue();
          fail('expected a refusal');
        } on SabnzbdException catch (error) {
          expect(error.reason, ServiceFailureReason.unauthorized);
        }
      },
    );

    test('Jellyfin answers its public probe and refuses the rest', () async {
      final harness = await ProfileHarness.start(
        Profiles.p1.withBehaviour(
          WorldIds.jellyfin,
          ConnectionBehaviour.refusesKey,
        ),
      );
      final client = harness.container().read(jellyfinClientProvider);

      expect(await client.probeVersion(), isNotNull);
      expect(
        await _failureOf(client.getSessionsOrThrow),
        ServiceFailureReason.unauthorized,
      );
    });

    test('Seerr refuses with 403 behind a public status route', () async {
      final harness = await ProfileHarness.start(
        Profiles.p2.withBehaviour(
          WorldIds.seerr,
          ConnectionBehaviour.refusesKey,
        ),
      );
      final seerr = harness.container().read(seerrServiceProvider);

      expect(
        await _failureOf(seerr.testConnection),
        ServiceFailureReason.unauthorized,
      );
    });

    test('TrueNAS refuses the key login', () async {
      final harness = await ProfileHarness.start(
        Profiles.p1.withBehaviour(
          WorldIds.truenas,
          ConnectionBehaviour.refusesKey,
        ),
      );
      final container = harness.container();

      try {
        await container.read(truenasServiceProvider).getSystemInfo();
        fail('expected a refused key');
      } on TrueNasException catch (error) {
        expect(error.reason, ServiceFailureReason.unauthorized);
      }
    });

    test('Dockge refuses the login', () async {
      final harness = await ProfileHarness.start(
        Profiles.p1.withBehaviour(
          WorldIds.dockge,
          ConnectionBehaviour.refusesKey,
        ),
      );
      final client = harness.container().read(dockgeClientProvider);

      try {
        await client.ensureConnected();
        fail('expected a refused login');
      } on DockgeException catch (error) {
        expect(error.reason, ServiceFailureReason.unauthorized);
      }
    });
  });

  group('readOnly', () {
    test(
      "TrueNAS's own capability probe reads read-only, and writes are refused",
      () async {
        final harness = await ProfileHarness.start(
          Profiles.p7.at(NetworkPlace.home),
        );
        final container = harness.container();

        final grant = await container.read(
          connectionCapabilityProvider(WorldIds.truenas).future,
        );
        expect(grant.scope, CapabilityScope.readOnly);
        expect(
          harness.network.rpcCalls,
          contains((WorldIds.truenas, 'auth.me')),
        );

        try {
          await container.read(truenasServiceProvider).stopService('ssh');
          fail('expected a refused write');
        } on TrueNasException catch (error) {
          expect(error.isPermissionRefusal, isTrue);
        }
        // Reads still answer.
        expect(
          await container.read(truenasServiceProvider).getPools(),
          hasLength(2),
        );
      },
    );

    test("NPM's capability probe reads view-only", () async {
      final harness = await ProfileHarness.start(
        Profiles.p1.withConnection(
          WorldConnections.npm.withBehaviour(ConnectionBehaviour.readOnly),
        ),
      );
      final grant = await harness.container().read(
        connectionCapabilityProvider('npm').future,
      );
      expect(grant.scope, CapabilityScope.readOnly);
    });

    test("Unraid's capability probe reads read-only", () async {
      final harness = await ProfileHarness.start(
        Profiles.p1.withConnection(
          WorldConnections.unraid.withBehaviour(ConnectionBehaviour.readOnly),
        ),
      );
      final grant = await harness.container().read(
        connectionCapabilityProvider('unraid').future,
      );
      expect(grant.scope, CapabilityScope.readOnly);
    });

    test(
      'an arr with one admin key refuses the write with 403 and still reads',
      () async {
        final harness = await ProfileHarness.start(
          Profiles.p1.withBehaviour(
            WorldIds.radarr,
            ConnectionBehaviour.readOnly,
          ),
        );
        final radarr = harness.container().read(radarrServiceProvider);

        expect(await radarr.getMovies(), isNotEmpty);
        expect(
          await _failureOf(() => radarr.searchMovie(1)),
          ServiceFailureReason.unauthorized,
        );
      },
    );
  });

  group('homeOnly', () {
    test('does not answer away, and answers at home', () async {
      final away = await ProfileHarness.start(Profiles.p7);
      expect(
        await _failureOf(
          () => away.container().read(sabnzbdClientProvider).getQueue(),
        ),
        ServiceFailureReason.unreachable,
      );

      final home = await ProfileHarness.start(
        Profiles.p7.at(NetworkPlace.home),
      );
      expect(
        (await home.container().read(sabnzbdClientProvider).getQueue()).slots,
        isNotEmpty,
      );
    });
  });

  group('knownThroughAnother (P5)', () {
    test(
      "Seerr's settings name a Radarr and a Sonarr Cupola has no connection to",
      () async {
        final harness = await ProfileHarness.start(Profiles.p5);
        final container = harness.container();

        final servers = await container
            .read(seerrServiceProvider)
            .getRadarrServers();
        expect(servers.map((s) => s['name']), ['Radarr']);
        expect(
          Profiles.p5.settings.isServiceConfigured(ServiceKey.radarr),
          isFalse,
        );

        // Seerr's admin view carries the address and key a setup-from-Seerr
        // flow would read. The app does not call it yet, so ask it directly.
        final admin = await Dio().get<List<dynamic>>(
          '${WorldHosts.seerr}/api/v1/settings/radarr',
        );
        final radarr = admin.data!.single as Map<String, dynamic>;
        expect(radarr['hostname'], 'nas.home.arpa');
        expect(radarr['port'], 7878);
        expect(radarr['apiKey'], worldKey(WorldIds.radarr));
        expect(radarr['isDefault'], isTrue);

        // The server Seerr names answers at its address, unconfigured in Cupola:
        // what a setup-from-Seerr flow will find when it dials it.
        final known = harness.network.servers.where(
          (s) => !s.configuredInCupola,
        );
        expect(known.map((s) => s.service).toSet(), {
          ServiceKey.radarr,
          ServiceKey.sonarr,
        });
        expect(known.map((s) => s.origin), contains('nas.home.arpa:7878'));
      },
    );
  });

  group('matchNotVerified (P1)', () {
    test(
      'Jellyfin holds Elephants Dream under another TMDB id, so no match',
      () async {
        final harness = await ProfileHarness.start(Profiles.p1);
        final jellyfin = harness.container().read(jellyfinClientProvider);

        final unverified = await jellyfin.findByExternalId(
          tmdbId: '${WorldTitles.elephantsDream.tmdbId}',
          kind: StreamItemKind.movie,
        );
        final verified = await jellyfin.findByExternalId(
          tmdbId: '${WorldTitles.sintel.tmdbId}',
          kind: StreamItemKind.movie,
        );

        expect(unverified, isNull);
        expect(verified?.title, WorldTitles.sintel.title);
        // The server did answer with the item: the app's own check refused it.
        expect(
          harness.network
              .requestsTo(WorldIds.jellyfin)
              .where((r) => r.path == '/Items'),
          hasLength(2),
        );
      },
    );
  });

  group('routes a test adds', () {
    test('answer ahead of the world, on the server they name only', () async {
      final harness = await ProfileHarness.start(Profiles.p1);
      harness.network.on(
        WorldIds.radarr4k,
        'GET',
        '/api/v3/movie',
        (_) => NetworkReply.json(const <Object?>[]),
      );
      final container = harness.container();

      expect(
        await container
            .read(radarrServiceForProvider(WorldIds.radarr4k))
            .getMovies(),
        isEmpty,
      );
      expect(
        await container.read(radarrServiceProvider).getMovies(),
        isNotEmpty,
      );
    });

    test('a TrueNAS method can be scripted to fail as TrueNAS does', () async {
      final harness = await ProfileHarness.start(Profiles.p1);
      harness.network.onRpc(
        WorldIds.truenas,
        'pool.query',
        (_) => throw TrueNasRpcFault.eacces(),
      );

      try {
        await harness.container().read(truenasServiceProvider).getPools();
        fail('expected a refusal');
      } on TrueNasException catch (error) {
        expect(error.isPermissionRefusal, isTrue);
      }
    });
  });

  group('latency', () {
    testWidgets('a source slower than the probe deadline reads offline', (
      tester,
    ) async {
      final harness = await ProfileHarness.start(
        Profiles.p3.withLatency(WorldIds.seerr, const Duration(seconds: 30)),
      );
      final container = harness.container(retry: (_, _) => null);
      final probe = container.read(
        instanceSummaryProvider((
          service: ServiceKey.seerr,
          instanceId: WorldIds.seerr,
        )).future,
      );

      await tester.pump(const Duration(seconds: 31));
      expect((await probe).isOnline, isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });
}
