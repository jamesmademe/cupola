/// The download clients are one family on Home.
///
/// qBittorrent, Transmission, SABnzbd and NZBGet each feed Downloads, each
/// add their rate to the line under its name, each raise their faults in
/// Needs you and each are named under the module when they do not answer.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/theme.dart';
import 'package:cupola/features/home/presentation/widgets/downloads_module.dart';
import 'package:cupola/features/home/presentation/home_screen.dart';
import 'package:cupola/features/services/domain/dashboard_decision.dart';
import 'package:cupola/features/services/domain/in_flight.dart';
import 'package:cupola/features/services/domain/source_coverage.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import '../../../test_helpers/decision_rows.dart';
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

/// A job somebody added to SABnzbd by hand, which SABnzbd paused because
/// its archive is encrypted.
const _sabEncrypted = WorldDownload(
  id: 'SABnzbd_nzo_encrypted1',
  release: 'Coffee.Run.Making.Of.2020.1080p',
  client: 'sabnzbd',
  state: DownloadState.heldByClient,
  progress: 0.1,
  size: _gb,
);

/// An NZB somebody added to NZBGet by hand that lost too many articles.
const _nzbgetBroken = WorldDownload(
  id: 'nzbget-hand-0001',
  release: 'Spring.2019.1080p.WEB',
  client: 'nzbget',
  state: DownloadState.failed,
  progress: 0.2,
  size: _gb,
);

/// The one torrent qBittorrent lists: a magnet in [state] for three hours,
/// with nothing received and no file list yet, as its in-flight item.
Future<ServiceQueueItem> _magnetWaiting(String state) async {
  final now = DateTime(2026, 10, 9, 20, 53);
  final harness = await ProfileHarness.start(
    Profiles.p1,
    now: now,
    overrides: [
      stallClockProvider.overrideWith(
        (ref) =>
            () => now,
      ),
    ],
  );
  const hash = 'c0ffee00c0ffee00c0ffee00c0ffee00c0ffee00';
  final since =
      now.subtract(const Duration(hours: 3)).millisecondsSinceEpoch ~/ 1000;
  harness.network.on(
    WorldIds.qbittorrent,
    'GET',
    '/api/v2/torrents/info',
    (request) => NetworkReply.json([
      {
        'hash': hash,
        'name': 'Sintel.Magnet',
        'state': state,
        'progress': 0,
        'size': 0,
        'total_size': 0,
        'dlspeed': 0,
        'upspeed': 0,
        'eta': 8640000,
        'category': '',
        'tags': '',
        'added_on': since,
        'last_activity': since,
        'num_complete': 0,
        'num_seeds': 0,
        'num_leechs': 0,
        'tracker': '',
      },
    ]),
  );
  final container = harness.container(retry: (_, _) => null);
  final inFlight = await container.read(servicesInFlightProvider.future);
  return inFlight.faults.singleWhere((item) => item.id == hash);
}

Future<ProviderContainer> _start(ConfigProfile profile) async {
  final harness = await ProfileHarness.start(profile);
  return harness.container(retry: (_, _) => null);
}

Future<ProfileHarness> _pump(
  WidgetTester tester,
  ConfigProfile profile, {
  Widget home = const HomeScreen(),
}) async {
  final harness = await ProfileHarness.start(profile);
  await tester.binding.setSurfaceSize(const Size(430, 6000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: harness.overrides,
      child: MaterialApp(theme: AppTheme.darkTheme(), home: home),
    ),
  );
  await harness.settle(tester);
  return harness;
}

/// The decision rows of [profile]: the Home leads with one line (Needs you)
/// and no longer lists them, so the row is mounted on its own.
Future<ProfileHarness> _pumpRows(WidgetTester tester, ConfigProfile profile) =>
    _pump(tester, profile, home: const Scaffold(body: ProvidedDecisionRows()));

Finder _inDownloads(Finder matching) =>
    find.descendant(of: find.byType(HomeDownloadsModule), matching: matching);

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
      // Night Shift's own record: series 2, never Cosmos Laundromat.
      expect(nightShift.title, startsWith('Night Shift · S'));
      expect(nightShift.mediaId, 2);
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

    test('P4: one peer is a peer, and one seed a seed', () async {
      final container = await _start(
        Profiles.p4.withDownloads([
          const WorldDownload(
            id: 'b2e1d4c5f6a70819304b5c6d7e8f901234567803',
            release: 'Big.Buck.Bunny.2008.720p.WEB',
            client: 'transmission',
            state: DownloadState.failed,
            progress: 0.5,
            size: _gb,
            peers: 1,
          ),
          const WorldDownload(
            id: 'a1f0c3d4e5f60718293a4b5c6d7e8f9012345613',
            release: 'Coffee.Run.2020.720p.WEB',
            client: 'qbittorrent',
            state: DownloadState.failed,
            progress: 0.5,
            size: _gb,
            peers: 1,
          ),
        ]),
      );
      final decisions = await container.read(
        dashboardDecisionSourceProvider(DecisionSource.queue).future,
      );
      String detailOf(String title) =>
          decisions.decisions.singleWhere((d) => d.title == title).detail;

      expect(detailOf('Big.Buck.Bunny.2008.720p.WEB'), contains('1 peer ·'));
      expect(detailOf('Coffee.Run.2020.720p.WEB'), contains('1 seed ·'));
    });

    testWidgets('P4 on Home: the line sums both clients', (tester) async {
      final harness = await _pump(tester, Profiles.p4);

      // qBittorrent's 22.4 MB/s and Transmission's 3: one speed, and the
      // Sonarr grab Transmission moves is counted once among the four.
      expect(
        _inDownloads(find.text('4 moving · 1 stuck · 25.4\u00A0MB/s')),
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

    test('a magnet still fetching its file list is a stall that says so, '
        'not that nobody has the file', () async {
      final magnet = await _magnetWaiting('metaDL');
      expect(magnet.service, ServiceKey.qbittorrent);
      expect(magnet.fault, InFlightFault.stalled);
      expect(magnet.awaitingMetadata, isTrue);
      expect(magnet.swarmSeeds, 0);
    });

    test('a magnet started by hand (forcedMetaDL) waits for its file list '
        'the same way', () async {
      final magnet = await _magnetWaiting('forcedMetaDL');
      expect(magnet.fault, InFlightFault.stalled);
      expect(magnet.awaitingMetadata, isTrue);
    });

    testWidgets('P1 on Home: the two broken torrents are rows of Downloads, '
        'stuck and not moving', (tester) async {
      final harness = await _pump(
        tester,
        Profiles.p1.withDownloads([_qbError, _qbMissing]),
      );

      // Big Buck Bunny's stall and the two broken torrents are stuck; the
      // four that move are the same four as without them. Sintel on the 4K
      // waits its turn in SABnzbd: it used to be counted among the moving
      // (`5 moving`) and is now said apart, after what is stuck.
      expect(
        _inDownloads(
          find.text('4 moving · 3 stuck · 1 queued · 40.4\u00A0MB/s'),
        ),
        findsOneWidget,
      );
      // Each says it failed, and carries its remedy: another download of
      // what Radarr grabbed (Coffee Run, and Big Buck Bunny's stall), and
      // the torrent nobody's arr asked for opens in its client.
      expect(_inDownloads(find.text('Failed')), findsNWidgets(2));
      expect(_inDownloads(find.text('Try another download')), findsNWidgets(2));
      expect(_inDownloads(find.text('Open in qBittorrent')), findsOneWidget);

      await harness.unmount(tester);
    });

    testWidgets('P1: the two broken torrents are listed as decisions', (
      tester,
    ) async {
      final harness = await _pumpRows(
        tester,
        Profiles.p1.withDownloads([_qbError, _qbMissing]),
      );

      expect(find.textContaining('Files missing'), findsOneWidget);

      await harness.unmount(tester);
    });
  });

  group('NZBGet', () {
    test('P4 + NZBGet, its disk full: the paused queue is a stall on the '
        'arr row it moves, in the disk\'s words', () async {
      final container = await _start(
        Profiles.p4
            .withConnection(WorldConnections.nzbget)
            .withDownloads([_nzbgetGrab])
            .withFullDisk(WorldConnections.nzbget.id),
      );
      final inFlight = await container.read(servicesInFlightProvider.future);

      final grab = inFlight.faults.singleWhere(
        (item) => item.downloadId == _nzbgetGrab.id,
      );
      expect(grab.service, ServiceKey.sonarr);
      expect(grab.clientService, ServiceKey.nzbget);
      expect(grab.fault, InFlightFault.stalled);
      expect(grab.warning, 'Disk full');
    });

    test('P4 + NZBGet: a job below its critical health is a failure, '
        'opened in NZBGet', () async {
      final container = await _start(
        Profiles.p4.withConnection(WorldConnections.nzbget).withDownloads([
          _nzbgetBroken,
        ]),
      );
      final inFlight = await container.read(servicesInFlightProvider.future);

      final broken = inFlight.faults.singleWhere(
        (item) => item.title == _nzbgetBroken.release,
      );
      expect(broken.service, ServiceKey.nzbget);
      expect(broken.fault, InFlightFault.failed);
      expect(broken.warning, 'Damaged beyond repair');

      final decisions = await container.read(
        dashboardDecisionSourceProvider(DecisionSource.queue).future,
      );
      expect(
        decisions.decisions
            .singleWhere((d) => d.title == _nzbgetBroken.release)
            .actionTarget,
        ServiceKey.nzbget,
      );
    });

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

  group('SABnzbd', () {
    test('P1, SABnzbd\'s disk full: the queue it stopped is a fault on each '
        'job, never a pause', () async {
      final container = await _start(
        Profiles.p1.withFullDisk(WorldIds.sabnzbd),
      );
      final inFlight = await container.read(servicesInFlightProvider.future);

      for (final download in [
        WorldDownloads.elephantsDream4k,
        WorldDownloads.sintel4k,
      ]) {
        final row = inFlight.faults.singleWhere(
          (item) => item.downloadId == download.id,
        );
        // Radarr 4K's row, which still says downloading, takes the fault.
        expect(row.service, ServiceKey.radarr);
        expect(row.connectionName, isNotNull);
        expect(row.fault, InFlightFault.stalled);
        expect(row.clientService, ServiceKey.sabnzbd);
      }
      expect(
        inFlight.preview.map((item) => item.clientService),
        isNot(contains(ServiceKey.sabnzbd)),
      );

      final decisions = await container.read(
        dashboardDecisionSourceProvider(DecisionSource.queue).future,
      );
      expect(
        decisions.decisions
            .where((d) => d.detail.contains('Disk full'))
            .map((d) => d.actionTarget)
            .toSet(),
        {ServiceKey.sabnzbd},
      );
    });

    test(
      'P1: a job SABnzbd paused itself is a decision in the house words; the '
      'answering queue stays in flight',
      () async {
        final container = await _start(
          Profiles.p1.withDownloads([_sabEncrypted]),
        );
        final inFlight = await container.read(servicesInFlightProvider.future);

        final held = inFlight.faults.singleWhere(
          (item) => item.id == _sabEncrypted.id,
        );
        expect(held.service, ServiceKey.sabnzbd);
        expect(held.fault, InFlightFault.stalled);
        // SABnzbd's ENCRYPTED, in the word NZBGet's own case uses.
        expect(held.warning, 'Password needed');
        expect(
          inFlight.preview.where(
            (item) => item.downloadId == WorldDownloads.elephantsDream4k.id,
          ),
          hasLength(1),
        );
      },
    );

    test('P1: a SABnzbd job shows what it weighs and how much has come, '
        'like every other client\'s', () async {
      final container = await _start(
        Profiles.p1.withDownloads([
          const WorldDownload(
            id: 'SABnzbd_nzo_byhand01',
            release: 'Agent.327.Making.Of.1080p',
            client: 'sabnzbd',
            state: DownloadState.downloading,
            progress: 0.25,
            size: 4 * _gb,
          ),
        ]),
      );
      final inFlight = await container.read(servicesInFlightProvider.future);
      final job = inFlight.preview.singleWhere(
        (item) => item.id == 'SABnzbd_nzo_byhand01',
      );

      expect(job.totalBytes, 4 * _gb);
      expect(job.doneBytes, _gb);
      expect(
        formatDoneOfTotal(doneBytes: job.doneBytes, totalBytes: job.totalBytes),
        '1.0 of 4.0\u00A0GB',
      );
    });

    testWidgets('P1 on Home, SABnzbd\'s disk full: the stops are counted '
        'under Downloads', (tester) async {
      final harness = await _pump(
        tester,
        Profiles.p1.withFullDisk(WorldIds.sabnzbd),
      );

      // Big Buck Bunny, and the two jobs the disk stopped.
      expect(_inDownloads(find.textContaining('3 stuck')), findsOneWidget);

      await harness.unmount(tester);
    });

    testWidgets('P1, SABnzbd\'s disk full: the stops are listed as one '
        'decision', (tester) async {
      final harness = await _pumpRows(
        tester,
        Profiles.p1.withFullDisk(WorldIds.sabnzbd),
      );

      // The 4K's two stops fold into one row, which keeps their shared cause.
      expect(find.textContaining('Disk full'), findsOneWidget);

      await harness.unmount(tester);
    });
  });

  group('paused on purpose', () {
    /// A Radarr grab somebody paused in qBittorrent: Radarr says paused.
    const pausedGrab = WorldDownload(
      id: 'a1f0c3d4e5f60718293a4b5c6d7e8f9012345614',
      release: 'Coffee.Run.2020.1080p.WEB',
      client: 'qbittorrent',
      state: DownloadState.paused,
      progress: 0.3,
      size: _gb,
      arr: WorldIds.radarr,
      title: WorldTitles.coffeeRun,
    );

    test('P1: a torrent paused on purpose is backlog, neither in flight nor '
        'a decision, on the arr\'s row too', () async {
      final container = await _start(Profiles.p1.withDownloads([pausedGrab]));
      final inFlight = await container.read(servicesInFlightProvider.future);

      expect(
        inFlight.preview.map((item) => item.downloadId?.toLowerCase()),
        isNot(contains(pausedGrab.id)),
      );
      expect(
        inFlight.faults.map((item) => item.downloadId?.toLowerCase()),
        isNot(contains(pausedGrab.id)),
      );
      expect(inFlight.held, 1);
      // Sprite Fright, Cosmos E4 and E5 and Elephants Dream: what was moving
      // before the pause, and nothing more. Sintel on the 4K waits its turn:
      // it was counted as moving (5) and is queued now.
      expect(inFlight.activeCount, 4);
      expect(inFlight.movingCount, 4);
      expect(inFlight.queued.map((item) => item.downloadId), [
        WorldDownloads.sintel4k.id,
      ]);
    });

    test('P1, SABnzbd paused on purpose: its jobs are held, as a paused '
        'torrent is', () async {
      final container = await _start(
        Profiles.p1.withPausedQueue(WorldIds.sabnzbd),
      );
      final inFlight = await container.read(servicesInFlightProvider.future);

      for (final download in [
        WorldDownloads.elephantsDream4k,
        WorldDownloads.sintel4k,
      ]) {
        expect(
          inFlight.preview.where((item) => item.downloadId == download.id),
          isEmpty,
        );
        expect(
          inFlight.faults.where((item) => item.downloadId == download.id),
          isEmpty,
        );
      }
      expect(inFlight.held, 2);
      expect(inFlight.activeCount, 3);
    });

    test('P4 + NZBGet paused on purpose: its job is held', () async {
      final container = await _start(
        Profiles.p4
            .withConnection(WorldConnections.nzbget)
            .withDownloads([_nzbgetGrab])
            .withPausedQueue(WorldConnections.nzbget.id),
      );
      final inFlight = await container.read(servicesInFlightProvider.future);

      expect(
        inFlight.preview.where((item) => item.downloadId == _nzbgetGrab.id),
        isEmpty,
      );
      expect(inFlight.held, 1);
    });
  });
}
