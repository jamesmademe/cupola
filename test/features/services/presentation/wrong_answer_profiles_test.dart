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
import 'package:cupola/core/theme.dart';
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
}

/// The headline the classification gives an answer nobody can read.
String describeUnreadable(ServiceKey service) => failureHeadline(
  ServiceFailureReason.invalidResponse,
  subject: service.title,
);
