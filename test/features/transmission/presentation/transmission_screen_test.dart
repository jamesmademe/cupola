import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/models/service_kpi.dart';
import 'package:cupola/core/widgets/section_header.dart';
import 'package:cupola/features/services/domain/service_summary.dart';
import 'package:cupola/features/services/presentation/service_kpi_provider.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/transmission/domain/models/transmission_models.dart';
import 'package:cupola/features/transmission/presentation/transmission_provider.dart';
import 'package:cupola/features/transmission/presentation/transmission_screen.dart';

import '../../../test_helpers/settings_scope.dart';

final _configured = settingsWith(
  transmissionUrl: 'https://transmission.test',
  transmissionUsername: 'user',
  transmissionPassword: 'secret',
);

/// Status 4 is downloading, 6 is seeding.
TransmissionTorrent _torrent(int id, {required int status}) {
  return TransmissionTorrent.fromJson({
    'id': id,
    'hashString': 'hash$id',
    'name': '${status == 4 ? 'Download' : 'Seed'} $id',
    'status': status,
    'percentDone': status == 4 ? 0.4 : 1.0,
    'totalSize': 1024 * 1024 * 1024,
    'sizeWhenDone': 1024 * 1024 * 1024,
    'leftUntilDone': status == 4 ? 512 * 1024 * 1024 : 0,
    'rateDownload': 0,
    'rateUpload': 0,
    'eta': -1,
    'uploadRatio': 1.0,
  });
}

List<Override> _ambient() => [
  currentSettingsProvider.overrideWith((ref) => _configured),
  serviceSummaryProvider.overrideWith(
    (ref, service) async => ServiceSummary(
      service: service,
      status: ServiceSummaryStatus.online,
      host: 'transmission.test',
      version: '4.0.6',
    ),
  ),
  serviceKpiProvider.overrideWith((ref, service) async => const <ServiceKpi>[]),
  transmissionSessionProvider.overrideWith(
    (ref) async => TransmissionSession.fromJson(const {
      'version': '4.0.6',
      'rpc-version': 17,
    }),
  ),
];

Future<void> _pump(WidgetTester tester, List<Override> overrides) async {
  await tester.pumpWidget(
    ProviderScope(
      retry: (_, _) => null,
      overrides: [..._ambient(), ...overrides],
      child: const MaterialApp(home: TransmissionScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

String? _subtitleOf(WidgetTester tester, String title) {
  return tester
      .widget<SectionHeader>(
        find.byWidgetPredicate((w) => w is SectionHeader && w.title == title),
      )
      .subtitle;
}

void main() {
  group('transmissionTorrentCountLabel', () {
    test('states the count, and nothing while there is nothing to count', () {
      expect(transmissionTorrentCountLabel(null), isNull);
      expect(transmissionTorrentCountLabel(0), '0 torrents');
      expect(transmissionTorrentCountLabel(1), '1 torrent');
      expect(transmissionTorrentCountLabel(8), '8 torrents');
    });
  });

  // OPS-02. The Queue tab drew `take(5)` transfers and `take(10)` seeds with no
  // count and no way to reach the rest: eight downloads read as five.
  testWidgets('every transfer and every seed is reachable, with its count', (
    tester,
  ) async {
    final torrents = [
      for (var i = 1; i <= 8; i++) _torrent(i, status: 4),
      for (var i = 101; i <= 112; i++) _torrent(i, status: 6),
    ];
    await _pump(tester, [
      transmissionTorrentsProvider.overrideWith((ref) async => torrents),
    ]);

    expect(_subtitleOf(tester, 'Transferring'), '8 torrents');

    final list = find.byType(Scrollable).first;
    // The sixth to eighth transfers and the eleventh and twelfth seeds were
    // exactly the rows the old caps cut off.
    for (final name in ['Download 6', 'Download 8']) {
      await tester.scrollUntilVisible(find.text(name), 200, scrollable: list);
      expect(find.text(name), findsOneWidget);
    }
    await tester.scrollUntilVisible(
      find.text('Seeding and idle'),
      200,
      scrollable: list,
    );
    expect(_subtitleOf(tester, 'Seeding and idle'), '12 torrents');
    for (final name in ['Seed 111', 'Seed 112']) {
      await tester.scrollUntilVisible(find.text(name), 200, scrollable: list);
      expect(find.text(name), findsOneWidget);
    }
  });

  testWidgets('the rows are built lazily, not all at once', (tester) async {
    // A seedbox is two thousand seeds. Inside a `Column` every one was built
    // and laid out per rebuild; the sliver builds what is on screen.
    final torrents = [for (var i = 1; i <= 400; i++) _torrent(i, status: 6)];
    await _pump(tester, [
      transmissionTorrentsProvider.overrideWith((ref) async => torrents),
    ]);

    expect(_subtitleOf(tester, 'Seeding and idle'), '400 torrents');
    expect(find.text('Seed 400', skipOffstage: false), findsNothing);
  });

  testWidgets('a list still loading states no count, never zero', (
    tester,
  ) async {
    final gate = Completer<List<TransmissionTorrent>>();
    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: [
          ..._ambient(),
          transmissionTorrentsProvider.overrideWith((ref) => gate.future),
        ],
        child: const MaterialApp(home: TransmissionScreen()),
      ),
    );
    await tester.pump();

    expect(_subtitleOf(tester, 'Transferring'), isNull);
    expect(_subtitleOf(tester, 'Seeding and idle'), isNull);
    expect(find.textContaining('0 torrents'), findsNothing);

    gate.complete([_torrent(1, status: 4)]);
    await tester.pumpAndSettle();
    expect(_subtitleOf(tester, 'Transferring'), '1 torrent');
    expect(_subtitleOf(tester, 'Seeding and idle'), '0 torrents');
  });
}
