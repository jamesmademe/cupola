import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/services/domain/service_summary.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';
import 'package:cupola/features/transmission/domain/models/transmission_models.dart';
import 'package:cupola/features/transmission/presentation/transmission_overview_provider.dart';
import 'package:cupola/features/transmission/presentation/transmission_overview_screen.dart';
import 'package:cupola/features/transmission/presentation/transmission_provider.dart';

import '../../../test_helpers/settings_scope.dart';

void main() {
  testWidgets('draws the regions in the order the board draws them', (
    tester,
  ) async {
    await _pump(tester);

    // Identity and the readouts come before any region, and only this tab
    // carries them.
    expect(find.byType(ServiceOverviewIdentity), findsOneWidget);
    expect(find.byType(ServiceKpiPeek), findsOneWidget);

    // What is moving, how it is filed, how the daemon is set up, what landed.
    // The mobile board is what fixes this order: it keeps Transferring
    // immediately under the readouts and lets the rest fall below the fold.
    expect(
      tester
          .widgetList<SectionHeader>(find.byType(SectionHeader))
          .map((header) => header.title),
      ['Transferring', 'Labels', 'Session', 'Finished today'],
    );
  });

  testWidgets('each region link is named after the tab it opens', (
    tester,
  ) async {
    await _pump(tester);

    expect(
      tester
          .widgetList<SectionHeader>(find.byType(SectionHeader))
          .map((header) => header.semanticHint),
      [
        'opens the Transmission Queue tab',
        'opens the Transmission Labels tab',
        'opens the Transmission Session tab',
        // Finished today has no link: the board labels it `History`, and
        // Transmission's bar has no History tab to open.
        null,
      ],
    );
  });

  testWidgets('the queue rows are drawn on the shared plate', (tester) async {
    await _pump(tester);

    // Not a private row shape rebuilt for the Overview: this is the one plate
    // every download client's queue row is drawn on.
    expect(find.byType(DownloadQueueTile), findsNWidgets(3));
  });

  testWidgets('the Transferring subtitle counts the whole queue', (
    tester,
  ) async {
    await _pump(tester);

    expect(find.text('1 downloading · 2 seeding'), findsOneWidget);
  });

  testWidgets('a queue that never answered counts nothing, not zero', (
    tester,
  ) async {
    await _pump(tester, failTorrents: true);

    expect(find.text('—'), findsWidgets);
    // The figure the failure would otherwise invent.
    expect(find.text('0 downloading · 0 seeding'), findsNothing);
  });

  testWidgets('free space nobody could measure reads an em dash, not 0 B', (
    tester,
  ) async {
    await _pump(tester, freeSpace: null);

    expect(find.text('Free space · —'), findsOneWidget);
    expect(find.text('0\u00A0B'), findsNothing);
    // Spoken as one sentence, with the path still attached: a free-space figure
    // with no path is a number about an unnamed disk.
    expect(find.semantics.byLabel('Free space, —, /downloads'), findsOneWidget);
  });

  testWidgets('free space the daemon did report is printed', (tester) async {
    // The other half of the em-dash rule: the dash has to mean "not measured"
    // and not "this row never prints a figure".
    await _pump(tester, freeSpace: 2 * 1024 * 1024 * 1024 * 1024);

    expect(
      find.semantics.byLabel('Free space, 2.0\u00A0TB, /downloads'),
      findsOneWidget,
    );
  });

  testWidgets('a finished row speaks as one sentence', (tester) async {
    await _pump(tester);

    expect(
      find.semantics.byLabel(
        RegExp(r'^Past\.Lives\.2023, 6\.0\u00A0GB, .+, seeding, ratio 1\.40$'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('a label row speaks its count as a noun', (tester) async {
    await _pump(tester);

    expect(find.semantics.byLabel('movies, 2 torrents'), findsOneWidget);
    expect(find.text('movies'), findsOneWidget);
  });

  testWidgets('the identity block says Answering, never Online', (
    tester,
  ) async {
    await _pump(tester);

    expect(
      find.semantics.byLabel(
        'Transmission, transmission.test:9091, v4.0.6, Answering',
      ),
      findsOneWidget,
    );
    expect(find.text('Online'), findsNothing);
  });

  testWidgets('slow mode is drawn as a state, never as an alarm', (
    tester,
  ) async {
    await _pump(tester, altSpeedEnabled: true);

    expect(
      find.semantics.byLabel('Slow mode, On, alternative limits are in force'),
      findsOneWidget,
    );
  });

  testWidgets('a Session value is prose, so it never rides the figure slot', (
    tester,
  ) async {
    await _pump(tester);

    // `ServiceOverviewRow.trailing` is 132pt wide, one line, ellipsised:
    // shaped for Prowlarr's `298 queries`. Every value in this region is a
    // phrase, and at 3× reading size that slot holds about seven characters,
    // so `Not limited` would ellipsise to nothing while being the row's whole
    // content. They ride the title line instead, which wraps.
    final sessionRows = tester
        .widgetList<ServiceOverviewRow>(find.byType(ServiceOverviewRow))
        .where((row) => row.title.contains(' · '))
        .toList();

    expect(find.text('Download limit · 4096\u00A0KB/s'), findsOneWidget);
    expect(find.text('Upload limit · Not limited'), findsOneWidget);
    expect(sessionRows, hasLength(4));
    for (final row in sessionRows) {
      expect(
        row.trailing,
        isNull,
        reason: '${row.title} is prose, not a figure',
      );
    }
  });

  testWidgets('the Labels header counts the queue, not the six rows drawn', (
    tester,
  ) async {
    // Five more on top of the fixture's own two: seven labels in use, six rows
    // of room.
    await _pump(tester, labelCount: 5);

    // The cap is applied in the screen and the count is read off the whole
    // list, which is the only arrangement where the subtitle is true: a
    // seventh label is reported even though it is not drawn.
    expect(find.byIcon(Icons.sell_outlined), findsNWidgets(6));
    expect(
      tester
          .widgetList<SectionHeader>(find.byType(SectionHeader))
          .firstWhere((header) => header.title == 'Labels')
          .subtitle,
      '7',
    );
  });

  testWidgets('a region whose source failed does not take the page with it', (
    tester,
  ) async {
    await _pump(tester, failSession: true);

    // The Session region says so in its own slot…
    expect(find.byType(InlineErrorRetry), findsOneWidget);
    expect(
      find.textContaining(", so its session settings are not shown."),
      findsOneWidget,
    );
    // …and the other three still drew their headings and their rows.
    expect(find.byType(SectionHeader), findsNWidgets(4));
    expect(find.byType(DownloadQueueTile), findsNWidgets(3));
  });

  testWidgets('nothing overflows at an accessibility reading size', (
    tester,
  ) async {
    await _pump(tester, textScaleFactor: 3.0);

    // A `RenderFlex overflowed` is thrown, not merely painted, under test.
    expect(tester.takeException(), isNull);
  });

  testWidgets('a Transmission that was never set up gets its own door', (
    tester,
  ) async {
    await _pump(tester, configured: false);

    final placeholder = tester.widget<NotConfiguredPlaceholder>(
      find.byType(NotConfiguredPlaceholder),
    );
    expect(placeholder.service, ServiceKey.transmission);
    // No region was built, which is the point: the screen asks settings before
    // it watches a provider, so nothing reached `transmissionClientProvider` to
    // throw "not configured" and leave a failed provider retrying on a timer.
    expect(find.byType(SectionHeader), findsNothing);
    expect(find.byType(ServiceKpiPeek), findsNothing);
  });
}

// ─── Harness ────────────────────────────────────────────────────────────────

/// A torrent through `fromJson`, which is the only constructor production uses
/// and the one that applies the `-1` sentinels.
TransmissionTorrent _torrent({
  required int id,
  required String name,
  int status = 6,
  int rateDownload = 0,
  int rateUpload = 0,
  int queuePosition = 0,
  List<String> labels = const [],
  int doneDate = 0,
  int totalSize = 1024 * 1024 * 1024,
  double uploadRatio = 1.4,
}) {
  return TransmissionTorrent.fromJson({
    'id': id,
    'hashString': 'hash$id',
    'name': name,
    'status': status,
    'percentDone': status == 4 ? 0.61 : 1.0,
    'totalSize': totalSize,
    'sizeWhenDone': totalSize,
    'leftUntilDone': status == 4 ? totalSize ~/ 3 : 0,
    'rateDownload': rateDownload,
    'rateUpload': rateUpload,
    'queuePosition': queuePosition,
    'uploadRatio': uploadRatio,
    'labels': labels,
    'doneDate': doneDate,
  });
}

Future<void> _pump(
  WidgetTester tester, {
  bool configured = true,
  bool failTorrents = false,
  bool failSession = false,
  bool altSpeedEnabled = false,
  int? freeSpace,
  int labelCount = 0,
  double textScaleFactor = 1.0,
}) async {
  await tester.binding.setSurfaceSize(const Size(420, 3200));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  // Two hours ago, but never before local midnight: "finished today" is the
  // rule under test, so a fixture that slid into yesterday in the first two
  // hours of the day made the suite fail by the clock.
  final now = DateTime.now();
  final midnight = DateTime(now.year, now.month, now.day);
  final twoHoursAgo = now.subtract(const Duration(hours: 2));
  final doneToday = twoHoursAgo.isBefore(midnight) ? midnight : twoHoursAgo;

  final torrents = [
    _torrent(
      id: 1,
      name: 'Dune.Part.Three.2026',
      status: 4,
      rateDownload: 2600000,
      queuePosition: 0,
      labels: const ['movies'],
    ),
    _torrent(
      id: 2,
      name: 'ubuntu-24.04.3-live-server-amd64.iso',
      rateUpload: 380000,
      queuePosition: 1,
      labels: const ['linux-iso'],
    ),
    _torrent(
      id: 3,
      name: 'Past.Lives.2023',
      queuePosition: 2,
      labels: const ['movies'],
      totalSize: 6 * 1024 * 1024 * 1024,
      doneDate: doneToday.millisecondsSinceEpoch ~/ 1000,
    ),
    // One torrent per extra label, so the Labels region has more of them than
    // it draws. Filed under `zz-` so they sort last and the fixture's own two
    // labels keep their rows.
    for (var i = 0; i < labelCount; i++)
      _torrent(
        id: 100 + i,
        name: 'filed-$i',
        queuePosition: 100 + i,
        labels: ['zz-label-$i'],
      ),
  ];

  final session = TransmissionSession.fromJson({
    'version': '4.0.6',
    'rpc-version': 17,
    'download-dir': '/downloads',
    'alt-speed-enabled': altSpeedEnabled,
    'speed-limit-down': 4096,
    'speed-limit-down-enabled': true,
    'speed-limit-up': 1024,
    'speed-limit-up-enabled': false,
  });

  await tester.pumpWidget(
    ProviderScope(
      // Riverpod 3 re-runs a failed provider on an exponential backoff, so one
      // `pumpAndSettle` would otherwise watch a deliberately failing region
      // retry a dozen times and never settle.
      retry: (_, _) => null,
      overrides: [
        currentSettingsProvider.overrideWith(
          (ref) => configured
              ? settingsWith(
                  transmissionUrl: 'http://transmission.test:9091',
                  transmissionUsername: 'user',
                  transmissionPassword: 'secret',
                )
              : const SettingsModel(),
        ),
        // Overridden whole rather than through a client factory: the
        // Transmission branch of `_loadVersion` builds its own
        // `TransmissionClient` with no injection point, so an un-overridden
        // summary would spend eight seconds failing to reach a host that does
        // not exist.
        serviceSummaryProvider(ServiceKey.transmission).overrideWith(
          (ref) async => const ServiceSummary(
            service: ServiceKey.transmission,
            status: ServiceSummaryStatus.online,
            host: 'transmission.test',
            version: '4.0.6',
          ),
        ),
        transmissionTorrentsProvider.overrideWith((ref) async {
          if (failTorrents) throw Exception('torrent-get failed');
          return torrents;
        }),
        transmissionSessionProvider.overrideWith((ref) async {
          if (failSession) throw Exception('session-get failed');
          return session;
        }),
        transmissionStatsProvider.overrideWith(
          (ref) async => TransmissionStats.fromJson({
            'downloadSpeed': 2600000,
            'uploadSpeed': 380000,
            'torrentCount': torrents.length,
            'activeTorrentCount': 2,
            'pausedTorrentCount': 0,
          }),
        ),
        // Overridden rather than left to derive, because the real one reaches
        // for `transmissionClientProvider`, which in a test has no daemon to
        // ask and, unconfigured, throws. The chain itself (session-get before
        // free-space, the empty path that is never asked, the refusal that
        // costs one figure, the zero that is silence) is driven through a
        // real container over a scripted client in
        // transmission_overview_provider_test.dart, so overriding it here
        // stubs a tested fetch rather than hiding an untested one.
        transmissionFreeSpaceProvider.overrideWith((ref) async => freeSpace),
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
        home: const TransmissionOverviewScreen(topPadding: 0),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
