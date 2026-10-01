/// An episode Sonarr is downloading reads downloading on its series page.
///
/// The episode rows and the season headers read no queue at all, so Cosmos
/// Laundromat's S2 E4, 88 % of the way down, read Missing beside the search
/// that would have fetched it a second time.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/theme.dart';
import 'package:cupola/features/series/presentation/series_detail_screen.dart';

import '../../../test_helpers/profiles/profiles.dart';

const _tall = Size(430, 4000);

Future<ProfileHarness> _pumpCosmos(
  WidgetTester tester, {
  void Function(ProfileNetwork network)? before,
}) async {
  final harness = await ProfileHarness.start(Profiles.p1);
  before?.call(harness.network);
  await tester.binding.setSurfaceSize(_tall);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: harness.overrides,
      child: MaterialApp(
        theme: AppTheme.darkTheme(),
        home: const SeriesDetailScreen(seriesId: 1, heroTag: 'series-1'),
      ),
    ),
  );
  await harness.settle(tester);
  await tester.tap(find.text('S2'));
  await harness.settle(tester);
  return harness;
}

void main() {
  testWidgets('P1: S2 E4 and E5 read downloading, the rest of the gap '
      'Missing', (tester) async {
    final harness = await _pumpCosmos(tester);

    expect(find.textContaining('Downloading 88%'), findsOneWidget);
    expect(find.textContaining('Downloading 9%'), findsOneWidget);
    // E6 to E10: aired, no file, and not in the queue.
    expect(find.textContaining('Missing'), findsWidgets);

    await harness.unmount(tester);
  });

  testWidgets('P1, the queue unreadable: no aired episode reads Missing', (
    tester,
  ) async {
    final harness = await _pumpCosmos(
      tester,
      before: (network) => network.on(
        WorldIds.sonarr,
        'GET',
        '/api/v3/queue',
        (_) => NetworkReply.json({'message': 'boom'}, status: 500),
      ),
    );

    expect(find.textContaining('Missing'), findsNothing);
    expect(find.textContaining('Unknown'), findsWidgets);

    await harness.unmount(tester);
  });
}
