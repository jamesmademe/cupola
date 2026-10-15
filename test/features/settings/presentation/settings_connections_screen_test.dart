import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/widgets/app_card.dart';
import 'package:cupola/features/settings/data/connection_reach_provider.dart';
import 'package:cupola/features/settings/data/service_connection_provider.dart';
import 'package:cupola/features/settings/data/service_verification.dart';
import 'package:cupola/features/onboarding/data/known_candidates_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/connection_address.dart';
import 'package:cupola/features/settings/domain/connection_candidate.dart';
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

    group('home and away (J-Config-Away-States e)', () {
      const radarr = ServiceInstance(
        id: 'radarr',
        service: ServiceKey.radarr,
        url: 'http://nas.home.arpa:7878',
        credential: 'key',
        away: ConnectionAddress(url: 'https://radarr.example.net'),
      );
      const sabnzbd = ServiceInstance(
        id: 'sabnzbd',
        service: ServiceKey.sabnzbd,
        url: 'http://nas.home.arpa:8080',
        credential: 'key',
      );

      testWidgets('at home, line two is the setup and the address in use', (
        tester,
      ) async {
        await _pumpConnectionsScreen(
          tester,
          settings: const SettingsModel(instances: [radarr, sabnzbd]),
          diagnosis: const ServiceDiagnosis.connected(),
          routes: const {},
        );
        expect(find.text('Home and away · nas.home.arpa:7878'), findsOneWidget);
        expect(find.text('Home only · nas.home.arpa:8080'), findsOneWidget);
      });

      testWidgets('away, the address follows the route and a home-only row '
          'says its state, neutral', (tester) async {
        await _pumpConnectionsScreen(
          tester,
          settings: const SettingsModel(instances: [radarr, sabnzbd]),
          diagnosis: const ServiceDiagnosis.connected(),
          diagnoses: const {ServiceKey.sabnzbd: ServiceDiagnosis.onlyAtHome()},
          routes: const {'radarr': ConnectionRoute.away},
        );
        expect(find.text('Home and away · radarr.example.net'), findsOneWidget);
        expect(find.text('Only at home · nas.home.arpa:8080'), findsOneWidget);
        expect(find.textContaining('Did not answer'), findsNothing);
      });

      testWidgets('neither address answering, the row says it of both and '
          'names no address in use', (tester) async {
        await _pumpConnectionsScreen(
          tester,
          settings: const SettingsModel(instances: [radarr, sabnzbd]),
          diagnosis: const ServiceDiagnosis.connected(),
          diagnoses: const {
            ServiceKey.radarr: ServiceDiagnosis(
              ServiceConnectionStatus.disconnected,
              ServiceFailureReason.unreachableAtBoth,
            ),
          },
          routes: const {},
        );
        expect(find.text('Did not answer at home or away'), findsOneWidget);
        expect(find.text('Home only · nas.home.arpa:8080'), findsOneWidget);
      });

      testWidgets('without any address away, the rows say what they said', (
        tester,
      ) async {
        await _pumpConnectionsScreen(
          tester,
          settings: const SettingsModel(instances: [sabnzbd]),
          diagnosis: const ServiceDiagnosis.connected(),
        );
        expect(find.text('nas.home.arpa:8080'), findsOneWidget);
        expect(find.textContaining('Home only'), findsNothing);
      });
    });

    testWidgets('offers first what the connections already know, filled in', (
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
        found: const [
          ConnectionCandidate(
            service: ServiceKey.radarr,
            name: 'Radarr 4K',
            reportedUrl: 'https://radarr.local:7879',
            source: CandidateSource(
              service: ServiceKey.seerr,
              connectionId: 'seerr',
              url: 'https://seerr.local',
            ),
            apiKey: 'found-key',
          ),
        ],
      );

      expect(find.text('Ready to add'), findsOneWidget);
      expect(find.text('Add Radarr 4K'), findsOneWidget);
      expect(find.text('Seerr knows it · key found'), findsOneWidget);
      // Above what is set up.
      expect(
        tester.getTopLeft(find.text('Ready to add')).dy,
        lessThan(tester.getTopLeft(find.text('Your services')).dy),
      );

      await tester.tap(find.text('Add Radarr 4K'));
      await tester.pumpAndSettle();

      expect(find.text('ServicePage:radarr'), findsOneWidget);
      // A second Radarr, beside the one set up; only names in the location.
      expect(
        find.text('Query:new=1&from=seerr&known=Radarr+4K'),
        findsOneWidget,
      );
    });

    testWidgets('with nothing known, there is no such section', (tester) async {
      await _pumpConnectionsScreen(tester);
      expect(find.text('Ready to add'), findsNothing);
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

      expect(find.text('Media'), findsOneWidget);
      expect(find.text('Downloads'), findsOneWidget);
      // Nothing configured in Infrastructure, so that header stays out of the
      // connected section entirely.
      expect(find.text('Infrastructure'), findsNothing);
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
      // job and one target. It used to carry a delete button immediately left
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
      // second Radarr, the one screen in the app that did not know.
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

      expect(find.text('Refused the key · radarr.local:7878'), findsOneWidget);
      expect(
        find.semantics.byLabel('Radarr, Refused the key, radarr.local:7878'),
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

class _Routes extends ConnectionRoutesNotifier {
  _Routes(this._routes);

  final Map<String, ConnectionRoute> _routes;

  @override
  Map<String, ConnectionRoute> build() => _routes;
}

Future<void> _pumpConnectionsScreen(
  WidgetTester tester, {
  SettingsModel settings = const SettingsModel(),
  ServiceDiagnosis? diagnosis,
  Map<ServiceKey, ServiceDiagnosis> diagnoses = const {},
  Map<String, ConnectionRoute>? routes,
  List<ConnectionCandidate> found = const [],
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
          return Scaffold(
            body: Column(
              children: [
                Text('ServicePage:$service'),
                Text('Query:${state.uri.query}'),
              ],
            ),
          );
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
        foundCandidatesProvider.overrideWith((ref) async => found),
        if (diagnosis != null || diagnoses.isNotEmpty)
          serviceDiagnosisProvider.overrideWith((ref, service) async {
            return diagnoses[service] ?? diagnosis!;
          }),
        if (routes != null)
          connectionRoutesProvider.overrideWith(() => _Routes(routes)),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}
