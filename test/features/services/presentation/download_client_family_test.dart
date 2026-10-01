/// The download clients are one family on Home.
///
/// qBittorrent, Transmission, SABnzbd and NZBGet each feed In flight, each
/// add their rate to the eyebrow, each raise their faults under Needs a
/// decision and each are named under the region when they do not answer.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/theme.dart';
import 'package:cupola/features/services/domain/dashboard_decision.dart';
import 'package:cupola/features/services/domain/in_flight.dart';
import 'package:cupola/features/services/domain/source_coverage.dart';
import 'package:cupola/features/services/presentation/dashboard_screen.dart';
import 'package:cupola/features/services/presentation/dashboard_sections.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import '../../../test_helpers/profiles/profiles.dart';

const _mb = 1024 * 1024;
const _gb = 1024 * 1024 * 1024;

/// A torrent somebody added to Transmission by hand, whose data went
/// missing.
const _brokenTransmission = WorldDownload(
  id: 'b2e1d4c5f6a70819304b5c6d7e8f901234567802',
  release: 'Big.Buck.Bunny.2008.2160p.Remux',
  client: 'transmission',
  state: DownloadState.failed,
  progress: 0.3,
  size: 12 * _gb,
);

Future<ProviderContainer> _start(ConfigProfile profile) async {
  final harness = await ProfileHarness.start(profile);
  return harness.container(retry: (_, _) => null);
}

Future<ProfileHarness> _pumpHome(
  WidgetTester tester,
  ConfigProfile profile,
) async {
  final harness = await ProfileHarness.start(profile);
  await tester.binding.setSurfaceSize(const Size(430, 6000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: harness.overrides,
      child: MaterialApp(
        theme: AppTheme.darkTheme(),
        home: const DashboardScreen(),
      ),
    ),
  );
  await harness.settle(tester);
  return harness;
}

Finder _inFlight(Finder matching) => find.descendant(
  of: find.byType(ServicesInFlightSection),
  matching: matching,
);

void main() {
  group('Transmission', () {
    test('P4: a Sonarr grab moving through Transmission takes its rate, time '
        'left and client off the torrent', () async {
      final container = await _start(Profiles.p4);
      final inFlight = await container.read(servicesInFlightProvider.future);

      final nightShift = inFlight.preview.singleWhere(
        (item) =>
            item.downloadId?.toLowerCase() ==
            WorldDownloads.nightShiftTransmission.id,
      );
      expect(nightShift.service, ServiceKey.sonarr);
      expect(nightShift.clientService, ServiceKey.transmission);
      expect(nightShift.clientInstanceId, WorldIds.transmission);
      expect(nightShift.etaSeconds, 240);
      // Counted once: the arr row absorbed the torrent.
      expect(inFlight.activeCount, 4);

      // qBittorrent's moving torrents and Transmission's, per client.
      expect(inFlight.clients, 2);
      expect(
        inFlight.rateBytesPerSecond,
        (4.2 * _mb) ~/ 1 + (12.1 * _mb) ~/ 1 + (6.1 * _mb) ~/ 1 + 3 * _mb,
      );
      expect(
        inFlight.coverage.answered.map((source) => source.service),
        contains(ServiceKey.transmission),
      );
    });

    test('P4, Transmission dark: it is named under the region, and the arr '
        'row it was moving stays', () async {
      final container = await _start(
        Profiles.p4.withBehaviour(
          WorldIds.transmission,
          ConnectionBehaviour.didNotAnswer,
        ),
      );
      final inFlight = await container.read(servicesInFlightProvider.future);

      expect(inFlight.coverage.failed.keys.map((source) => source.service), [
        ServiceKey.transmission,
      ]);
      expect(coverageNote(inFlight.coverage), contains('Transmission'));
      // The rate is the client that answered, never a zero for the one
      // that did not.
      expect(inFlight.clients, 1);
      expect(
        inFlight.preview.where(
          (item) =>
              item.downloadId?.toLowerCase() ==
              WorldDownloads.nightShiftTransmission.id,
        ),
        hasLength(1),
      );
    });

    test('P4: a torrent in error is a decision in the daemon\'s words, opened '
        'in Transmission', () async {
      final container = await _start(
        Profiles.p4.withDownloads([_brokenTransmission]),
      );
      final inFlight = await container.read(servicesInFlightProvider.future);

      final broken = inFlight.faults.singleWhere(
        (item) => item.id == _brokenTransmission.id,
      );
      expect(broken.service, ServiceKey.transmission);
      expect(broken.fault, InFlightFault.failed);
      expect(broken.warning, startsWith('No data found!'));

      final decisions = await container.read(
        dashboardDecisionSourceProvider(DecisionSource.queue).future,
      );
      final decision = decisions.decisions.singleWhere(
        (d) => d.title == _brokenTransmission.release,
      );
      expect(decision.kind, DecisionKind.stalledDownload);
      expect(decision.actionTarget, ServiceKey.transmission);
      expect(decision.actionInstanceId, WorldIds.transmission);
    });

    testWidgets('P4 on Home: the eyebrow sums both clients', (tester) async {
      final harness = await _pumpHome(tester, Profiles.p4);

      expect(
        _inFlight(find.textContaining('across 2 clients')),
        findsOneWidget,
      );

      await harness.unmount(tester);
    });
  });
}
