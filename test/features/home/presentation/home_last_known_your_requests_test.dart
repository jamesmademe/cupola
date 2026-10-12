import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/features/discover/domain/models/seerr_request.dart';
import 'package:cupola/features/home/data/last_known/my_requests_last_known.dart';
import 'package:cupola/features/home/presentation/widgets/your_requests_module.dart';
import 'package:cupola/features/requests/presentation/widgets/requester_request_row.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';

import '../../../test_helpers/requester_cold_start.dart';

/// The requester's Your requests at a cold start: the rows it last listed,
/// said for what they are, and without a figure that does not run.
void main() {
  late RequesterColdStart app;
  setUp(() => app = RequesterColdStart());

  Future<void> run(
    WidgetTester tester, {
    Future<List<SeerrRequest>> Function()? requests,
    DateTime? now,
    int userId = 7,
    SettingsModel Function(SettingsModel)? customize,
  }) => app.run(
    tester,
    child: const HomeYourRequestsModule(),
    requests: requests,
    now: now,
    userId: userId,
    customize: customize,
  );

  Finder inRows(Finder finder) =>
      find.descendant(of: find.byType(RequesterRequestRow), matching: finder);

  List<String> listed(WidgetTester tester) => [
    for (final row in tester.widgetList<RequesterRequestRow>(
      find.byType(RequesterRequestRow),
    ))
      row.mine.title,
  ];

  /// What her Seerr says: Sprite Fright at 62% and ending at 21:10, Charge
  /// waiting for approval since two hours, Cosmos Laundromat on its way with
  /// nothing Seerr can measure, and a no of three days ago.
  List<SeerrRequest> seerrSays() => [
    requesterRequest(
      id: 1,
      title: 'Sprite Fright',
      tmdbId: 11,
      status: RequestStatus.approved,
      availability: SeerrMediaAvailability.processing,
      asked: const Duration(days: 3),
      arrived: null,
      downloads: [movingDownload(DateTime(2026, 10, 12, 21, 10))],
    ),
    requesterRequest(
      id: 2,
      title: 'Charge',
      tmdbId: 12,
      status: RequestStatus.pendingApproval,
      availability: SeerrMediaAvailability.unknown,
      asked: const Duration(hours: 2),
      arrived: null,
    ),
    requesterRequest(
      id: 3,
      title: 'Cosmos Laundromat',
      tmdbId: 13,
      status: RequestStatus.approved,
      availability: SeerrMediaAvailability.processing,
      asked: const Duration(days: 1),
      arrived: null,
    ),
    requesterRequest(
      id: 4,
      title: 'Big Buck Bunny',
      tmdbId: 14,
      status: RequestStatus.declined,
      availability: SeerrMediaAvailability.unknown,
      asked: const Duration(days: 4),
      answered: const Duration(days: 3),
      arrived: null,
    ),
  ];

  Future<void> firstRun(
    WidgetTester tester, [
    List<SeerrRequest>? requests,
  ]) async {
    await run(tester, requests: () async => requests ?? seerrSays());
    await tester.pumpAndSettle();
    expect(find.byType(RequesterRequestRow), findsWidgets);
    expect(find.textContaining('As of'), findsNothing);
  }

  testWidgets('draws the rows it last listed at once, says so, then the live '
      'ones', (tester) async {
    await firstRun(tester);
    // The live list does run: a percentage and the time it should end.
    expect(find.text('62%'), findsOne);
    expect(find.text('Ready around 21:10'), findsOne);

    final answer = Completer<List<SeerrRequest>>();
    await run(
      tester,
      requests: () => answer.future,
      now: requesterNow.add(const Duration(hours: 1)),
    );
    // No skeleton: three rows and the count, the youngest on its way first,
    // then what waits; and the one line.
    expect(find.text('Your requests'), findsOne);
    expect(find.text('3 on the way'), findsOne);
    expect(listed(tester), ['Cosmos Laundromat', 'Sprite Fright', 'Charge']);
    expect(find.text('All your requests'), findsOne);
    expect(find.text('As of 20:53 · checking now'), findsOne);

    answer.complete([
      requesterRequest(
        id: 9,
        title: 'Spring',
        tmdbId: 19,
        status: RequestStatus.pendingApproval,
        availability: SeerrMediaAvailability.unknown,
        arrived: null,
      ),
    ]);
    await tester.pumpAndSettle();
    expect(listed(tester), ['Spring']);
    expect(find.text('1 on its way'), findsOne);
    expect(find.textContaining('As of'), findsNothing);
  });

  testWidgets('a download does not run in a drawing: no percentage, no time '
      'left, on its way', (tester) async {
    await firstRun(tester);

    await run(tester);
    expect(inRows(find.text('Sprite Fright')), findsOne);
    expect(find.text('62%'), findsNothing);
    expect(find.textContaining('Ready around'), findsNothing);
    // Both approved requests are on its way, in her words, with no bar.
    expect(inRows(find.text('On its way')), findsNWidgets(2));
    expect(inRows(find.text('Being fetched')), findsNWidgets(2));
    expect(find.text('Downloading 62%'), findsNothing);
  });

  testWidgets('a time is said again against the time of the drawing', (
    tester,
  ) async {
    await firstRun(tester);
    expect(find.text('Asked 2\u00A0h ago · Standard'), findsOne);

    await run(tester, now: requesterNow.add(const Duration(hours: 1)));
    expect(find.text('Asked 3\u00A0h ago · Standard'), findsOne);
  });

  testWidgets('a live read that fails keeps the rows over the failure and '
      'stops checking', (tester) async {
    await firstRun(tester);

    await run(
      tester,
      requests: () async =>
          throw const ClassifiedFailure(ServiceFailureReason.unreachable),
    );
    await tester.pumpAndSettle();
    // The module draws no failure of its own: the Home says it once.
    expect(find.text('3 on the way'), findsOne);
    expect(listed(tester), ['Cosmos Laundromat', 'Sprite Fright', 'Charge']);
    expect(find.text('As of 20:53'), findsOne);
  });

  group('whose drawing it is', () {
    Future<void> control(WidgetTester tester) async {
      await run(tester);
      expect(find.text('3 on the way'), findsOne, reason: 'the control draws');
      expect(find.textContaining('· checking now'), findsOne);
    }

    testWidgets('another server draws nothing of it', (tester) async {
      await firstRun(tester);
      await control(tester);

      await run(
        tester,
        customize: (settings) => settings.copyWithInstance(
          settings
              .instancesOf(ServiceKey.seerr)
              .first
              .copyWith(url: 'https://other.example.com'),
        ),
      );
      expect(find.byType(RequesterRequestRow), findsNothing);
      expect(find.textContaining('As of'), findsNothing);
    });

    testWidgets('another person draws nothing of it', (tester) async {
      await firstRun(tester);
      await control(tester);

      await run(tester, userId: 8);
      expect(find.byType(RequesterRequestRow), findsNothing);
      expect(find.textContaining('As of'), findsNothing);
    });
  });

  group('the week is cut again', () {
    final answeredSixDaysAgo = [
      requesterRequest(
        id: 4,
        title: 'Big Buck Bunny',
        tmdbId: 14,
        status: RequestStatus.declined,
        availability: SeerrMediaAvailability.unknown,
        asked: const Duration(days: 8),
        answered: const Duration(days: 6),
        arrived: null,
      ),
      requesterRequest(
        id: 2,
        title: 'Charge',
        tmdbId: 12,
        status: RequestStatus.pendingApproval,
        availability: SeerrMediaAvailability.unknown,
        asked: const Duration(hours: 2),
        arrived: null,
      ),
    ];

    testWidgets('a no the week left behind is not listed', (tester) async {
      await firstRun(tester, answeredSixDaysAgo);
      await run(tester, now: requesterNow.add(const Duration(hours: 5)));
      expect(listed(tester), ['Charge', 'Big Buck Bunny']);
      expect(inRows(find.text('Declined')), findsOne);

      await run(tester, now: requesterNow.add(const Duration(days: 2)));
      expect(listed(tester), ['Charge']);
      expect(find.text('Declined'), findsNothing);
    });

    testWidgets('a drawing with nothing left is the skeleton, not Nothing on '
        'its way, and says nothing about itself', (tester) async {
      await firstRun(tester, [answeredSixDaysAgo.first]);
      await run(tester, now: requesterNow.add(const Duration(hours: 5)));
      expect(listed(tester), ['Big Buck Bunny']);

      await run(tester, now: requesterNow.add(const Duration(days: 2)));
      expect(find.text('Your requests'), findsOne);
      expect(find.byType(RequesterRequestRow), findsNothing);
      expect(find.text('Nothing on its way'), findsNothing);
      expect(find.textContaining('As of'), findsNothing);
    });

    testWidgets('and over a failure, nothing at all', (tester) async {
      await firstRun(tester, [answeredSixDaysAgo.first]);

      await run(
        tester,
        now: requesterNow.add(const Duration(days: 2)),
        requests: () async =>
            throw const ClassifiedFailure(ServiceFailureReason.unreachable),
      );
      await tester.pumpAndSettle();
      expect(find.text('Your requests'), findsNothing);
      expect(find.text('Nothing on its way'), findsNothing);
      expect(find.textContaining('As of'), findsNothing);
    });
  });

  testWidgets('every request on its way is counted, not the three listed', (
    tester,
  ) async {
    await firstRun(tester, [
      for (var i = 0; i < 5; i++)
        requesterRequest(
          id: i + 1,
          title: 'Waiting $i',
          tmdbId: 100 + i,
          status: RequestStatus.pendingApproval,
          availability: SeerrMediaAvailability.unknown,
          asked: Duration(hours: 1 + i),
          arrived: null,
        ),
    ]);
    expect(find.text('5 on the way'), findsOne);

    await run(tester);
    expect(find.text('5 on the way'), findsOne);
    expect(find.byType(RequesterRequestRow), findsNWidgets(yourRequestsLimit));
  });

  test('the drawing keeps no figure that runs', () {
    final data = jsonEncode(myRequestsLastKnown.encode(seerrSays()));
    for (final running in [
      'progress',
      'sizeLeft',
      'estimatedCompletionTime',
      'readyAround',
      'downloadStatus',
    ]) {
      expect(data, isNot(contains(running)), reason: running);
    }
  });
}
