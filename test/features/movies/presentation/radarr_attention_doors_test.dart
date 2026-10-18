/// Radarr's Needs attention leads where the fault is fixed: one stuck download
/// opens that download's own page, several are one row that opens the Queue
/// tab, and the backlog opens Wanted, which lists it.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/movies/presentation/radarr_overview_screen.dart';
import 'package:cupola/features/services/domain/service_tab.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import '../../../test_helpers/overview_shell.dart';
import '../../../test_helpers/profiles/profiles.dart';

/// A stalled record of Radarr's queue, as the \*arr sends one.
Map<String, Object?> _stalled(int id, String title, String hash) => {
  'id': id,
  'movieId': id,
  'movie': {'id': id, 'title': title, 'tmdbId': 100 + id},
  'title': '$title.2021.1080p.WEB',
  'status': 'warning',
  'trackedDownloadStatus': 'warning',
  'trackedDownloadState': 'downloading',
  'statusMessages': [
    {
      'title': title,
      'messages': ['The download is stalled with no connections'],
    },
  ],
  'errorMessage': 'The download is stalled with no connections',
  'added': DateTime.now().toUtc().toIso8601String(),
  'downloadId': hash,
  'downloadClient': 'qBittorrent',
  'size': 1000,
  'sizeleft': 500,
};

Future<(ProfileHarness, OverviewShell)> _pump(
  WidgetTester tester, {
  List<Map<String, Object?>>? queue,
}) async {
  final harness = await ProfileHarness.start(Profiles.p1);
  if (queue != null) {
    harness.network.on(
      WorldIds.radarr,
      'GET',
      '/api/v3/queue',
      (request) => NetworkReply.json({
        'page': 1,
        'pageSize': 200,
        'totalRecords': queue.length,
        'records': queue,
      }),
    );
  }
  harness.network.followFakeTime(tester.binding);
  await tester.binding.setSurfaceSize(const Size(430, 2600));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final shell = OverviewShell(
    ServiceKey.radarr,
    const RadarrOverviewScreen(topPadding: 0),
  );
  await tester.pumpWidget(
    ProviderScope(overrides: harness.overrides, child: shell.app),
  );
  await harness.settle(tester);
  return (harness, shell);
}

void main() {
  testWidgets('P1: the stuck download opens its own page, on the connection '
      'that listed it', (tester) async {
    final (harness, shell) = await _pump(tester);

    final row = find.textContaining('Stuck · Big Buck Bunny');
    expect(row, findsOneWidget);
    expect(
      find.semantics.byLabel(RegExp(r'^Stuck, Big Buck Bunny, ')),
      containsSemantics(
        isButton: true,
        hasTapAction: true,
        hint: 'opens this download',
      ),
    );

    await tester.tap(row);
    await harness.settle(tester);

    // The \*arr records the torrent's hash upper-cased; the page reads it
    // whatever the case.
    expect(
      shell.location,
      '/activity/download?i=${WorldIds.radarr}'
      '&id=${WorldDownloads.bigBuckBunny.id.toUpperCase()}',
    );

    await harness.unmount(tester);
  });

  testWidgets('P1: several stuck downloads are one row, and its door is the '
      'Queue tab', (tester) async {
    final (harness, shell) = await _pump(
      tester,
      queue: [
        _stalled(1, 'Sprite Fright', 'AAA1'),
        _stalled(2, 'Big Buck Bunny', 'AAA2'),
        _stalled(3, 'Tears of Steel', 'AAA3'),
      ],
    );

    expect(find.text('3 downloads stuck'), findsOneWidget);
    expect(find.textContaining('Stuck ·'), findsNothing);
    expect(
      find.text('Sprite Fright, Big Buck Bunny, Tears of Steel'),
      findsOneWidget,
    );
    expect(
      find.semantics.byLabel(
        '3 downloads stuck, Sprite Fright, Big Buck Bunny, Tears of Steel',
      ),
      containsSemantics(isButton: true, hint: 'opens the Radarr Queue tab'),
    );

    await tester.tap(find.text('3 downloads stuck'));
    await harness.settle(tester);
    expect(shell.tab, ServiceTab.queue);

    await harness.unmount(tester);
  });

  testWidgets('P1: the header counts the three downloads, not the one row '
      'that stands for them', (tester) async {
    final (harness, _) = await _pump(
      tester,
      queue: [
        _stalled(1, 'Sprite Fright', 'AAA1'),
        _stalled(2, 'Big Buck Bunny', 'AAA2'),
        _stalled(3, 'Tears of Steel', 'AAA3'),
      ],
    );

    expect(find.semantics.byLabel('Needs attention, 3'), findsOneWidget);

    await harness.unmount(tester);
  });
}
