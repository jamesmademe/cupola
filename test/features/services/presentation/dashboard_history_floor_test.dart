/// Home reads one page of history per connection, and a page that came back
/// full is a window onto more of it.
///
/// Arrived counted the imports on that page and stated them as the total, and
/// the failed imports Needs you counts after its lead were stated as every one
/// there is.
/// Past a full page are older imports and older failures nobody read, so the
/// figures over it are floors.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/api/base_arr_service.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/features/home/presentation/home_screen.dart';
import 'package:cupola/features/home/presentation/widgets/needs_you_banner.dart';
import 'package:cupola/features/services/presentation/dashboard_sections.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';

import '../../../test_helpers/profiles/profiles.dart';
import '../../../test_helpers/profiles/service_fakes.dart';

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

  testWidgets('P1, a busy HD Radarr: the counts over its full page are '
      'floors', (tester) async {
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

    // Twenty on the HD's page, two on the 4K's, one on Sonarr's: at least
    // twenty-three, and maybe more past the HD's page.
    expect(
      find.descendant(
        of: find.byType(HomeArrivedModule),
        matching: find.text('23+ imported'),
      ),
      findsOne,
    );
    expect(
      find.bySemanticsLabel(RegExp(r'^Arrived, at least 23 imported')),
      findsOne,
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
}
