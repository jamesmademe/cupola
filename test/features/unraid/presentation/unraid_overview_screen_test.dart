import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/models/service_kpi.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/services/domain/service_summary.dart';
import 'package:cupola/features/services/presentation/service_kpi_provider.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';
import 'package:cupola/features/unraid/domain/models/unraid_models.dart';
import 'package:cupola/features/unraid/presentation/unraid_overview_provider.dart';
import 'package:cupola/features/unraid/presentation/unraid_overview_screen.dart';
import 'package:cupola/features/unraid/presentation/unraid_provider.dart';

import '../../../test_helpers/settings_scope.dart';

void main() {
  testWidgets('draws the three regions the read layer can fill', (
    tester,
  ) async {
    await _pump(tester);

    // Identity and the readouts come before any section, and only this tab
    // carries them: the Array and Docker halves stopped drawing them when the
    // old single page was split, which is why they are here.
    expect(find.byType(ServiceKpiPeek), findsOneWidget);

    expect(
      tester
          .widgetList<SectionHeader>(find.byType(SectionHeader))
          .map((header) => header.title),
      ['Array', 'Docker', 'System'],
    );

    // VMs, Notifications and Shares are on the bar and absent here: the client
    // speaks `info`, `array` and `dockerContainers` and nothing else, and a
    // section of zeroes is a claim nobody made.
    expect(find.text('VMs'), findsNothing);
    expect(find.text('Notifications'), findsNothing);
    expect(find.text('Shares'), findsNothing);
    // Nor a parity verdict, which the `array` document does not carry.
    expect(find.textContaining('Parity'), findsNothing);
  });

  testWidgets('each section link is named after the tab it opens', (
    tester,
  ) async {
    await _pump(tester);

    expect(
      tester
          .widgetList<SectionHeader>(find.byType(SectionHeader))
          .map((header) => header.semanticHint),
      [
        'opens the Unraid Array tab',
        'opens the Unraid Docker tab',
        // System has nowhere to go: Unraid's bar has no System tab, and a link
        // named after a tab that does not exist is a promise the app cannot
        // keep.
        null,
      ],
    );
  });

  testWidgets('the identity block says Answering, never Online', (
    tester,
  ) async {
    await _pump(tester);

    expect(
      find.semantics.byLabel('Unraid, tower.lan, v7.0.1, Answering'),
      findsOneWidget,
    );
    expect(find.text('Online'), findsNothing);
  });

  testWidgets('a spun-down disk says so rather than reading 0 °C', (
    tester,
  ) async {
    await _pump(tester);

    // The rule the Array tab already states, and this page must not contradict
    // it: a slot Unraid reads no temperature from is asleep, not at zero.
    expect(find.text('spun down'), findsOneWidget);
    expect(find.textContaining('0\u00A0°C'), findsNothing);
    // One node for the whole row, with the unit said rather than glyphed, not
    // three fragments a screen reader walks separately.
    expect(
      find.semantics.byLabel('parity, DISK_OK, spun down'),
      findsOneWidget,
    );
  });

  testWidgets('a warm disk is a fault, and a stopped container is not', (
    tester,
  ) async {
    await _pump(
      tester,
      array: const UnraidArray(
        state: 'STARTED',
        usedFraction: 0.78,
        disks: [UnraidDisk(name: 'disk1', status: 'DISK_OK', temp: 47)],
      ),
      containers: [_container('plex', 'Exited (0) 2 days ago')],
    );

    // The header names the fault without being asked to colour it…
    final array = tester.widget<SectionHeader>(
      find.widgetWithText(SectionHeader, 'Array'),
    );
    expect(array.subtitle, 'started · 1 disk · 1 above 45\u00A0°C');

    // …and the deliberate stop is counted as backlog, in the plain census. It
    // is never called a failure: painting a stop the user chose the same amber
    // as a crash is how the tone rule breaks in a Docker list.
    final docker = tester.widget<SectionHeader>(
      find.widgetWithText(SectionHeader, 'Docker'),
    );
    expect(docker.subtitle, '1 container · 1 stopped');
    expect(find.textContaining('failed'), findsNothing);
    expect(
      find.semantics.byLabel('plex, stopped on purpose · exit 0 · 2 days ago'),
      findsOneWidget,
    );
  });

  testWidgets('the Docker header counts every container, not the rows drawn', (
    tester,
  ) async {
    await _pump(
      tester,
      containers: [for (var i = 0; i < 14; i++) _container('c$i', 'Up 1 day')],
    );

    // Fourteen containers, five rows. `dockerContainers` is not paged, so the
    // total may honestly be stated; the length of the preview never may.
    final docker = tester.widget<SectionHeader>(
      find.widgetWithText(SectionHeader, 'Docker'),
    );
    expect(docker.subtitle, '14 containers · 14 running');
    expect(
      find.byType(ServiceOverviewRow),
      // Five containers, two disks, two system facts.
      findsNWidgets(unraidContainerPreviewLimit + 4),
    );
  });

  testWidgets('a figure whose source did not answer reads `—` and never 0', (
    tester,
  ) async {
    await _pump(tester, failArray: true);

    // "0 disks" over an unanswered question is a claim nobody made, and the
    // claim it makes, "there is no array", is the one a user would act on.
    final header = tester.widget<SectionHeader>(
      find.widgetWithText(SectionHeader, 'Array'),
    );
    expect(header.subtitle, '—');
    expect(find.text('0 disks'), findsNothing);
  });

  testWidgets('an array that reported no slots does not claim it has none', (
    tester,
  ) async {
    await _pump(
      tester,
      // `disks` is nullable in the committed SDL, and this app has never run
      // against a real instance, so the array answering without a slot list is
      // a real shape, not a hypothetical.
      array: const UnraidArray(
        state: 'STARTED',
        usedFraction: null,
        disks: null,
      ),
    );

    final header = tester.widget<SectionHeader>(
      find.widgetWithText(SectionHeader, 'Array'),
    );
    // The state it *did* answer with, and nothing about drives it never
    // mentioned. "0 disks" beside "No disks reported" would be two positive
    // claims built out of one silence.
    expect(header.subtitle, 'started');
    expect(find.text('0 disks'), findsNothing);
  });

  testWidgets('an Unraid that answered without an uptime reads —', (
    tester,
  ) async {
    await _pump(
      tester,
      info: const UnraidInfo(distro: 'Unraid', version: '7.0.1', uptime: null),
    );

    // The row stays and says it has no figure, rather than vanishing: `info`
    // replied, and the shape of the page does not depend on the payload.
    expect(find.semantics.byLabel('Uptime, —'), findsOneWidget);
    expect(find.semantics.byLabel('Release, Unraid 7.0.1'), findsOneWidget);
  });

  testWidgets('a section whose source failed does not take the page with it', (
    tester,
  ) async {
    await _pump(tester, failDocker: true);

    // The failed region says so in its own slot…
    expect(find.byType(InlineErrorRetry), findsOneWidget);
    expect(
      find.textContaining(", so its containers are not shown."),
      findsOneWidget,
    );
    // …and the other two still drew their headings.
    expect(find.byType(SectionHeader), findsNWidgets(3));
  });

  testWidgets('nothing overflows at an accessibility reading size', (
    tester,
  ) async {
    await _pump(
      tester,
      textScaleFactor: 3.0,
      containers: [
        _container(
          'a-container-with-an-unreasonably-long-name-from-a-template',
          'Exited (137) 3 hours ago',
        ),
      ],
    );

    // A `RenderFlex overflowed` is thrown, not merely painted, under test.
    expect(tester.takeException(), isNull);
  });

  testWidgets('an Unraid that was never set up gets its own door', (
    tester,
  ) async {
    await _pump(tester, configured: false);

    final placeholder = tester.widget<NotConfiguredPlaceholder>(
      find.byType(NotConfiguredPlaceholder),
    );
    expect(placeholder.service, ServiceKey.unraid);
    // Nothing behind the door was built, which is the point: every provider on
    // this page reaches `unraidClientProvider`, which throws "not configured",
    // and a provider that throws is a *failed* provider retrying on a backoff
    // for a condition no waiting changes. A pending timer here would be the
    // tell.
    expect(find.byType(SectionHeader), findsNothing);
  });
}

// ─── Harness ────────────────────────────────────────────────────────────────

const _array = UnraidArray(
  state: 'STARTED',
  usedFraction: 0.5,
  disks: [
    UnraidDisk(name: 'disk1', status: 'DISK_OK', temp: 38),
    // No temperature: the slot is spun down, which the page has to say rather
    // than render as a reading.
    UnraidDisk(name: 'parity', status: 'DISK_OK', temp: null),
  ],
  usedBytes: 5 * 1024 * 1024 * 1024 * 1024,
  totalBytes: 10 * 1024 * 1024 * 1024 * 1024,
);

const _info = UnraidInfo(
  distro: 'Unraid',
  version: '7.0.1',
  uptime: '2026-08-30T12:00:00Z',
);

UnraidDockerContainer _container(String name, String status) =>
    UnraidDockerContainer.fromJson({
      'id': name,
      'names': ['/$name'],
      'state': status.toLowerCase().startsWith('up') ? 'RUNNING' : 'EXITED',
      'status': status,
      'autoStart': true,
    });

Future<void> _pump(
  WidgetTester tester, {
  UnraidArray array = _array,
  UnraidInfo info = _info,
  List<UnraidDockerContainer>? containers,
  bool failArray = false,
  bool failDocker = false,
  bool configured = true,
  double textScaleFactor = 1.0,
}) async {
  await tester.binding.setSurfaceSize(const Size(420, 2600));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    ProviderScope(
      // Riverpod 3 re-runs a failed provider on an exponential backoff, so one
      // `pumpAndSettle` would otherwise watch a deliberately failing section
      // retry a dozen times and never settle.
      retry: (_, _) => null,
      overrides: [
        currentSettingsProvider.overrideWith(
          (ref) => configured
              ? settingsWith(
                  unraidUrl: 'http://tower.lan',
                  unraidApiKey: 'unraid-key',
                )
              : const SettingsModel(),
        ),
        // The three documents the page is folded from, each overridable on its
        // own so a failing one can be shown not to take the others down.
        unraidArrayProvider.overrideWith((ref) async {
          if (failArray) throw Exception('array failed');
          return array;
        }),
        unraidDockerProvider.overrideWith((ref) async {
          if (failDocker) throw Exception('docker failed');
          return containers ?? [_container('plex', 'Up 12 days')];
        }),
        unraidInfoProvider.overrideWith((ref) async => info),
        serviceSummaryProvider.overrideWith(
          (ref, service) async => ServiceSummary(
            service: service,
            status: ServiceSummaryStatus.online,
            host: 'tower.lan',
            version: '7.0.1',
          ),
        ),
        // The readout rail is not what these tests are about, and it reads the
        // same two documents through a provider of its own.
        serviceKpiProvider.overrideWith(
          (ref, service) async => const <ServiceKpi>[],
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.darkTheme(),
        themeAnimationDuration: Duration.zero,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScaleFactor)),
          child: child!,
        ),
        home: const UnraidOverviewScreen(topPadding: 0),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
