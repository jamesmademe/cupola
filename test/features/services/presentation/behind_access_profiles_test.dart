/// A connection's access reaches every request it makes: under P8 (Radarr,
/// Sonarr and Seerr behind Cloudflare Access), Radarr's token lets Home, the
/// library and the artwork through, Sonarr's missing token is named, and
/// Seerr's token without a policy reads as a token refused. Every other
/// client, the two WebSocket ones included, carries a token the same way.
library;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/utils/image_utils.dart';
import 'package:cupola/core/widgets/service_offline_state.dart';
import 'package:cupola/features/jellyfin/data/jellyfin_client.dart';
import 'package:cupola/features/movies/presentation/movies_provider.dart';
import 'package:cupola/features/movies/presentation/movies_screen.dart';
import 'package:cupola/features/series/presentation/series_screen.dart';
import 'package:cupola/features/services/domain/service_summary.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/services/presentation/stack_screen.dart';
import 'package:cupola/features/settings/domain/connection_address.dart';
import 'package:cupola/features/settings/data/service_verification.dart';
import 'package:cupola/features/settings/domain/connection_access.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import '../../../test_helpers/profiles/profiles.dart';

Future<ServiceSummary> _probe(ConfigProfile profile, String id) async {
  final harness = await ProfileHarness.start(profile);
  final container = harness.container(retry: (_, _) => null);
  return container.read(
    instanceSummaryProvider((
      service: profile.connection(id).service,
      instanceId: id,
    )).future,
  );
}

Future<ServiceDiagnosis> _test(ConfigProfile profile, String id) async {
  await ProfileHarness.start(profile);
  return diagnoseInstance(
    profile.connection(id).instance,
    profile.settings,
    route: ConnectionRoute.home,
  );
}

const _token = (id: 'world-any.access', secret: 'world-any-cf-secret');

void main() {
  group('P8 on Home', () {
    test('Radarr, with a token Access lets through, answers', () async {
      final summary = await _probe(Profiles.p8, WorldIds.radarr);

      expect(summary.isOnline, isTrue);
    });

    test('Sonarr, with no token, names Cloudflare Access', () async {
      final summary = await _probe(Profiles.p8, WorldIds.sonarr);

      expect(summary.failureReason, ServiceFailureReason.accessGateway);
      final gateway = summary.failure?.gateway;
      expect(gateway?.kind, AccessGatewayKind.cloudflareAccess);
      expect(gateway?.credentialsSent, isFalse);
      expect(gateway?.gatewayHost, 'cupola-home.cloudflareaccess.com');
    });

    test(
      'Seerr, with a token no policy admits, reads as a token refused',
      () async {
        final summary = await _probe(Profiles.p8, WorldIds.seerr);

        expect(summary.failureReason, ServiceFailureReason.accessGateway);
        expect(summary.failure?.gateway?.credentialsSent, isTrue);
      },
    );

    testWidgets('the Stack says each one\'s state', (tester) async {
      final harness = await pumpWithProfile(
        tester,
        Profiles.p8,
        child: const StackScreen(),
        surfaceSize: const Size(430, 2400),
      );

      Finder inCell(String id, String text) => find.descendant(
        of: find.byKey(ValueKey('service-matrix-cell-$id')),
        matching: find.text(text),
      );
      expect(inCell('sonarr', 'Behind Cloudflare Access'), findsOneWidget);
      expect(inCell('seerr', 'Service token not accepted'), findsOneWidget);
      expect(inCell('radarr', 'Behind Cloudflare Access'), findsNothing);
      expect(inCell('radarr', 'Service token not accepted'), findsNothing);

      await harness.unmount(tester);
    });
  });

  group('P8 in the libraries', () {
    testWidgets('Radarr\'s library reads through the token', (tester) async {
      final harness = await pumpWithProfile(
        tester,
        Profiles.p8,
        child: const MoviesScreen(showAppBar: false),
      );

      expect(find.byType(ServiceOfflineState), findsNothing);
      final movies = await tester.runAsync(
        () => ProviderScope.containerOf(
          tester.element(find.byType(MoviesScreen)),
        ).read(moviesProvider.future),
      );
      expect(
        movies?.map((m) => m.title),
        contains(WorldTitles.spriteFright.title),
      );
      // Every request to Radarr carried the token.
      for (final request in harness.network.requestsTo(WorldIds.radarr)) {
        expect(
          request.headers['cf-access-client-id'],
          WorldTokens.radarr.id,
          reason: '$request',
        );
      }

      await harness.unmount(tester);
    });

    testWidgets('Sonarr\'s library names the gateway and asks for a token', (
      tester,
    ) async {
      final harness = await pumpWithProfile(
        tester,
        Profiles.p8,
        child: const SeriesScreen(showAppBar: false),
      );

      expect(
        find.text('Cloudflare Access answered instead of Sonarr'),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(FilledButton, 'Add a service token'),
        findsOneWidget,
      );

      await harness.unmount(tester);
    });
  });

  group('P8 artwork', () {
    test('a Radarr poster carries the token and crosses Access; Sonarr\'s, '
        'with none, does not', () async {
      final harness = await ProfileHarness.start(Profiles.p8);
      const poster = '/MediaCover/1/poster.jpg';
      for (final id in [WorldIds.radarr, WorldIds.sonarr]) {
        harness.network.on(
          id,
          'GET',
          poster,
          (_) =>
              const NetworkReply(200, body: 'jpeg', contentType: 'image/jpeg'),
        );
      }

      Future<int?> fetch(String id) async {
        final source = ImageUtils.extractPosterUrl(
          [
            {'coverType': 'poster', 'url': poster},
          ],
          baseUrl: Profiles.p8.connection(id).instance.url,
          apiKey: worldKey(id),
        );
        // How `CachedNetworkImage` asks: the URL and headers, nothing more.
        final dio = Dio(
          BaseOptions(followRedirects: false, validateStatus: (_) => true),
        );
        addTearDown(dio.close);
        final response = await dio.get<String>(
          source.url,
          options: Options(
            headers: source.headers,
            responseType: ResponseType.plain,
          ),
        );
        return response.statusCode;
      }

      expect(await fetch(WorldIds.radarr), 200);
      expect(await fetch(WorldIds.sonarr), 302);
    });
  });

  group('every client carries its connection\'s token', () {
    final connections = <ProfileConnection>[
      WorldConnections.radarr,
      WorldConnections.lidarr,
      WorldConnections.prowlarr,
      WorldConnections.bazarr,
      WorldConnections.seerr,
      WorldConnections.qbittorrent,
      WorldConnections.sabnzbd,
      WorldConnections.jellyfin,
      WorldConnections.plex,
      WorldConnections.transmission,
      WorldConnections.nzbget,
      WorldConnections.unraid,
      WorldConnections.npm,
      WorldConnections.truenas,
      WorldConnections.dockge,
    ];

    for (final connection in connections) {
      final service = connection.service;
      final behind = Profiles.p1
          .withConnection(connection)
          .withBehaviour(
            connection.id,
            const ConnectionBehaviour.behindCloudflareAccess(
              serviceToken: _token,
            ),
          );
      final withToken = behind.withConnection(
        behind.connection(connection.id).withAccess(_token.access),
      );

      test(
        '${service.title}: with the token, Home and the test pass',
        () async {
          final summary = await _probe(withToken, connection.id);
          final diagnosis = await _test(withToken, connection.id);

          expect(summary.isOnline, isTrue, reason: '${summary.failureReason}');
          expect(diagnosis.isConnected, isTrue, reason: '${diagnosis.reason}');
        },
      );

      test('${service.title}: without it, the gateway is named', () async {
        final summary = await _probe(behind, connection.id);
        final diagnosis = await _test(behind, connection.id);

        expect(summary.failureReason, ServiceFailureReason.accessGateway);
        expect(
          summary.failure?.gateway?.kind,
          AccessGatewayKind.cloudflareAccess,
        );
        expect(diagnosis.reason, ServiceFailureReason.accessGateway);
      });
    }
  });

  group('a proxy password in front of Jellyfin', () {
    const password = ProxyPassword(username: 'matt', password: 'proxy-pw');
    final behind = Profiles.p1.withBehaviour(
      WorldIds.jellyfin,
      const ConnectionBehaviour.behindPasswordPrompt(
        credentials: (username: 'matt', password: 'proxy-pw'),
      ),
    );
    final configured = behind.withConnection(
      behind.connection(WorldIds.jellyfin).withAccess(password),
    );

    test('takes Authorization, and Jellyfin\'s token moves to X-Emby-Token and '
        'the ApiKey parameter, which recent servers read instead', () async {
      final harness = await ProfileHarness.start(configured);
      final summary = await harness
          .container(retry: (_, _) => null)
          .read(
            instanceSummaryProvider((
              service: ServiceKey.jellyfin,
              instanceId: WorldIds.jellyfin,
            )).future,
          );

      expect(summary.isOnline, isTrue, reason: '${summary.failureReason}');
      final requests = harness.network.requestsTo(WorldIds.jellyfin);
      expect(requests, isNotEmpty);
      for (final request in requests) {
        expect(
          request.headers['authorization'],
          password.headers()['Authorization'],
          reason: '$request',
        );
        expect(
          request.headers['x-emby-token'],
          worldKey(WorldIds.jellyfin),
          reason: '$request',
        );
        expect(
          request.uri.queryParameters['ApiKey'],
          worldKey(WorldIds.jellyfin),
          reason: '$request',
        );
      }
    });

    test('and its artwork goes the same way', () {
      final client = JellyfinClient(
        baseUrl: WorldHosts.jellyfin,
        apiKey: 'token',
        accessHeaders: password.headers(),
      );
      addTearDown(client.close);

      final image = client.imageFor('/Items/1/Images/Primary');
      expect(image?.headers, {...password.headers(), 'X-Emby-Token': 'token'});
      // Never in the URL: it would name a file in the image cache.
      expect(image?.url, isNot(contains('token')));
    });

    test('without a proxy, Jellyfin keeps Authorization', () {
      final client = JellyfinClient(
        baseUrl: WorldHosts.jellyfin,
        apiKey: 'token',
      );
      addTearDown(client.close);

      final headers = client.imageFor('/Items/1/Images/Primary')?.headers;
      expect(headers?['Authorization'], startsWith('MediaBrowser '));
      expect(headers?.containsKey('X-Emby-Token'), isFalse);
    });
  });
}
