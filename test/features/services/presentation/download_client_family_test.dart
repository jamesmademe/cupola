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

/// An upgrade Radarr grabbed whose torrent qBittorrent can no longer write:
/// Radarr still calls it downloading.
const _qbError = WorldDownload(
  id: 'a1f0c3d4e5f60718293a4b5c6d7e8f9012345611',
  release: 'Coffee.Run.2020.2160p.WEB',
  client: 'qbittorrent',
  state: DownloadState.failed,
  progress: 0.55,
  size: 3 * _gb,
  arr: WorldIds.radarr,
  title: WorldTitles.coffeeRun,
);

/// A torrent added by hand whose files were moved away.
const _qbMissing = WorldDownload(
  id: 'a1f0c3d4e5f60718293a4b5c6d7e8f9012345612',
  release: 'Agent.327.Operation.Barbershop.1080p',
  client: 'qbittorrent',
  state: DownloadState.missingFiles,
  progress: 1,
  size: _gb,
);

/// A Sonarr grab moving through NZBGet, tagged with the arr's drone id.
const _nzbgetGrab = WorldDownload(
  id: '5f0b7c1e-9d2a-4e51-8c3b-2a6d7e8f9a01',
  release: 'Night.Shift.S02E03.1080p.WEB',
  client: 'nzbget',
  state: DownloadState.downloading,
  progress: 0.5,
  size: 2 * _gb,
  arr: WorldIds.sonarr,
  title: WorldTitles.nightShift,
  season: 2,
  episode: 3,
  speed: 8 * _mb,
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

  group('qBittorrent', () {
    test('P1: a torrent in error and one missing its files are counted as '
        'faults, never dropped', () async {
      final container = await _start(
        Profiles.p1.withDownloads([_qbError, _qbMissing]),
      );
      final inFlight = await container.read(servicesInFlightProvider.future);

      // Radarr still says downloading; qBittorrent knows better, and the
      // joined row takes the client's fault.
      final coffeeRun = inFlight.faults.singleWhere(
        (item) => item.downloadId?.toLowerCase() == _qbError.id,
      );
      expect(coffeeRun.service, ServiceKey.radarr);
      expect(coffeeRun.fault, InFlightFault.failed);
      expect(coffeeRun.clientService, ServiceKey.qbittorrent);

      final missing = inFlight.faults.singleWhere(
        (item) => item.id == _qbMissing.id,
      );
      expect(missing.service, ServiceKey.qbittorrent);
      expect(missing.fault, InFlightFault.failed);
      expect(missing.warning, 'Files missing');

      expect(
        inFlight.preview.map((item) => item.id),
        isNot(contains(_qbMissing.id)),
      );
    });

    testWidgets('P1 on Home: the two broken torrents are counted under the '
        'region and listed as decisions', (tester) async {
      final harness = await _pumpHome(
        tester,
        Profiles.p1.withDownloads([_qbError, _qbMissing]),
      );

      expect(_inFlight(find.textContaining('2 failed')), findsOneWidget);
      expect(find.textContaining('Files missing'), findsOneWidget);

      await harness.unmount(tester);
    });
  });

  group('NZBGet', () {
    test('P4 + NZBGet: its rate enters the sum, once, keyed on the '
        'client', () async {
      final container = await _start(
        Profiles.p4.withConnection(WorldConnections.nzbget).withDownloads([
          _nzbgetGrab,
        ]),
      );
      final inFlight = await container.read(servicesInFlightProvider.future);

      final grab = inFlight.preview.singleWhere(
        (item) => item.downloadId == _nzbgetGrab.id,
      );
      expect(grab.service, ServiceKey.sonarr);
      expect(grab.clientService, ServiceKey.nzbget);
      expect(grab.clientRateBytesPerSecond, 8 * _mb);

      expect(inFlight.clients, 3);
      expect(
        inFlight.rateBytesPerSecond,
        (4.2 * _mb) ~/ 1 +
            (12.1 * _mb) ~/ 1 +
            (6.1 * _mb) ~/ 1 +
            3 * _mb +
            8 * _mb,
      );
    });
  });
}
