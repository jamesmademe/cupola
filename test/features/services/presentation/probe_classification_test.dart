/// The Stack's probe, driven through the app's real clients on the
/// profiles' fake network: a failure is classified before it is painted.
///
/// The probe used to catch every error and report `offline`, so a refused key
/// read red "did not answer"; and four probes could not see a refused key at
/// all: SABnzbd's `mode=version`, and the anonymous status routes of
/// Jellyfin, Plex and Nginx Proxy Manager, so a wrong key read as answering.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/status_badge.dart';
import 'package:cupola/features/services/domain/service_summary.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/services/presentation/stack_screen.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/shell/domain/stack_health.dart';

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

void main() {
  group('a refused credential is a fault, never "did not answer"', () {
    final cases = <(String, ConfigProfile, ServiceKey, String)>[
      ('Radarr', Profiles.p1, ServiceKey.radarr, WorldIds.radarr),
      ('Seerr', Profiles.p1, ServiceKey.seerr, WorldIds.seerr),
      (
        'qBittorrent',
        Profiles.p1,
        ServiceKey.qbittorrent,
        WorldIds.qbittorrent,
      ),
      ('TrueNAS', Profiles.p1, ServiceKey.truenas, WorldIds.truenas),
      // The four probes that could not see a refused key at all.
      ('SABnzbd', Profiles.p1, ServiceKey.sabnzbd, WorldIds.sabnzbd),
      ('Jellyfin', Profiles.p1, ServiceKey.jellyfin, WorldIds.jellyfin),
      ('Plex', Profiles.p6, ServiceKey.plex, WorldIds.plex),
      (
        'Nginx Proxy Manager',
        Profiles.p1.withConnection(WorldConnections.npm),
        ServiceKey.nginxProxyManager,
        WorldConnections.npm.id,
      ),
    ];

    for (final (name, profile, service, id) in cases) {
      test(name, () async {
        final summary = await _probe(
          profile.withBehaviour(id, ConnectionBehaviour.refusesKey),
          service,
          id,
        );

        expect(summary.status, ServiceSummaryStatus.fault);
        expect(summary.isOnline, isFalse);
        expect(summary.didNotAnswer, isFalse);
        expect(summary.failureReason, ServiceFailureReason.unauthorized);
      });
    }
  });

  group('nothing answering is the one red state', () {
    for (final behaviour in const [
      ConnectionBehaviour.didNotAnswer,
      ConnectionBehaviour.timesOut,
    ]) {
      test('Radarr, ${behaviour.name}', () async {
        final summary = await _probe(
          Profiles.p1.withBehaviour(WorldIds.radarr, behaviour),
          ServiceKey.radarr,
          WorldIds.radarr,
        );

        expect(summary.status, ServiceSummaryStatus.offline);
        expect(summary.failureReason, ServiceFailureReason.unreachable);
      });
    }
  });

  group('the keyed probes still answer a good key', () {
    test('Jellyfin names its version, which it spells "Version"', () async {
      final summary = await _probe(
        Profiles.p1,
        ServiceKey.jellyfin,
        WorldIds.jellyfin,
      );

      expect(summary.isOnline, isTrue);
      expect(summary.version, '10.11.11');
    });

    test(
      'a non-administrator Jellyfin token answers: narrower, not refused',
      () async {
        // `/System/Info` is 403 for a valid user token without the admin's
        // reads. That is the credential-scope case, not a fault.
        final summary = await _probe(
          Profiles.p2WithJellyfin,
          ServiceKey.jellyfin,
          WorldIds.jellyfin,
        );

        expect(summary.isOnline, isTrue);
        expect(summary.version, '10.11.11');
      },
    );

    test(
      'SABnzbd, Plex and Nginx Proxy Manager answer with a good key',
      () async {
        expect(
          (await _probe(
            Profiles.p1,
            ServiceKey.sabnzbd,
            WorldIds.sabnzbd,
          )).isOnline,
          isTrue,
        );
        expect(
          (await _probe(Profiles.p6, ServiceKey.plex, WorldIds.plex)).isOnline,
          isTrue,
        );
        expect(
          (await _probe(
            Profiles.p1.withConnection(WorldConnections.npm),
            ServiceKey.nginxProxyManager,
            WorldConnections.npm.id,
          )).isOnline,
          isTrue,
        );
      },
    );
  });

  group('P7: the fleet counts a refusal apart from the dark', () {
    test(
      'qBittorrent refusing the sign-in is a fault, not an outage',
      () async {
        final harness = await ProfileHarness.start(Profiles.p7);
        final container = harness.container(retry: (_, _) => null);
        for (final connection in Profiles.p7.connections) {
          await container.read(
            instanceSummaryProvider((
              service: connection.instance.service,
              instanceId: connection.id,
            )).future,
          );
        }

        final qb = container.read(
          foldedServiceHealthProvider(ServiceKey.qbittorrent),
        );
        expect(qb.faulted, 1);
        expect(qb.offline, 0);

        final dark = container.read(unreachableServicesProvider);
        expect(dark, contains(ServiceKey.jellyfin));
        expect(dark, contains(ServiceKey.bazarr));
        expect(dark, isNot(contains(ServiceKey.qbittorrent)));

        final health = container.read(stackHealthProvider);
        expect(health.faulted, 1);
        expect(health.sentence, contains('1 fault'));
        expect(health.sentence, isNot(contains('unreachable')));
      },
    );
  });

  group('the Stack paints it', () {
    testWidgets('a refused key reads amber in its own words, and the band '
        'that names what did not answer leaves it out', (tester) async {
      final harness = await pumpWithProfile(
        tester,
        Profiles.p3.withBehaviour(
          WorldIds.sonarr,
          ConnectionBehaviour.refusesKey,
        ),
        child: const StackScreen(),
        surfaceSize: const Size(430, 2400),
      );

      final cell = find.byKey(const ValueKey('service-matrix-cell-sonarr'));
      expect(cell, findsOneWidget);
      final label = find.descendant(
        of: cell,
        matching: find.text('Refused the key'),
      );
      expect(label, findsOneWidget);
      final scheme = AppTheme.darkTheme().colorScheme;
      final ink = tester.widget<Text>(label).style?.color;
      // Amber, measured on the lit card: the service answered.
      expect(
        ink,
        statusToneColor(
          scheme,
          StatusTone.warning,
          surface: scheme.surfaceContainer,
        ),
      );
      expect(
        find.descendant(of: cell, matching: find.text('Did not answer')),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('services-alert-band')), findsNothing);

      await harness.unmount(tester);
    });
  });
}
