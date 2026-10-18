/// Lidarr's Needs attention leads where the fault is fixed: a stuck download
/// opens its own page, and the albums with no files open Wanted, which lists
/// them.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/music/presentation/lidarr_overview_screen.dart';
import 'package:cupola/features/services/domain/service_tab.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import '../../../test_helpers/overview_shell.dart';
import '../../../test_helpers/profiles/profiles.dart';

Future<(ProfileHarness, OverviewShell)> _pump(WidgetTester tester) async {
  final harness = await ProfileHarness.start(Profiles.p1);
  harness.network.on(
    WorldIds.lidarr,
    'GET',
    '/api/v1/queue',
    (request) => NetworkReply.json({
      'page': 1,
      'pageSize': 200,
      'totalRecords': 1,
      'records': [
        {
          'id': 5,
          'artist': {'artistName': 'Alvvays'},
          'album': {'title': 'Blue Rev'},
          'status': 'warning',
          'trackedDownloadStatus': 'warning',
          'trackedDownloadState': 'downloading',
          'errorMessage': 'The download is stalled with no connections',
          'added': DateTime.now().toUtc().toIso8601String(),
          'downloadId': 'HASH5',
          'downloadClient': 'qBittorrent',
        },
      ],
    }),
  );
  harness.network.on(
    WorldIds.lidarr,
    'GET',
    '/api/v1/wanted/missing',
    (request) => NetworkReply.json({
      'page': 1,
      'pageSize': 20,
      'totalRecords': 2,
      'records': [
        {
          'id': 1,
          'title': 'Blue Rev',
          'artist': {'artistName': 'Alvvays'},
        },
        {
          'id': 2,
          'title': 'Antisocialites',
          'artist': {'artistName': 'Alvvays'},
        },
      ],
    }),
  );
  harness.network.followFakeTime(tester.binding);
  await tester.binding.setSurfaceSize(const Size(430, 2600));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final shell = OverviewShell(
    ServiceKey.lidarr,
    const LidarrOverviewScreen(topPadding: 0),
  );
  await tester.pumpWidget(
    ProviderScope(overrides: harness.overrides, child: shell.app),
  );
  await harness.settle(tester);
  return (harness, shell);
}

void main() {
  testWidgets('P1: the stuck download opens its own page', (tester) async {
    final (harness, shell) = await _pump(tester);

    final row = find.textContaining('Stuck\u00A0· Alvvays');
    expect(row, findsOneWidget);
    expect(
      find.semantics.byLabel(RegExp(r'^Stuck, Alvvays, Blue Rev, ')),
      containsSemantics(isButton: true, hint: 'opens this download'),
    );

    await tester.tap(row);
    await harness.settle(tester);
    expect(shell.location, '/activity/download?i=${WorldIds.lidarr}&id=HASH5');

    await harness.unmount(tester);
  });

  testWidgets('P1: the albums with no files open Wanted', (tester) async {
    final (harness, shell) = await _pump(tester);

    final row = find.textContaining('missing monitored albums');
    expect(row, findsOneWidget);
    expect(
      find.semantics.byLabel(RegExp(r'^2 missing monitored albums')),
      containsSemantics(isButton: true, hint: 'opens the Lidarr Wanted tab'),
    );

    await tester.tap(row);
    await harness.settle(tester);
    expect(shell.tab, ServiceTab.wanted);

    await harness.unmount(tester);
  });
}
