import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/features/settings/data/service_verification.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';
import 'package:cupola/features/settings/presentation/settings_home_screen.dart';

import '../../../test_helpers/settings_scope.dart';

/// `/settings` is two things at one address, and this is the seam between them:
/// a window wide enough for the rail gets the summary pane, anything narrower
/// gets the index. Both are the same route.
void main() {
  group('on a window', () {
    testWidgets('the root route is the summary, not the index', (tester) async {
      await _onDesktop(() async {
        await _pumpHome(tester, size: const Size(1440, 900));

        // Six cards, one per area, each a door to its own pane.
        for (final card in const [
          'CONNECTIONS',
          'TRUSTED CERTIFICATES',
          'BACKGROUND SEARCH',
          'REGION',
          'APPEARANCE',
          'HINTS',
        ]) {
          expect(find.text(card), findsOneWidget, reason: '$card card missing');
        }
        // General belongs to the narrow layout: beside the rail its rows
        // would be a second copy of the rail.
        expect(find.text('GENERAL'), findsNothing);
      });
    });

    testWidgets('what the rail cannot carry is still reachable', (
      tester,
    ) async {
      // About, Revisit onboarding and Reset are not pages, so the rail never
      // had them — and while only the phone index built them, a window this
      // wide had no door to the licence page, feedback, the donation sheet,
      // the onboarding replay or Reset at all.
      await _onDesktop(() async {
        await _pumpHome(tester, size: const Size(1440, 2400));

        for (final label in const ['ONBOARDING', 'ABOUT', 'DANGER ZONE']) {
          expect(find.text(label), findsOneWidget, reason: '$label missing');
        }
        for (final row in const [
          'Revisit onboarding',
          'GitHub',
          'Send feedback',
          'Support development',
          'Licenses & trademarks',
          'Reset app data',
        ]) {
          expect(find.text(row), findsOneWidget, reason: '$row missing');
        }

        // Reset keeps its confirmation on this layout too.
        await tester.tap(find.text('Reset app data'));
        await tester.pumpAndSettle();
        expect(find.text('Reset all data?'), findsOneWidget);
        await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
        await tester.pumpAndSettle();
        expect(find.text('Reset all data?'), findsNothing);

        // And the licence page opens from here.
        await tester.tap(find.text('Licenses & trademarks'));
        await tester.pumpAndSettle();
        expect(find.byType(LicensePage), findsOneWidget);
      });
    });

    testWidgets('a pin no service reaches any more is named here', (
      tester,
    ) async {
      // The one fact about trust that no other screen can show: the
      // per-service form only ever knows about its own address, so an origin
      // that outlived every service using it is invisible everywhere else
      // (ADR-6).
      await _onDesktop(() async {
        await _pumpHome(
          tester,
          size: const Size(1440, 900),
          settings:
              settingsWith(
                radarrUrl: 'https://radarr.local:7878',
                radarrApiKey: 'radarr-key',
              ).copyWith(
                trustedCertificates: const {'https://nas.local:8443': 'ab12cd'},
              ),
        );

        expect(find.text('1 pinned origin'), findsOneWidget);
        expect(find.text('nas.local:8443'), findsOneWidget);
        expect(
          find.text('No configured service uses this address.'),
          findsOneWidget,
        );
      });
    });

    testWidgets('a pin a service still uses is not worth a line', (
      tester,
    ) async {
      await _onDesktop(() async {
        await _pumpHome(
          tester,
          size: const Size(1440, 900),
          settings:
              settingsWith(
                radarrUrl: 'https://radarr.local:7878',
                radarrApiKey: 'radarr-key',
              ).copyWith(
                trustedCertificates: const {
                  'https://radarr.local:7878': 'ab12cd',
                },
              ),
        );

        expect(find.text('1 pinned origin'), findsOneWidget);
        expect(
          find.text('No configured service uses this address.'),
          findsNothing,
        );
      });
    });
  });

  group('Test all', () {
    testWidgets('re-asks every connection', (tester) async {
      // "Test all" and ⌘R are one command, and what it means is: ask every
      // saved server again. A button that only refreshed what happened to be
      // on screen would be a different command with the same name.
      var probes = 0;
      await _pumpHome(
        tester,
        size: const Size(1000, 2400),
        settings: settingsWith(
          radarrUrl: 'https://radarr.local:7878',
          radarrApiKey: 'radarr-key',
          sonarrUrl: 'https://sonarr.local:8989',
          sonarrApiKey: 'sonarr-key',
        ),
        onDiagnose: () => probes++,
      );

      expect(probes, 2, reason: 'both connections are asked on first build');

      await tester.tap(find.text('Test all'));
      await tester.pumpAndSettle();

      expect(probes, 4, reason: 'and both are asked again');
    });
  });
}

/// The rail — and so the summary pane — draws on a desktop build only. The
/// override is undone inside the body because `flutter_test` asserts on it
/// before tear-downs run.
Future<void> _onDesktop(Future<void> Function() body) async {
  debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
  try {
    await body();
  } finally {
    debugDefaultTargetPlatformOverride = null;
  }
}

Future<void> _pumpHome(
  WidgetTester tester, {
  required Size size,
  SettingsModel settings = const SettingsModel(),
  VoidCallback? onDiagnose,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final router = GoRouter(
    initialLocation: '/settings',
    routes: [
      GoRoute(
        path: '/settings',
        builder: (_, _) => const SettingsHomeScreen(),
        routes: [
          GoRoute(
            path: 'connections',
            builder: (_, _) => const Scaffold(body: Text('ConnectionsPage')),
          ),
          GoRoute(
            path: 'certificates',
            builder: (_, _) => const Scaffold(body: Text('CertificatesPage')),
          ),
        ],
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentSettingsProvider.overrideWith((ref) => settings),
        serviceDiagnosisProvider.overrideWith((ref, service) async {
          onDiagnose?.call();
          return const ServiceDiagnosis.connected();
        }),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}
