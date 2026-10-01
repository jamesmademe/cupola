/// Something other than the service answers at its address, and the app says
/// so: on the Dashboard, on the service's library and in its connection test.
///
/// The case behind "Radarr and Sonarr answering, with empty libraries": a web
/// page (a proxy's default page, an address missing its base path) answered
/// every request with a 200, the probe called any 2xx answering, and every
/// list read turned the page into `[]`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/platform/local_network_access.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/failure_remedy.dart';
import 'package:cupola/core/widgets/service_offline_state.dart';
import 'package:cupola/core/widgets/status_badge.dart';
import 'package:cupola/features/movies/presentation/movies_screen.dart';
import 'package:cupola/features/music/presentation/music_screen.dart';
import 'package:cupola/features/series/presentation/series_screen.dart';
import 'package:cupola/features/services/domain/service_summary.dart';
import 'package:cupola/features/services/presentation/dashboard_screen.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/data/service_verification.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/presentation/service_settings_screen.dart';

import '../../../test_helpers/profiles/profiles.dart';

Future<ServiceSummary> _probe(
  ConfigProfile profile,
  ServiceKey service,
  String id,
) async {
  final harness = await ProfileHarness.start(profile);
  final container = harness.container(retry: (_, _) => null);
  return container.read(
    instanceSummaryProvider((service: service, instanceId: id)).future,
  );
}

/// What the connection test says about [id] on [profile].
Future<ServiceDiagnosis> _test(ConfigProfile profile, String id) async {
  await ProfileHarness.start(profile);
  return diagnoseInstance(profile.connection(id).instance, profile.settings);
}

Color _amber() {
  final scheme = AppTheme.darkTheme().colorScheme;
  return statusToneColor(scheme, StatusTone.warning);
}

void main() {
  group('a web page answering for an arr', () {
    test('is a fault on the probe, never answering', () async {
      final summary = await _probe(
        Profiles.p1.withBehaviour(
          WorldIds.radarr,
          ConnectionBehaviour.servesHtmlPage,
        ),
        ServiceKey.radarr,
        WorldIds.radarr,
      );

      expect(summary.isOnline, isFalse);
      expect(summary.status, ServiceSummaryStatus.fault);
    });

    final libraries = <(String, ServiceKey, String, Widget)>[
      (
        'Radarr',
        ServiceKey.radarr,
        WorldIds.radarr,
        const MoviesScreen(showAppBar: false),
      ),
      (
        'Sonarr',
        ServiceKey.sonarr,
        WorldIds.sonarr,
        const SeriesScreen(showAppBar: false),
      ),
      (
        'Lidarr',
        ServiceKey.lidarr,
        WorldIds.lidarr,
        const MusicScreen(showAppBar: false),
      ),
    ];

    for (final (name, service, id, screen) in libraries) {
      testWidgets('the $name library says what answered, not that it is '
          'empty', (tester) async {
        final harness = await pumpWithProfile(
          tester,
          Profiles.p1.withBehaviour(id, ConnectionBehaviour.servesHtmlPage),
          child: screen,
        );

        expect(find.byType(ServiceOfflineState), findsOneWidget);
        expect(find.text(describeUnreadable(service)), findsOneWidget);
        expect(find.text('No items found'), findsNothing);
        final glyph = tester.widget<Icon>(
          find
              .descendant(
                of: find.byType(ServiceOfflineState),
                matching: find.byType(Icon),
              )
              .first,
        );
        expect(glyph.color, _amber());
        expect(
          find.textContaining('A web page answered at nas.home.arpa:'),
          findsOneWidget,
        );

        await harness.unmount(tester);
      });
    }
  });

  group('the probe checks who answered', () {
    final otherOnRadarrsPort = Profiles.p1.withBehaviour(
      WorldIds.radarr,
      const ConnectionBehaviour.answersAsOtherService(ServiceKey.sonarr),
    );
    final pageForRadarr = Profiles.p1.withBehaviour(
      WorldIds.radarr,
      ConnectionBehaviour.servesHtmlPage,
    );

    test(
      'a Sonarr on Radarr\'s port is named, on Home and in Settings',
      () async {
        final summary = await _probe(
          otherOnRadarrsPort,
          ServiceKey.radarr,
          WorldIds.radarr,
        );
        final diagnosis = await _test(otherOnRadarrsPort, WorldIds.radarr);

        expect(summary.status, ServiceSummaryStatus.fault);
        expect(summary.failureReason, ServiceFailureReason.notFound);
        expect(
          summary.failure?.detail,
          'Sonarr answered at nas.home.arpa:7878, not Radarr.',
        );
        expect(diagnosis.reason, summary.failureReason);
        expect(
          diagnosis.messageFor(ServiceKey.radarr),
          summary.failure?.detail,
        );
      },
    );

    test(
      'a web page is something that is not Radarr, with the path hint',
      () async {
        final summary = await _probe(
          pageForRadarr,
          ServiceKey.radarr,
          WorldIds.radarr,
        );
        final diagnosis = await _test(pageForRadarr, WorldIds.radarr);

        expect(summary.failureReason, ServiceFailureReason.notFound);
        expect(
          summary.failure?.detail,
          "Something answered at nas.home.arpa:7878, but it isn't Radarr.\n"
          'If Radarr sits under a path, add it: http://nas.home.arpa:7878/radarr',
        );
        expect(diagnosis.reason, ServiceFailureReason.notFound);
        expect(
          diagnosis.messageFor(ServiceKey.radarr),
          summary.failure?.detail,
        );
      },
    );

    final special = <(String, ServiceKey, String, String)>[
      ('Seerr', ServiceKey.seerr, WorldIds.seerr, 'nas.home.arpa:5055'),
      (
        'qBittorrent',
        ServiceKey.qbittorrent,
        WorldIds.qbittorrent,
        'nas.home.arpa:8080',
      ),
      ('SABnzbd', ServiceKey.sabnzbd, WorldIds.sabnzbd, 'nas.home.arpa:8085'),
      (
        'Jellyfin',
        ServiceKey.jellyfin,
        WorldIds.jellyfin,
        'nas.home.arpa:8096',
      ),
    ];
    for (final (name, service, id, host) in special) {
      test(
        '$name: a web page reads the same on Home and in Settings',
        () async {
          final profile = Profiles.p1.withBehaviour(
            id,
            ConnectionBehaviour.servesHtmlPage,
          );
          final summary = await _probe(profile, service, id);
          final diagnosis = await _test(profile, id);

          expect(summary.failureReason, ServiceFailureReason.notFound);
          expect(
            summary.failure?.detail,
            startsWith("Something answered at $host, but it isn't $name."),
          );
          expect(diagnosis.reason, ServiceFailureReason.notFound);
          expect(diagnosis.messageFor(service), summary.failure?.detail);
        },
      );
    }

    test('a genuine service still answers', () async {
      for (final (service, id) in [
        (ServiceKey.radarr, WorldIds.radarr),
        (ServiceKey.sonarr, WorldIds.sonarr),
        (ServiceKey.lidarr, WorldIds.lidarr),
        (ServiceKey.prowlarr, WorldIds.prowlarr),
        (ServiceKey.bazarr, WorldIds.bazarr),
        (ServiceKey.seerr, WorldIds.seerr),
        (ServiceKey.qbittorrent, WorldIds.qbittorrent),
        (ServiceKey.sabnzbd, WorldIds.sabnzbd),
        (ServiceKey.jellyfin, WorldIds.jellyfin),
      ]) {
        final summary = await _probe(Profiles.p1, service, id);
        final diagnosis = await _test(Profiles.p1, id);

        expect(summary.isOnline, isTrue, reason: service.title);
        expect(diagnosis.isConnected, isTrue, reason: service.title);
      }
    });

    testWidgets('Home paints a Sonarr on Radarr\'s port amber, in the '
        'address\'s words', (tester) async {
      final harness = await pumpWithProfile(
        tester,
        Profiles.p3.withBehaviour(
          WorldIds.radarr,
          const ConnectionBehaviour.answersAsOtherService(ServiceKey.sonarr),
        ),
        child: const DashboardScreen(),
        surfaceSize: const Size(430, 2400),
      );

      final cell = find.byKey(const ValueKey('service-matrix-cell-radarr'));
      final label = find.descendant(
        of: cell,
        matching: find.text(failureLabel(ServiceFailureReason.notFound)),
      );
      expect(label, findsOneWidget);
      final scheme = AppTheme.darkTheme().colorScheme;
      expect(
        tester.widget<Text>(label).style?.color,
        statusToneColor(
          scheme,
          StatusTone.warning,
          surface: scheme.surfaceContainer,
        ),
      );
      expect(
        find.descendant(of: cell, matching: find.text('Answering')),
        findsNothing,
      );

      await harness.unmount(tester);
    });
  });

  group('a gateway in front of Radarr is named', () {
    final gateways = <(ConnectionBehaviour, AccessGatewayKind, String)>[
      (
        const ConnectionBehaviour.behindCloudflareAccess(),
        AccessGatewayKind.cloudflareAccess,
        'cupola-home.cloudflareaccess.com',
      ),
      (
        const ConnectionBehaviour.behindCloudflareAccess(
          mode: CloudflareAccessMode.unauthorized,
        ),
        AccessGatewayKind.cloudflareAccess,
        'nas.home.arpa',
      ),
      (
        const ConnectionBehaviour.behindSignInPage(),
        AccessGatewayKind.signInPage,
        'auth.example.net',
      ),
      (
        const ConnectionBehaviour.behindSignInPage(
          mode: SignInPageMode.sameHostForm,
        ),
        AccessGatewayKind.signInPage,
        'nas.home.arpa',
      ),
      (
        const ConnectionBehaviour.behindPasswordPrompt(),
        AccessGatewayKind.passwordPrompt,
        'nas.home.arpa',
      ),
    ];

    for (final (behaviour, kind, gatewayHost) in gateways) {
      test(
        '${behaviour.label}: the same words on Home and in Settings',
        () async {
          final profile = Profiles.p1.withBehaviour(WorldIds.radarr, behaviour);
          final summary = await _probe(
            profile,
            ServiceKey.radarr,
            WorldIds.radarr,
          );
          final diagnosis = await _test(profile, WorldIds.radarr);

          expect(summary.status, ServiceSummaryStatus.fault);
          expect(summary.failureReason, ServiceFailureReason.accessGateway);
          final gateway = summary.failure?.gateway;
          expect(gateway?.kind, kind);
          expect(gateway?.credentialsSent, isFalse);
          expect(gateway?.gatewayHost, gatewayHost);
          expect(gateway?.serviceHost, 'nas.home.arpa:7878');

          expect(diagnosis.reason, ServiceFailureReason.accessGateway);
          expect(diagnosis.gateway?.kind, kind);
          expect(
            diagnosis.messageFor(ServiceKey.radarr),
            connectionFailureMessage(
              ServiceKey.radarr,
              ServiceFailureReason.accessGateway,
              gateway: gateway,
            ),
          );
          // The service was never asked: the gateway answered for it.
          expect(
            FailureRemedy.forReason(
              ServiceKey.radarr,
              ServiceFailureReason.accessGateway,
              gateway: gateway,
            )?.retryHelps,
            isFalse,
          );
        },
      );
    }

    // The clients that wrap a failure in their own exception keep the
    // gateway as its cause, and none reads a gateway's 401 or 403 as its own
    // refusal (Plex's token, Transmission's whitelist, NPM's login,
    // qBittorrent's session, Jellyfin's narrower token).
    final clients = <(ServiceKey, ProfileConnection)>[
      (ServiceKey.qbittorrent, WorldConnections.qbittorrent),
      (ServiceKey.sabnzbd, WorldConnections.sabnzbd),
      (ServiceKey.jellyfin, WorldConnections.jellyfin),
      (ServiceKey.plex, WorldConnections.plex),
      (ServiceKey.transmission, WorldConnections.transmission),
      (ServiceKey.nzbget, WorldConnections.nzbget),
      (ServiceKey.unraid, WorldConnections.unraid),
      (ServiceKey.nginxProxyManager, WorldConnections.npm),
      (ServiceKey.seerr, WorldConnections.seerr),
      (ServiceKey.bazarr, WorldConnections.bazarr),
    ];
    for (final (service, connection) in clients) {
      test('${service.title} behind Cloudflare Access is named, on Home and '
          'in Settings', () async {
        final profile = Profiles.p1
            .withConnection(connection)
            .withBehaviour(
              connection.id,
              const ConnectionBehaviour.behindCloudflareAccess(
                mode: CloudflareAccessMode.unauthorized,
              ),
            );
        final summary = await _probe(profile, service, connection.id);
        final diagnosis = await _test(profile, connection.id);

        expect(summary.failureReason, ServiceFailureReason.accessGateway);
        expect(
          summary.failure?.gateway?.kind,
          AccessGatewayKind.cloudflareAccess,
        );
        expect(diagnosis.reason, ServiceFailureReason.accessGateway);
        expect(diagnosis.gateway?.kind, AccessGatewayKind.cloudflareAccess);
      });
    }

    test('qBittorrent behind a password prompt: the proxy\'s, not its own '
        'refused sign-in', () async {
      final profile = Profiles.p1.withBehaviour(
        WorldIds.qbittorrent,
        const ConnectionBehaviour.behindPasswordPrompt(),
      );
      final summary = await _probe(
        profile,
        ServiceKey.qbittorrent,
        WorldIds.qbittorrent,
      );

      expect(summary.failureReason, ServiceFailureReason.accessGateway);
      expect(summary.failure?.gateway?.kind, AccessGatewayKind.passwordPrompt);
    });

    test('NZBGet signs in with Basic itself, so a Basic 401 is its own '
        'refusal', () async {
      final profile = Profiles.p1
          .withConnection(WorldConnections.nzbget)
          .withBehaviour(
            WorldConnections.nzbget.id,
            const ConnectionBehaviour.behindPasswordPrompt(),
          );
      final summary = await _probe(
        profile,
        ServiceKey.nzbget,
        WorldConnections.nzbget.id,
      );

      expect(summary.failureReason, ServiceFailureReason.unauthorized);
      expect(summary.failure?.gateway, isNull);
    });

    testWidgets('Home paints Cloudflare Access amber, by name', (tester) async {
      final harness = await pumpWithProfile(
        tester,
        Profiles.p3.withBehaviour(
          WorldIds.radarr,
          const ConnectionBehaviour.behindCloudflareAccess(
            mode: CloudflareAccessMode.unauthorized,
          ),
        ),
        child: const DashboardScreen(),
        surfaceSize: const Size(430, 2400),
      );

      final cell = find.byKey(const ValueKey('service-matrix-cell-radarr'));
      final label = find.descendant(
        of: cell,
        matching: find.text('Behind Cloudflare Access'),
      );
      expect(label, findsOneWidget);
      final scheme = AppTheme.darkTheme().colorScheme;
      expect(
        tester.widget<Text>(label).style?.color,
        statusToneColor(
          scheme,
          StatusTone.warning,
          surface: scheme.surfaceContainer,
        ),
      );
      // Not the key: the service never saw it.
      expect(
        find.descendant(of: cell, matching: find.text('Refused the key')),
        findsNothing,
      );

      await harness.unmount(tester);
    });

    final libraries = <(ConnectionBehaviour, String, String, String)>[
      (
        const ConnectionBehaviour.behindCloudflareAccess(
          mode: CloudflareAccessMode.unauthorized,
        ),
        'Cloudflare Access answered instead of Radarr',
        'Radarr is behind Cloudflare Access. Cupola needs a service token to '
            'reach it.',
        'Add a service token',
      ),
      (
        const ConnectionBehaviour.behindSignInPage(),
        'A sign-in page answered instead of Radarr',
        'Something in front of Radarr asks for a sign-in that Cupola cannot '
            'complete.',
        'Add access',
      ),
      (
        const ConnectionBehaviour.behindPasswordPrompt(),
        'A password prompt answered instead of Radarr',
        'Something in front of Radarr asks for a username and password.',
        'Add the password',
      ),
    ];
    for (final (behaviour, headline, sentence, remedy) in libraries) {
      testWidgets('the Radarr library, ${behaviour.label}: the cause, and '
          'its remedy in the amber fill', (tester) async {
        final harness = await pumpWithProfile(
          tester,
          Profiles.p1.withBehaviour(WorldIds.radarr, behaviour),
          child: const MoviesScreen(showAppBar: false),
        );

        final leaf = find.byType(ServiceOfflineState);
        expect(leaf, findsOneWidget);
        expect(find.text(headline), findsOneWidget);
        expect(find.textContaining(sentence), findsOneWidget);
        expect(find.text('No items found'), findsNothing);
        final button = find.widgetWithText(FilledButton, remedy);
        expect(button, findsOneWidget);
        final style = tester.widget<FilledButton>(button).style;
        final room = CupolaRoom.of(tester.element(leaf));
        expect(style?.backgroundColor?.resolve(const {}), room.toneAmberFill);
        // Asking the gateway the same thing again cannot help.
        expect(find.text('Retry'), findsNothing);
        final glyph = tester.widget<Icon>(
          find.descendant(of: leaf, matching: find.byType(Icon)).first,
        );
        expect(glyph.color, _amber());

        await harness.unmount(tester);
      });
    }

    testWidgets('the connection test says what Home says', (tester) async {
      // P3: one Radarr, so the form asks for no name before it tests.
      final profile = Profiles.p3.withBehaviour(
        WorldIds.radarr,
        const ConnectionBehaviour.behindCloudflareAccess(),
      );
      final harness = await pumpWithProfile(
        tester,
        profile,
        child: ServiceSettingsScreen(
          service: ServiceKey.radarr,
          instanceId: WorldIds.radarr,
          certificateProber: (_, {pinnedFingerprint = ''}) async => null,
          localNetworkProbe: (_, {timeout = Duration.zero}) async =>
              LocalNetworkAccess.unrestricted,
        ),
        surfaceSize: const Size(430, 2400),
      );

      await tester.tap(find.text('Test connection'));
      await harness.settle(tester);

      expect(
        find.semantics.byLabel(
          RegExp(
            r'^Connection test failed\. Radarr is behind Cloudflare Access\. '
            r'Cupola needs a service token to reach it\.',
          ),
        ),
        findsOneWidget,
      );
      expect(find.text('Behind Cloudflare Access'), findsWidgets);

      await harness.unmount(tester);
    });
  });
}

/// The headline the classification gives an answer nobody can read.
String describeUnreadable(ServiceKey service) => failureHeadline(
  ServiceFailureReason.invalidResponse,
  subject: service.title,
);
