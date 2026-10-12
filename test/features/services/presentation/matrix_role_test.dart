import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cupola/core/theme.dart';
import 'package:cupola/features/services/domain/service_summary.dart';
import 'package:cupola/features/services/presentation/service_matrix.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';

import '../../../test_helpers/fake_secure_settings_store.dart';

const _fourK = ServiceInstance(
  id: 'radarr',
  service: ServiceKey.radarr,
  label: '4K',
  url: 'https://four-k.lan:7878',
  credential: 'k',
);
const _hd = ServiceInstance(
  id: 'radarr-hd11111',
  service: ServiceKey.radarr,
  label: 'HD',
  url: 'https://hd.lan:7879',
  credential: 'k',
);
const _sonarr = ServiceInstance(
  id: 'sonarr',
  service: ServiceKey.sonarr,
  url: 'https://sonarr.lan:8989',
  credential: 'k',
);

ServiceSummary _up(ServiceKey service) => ServiceSummary(
  service: service,
  status: ServiceSummaryStatus.online,
  host: 'somewhere',
  version: '5.0',
);

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  required ServiceMatrixRole role,
  List<ServiceInstance> instances = const [_fourK, _hd, _sonarr],
}) async {
  // A real phone, not the 800x600 default: the matrix resolves its columns
  // against a preferred cell width, so a viewport that is not a phone gives
  // cells a shape the layout was never tuned for.
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      secureSettingsStoreProvider.overrideWithValue(FakeSecureSettingsStore()),
      currentSettingsProvider.overrideWith(
        (ref) => SettingsModel(instances: instances),
      ),
      for (final instance in instances)
        instanceSummaryProvider((
          service: instance.service,
          instanceId: instance.id,
        )).overrideWith((ref) async => _up(instance.service)),
    ],
  );
  addTearDown(container.dispose);

  // A real router: a picker cell navigates as well as moving the lens, and a
  // bare MaterialApp has nothing for `context.push` to reach.
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => Scaffold(
          body: SingleChildScrollView(child: ServiceMatrix(role: role)),
        ),
        routes: [
          GoRoute(
            path: 'stack/:service',
            builder: (context, state) =>
                const Scaffold(body: Text('elsewhere')),
          ),
        ],
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        theme: AppTheme.darkTheme(),
        routerConfig: router,
        // The app root installs this, and the compact cell's 32pt is measured
        // against it: without it a single `bodySmall` line measures 17 instead
        // of 15 and the cell overflows by a point. A harness that omits it is
        // not testing the app: see `ServiceMatrixMetrics.compactCellBaseHeight`.
        builder: (context, child) => DefaultTextHeightBehavior(
          textHeightBehavior: const TextHeightBehavior(
            applyHeightToFirstAscent: false,
            applyHeightToLastDescent: false,
          ),
          child: child ?? const SizedBox.shrink(),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

Finder _cell(String routeParam, [String? instanceId]) => find.byKey(
  ValueKey(
    instanceId == null
        ? 'service-matrix-cell-$routeParam'
        : 'service-matrix-cell-$routeParam-$instanceId',
  ),
);

void main() {
  group('readout', () {
    testWidgets('folds two connections into one cell', (tester) async {
      await _pump(tester, role: ServiceMatrixRole.readout);

      expect(_cell('radarr'), findsOneWidget);
      expect(_cell('radarr', 'radarr-hd11111'), findsNothing);
    });

    testWidgets('keeps the key nine assertions already address', (
      tester,
    ) async {
      // The readout key must not gain an instance suffix. A folded cell still
      // stands for the service, so the name it had is still the true one, and
      // services_screen_test addresses it by that name.
      await _pump(tester, role: ServiceMatrixRole.readout);

      expect(_cell('sonarr'), findsOneWidget);
      expect(_cell('radarr'), findsOneWidget);
    });

    testWidgets('names the service, not a connection', (tester) async {
      await _pump(tester, role: ServiceMatrixRole.readout);

      expect(find.text('Radarr'), findsOneWidget);
      expect(find.text('4K'), findsNothing);
    });

    // The address is NOT on the readout: `home` §4 is explicit that it lives
    // on the Portal's picker cells and on the service home. What the folded
    // card owes instead is the fact that it stands for more than one
    // connection, which is what `×2` says.
    testWidgets('a folded cell says how many connections it stands for', (
      tester,
    ) async {
      final container = await _pump(tester, role: ServiceMatrixRole.readout);

      expect(
        container.read(activeInstanceProvider(ServiceKey.radarr))?.id,
        'radarr',
        reason: 'the lens starts on the first connection',
      );
      expect(find.text('×2'), findsOneWidget);
      expect(
        find.textContaining('4K'),
        findsNothing,
        reason: 'the readout names the service; the picker names connections',
      );
    });

    testWidgets('the readout never prints an address', (tester) async {
      final container = await _pump(tester, role: ServiceMatrixRole.readout);

      await container
          .read(activeInstancesProvider.notifier)
          .select(ServiceKey.radarr, 'radarr-hd11111');
      await tester.pumpAndSettle();

      // Moving the lens changes which connection the figures belong to, and
      // changes nothing the cell prints about *where*, because it prints none.
      expect(find.text('×2'), findsOneWidget);
      expect(find.textContaining('somewhere'), findsNothing);
    });

    testWidgets('a lone connection grows no count of one', (tester) async {
      await _pump(
        tester,
        role: ServiceMatrixRole.readout,
        instances: const [_sonarr],
      );

      expect(find.textContaining('×'), findsNothing);
    });
  });

  group('picker', () {
    testWidgets('gives every connection its own cell', (tester) async {
      await _pump(tester, role: ServiceMatrixRole.picker);

      expect(_cell('radarr', 'radarr'), findsOneWidget);
      expect(_cell('radarr', 'radarr-hd11111'), findsOneWidget);
      expect(_cell('sonarr', 'sonarr'), findsOneWidget);
      // A picker that hides a destination is a wall, so the folded key is gone.
      expect(_cell('radarr'), findsNothing);
    });

    testWidgets('names each connection', (tester) async {
      await _pump(tester, role: ServiceMatrixRole.picker);

      expect(find.text('4K'), findsOneWidget);
      expect(find.text('HD'), findsOneWidget);
      // The unlabelled one falls back to its service name rather than its id.
      expect(find.text('Sonarr'), findsOneWidget);
    });

    testWidgets('tapping moves the lens before it navigates', (tester) async {
      // Navigating alone would land on whichever connection the lens already
      // pointed at, which is the cell the user did not tap.
      final container = await _pump(tester, role: ServiceMatrixRole.picker);
      expect(
        container.read(activeInstanceProvider(ServiceKey.radarr))?.id,
        'radarr',
      );

      await tester.tap(_cell('radarr', 'radarr-hd11111'));
      await tester.pumpAndSettle();

      expect(
        container.read(activeInstanceProvider(ServiceKey.radarr))?.id,
        'radarr-hd11111',
      );
      // The other half of the invariant, and the half that was missing: the
      // lens moving is only useful if the route follows it. Asserted on the
      // destination rather than on the location string, because the cell
      // navigates with `go` and a picker that moved the lens without
      // travelling would leave the user on the floor it was tapped from.
      expect(find.text('elsewhere'), findsOneWidget);
    });

    testWidgets('a media server gets a cell per connection too', (
      tester,
    ) async {
      // Jellyfin, Plex and TrueNAS were folded even on the picker, because
      // their clients were built from the flat first-instance projections and a
      // cell per connection would have offered a destination the app then
      // ignored. Their clients go through `watchTransport` now, so the picker
      // owes them the same cell per connection as everyone else.
      const home = ServiceInstance(
        id: 'jellyfin',
        service: ServiceKey.jellyfin,
        label: 'Home',
        url: 'https://home.lan:8096',
        credential: 'k',
      );
      const away = ServiceInstance(
        id: 'jellyfin-away11',
        service: ServiceKey.jellyfin,
        label: 'Away',
        url: 'https://away.lan:8096',
        credential: 'k',
      );
      await _pump(
        tester,
        role: ServiceMatrixRole.picker,
        instances: const [_fourK, _hd, home, away],
      );

      expect(_cell('jellyfin', 'jellyfin'), findsOneWidget);
      expect(_cell('jellyfin', 'jellyfin-away11'), findsOneWidget);
      // The folded cell is what a picker must never fall back to: it reaches
      // the service and hides every connection but the lens's.
      expect(_cell('jellyfin'), findsNothing);
      expect(_cell('radarr', 'radarr-hd11111'), findsOneWidget);
    });

    testWidgets('an unconfigured connection is not offered', (tester) async {
      const blank = ServiceInstance(
        id: 'radarr-blank11',
        service: ServiceKey.radarr,
        label: 'Half done',
      );
      await _pump(
        tester,
        role: ServiceMatrixRole.picker,
        instances: const [_fourK, blank],
      );

      expect(_cell('radarr', 'radarr'), findsOneWidget);
      expect(_cell('radarr', 'radarr-blank11'), findsNothing);
    });
  });
}
