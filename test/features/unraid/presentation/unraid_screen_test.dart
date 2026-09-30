import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/capability/capability_scope.dart';
import 'package:cupola/core/models/service_kpi.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/services/domain/service_summary.dart';
import 'package:cupola/features/services/presentation/service_kpi_provider.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/unraid/data/unraid_client.dart';
import 'package:cupola/features/unraid/domain/models/unraid_models.dart';
import 'package:cupola/features/unraid/presentation/unraid_capability.dart';
import 'package:cupola/features/unraid/presentation/unraid_provider.dart';
import 'package:cupola/features/unraid/presentation/unraid_screen.dart';

import '../../../test_helpers/capability_overrides.dart';
import '../../../test_helpers/capturing_http_adapter.dart';
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

const _vms = [UnraidVm(id: 'vm:1', name: 'Home Assistant', state: 'RUNNING')];

const _notifications = UnraidNotifications(
  unread: UnraidNotificationCounts(info: 0, warning: 1, alert: 0, total: 1),
  archived: UnraidNotificationCounts(info: 0, warning: 0, alert: 0, total: 0),
  items: [
    UnraidNotification(
      id: 'notification:1',
      title: 'Disk warm',
      subject: 'disk1',
      description: 'disk1 reached 47 C',
      importance: 'WARNING',
      type: 'UNREAD',
    ),
  ],
);

const _shares = [
  UnraidShare(
    id: 'share:1',
    name: 'media',
    usedKilobytes: 400,
    sizeKilobytes: 1000,
  ),
];

/// Every write the page can make lands on this adapter, so a gated tap is
/// proved to have reached nothing.
CapturingHttpAdapter _adapter() => CapturingHttpAdapter(
  response: {
    'data': {
      'vm': {'start': true, 'stop': true, 'resume': true},
      'archiveNotification': {'id': 'notification:1'},
    },
  },
);

Future<void> _pump(
  WidgetTester tester,
  Widget screen, {
  UnraidSection? failingSection,
  CapabilityGrant grant = const CapabilityGrant.unknown(),
  CapturingHttpAdapter? adapter,
}) async {
  final dio = Dio(BaseOptions(baseUrl: 'https://unraid.local'))
    ..httpClientAdapter = adapter ?? _adapter();
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
        unraidClientProvider.overrideWithValue(
          UnraidClient(url: 'https://unraid.local', apiKey: 'K', dio: dio),
        ),
        // The first Unraid connection takes the service's route param as id.
        capabilityOverride({'unraid': grant}),
        unraidVmsProvider.overrideWith((ref) async {
          if (failingSection == UnraidSection.vms) throw Exception('offline');
          return _vms;
        }),
        unraidNotificationsProvider.overrideWith((ref) async {
          if (failingSection == UnraidSection.notifications) {
            throw Exception('offline');
          }
          return _notifications;
        }),
        unraidSharesProvider.overrideWith((ref) async {
          if (failingSection == UnraidSection.shares) {
            throw Exception('offline');
          }
          return _shares;
        }),
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

  testWidgets('VMs, Notifications and Shares render separate documents', (
    tester,
  ) async {
    await _pump(tester, const UnraidScreen.vms(showAppBar: false));
    expect(find.text('Home Assistant'), findsOneWidget);
    expect(find.text('Disk warm'), findsNothing);

    await _pump(tester, const UnraidScreen.notifications(showAppBar: false));
    expect(find.text('Disk warm'), findsOneWidget);
    expect(find.text('media'), findsNothing);

    await _pump(tester, const UnraidScreen.shares(showAppBar: false));
    expect(find.text('media'), findsOneWidget);
    expect(find.text('40% used'), findsOneWidget);
  });

  testWidgets('each new document owns an explicit remote-error state', (
    tester,
  ) async {
    await _pump(
      tester,
      const UnraidScreen.vms(showAppBar: false),
      failingSection: UnraidSection.vms,
    );
    // An error nobody can attribute is a fault that answered, not silence:
    // the words say so rather than blaming reachability.
    expect(
      find.text(
        'The request to Unraid did not complete, so its virtual machines '
        'are not shown.',
      ),
      findsOneWidget,
    );

    await _pump(
      tester,
      const UnraidScreen.notifications(showAppBar: false),
      failingSection: UnraidSection.notifications,
    );
    expect(
      find.text(
        'The request to Unraid did not complete, so its notifications are '
        'not shown.',
      ),
      findsOneWidget,
    );

    await _pump(
      tester,
      const UnraidScreen.shares(showAppBar: false),
      failingSection: UnraidSection.shares,
    );
    expect(
      find.text(
        'The request to Unraid did not complete, so its shares are not shown.',
      ),
      findsOneWidget,
    );
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
      UnraidScreen.vms(showAppBar: false),
      UnraidScreen.notifications(showAppBar: false),
      UnraidScreen.shares(showAppBar: false),
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

  group('a read-only key', () {
    for (final (section, screen, tooltip, copy, blocked) in [
      (
        'VMs',
        const UnraidScreen.vms(showAppBar: false),
        'stop Home Assistant',
        unraidVmsCopy,
        'This Unraid key can\'t start or stop VMs.',
      ),
      (
        'Notifications',
        const UnraidScreen.notifications(showAppBar: false),
        'Archive notification',
        unraidNotificationsCopy,
        'This Unraid key can\'t archive notifications.',
      ),
    ]) {
      testWidgets('$section: one banner, first, and a dimmed live control', (
        tester,
      ) async {
        final adapter = _adapter();
        await _pump(
          tester,
          screen,
          grant: const CapabilityGrant.readOnly(),
          adapter: adapter,
        );

        expect(find.byType(CapabilityBanner), findsOneWidget);
        expect(find.text(copy.answered), findsOneWidget);
        // First: above the section header.
        expect(
          tester.getTopLeft(find.byType(CapabilityBanner)).dy,
          lessThan(tester.getTopLeft(find.byType(SectionHeader).first).dy),
        );

        final control = find.byTooltip(tooltip);
        expect(
          tester.getSemantics(control),
          containsSemantics(
            hint: copy.hint,
            isButton: true,
            isEnabled: true,
            hasTapAction: true,
          ),
        );
        expect(
          find.descendant(
            of: find.byType(IconButton),
            matching: find.byType(Opacity),
          ),
          findsOneWidget,
        );

        await tester.tap(control);
        await tester.pumpAndSettle();
        expect(find.text(blocked), findsOneWidget);
        // No confirmation drawn, and nothing reached the server.
        expect(find.byType(AlertDialog), findsNothing);
        expect(adapter.callCount, 0);
      });
    }
  });

  testWidgets('a read-write key: no banner, and the write goes out', (
    tester,
  ) async {
    final adapter = _adapter();
    await _pump(
      tester,
      const UnraidScreen.notifications(showAppBar: false),
      grant: const CapabilityGrant.readWrite(),
      adapter: adapter,
    );
    expect(find.byType(CapabilityBanner), findsNothing);
    await tester.tap(find.byTooltip('Archive notification'));
    await tester.pumpAndSettle();
    expect(adapter.callCount, 1);
  });

  testWidgets('an unprobed key: no banner, controls live', (tester) async {
    await _pump(tester, const UnraidScreen.vms(showAppBar: false));
    expect(find.byType(CapabilityBanner), findsNothing);
    await tester.tap(find.byTooltip('stop Home Assistant'));
    await tester.pumpAndSettle();
    // Live: the stop confirmation, naming the host.
    expect(find.text('Stop Home Assistant?'), findsOneWidget);
  });

  testWidgets('a key that may write VMs only gets a banner on Notifications', (
    tester,
  ) async {
    await _pump(
      tester,
      const UnraidScreen.vms(showAppBar: false),
      grant: const CapabilityGrant.partial({'vms'}),
    );
    expect(find.byType(CapabilityBanner), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await _pump(
      tester,
      const UnraidScreen.notifications(showAppBar: false),
      grant: const CapabilityGrant.partial({'vms'}),
    );
    expect(find.byType(CapabilityBanner), findsOneWidget);
  });

  testWidgets('a FORBIDDEN on a write marks the key and says so', (
    tester,
  ) async {
    final adapter = CapturingHttpAdapter(
      response: {
        'errors': [
          {
            'message': 'Forbidden resource',
            'extensions': {'code': 'FORBIDDEN'},
          },
        ],
        'data': null,
      },
    );
    await _pump(
      tester,
      const UnraidScreen.notifications(showAppBar: false),
      adapter: adapter,
    );
    await tester.tap(find.byTooltip('Archive notification'));
    await tester.pumpAndSettle();

    expect(find.text(unraidNotificationsCopy.refusal), findsOneWidget);
    expect(find.textContaining('Could not archive'), findsNothing);
    // And the page now says why.
    expect(find.text(unraidNotificationsCopy.refused), findsOneWidget);
  });
}
