/// The blocklist at the foot of History: every arr's list in one, with what
/// each refused release was refused for, and a connection that did not
/// answer named instead of passed off as an empty list.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/widgets/brief_failure_line.dart';
import 'package:cupola/features/activity/presentation/activity_blocklist_page.dart';

import '../../../test_helpers/profiles/profiles.dart';

/// One blocklist record as Radarr sends it.
Map<String, Object?> _blocked(
  int id,
  String release,
  String message, {
  required DateTime at,
}) => {
  'id': id,
  'movieId': id,
  'sourceTitle': release,
  'message': message,
  'date': at.toUtc().toIso8601String(),
  'movie': {'id': id, 'title': 'Movie $id', 'year': 2024},
  'quality': {
    'quality': {'id': 7, 'name': 'Bluray-1080p', 'resolution': 1080},
  },
};

Future<ProfileHarness> _pump(
  WidgetTester tester,
  ConfigProfile profile, {
  void Function(ProfileHarness harness)? script,
}) async {
  final harness = await ProfileHarness.start(profile);
  script?.call(harness);
  harness.network.followFakeTime(tester.binding);
  await tester.binding.setSurfaceSize(const Size(430, 2400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: harness.overrides,
      child: const MaterialApp(home: ActivityBlocklistPage()),
    ),
  );
  await harness.settle(tester);
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 150)),
  );
  await harness.settle(tester);
  return harness;
}

void main() {
  testWidgets('P1: each blocked release is a row, with what it was refused '
      'for', (tester) async {
    final harness = await _pump(
      tester,
      Profiles.p1,
      script: (harness) => harness.network.on(
        WorldIds.radarr,
        'GET',
        '/api/v3/blocklist',
        (_) => NetworkReply.json({
          'page': 1,
          'pageSize': 20,
          'totalRecords': 2,
          'records': [
            _blocked(
              1,
              'Movie.1.2024.1080p.BluRay',
              'Release was marked as failed',
              at: harness.network.now.subtract(const Duration(hours: 3)),
            ),
            _blocked(
              2,
              'Movie.2.2024.1080p.WEB',
              'Manually blocked',
              at: harness.network.now.subtract(const Duration(days: 2)),
            ),
          ],
        }),
      ),
    );

    expect(find.text('Blocklist'), findsOneWidget);
    expect(find.textContaining('Movie 1'), findsWidgets);
    expect(find.textContaining('Movie 2'), findsWidgets);
    expect(find.text('The blocklist is empty'), findsNothing);

    await harness.unmount(tester);
  });

  testWidgets('P1: nothing blocked says so, and what puts a release there', (
    tester,
  ) async {
    final harness = await _pump(tester, Profiles.p1);

    expect(find.text('The blocklist is empty'), findsOneWidget);
    expect(
      find.textContaining('A release an arr will not take again'),
      findsOneWidget,
    );

    await harness.unmount(tester);
  });

  testWidgets('a connection that did not answer is named, and what the '
      'others hold is still listed', (tester) async {
    final harness = await _pump(
      tester,
      Profiles.p1.withBehaviour(
        WorldIds.sonarr,
        ConnectionBehaviour.didNotAnswer,
      ),
      script: (harness) => harness.network.on(
        WorldIds.radarr,
        'GET',
        '/api/v3/blocklist',
        (_) => NetworkReply.json({
          'page': 1,
          'pageSize': 20,
          'totalRecords': 1,
          'records': [
            _blocked(
              1,
              'Movie.1.2024.1080p.BluRay',
              'Release was marked as failed',
              at: harness.network.now.subtract(const Duration(hours: 3)),
            ),
          ],
        }),
      ),
    );

    expect(find.byType(BriefFailureLine), findsOneWidget);
    expect(find.textContaining('Movie 1'), findsWidgets);
    // Not an empty list: one arr is missing from it.
    expect(find.text('The blocklist is empty'), findsNothing);

    await harness.unmount(tester);
  });
}
