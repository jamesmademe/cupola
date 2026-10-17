import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/models/media_preview.dart';
import 'package:cupola/features/discover/presentation/catalog_providers.dart';
import 'package:cupola/features/discover/presentation/discover_details_provider.dart';
import 'package:cupola/features/home/data/stack_lights.dart';
import 'package:cupola/features/home/data/storage.dart';
import 'package:cupola/features/home/domain/stack_lights.dart';
import 'package:cupola/features/home/domain/storage.dart';
import 'package:cupola/features/home/presentation/widgets/discover_shelf_module.dart';
import 'package:cupola/features/home/presentation/widgets/stack_health_module.dart';
import 'package:cupola/features/home/presentation/widgets/storage_module.dart';
import 'package:cupola/features/services/domain/source_coverage.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import '../../../test_helpers/settings_scope.dart';

/// The three modules a person adds in Edit Home: Stack health, Storage and
/// Discover shelf, each in its states.
void main() {
  late List<String> went;

  Future<void> pump(
    WidgetTester tester,
    Widget module, {
    List<ServiceKey> configured = const [],
    List<Override> overrides = const [],
  }) async {
    went = [];
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final scope = await settingsScopeOverrides(configured: configured);
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => Scaffold(body: ListView(children: [module])),
        ),
        GoRoute(
          path: '/stack/:rest(.*)',
          builder: (_, state) {
            went.add(state.uri.path);
            return const SizedBox.shrink();
          },
        ),
        GoRoute(
          path: '/stack',
          builder: (_, state) {
            went.add(state.uri.path);
            return const SizedBox.shrink();
          },
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [...scope, ...overrides],
        child: MaterialApp.router(
          theme: AppTheme.darkTheme(),
          routerConfig: router,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  group('Stack health', () {
    StackLights lights(List<(ServiceKey, StackLight)> rows) => StackLights(
      rows: [
        for (final (service, light) in rows) (service: service, light: light),
      ],
    );

    testWidgets('every service its mark, the faults named in amber, one '
        'target to Stack', (tester) async {
      final semantics = tester.ensureSemantics();
      await pump(
        tester,
        const HomeStackHealthModule(),
        overrides: [
          stackLightsProvider.overrideWithValue(
            lights([
              (ServiceKey.radarr, StackLight.answering),
              (ServiceKey.sonarr, StackLight.fault),
              (ServiceKey.qbittorrent, StackLight.fault),
            ]),
          ),
        ],
      );
      expect(find.text('Stack'), findsOne);
      expect(find.text('3 of 3 answering\u00A0· 2 faults'), findsOne);
      expect(find.text('Faults: Sonarr and qBittorrent'), findsOne);
      expect(find.byType(StackLightMark), findsNWidgets(3));
      await tester.tap(
        find.bySemanticsLabel(
          'Answering: Radarr. Faults: Sonarr, qBittorrent.',
        ),
      );
      await tester.pumpAndSettle();
      expect(went, ['/stack']);
      semantics.dispose();
    });

    testWidgets('a service that did not answer: red, with Retry', (
      tester,
    ) async {
      await pump(
        tester,
        const HomeStackHealthModule(),
        overrides: [
          stackLightsProvider.overrideWithValue(
            lights([
              (ServiceKey.radarr, StackLight.silent),
              (ServiceKey.sonarr, StackLight.fault),
            ]),
          ),
        ],
      );
      expect(find.textContaining('Radarr did not answer'), findsOne);
      expect(find.text('Retry'), findsOne);
      // The red line stands alone: the amber one waits behind it.
      expect(find.textContaining('Faults:'), findsNothing);
    });

    testWidgets('servers reached that never replied: amber, one sentence, '
        'with Retry', (tester) async {
      await pump(
        tester,
        const HomeStackHealthModule(),
        overrides: [
          stackLightsProvider.overrideWithValue(
            lights([
              (ServiceKey.radarr, StackLight.stuck),
              (ServiceKey.sonarr, StackLight.stuck),
              (ServiceKey.lidarr, StackLight.fault),
            ]),
          ),
        ],
      );
      expect(
        find.text('1 of 3 answering\u00A0· 1 fault\u00A0· 2 timed out'),
        findsOne,
      );
      expect(
        find.textContaining(
          'Radarr and Sonarr were reached but did not reply in time.',
        ),
        findsOne,
      );
      expect(find.textContaining('did not answer'), findsNothing);
      expect(find.text('Retry'), findsOne);
    });

    testWidgets('before anything answers, every service is being asked', (
      tester,
    ) async {
      await pump(
        tester,
        const HomeStackHealthModule(),
        overrides: [
          stackLightsProvider.overrideWithValue(
            lights([
              (ServiceKey.radarr, StackLight.checking),
              (ServiceKey.sonarr, StackLight.checking),
            ]),
          ),
        ],
      );
      expect(find.text('Checking 2'), findsOne);
      expect(find.text('Asking each service'), findsOne);
    });
  });

  group('Storage', () {
    final tank = StoragePool(
      service: ServiceKey.truenas,
      instanceId: 'truenas',
      name: 'tank',
      healthy: false,
      state: 'Degraded',
      usedFraction: 0.72,
      usedBytes: 72,
      totalBytes: 100,
      disks: const ['Disk sdd has failed'],
    );

    testWidgets('each pool, its share in ink, the disk in trouble; a tap '
        'opens the pool', (tester) async {
      await pump(
        tester,
        const HomeStorageModule(),
        configured: const [ServiceKey.truenas],
        overrides: [
          homeStorageProvider.overrideWith(
            (ref) async => (
              pools: [tank],
              coverage: SourceCoverage.answeredBy(ServiceKey.truenas),
            ),
          ),
        ],
      );
      expect(find.text('Storage'), findsOne);
      expect(find.text('TrueNAS'), findsOne);
      expect(find.text('72%'), findsOne);
      expect(find.text('Disk sdd has failed'), findsOne);
      await tester.tap(find.text('tank'));
      await tester.pumpAndSettle();
      expect(went, ['/stack/truenas/storage/pool/tank']);
    });

    testWidgets('a TrueNAS that did not answer keeps the place, with '
        'Retry', (tester) async {
      await pump(
        tester,
        const HomeStorageModule(),
        configured: const [ServiceKey.truenas],
        overrides: [
          homeStorageProvider.overrideWith(
            (ref) async => (
              pools: const <StoragePool>[],
              coverage: SourceCoverage.failure(
                ServiceKey.truenas,
                const ClassifiedFailure(ServiceFailureReason.unreachable),
              ),
            ),
          ),
        ],
      );
      expect(find.text('Storage'), findsOne);
      expect(find.textContaining('TrueNAS'), findsWidgets);
      expect(find.text('Retry'), findsOne);
    });

    testWidgets('while it is read, its shape holds the place', (tester) async {
      final semantics = tester.ensureSemantics();
      await pump(
        tester,
        const HomeStorageModule(),
        configured: const [ServiceKey.truenas],
        overrides: [
          homeStorageProvider.overrideWith(
            (ref) => Completer<HomeStorage>().future,
          ),
        ],
      );
      expect(find.bySemanticsLabel('Loading storage'), findsOne);
      semantics.dispose();
    });

    testWidgets('switched on without TrueNAS or Unraid, it asks for TrueNAS', (
      tester,
    ) async {
      await pump(tester, const HomeStorageModule());
      expect(find.text('Set up TrueNAS to see your storage'), findsOne);
      expect(find.text('Set up TrueNAS'), findsOne);
    });
  });

  group('Discover shelf', () {
    testWidgets('Seerr\'s trending this week, the way into Discover at its '
        'head', (tester) async {
      await pump(
        tester,
        const HomeDiscoverShelfModule(),
        configured: const [ServiceKey.seerr],
        overrides: [
          seerrNumberingProvider.overrideWith((ref) async => null),
          atriumTrendingProvider.overrideWith(
            (ref) async => const [
              MediaPreview(id: 20, title: 'Sintel', mediaType: 'movie'),
              MediaPreview(id: 21, title: 'Charge', mediaType: 'movie'),
            ],
          ),
        ],
      );
      expect(find.text('Trending this week'), findsOne);
      expect(find.text('Sintel'), findsOne);
    });

    testWidgets('switched on without Seerr, it asks for Seerr', (tester) async {
      await pump(tester, const HomeDiscoverShelfModule());
      expect(find.text('Set up Seerr to discover movies and series'), findsOne);
    });
  });
}
