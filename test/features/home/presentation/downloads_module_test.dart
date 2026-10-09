import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/theme.dart';
import 'package:cupola/features/home/presentation/widgets/downloads_module.dart';
import 'package:cupola/features/services/domain/arr_import.dart';
import 'package:cupola/features/services/domain/in_flight.dart';
import 'package:cupola/features/services/domain/source_coverage.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import '../../../test_helpers/settings_scope.dart';

ServiceQueueItem _item(
  String title, {
  ServiceKey service = ServiceKey.radarr,
  String id = '7',
  double? progress = 0.5,
  int? eta = 600,
  InFlightFault? fault,
  ServiceKey? client,
}) => ServiceQueueItem(
  service: service,
  id: id,
  title: title,
  progress: progress,
  clientLabel: 'qBittorrent',
  etaSeconds: eta,
  fault: fault,
  clientService: client,
);

ServicesInFlight _inFlight({
  List<ServiceQueueItem> moving = const [],
  List<ServiceQueueItem> queued = const [],
  List<ServiceQueueItem> faults = const [],
  int? rate,
  SourceCoverage coverage = SourceCoverage.none,
}) => (
  preview: moving,
  activeCount: moving.length,
  movingCount: moving.length,
  queued: queued,
  faults: faults,
  held: 0,
  rateBytesPerSecond: rate,
  clients: rate == null ? 0 : 1,
  coverage: coverage,
);

/// Downloads on the Home: what moves, what is stuck with its remedy, and the
/// calm line when nothing moves.
void main() {
  Future<void> pump(
    WidgetTester tester,
    ServicesInFlight inFlight, {
    List<ServiceKey> configured = const [
      ServiceKey.radarr,
      ServiceKey.qbittorrent,
    ],
    ArrHistory? history,
  }) async {
    tester.view.physicalSize = const Size(1170, 3000);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...await settingsScopeOverrides(configured: configured),
          servicesInFlightProvider.overrideWith((ref) async => inFlight),
          servicesArrHistoryProvider.overrideWith(
            (ref) async =>
                history ??
                (
                  entries: const <ArrHistoryEntry>[],
                  coverage: SourceCoverage.none,
                ),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.darkTheme(),
          home: const Scaffold(
            body: SingleChildScrollView(child: HomeDownloadsModule()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('what moves, then the stuck one in amber with Try another '
      'download and More', (tester) async {
    await pump(
      tester,
      _inFlight(
        moving: [
          _item('Sprite Fright', id: '1', client: ServiceKey.qbittorrent),
        ],
        faults: [
          _item(
            'Big Buck Bunny',
            id: '2',
            progress: 0.47,
            fault: InFlightFault.stalled,
            client: ServiceKey.qbittorrent,
          ),
          _item('Cosmos', id: '3', fault: InFlightFault.needsImport),
        ],
        rate: 1000000,
      ),
    );

    expect(find.textContaining(RegExp(r'^1 moving · 1 stuck · ')), findsOne);
    expect(find.text('Stuck at 47%'), findsOne);
    expect(find.text('50% · 10\u00A0min'), findsOne);
    // The blocked import is no download: named once, and left to Needs you.
    expect(find.text('Cosmos'), findsNothing);
    expect(find.text('1 needs a manual import · in Needs you'), findsOne);
    expect(
      tester.getTopLeft(find.text('Sprite Fright')).dy,
      lessThan(tester.getTopLeft(find.text('Big Buck Bunny')).dy),
    );

    expect(find.text('Try another download'), findsOne);
    await tester.tap(find.byTooltip('More for Big Buck Bunny'));
    await tester.pumpAndSettle();
    expect(find.text('Open in qBittorrent'), findsOne);
    expect(find.text('Remove'), findsOne);
  });

  testWidgets('what waits its turn is counted after what is stuck, and is no '
      'row of the module', (tester) async {
    await pump(
      tester,
      _inFlight(
        moving: [
          _item('Sprite Fright', id: '1', client: ServiceKey.qbittorrent),
        ],
        queued: [
          ServiceQueueItem(
            service: ServiceKey.radarr,
            id: '5',
            title: 'Sintel',
            progress: 0,
            clientLabel: 'SABnzbd',
            queued: true,
          ),
        ],
        rate: 1000000,
      ),
    );

    expect(find.textContaining(RegExp(r'^1 moving · 1 queued · ')), findsOne);
    expect(find.text('Sprite Fright'), findsOne);
    expect(find.text('Sintel'), findsNothing);
  });

  testWidgets('Try another download asks before it blocklists', (tester) async {
    await pump(
      tester,
      _inFlight(faults: [_item('Big Buck Bunny', fault: InFlightFault.failed)]),
    );
    expect(find.text('Failed'), findsOne);
    await tester.tap(find.text('Try another download'));
    await tester.pumpAndSettle();
    expect(find.text('Try another download?'), findsOne);
  });

  testWidgets('a torrent no arr asked for offers its client alone', (
    tester,
  ) async {
    await pump(
      tester,
      _inFlight(
        faults: [
          _item(
            'ubuntu-24.04.iso',
            service: ServiceKey.qbittorrent,
            id: 'abc',
            fault: InFlightFault.stalled,
            client: ServiceKey.qbittorrent,
          ),
        ],
      ),
    );
    expect(find.text('Open in qBittorrent'), findsOne);
    expect(find.text('Try another download'), findsNothing);
  });

  testWidgets('without a download client the speed is not guessed, and the '
      'module says where it comes from', (tester) async {
    await pump(
      tester,
      _inFlight(moving: [_item('Sprite Fright')]),
      configured: const [ServiceKey.radarr],
    );
    expect(find.text('1 moving'), findsOne);
    expect(find.text('Speeds come from your download client'), findsOne);
  });

  testWidgets('nothing moving: the calm line and when the last download '
      'finished', (tester) async {
    final today = DateTime.now();
    final at = DateTime(today.year, today.month, today.day, 0, 1);
    await pump(
      tester,
      _inFlight(),
      history: (
        entries: [
          ArrHistoryEntry(
            service: ServiceKey.radarr,
            id: 1,
            mediaId: 1,
            title: 'Spring',
            unitId: null,
            detail: '',
            posterUrl: '',
            outcome: ArrImportOutcome.imported,
            at: at,
            reason: null,
          ),
        ],
        coverage: SourceCoverage.none,
      ),
    );
    expect(find.text('Nothing moving'), findsOne);
    expect(find.text('Nothing is downloading'), findsOne);
    expect(find.text('The last download finished at 00:01.'), findsOne);
    expect(find.text('Activity'), findsOne);
  });
}
