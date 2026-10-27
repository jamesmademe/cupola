/// Needs you reads one page of history per connection, and a page that came
/// back full is a window onto more of it.
///
/// The failed imports Needs you counts after its lead were stated as every one
/// there is. Past a full page are older failures nobody read, so the figure
/// over it is a floor. Arrived reads no page: a week of imports comes in one
/// answer per connection, so what it counts is every title there is, however
/// busy the evening, and it never says a floor.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/api/base_arr_service.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/features/home/presentation/home_screen.dart';
import 'package:cupola/features/home/presentation/widgets/arrived_module.dart';
import 'package:cupola/features/home/presentation/widgets/needs_you_banner.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';

import '../../../test_helpers/profiles/profiles.dart';
import 'package:cupola/demo/world/service_fakes.dart';

/// Twenty-five imports on the HD Radarr, newest first: more than one page.
List<Map<String, Object?>> _busyEvening(DateTime now) => [
  for (var i = 1; i <= 25; i++)
    {
      'id': 500 + i,
      'movieId': 100 + i,
      'eventType': 'downloadFolderImported',
      'sourceTitle': 'Short.Movie.$i.2024.1080p',
      'date': now.subtract(Duration(minutes: i)).toUtc().toIso8601String(),
      'movie': {'id': 100 + i, 'title': 'Short $i', 'year': 2024},
      'data': const <String, Object?>{},
    },
];

void main() {
  group('historyPageIsWindow', () {
    ArrRecordPage page(int rows, {int? total}) =>
        ArrRecordPage(records: List.filled(rows, const {}), total: total);

    test('a short page is every record there is', () {
      expect(historyPageIsWindow(page(7, total: 7), pageSize: 20), isFalse);
      expect(historyPageIsWindow(page(7), pageSize: 20), isFalse);
    });

    test('a full page is a window, unless the total says it is the whole', () {
      expect(historyPageIsWindow(page(20, total: 25), pageSize: 20), isTrue);
      expect(historyPageIsWindow(page(20), pageSize: 20), isTrue);
      expect(historyPageIsWindow(page(20, total: 20), pageSize: 20), isFalse);
    });
  });

  testWidgets('P1, a busy HD Radarr: Needs you\'s count over its full page '
      'is a floor, and Arrived\'s count over the whole week is not', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final harness = await ProfileHarness.start(Profiles.p1);
    harness.network.on(
      WorldIds.radarr,
      'GET',
      '/api/v3/history',
      (r) => NetworkReply.json(
        pagedEnvelope(r, _busyEvening(harness.network.now)),
      ),
    );
    // The same evening as the week's read answers it: every record, with no
    // page to run out.
    harness.network.on(
      WorldIds.radarr,
      'GET',
      '/api/v3/history/since',
      (r) => NetworkReply.json(_busyEvening(harness.network.now)),
    );
    await tester.binding.setSurfaceSize(const Size(430, 6000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: harness.overrides,
        child: MaterialApp(
          theme: AppTheme.darkTheme(),
          home: const HomeScreen(),
        ),
      ),
    );
    await harness.settle(tester);

    // Twenty-five titles on the HD's answer and two on the 4K's: the week's
    // total, which no page cut short. Sonarr's episode is of a series that
    // was already there, and is not a title that arrived.
    expect(
      find.descendant(
        of: find.byType(HomeArrivedModule),
        matching: find.text('Last 7 days\u00A0· 27 new'),
      ),
      findsOne,
    );
    expect(
      find.bySemanticsLabel(RegExp(r'^Arrived, Last 7 days, 27 new')),
      findsOne,
    );
    expect(
      find.descendant(
        of: find.byType(HomeArrivedModule),
        matching: find.textContaining(RegExp(r'\d\+')),
      ),
      findsNothing,
      reason: 'Arrived reads no page, so it has no floor to say',
    );
    // Needs you read the same page for failed imports. The blocked imports
    // it leads with come from the queue, read whole, so their eighteen is
    // every one there is; what follows them counts the failed imports of
    // that full page, and is the least there is.
    expect(
      find.descendant(
        of: find.byType(NeedsYouLine),
        matching: find.text('18 downloads need a manual import'),
      ),
      findsOne,
    );
    expect(
      find.descendant(
        of: find.byType(NeedsYouLine),
        matching: find.textContaining(RegExp(r'^\d+\+ more$')),
      ),
      findsOne,
    );
    expect(
      find.bySemanticsLabel(
        RegExp(
          r'^18 downloads need a manual import, and at least \d+ more '
          r'things? needs? you\. Review$',
        ),
      ),
      findsOne,
    );

    handle.dispose();
    await harness.unmount(tester);
  });

  test('P1 as it is: no page is full, and nothing is a floor', () async {
    final harness = await ProfileHarness.start(Profiles.p1);
    final container = harness.container(retry: (_, _) => null);

    final history = await container.read(servicesArrHistoryProvider.future);
    expect(history.coverage.isFloor, isFalse);
  });

  test('P1, a busy HD Radarr: the week is whole however many it holds, and '
      'is never a floor', () async {
    final harness = await ProfileHarness.start(Profiles.p1);
    harness.network.on(
      WorldIds.radarr,
      'GET',
      '/api/v3/history',
      (r) => NetworkReply.json(
        pagedEnvelope(r, _busyEvening(harness.network.now)),
      ),
    );
    harness.network.on(
      WorldIds.radarr,
      'GET',
      '/api/v3/history/since',
      (r) => NetworkReply.json(_busyEvening(harness.network.now)),
    );
    final container = harness.container(retry: (_, _) => null);
    container.listen(servicesArrivalsProvider, (_, _) {});

    // The page of twenty is a window onto the evening, and says so.
    final page = await container.read(servicesArrHistoryProvider.future);
    expect(page.coverage.isFloor, isTrue);

    // The week is the whole of it: past twenty, and not cut short.
    final week = await container.read(servicesArrivalsProvider.future);
    expect(
      week.entries.where((entry) => entry.instanceId == WorldIds.radarr),
      hasLength(25),
    );
    expect(week.coverage.isFloor, isFalse);
    expect(week.coverage.isWhole, isTrue);
  });
}
