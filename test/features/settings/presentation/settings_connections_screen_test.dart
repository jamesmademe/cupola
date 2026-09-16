import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/widgets/app_card.dart';
import 'package:cupola/features/settings/data/service_verification.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';
import 'package:cupola/features/settings/presentation/settings_connections_screen.dart';

import '../../../test_helpers/settings_scope.dart';

void main() {
  group('SettingsConnectionsScreen', () {
    testWidgets('splits configured services from the ones still to add', (
      tester,
    ) async {
      await _pumpConnectionsScreen(
        tester,
        settings: settingsWith(
          seerrUrl: 'https://seerr.local',
          seerrApiKey: 'key',
          radarrUrl: 'https://radarr.local:7878',
          radarrApiKey: 'key',
        ),
        diagnosis: const ServiceDiagnosis.connected(),
      );

      expect(find.text('Your services'), findsOneWidget);
      expect(find.text('Add a service'), findsOneWidget);
      // Both configured services are in Media, so one domain group plus the
      // single "add" group.
      expect(find.byType(SettingsGroupCard), findsNWidgets(2));
      // Derived from the registry rather than written down: these were literal
      // 13/11 and rotted when the Stream domain landed.
      final total = ServiceKey.values.length;
      expect(find.byType(SettingsCard), findsNWidgets(total));
      expect(find.text('2 of $total'), findsOneWidget);
      expect(find.text('seerr.local'), findsOneWidget);
      expect(find.text('radarr.local:7878'), findsOneWidget);
      expect(find.text('Not set up'), findsNWidgets(total - 2));
    });

    testWidgets('groups connected services by domain', (tester) async {
      await _pumpConnectionsScreen(
        tester,
        settings: settingsWith(
          radarrUrl: 'https://radarr.local:7878',
          radarrApiKey: 'key',
          qbittorrentUrl: 'https://qb.local',
          qbittorrentUsername: 'admin',
          qbittorrentPassword: 'pw',
        ),
        diagnosis: const ServiceDiagnosis.connected(),
      );

      expect(find.text('MEDIA'), findsOneWidget);
      expect(find.text('DOWNLOADS'), findsOneWidget);
      // Nothing configured in Infrastructure, so that header stays out of the
      // connected section entirely.
      expect(find.text('INFRASTRUCTURE'), findsNothing);
    });

    testWidgets('with nothing configured only the add section is shown', (
      tester,
    ) async {
      await _pumpConnectionsScreen(tester);

      expect(find.text('Your services'), findsNothing);
      expect(find.text('Add a service'), findsOneWidget);
      expect(find.byType(SettingsGroupCard), findsOneWidget);
    });

    testWidgets('tapping a service row navigates to the service route', (
      tester,
    ) async {
      await _pumpConnectionsScreen(tester);

      await tester.tap(find.text('Lidarr'));
      await tester.pumpAndSettle();

      expect(find.text('ServicePage:lidarr'), findsOneWidget);
    });

    testWidgets('an unconfigured row is spoken as a set-up action', (
      tester,
    ) async {
      // Removal moved onto the service screen, so a row here has exactly one
      // job and one target — it used to carry a delete button immediately left
      // of the chevron that opened the screen.
      await _pumpConnectionsScreen(tester);

      expect(
        find.semantics.byLabel('Lidarr, Not set up'),
        containsSemantics(
          isButton: true,
          hasTapAction: true,
          // "the Lidarr connection", not "Lidarr": what this row sets up is
          // how Cupola reaches Lidarr, not Lidarr's own configuration.
          hint: 'sets up the Lidarr connection',
        ),
      );
    });

    testWidgets('a configured row speaks its connection state', (tester) async {
      await _pumpConnectionsScreen(
        tester,
        settings: settingsWith(
          radarrUrl: 'https://radarr.local:7878',
          radarrApiKey: 'key',
        ),
        diagnosis: const ServiceDiagnosis.connected(),
      );

      expect(
        find.semantics.byLabel('Radarr, Answering, radarr.local:7878'),
        containsSemantics(
          isButton: true,
          hasTapAction: true,
          // Renamed with the pane: "Radarr settings" is now the name of the
          // service's own configuration page, so the row that opens the form
          // has to say which of the two it opens.
          hint: 'opens the Radarr connection settings',
        ),
      );
    });

    testWidgets('a second connection is visible on the Connections screen', (
      tester,
    ) async {
      // The screen is called Connections and had no way of showing that a
      // service had two: one row, the first connection's host, and a counter
      // that quite correctly counts services. Nothing on it revealed the
      // second Radarr — the one screen in the app that did not know.
      await _pumpConnectionsScreen(
        tester,
        settings:
            settingsWith(
              radarrUrl: 'https://radarr.local:7878',
              radarrApiKey: 'key',
              sonarrUrl: 'https://sonarr.local:8989',
              sonarrApiKey: 'key',
            ).copyWithInstance(
              const ServiceInstance(
                id: 'radarr-away111',
                service: ServiceKey.radarr,
                label: 'Away',
                url: 'https://away.local:7878',
                credential: 'key-away',
              ),
            ),
        diagnosis: const ServiceDiagnosis.connected(),
      );

      expect(find.text('radarr.local:7878 · 2 connections'), findsOneWidget);
      expect(
        find.semantics.byLabel(
          'Radarr, Answering, radarr.local:7878, 2 connections',
        ),
        findsOneWidget,
      );
      // The service with one is left exactly as it was: a stack with a single
      // Sonarr must not grow a count of one.
      expect(find.text('sonarr.local:8989'), findsOneWidget);
      // And the counter still counts SERVICES, which is what it says.
      expect(find.text('2 of ${ServiceKey.values.length}'), findsOneWidget);
    });

    testWidgets('a failing row leads with the cause, not the host', (
      tester,
    ) async {
      // "Could not reach it" sent people to re-check an address that was fine.
      // The classifier already knew the server had answered and rejected the
      // key; this is that verdict reaching the list.
      await _pumpConnectionsScreen(
        tester,
        settings: settingsWith(
          radarrUrl: 'https://radarr.local:7878',
          radarrApiKey: 'key',
        ),
        diagnosis: ServiceDiagnosis.failed(_UnauthorizedFailure()),
      );

      expect(find.text('API key rejected · radarr.local:7878'), findsOneWidget);
      expect(
        find.semantics.byLabel('Radarr, API key rejected, radarr.local:7878'),
        findsOneWidget,
      );
    });
  });
}

/// An error that already knows why it failed, the way the service clients do.
class _UnauthorizedFailure implements HasFailureReason {
  @override
  ServiceFailureReason get reason => ServiceFailureReason.unauthorized;
}

Future<void> _pumpConnectionsScreen(
  WidgetTester tester, {
  SettingsModel settings = const SettingsModel(),
  ServiceDiagnosis? diagnosis,
}) async {
  final router = GoRouter(
    initialLocation: '/settings/connections',
    routes: [
      GoRoute(
        path: '/settings/connections',
        builder: (_, _) => const SettingsConnectionsScreen(),
      ),
      GoRoute(
        path: '/settings/service/:service',
        builder: (context, state) {
          final service = state.pathParameters['service'] ?? 'unknown';
          return Scaffold(body: Text('ServicePage:$service'));
        },
      ),
    ],
  );

  addTearDown(router.dispose);

  // The screen is a lazy ListView; use a tall viewport so every domain card and
  // service row is built and counted, independent of scroll position.
  tester.view.physicalSize = const Size(1200, 3600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentSettingsProvider.overrideWith((ref) => settings),
        if (diagnosis != null)
          serviceDiagnosisProvider.overrideWith((ref, service) async {
            return diagnosis;
          }),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}
