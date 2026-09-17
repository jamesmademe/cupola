import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/models/service_kpi.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/services/domain/service_summary.dart';
import 'package:cupola/features/services/presentation/service_kpi_provider.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/unraid/domain/models/unraid_models.dart';
import 'package:cupola/features/unraid/presentation/unraid_provider.dart';
import 'package:cupola/features/unraid/presentation/unraid_screen.dart';

import '../../../test_helpers/settings_scope.dart';

const _array = UnraidArray(
  state: 'STARTED',
  usedFraction: 0.42,
  disks: [
    UnraidDisk(name: 'disk1', status: 'DISK_OK', temp: 38),
    UnraidDisk(name: 'parity', status: 'DISK_OK', temp: null),
  ],
);

const _containers = [
  UnraidDockerContainer(
    id: 'a1',
    name: 'immich',
    state: 'RUNNING',
    status: 'Up 3 days',
    autoStart: true,
    condition: UnraidContainerCondition.running,
    exitCode: null,
    age: 'Up 3 days',
  ),
];

Future<void> _pump(WidgetTester tester, Widget screen) async {
  tester.view.physicalSize = const Size(1000, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ...await settingsScopeOverrides(configured: const [ServiceKey.unraid]),
        // Both documents are answered whichever half is under test, so a half
        // that reached for the other one's data would show up as content rather
        // than as an error state.
        unraidArrayProvider.overrideWith((ref) async => _array),
        unraidDockerProvider.overrideWith((ref) async => _containers),
        serviceKpiProvider(ServiceKey.unraid).overrideWith(
          (ref) async => const [
            ServiceKpi(label: 'Used', value: '42%', icon: Icons.storage),
          ],
        ),
        serviceSummaryProvider(ServiceKey.unraid).overrideWith(
          (ref) async => const ServiceSummary(
            service: ServiceKey.unraid,
            status: ServiceSummaryStatus.online,
            host: 'tower.lan',
            version: '7.0.0',
          ),
        ),
      ],
      child: MaterialApp(home: screen),
    ),
  );
  await tester.pumpAndSettle();
}

/// The two halves of what was one Unraid page, asserted on the screens.
///
/// `router_test.dart` proves each tab mounts the constructor it names; this
/// proves the constructors draw different things. A split whose two halves both
/// render everything is a split in name only, and no route assertion would say
/// so.
void main() {
  testWidgets('the Array half draws the disks and not the containers', (
    tester,
  ) async {
    await _pump(tester, const UnraidScreen.array(showAppBar: false));

    expect(find.text('Array disks'), findsOneWidget);
    expect(find.text('disk1'), findsOneWidget);
    expect(find.text('Containers'), findsNothing);
    expect(find.text('immich'), findsNothing);
  });

  testWidgets('the Docker half draws the containers and not the disks', (
    tester,
  ) async {
    await _pump(tester, const UnraidScreen.docker(showAppBar: false));

    expect(find.text('Containers'), findsOneWidget);
    expect(find.text('immich'), findsOneWidget);
    expect(find.text('Array disks'), findsNothing);
    expect(find.text('disk1'), findsNothing);
  });

  testWidgets('neither half repeats the readouts', (tester) async {
    // `ServiceKpiPeek` sat on the single page because the single page was the
    // service. Under the tab model the Overview carries them, and a section tab
    // drawing them too would be the same figures twice in one scroll.
    for (final screen in const [
      UnraidScreen.array(showAppBar: false),
      UnraidScreen.docker(showAppBar: false),
    ]) {
      await _pump(tester, screen);
      expect(find.byType(ServiceKpiPeek), findsNothing, reason: '$screen');
    }
  });

  testWidgets('a spun-down slot says so instead of reading 0 °C', (
    tester,
  ) async {
    // The parity slot above reports no temperature. A missing figure rendered
    // as a number is the one failure this screen cannot recover from: 0 °C is a
    // reading, and nobody would doubt it.
    await _pump(tester, const UnraidScreen.array(showAppBar: false));

    expect(find.textContaining('spun down'), findsOneWidget);
    expect(find.textContaining('0°C'), findsNothing);
  });

  testWidgets('an unconfigured Unraid draws the placeholder on both halves', (
    tester,
  ) async {
    // Configuration is checked before any provider is read, so nothing is
    // overridden here: a half that reached `unraidClientProvider` would throw,
    // and a provider that throws schedules a retry for a condition no waiting
    // changes — which this test would report as a pending timer.
    for (final screen in const [
      UnraidScreen.array(showAppBar: false),
      UnraidScreen.docker(showAppBar: false),
    ]) {
      await tester.pumpWidget(
        ProviderScope(
          overrides: await settingsScopeOverrides(),
          child: MaterialApp(home: screen),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byType(NotConfiguredPlaceholder),
        findsOneWidget,
        reason: '$screen',
      );
    }
  });
}
