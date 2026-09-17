import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/models/service_kpi.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/qbittorrent/domain/models/torrent.dart';
import 'package:cupola/features/qbittorrent/domain/models/transfer_info.dart';
import 'package:cupola/features/qbittorrent/presentation/qbittorrent_overview_screen.dart';
import 'package:cupola/features/qbittorrent/presentation/qbittorrent_provider.dart';
import 'package:cupola/features/services/domain/service_summary.dart';
import 'package:cupola/features/services/presentation/service_kpi_provider.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';

import '../../../test_helpers/settings_scope.dart';

void main() {
  testWidgets('draws the regions in the order the board draws them', (
    tester,
  ) async {
    await _pump(tester);

    // Identity and the readouts come before any section, and only this tab
    // carries them.
    expect(find.byType(ServiceKpiPeek), findsOneWidget);

    // What is broken first, then what is moving, then how it is filed, then
    // what the session has done.
    expect(
      tester
          .widgetList<SectionHeader>(find.byType(SectionHeader))
          .map((header) => header.title),
      ['Needs attention', 'Queue', 'Categories', 'Session'],
    );

    // RSS is absent rather than stubbed: no `/api/v2/rss/*` call exists in
    // this client, and the tab bar is where that work belongs.
    expect(find.text('RSS'), findsNothing);
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
        'opens the qBittorrent Queue tab',
        'opens the qBittorrent Queue tab',
        // Categories and Session have nowhere to go: qBittorrent's bar is
        // Overview, Queue and RSS, and a link named after a tab that does not
        // exist is a promise the app cannot keep.
        null,
        null,
      ],
    );
  });

  testWidgets('the identity block says Answering, never Online', (
    tester,
  ) async {
    await _pump(tester);

    expect(
      find.semantics.byLabel('qBittorrent, qbit.lan:8080, v5.0.4, Answering'),
      findsOneWidget,
    );
    expect(find.text('Online'), findsNothing);
  });

  testWidgets(
    'an unreachable qBittorrent reads Unreachable, and its version is —',
    (tester) async {
      await _pump(tester, online: false);

      expect(
        find.semantics.byLabel('qBittorrent, qbit.lan:8080, —, Unreachable'),
        findsOneWidget,
      );
    },
  );

  testWidgets('a stalled torrent is a fault and speaks one sentence', (
    tester,
  ) async {
    await _pump(
      tester,
      torrents: [
        _torrent(
          name: 'The.Zone.of.Interest.2023',
          state: 'stalledDL',
          progress: 0.18,
          seeders: 3,
          lastActivity:
              DateTime.now()
                  .subtract(const Duration(minutes: 42))
                  .millisecondsSinceEpoch ~/
              1000,
        ),
      ],
    );

    // One node for the whole row, with the layout's dots read as pauses — not
    // four fragments a screen reader walks separately.
    expect(
      find.semantics.byLabel(
        'Stalled, The.Zone.of.Interest.2023, 18%, idle 42 min, 3 seeds',
      ),
      findsOneWidget,
    );
  });

  testWidgets('the attention header counts every fault, not the rows it drew', (
    tester,
  ) async {
    await _pump(
      tester,
      torrents: [
        for (var i = 0; i < 7; i++)
          _torrent(name: 'Stalled.$i', state: 'stalledDL'),
        _torrent(name: 'Errored.0', state: 'error'),
        _torrent(name: 'Gone.0', state: 'missingFiles'),
      ],
    );

    // Nine faults, four rows. The header is the only place the other five are
    // reported, so it prints the census — not the length of the sample below
    // it, which would tell a user with nine broken torrents they had four.
    final header = tester.widget<SectionHeader>(
      find.widgetWithText(SectionHeader, 'Needs attention'),
    );
    expect(header.subtitle, '9');
    // Four rows, in the worst-first order the fault kinds declare.
    expect(find.textContaining('Errored · '), findsOneWidget);
    expect(find.textContaining('Missing files · '), findsOneWidget);
    expect(find.textContaining('Stalled · '), findsNWidgets(2));
  });

  testWidgets('a paused torrent is backlog: it is counted, never flagged', (
    tester,
  ) async {
    await _pump(
      tester,
      torrents: [
        _torrent(name: 'Paused.Release', state: 'pausedDL', progress: 0.4),
        _torrent(name: 'Moving', state: 'downloading', progress: 0.6),
      ],
    );

    // Not in Needs attention…
    expect(find.text('Needs attention'), findsOneWidget);
    expect(find.textContaining('Paused.Release'), findsNothing);
    // …and not in the queue preview either, but present in the census the
    // header prints, as a plain figure in the ordinary ink.
    expect(
      find.text('2 torrents · 1 downloading · 0 seeding · 1 paused'),
      findsOneWidget,
    );
  });

  testWidgets('a fresh session reads — for its ratio, never 0.00', (
    tester,
  ) async {
    await _pump(
      tester,
      transfer: const TransferInfo(
        dlSpeed: 0,
        upSpeed: 0,
        dlInfoData: 0,
        upInfoData: 4096,
        dlRateLimit: 0,
        upRateLimit: 0,
        altSpeedEnabled: false,
      ),
    );

    expect(find.semantics.byLabel('Session ratio, —'), findsOneWidget);
    // And the global 0 sentinel is "no limit", never a bare 0 that reads as a
    // link throttled to nothing.
    expect(find.semantics.byLabel('Download limit, no limit'), findsOneWidget);
  });

  testWidgets('a fresh daemon downloaded 0 B, and says so', (tester) async {
    await _pump(
      tester,
      transfer: const TransferInfo(
        dlSpeed: 0,
        upSpeed: 0,
        dlInfoData: 0,
        upInfoData: 0,
        dlRateLimit: 0,
        upRateLimit: 0,
        altSpeedEnabled: false,
      ),
    );

    // `/transfer/info` answered, and its answer was zero. An em dash here would
    // claim the call failed while five rows beside it prove it did not.
    expect(
      find.semantics.byLabel('Downloaded this session, 0 B'),
      findsOneWidget,
    );
    expect(
      find.semantics.byLabel('Uploaded this session, 0 B'),
      findsOneWidget,
    );
  });

  testWidgets('a session row leads with the figure, not with its label', (
    tester,
  ) async {
    await _pump(tester);

    // The inverse of the other three regions on purpose: Session has no
    // subject, so the figure is the content and the label is the chrome. Put
    // the other way round it would be six captions at full ink with their
    // answers dimmed at the right margin, capped at 132pt.
    final row = tester.widget<ServiceOverviewRow>(
      find.widgetWithText(ServiceOverviewRow, 'Downloaded this session'),
    );
    expect(row.title, '1.00 MB');
    expect(row.detail, 'Downloaded this session');
    expect(row.trailing, isNull);
  });

  testWidgets('a section whose source has not answered prints — not 0', (
    tester,
  ) async {
    await _pump(tester, failTorrents: true);

    // Never "0" over a question nobody got an answer to: the reading the user
    // would act on is the opposite one.
    expect(find.text('0'), findsNothing);
    expect(find.text('—'), findsWidgets);
  });

  testWidgets('a section whose source failed does not take the page with it', (
    tester,
  ) async {
    await _pump(tester, failTransfer: true);

    // The failed region says so in its own slot…
    expect(find.byType(AppErrorState), findsOneWidget);
    // …and the other three still drew their headings.
    expect(find.byType(SectionHeader), findsNWidgets(4));
  });

  testWidgets('nothing overflows at an accessibility reading size', (
    tester,
  ) async {
    await _pump(
      tester,
      textScaleFactor: 3.0,
      torrents: [
        _torrent(
          name:
              'A.Torrent.With.An.Extremely.Long.Scene.Release.Name.2160p.UHD.'
              'BluRay.REMUX.HDR.DV.TrueHD.7.1.Atmos-GROUP',
          state: 'downloading',
          category: 'movies',
          progress: 0.92,
          size: 15 * 1024 * 1024 * 1024,
          dlSpeed: 8 * 1024 * 1024,
        ),
      ],
    );

    // A `RenderFlex overflowed` is thrown, not merely painted, under test.
    expect(tester.takeException(), isNull);
  });

  testWidgets('a qBittorrent that was never set up gets its own door', (
    tester,
  ) async {
    await _pump(tester, configured: false);

    final placeholder = tester.widget<NotConfiguredPlaceholder>(
      find.byType(NotConfiguredPlaceholder),
    );
    expect(placeholder.service, ServiceKey.qbittorrent);
    // Nothing behind the door was built, which is the point: every provider on
    // this page throws "not configured", and a provider that throws is a
    // *failed* provider retrying on a backoff for a condition no waiting
    // changes. A pending timer here would be the tell.
    expect(find.byType(SectionHeader), findsNothing);
  });
}

// ─── Harness ────────────────────────────────────────────────────────────────

Future<void> _pump(
  WidgetTester tester, {
  List<Torrent> torrents = const [],
  TransferInfo transfer = const TransferInfo(
    dlSpeed: 0,
    upSpeed: 0,
    dlInfoData: 1024 * 1024,
    upInfoData: 2 * 1024 * 1024,
    dlRateLimit: 0,
    upRateLimit: 0,
    altSpeedEnabled: false,
  ),
  bool failTorrents = false,
  bool failTransfer = false,
  bool online = true,
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
                  qbittorrentUrl: 'http://qbit.lan:8080',
                  qbittorrentUsername: 'admin',
                  qbittorrentPassword: 'secret',
                )
              : const SettingsModel(),
        ),
        // The one fetch every region but Session is folded from.
        allTorrentsProvider.overrideWith((ref) async {
          if (failTorrents) throw Exception('torrents failed');
          return torrents;
        }),
        transferInfoProvider.overrideWith((ref) async {
          if (failTransfer) throw Exception('transfer failed');
          return transfer;
        }),
        serviceSummaryProvider.overrideWith(
          (ref, service) async => ServiceSummary(
            service: service,
            status: online
                ? ServiceSummaryStatus.online
                : ServiceSummaryStatus.offline,
            host: 'qbit.lan:8080',
            version: online ? '5.0.4' : null,
          ),
        ),
        // The readout rail is not what these tests are about, and it reads the
        // torrent list through a provider of its own.
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
        home: const QbittorrentOverviewScreen(topPadding: 0),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// A torrent as `/torrents/info` would answer with it.
Torrent _torrent({
  String name = 'torrent',
  String state = 'downloading',
  double progress = 0.5,
  int size = 1024,
  String category = '',
  int dlSpeed = 0,
  int upSpeed = 0,
  int seeders = 0,
  int lastActivity = 0,
}) {
  return Torrent(
    hash: name,
    name: name,
    size: size,
    progress: progress,
    state: state,
    parsedState: TorrentState.fromString(state),
    dlSpeed: dlSpeed,
    upSpeed: upSpeed,
    eta: 0,
    category: category,
    tracker: '',
    tags: const [],
    ratio: 0,
    addedOn: 0,
    completed: 0,
    leechers: 0,
    seeders: seeders,
    lastActivity: lastActivity,
  );
}
