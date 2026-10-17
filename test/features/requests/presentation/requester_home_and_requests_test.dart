import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/discover/presentation/library_calendar_provider.dart'
    show calendarClockProvider;
import 'package:cupola/features/home/presentation/home_screen.dart';
import 'package:cupola/features/home/presentation/widgets/featured_pager.dart';
import 'package:cupola/features/requests/presentation/requests_screen.dart';
import 'package:cupola/features/requests/presentation/widgets/requester_request_row.dart';

import '../../../test_helpers/profiles/profiles.dart';

/// Anna's Home and her page of requests, against her own Seerr session: the
/// world gives her Charge waiting since two hours, Sprite Fright at 62% and
/// two episodes of Cosmos Laundromat on their way, Sintel on the server
/// since Wednesday and Tears of Steel in 4K since September.
void main() {
  // Friday 9 October 2026, 20:30.
  final now = DateTime(2026, 10, 9, 20, 30);
  const phone = Size(390, 3200);

  Future<ProfileHarness> pump(
    WidgetTester tester,
    Widget child, {
    ConfigProfile? profile,
  }) => pumpWithProfile(
    tester,
    profile ?? Profiles.p2,
    child: child,
    now: now,
    overrides: [calendarClockProvider.overrideWithValue(() => now)],
    surfaceSize: phone,
  );

  group('her Home', () {
    testWidgets('Ready to watch leads with what arrived, and the way to '
        'watch it', (tester) async {
      final harness = await pump(tester, const HomeScreen());

      expect(find.byType(FeaturedPager), findsOne);
      expect(find.text('Ready to watch\u00A0· since Wednesday'), findsOne);
      expect(find.text(WorldTitles.sintel.title), findsWidgets);
      expect(find.textContaining('You asked for it on Wed 30 Sep'), findsOne);
      expect(find.text('Watch on Jellyfin'), findsOne);
      expect(find.text('Details'), findsOne);
      // One arrival: no second line.
      expect(find.textContaining('Also ready'), findsNothing);

      await harness.unmount(tester);
    });

    testWidgets('Your requests: what moves first, then what waits, and the '
        'way to all of them', (tester) async {
      final harness = await pump(tester, const HomeScreen());

      expect(find.text('Your requests'), findsOne);
      expect(find.text('3 on the way'), findsOne);
      final rows = tester
          .widgetList<RequesterRequestRow>(find.byType(RequesterRequestRow))
          .map((row) => row.mine.title)
          .toList();
      expect(rows, [
        WorldTitles.spriteFright.title,
        WorldTitles.cosmosLaundromat.title,
        WorldTitles.charge.title,
      ]);
      expect(find.text('62%'), findsOne);
      expect(find.text('Ready around 20:41'), findsOne);
      expect(find.text('Waiting for approval'), findsOne);
      expect(find.text('Asked 2\u00A0h ago\u00A0· Standard'), findsOne);
      expect(find.text('All your requests'), findsOne);
      // Nothing of hers is a fault.
      expect(find.textContaining('Stuck'), findsNothing);

      await harness.unmount(tester);
    });

    testWidgets('a server that does not answer is one line, above '
        'everything, and no module of its own', (tester) async {
      final harness = await pump(
        tester,
        const HomeScreen(),
        profile: Profiles.p2.withBehaviour(
          WorldIds.seerr,
          ConnectionBehaviour.didNotAnswer,
        ),
      );

      expect(
        find.textContaining(RegExp(r"^Can't reach the server since \d\d:\d\d")),
        findsOne,
      );
      expect(find.text('Retry'), findsOne);
      expect(find.text('Your requests'), findsNothing);
      expect(find.byType(FeaturedPager), findsNothing);
      expect(find.textContaining('row is missing'), findsNothing);

      await harness.unmount(tester);
    });

    testWidgets('what was read before the server went quiet stays, with no '
        'figure that stopped moving', (tester) async {
      final harness = await pump(tester, const HomeScreen());
      expect(find.text('62%'), findsOne);

      harness.network.on(
        WorldIds.seerr,
        'GET',
        '/api/v1/request',
        (_) => NetworkReply.json({'message': 'down'}, status: 503),
      );
      // Driven through the indicator's own state: the page is one tall list
      // with horizontal rails inside it.
      unawaited(
        tester
            .state<RefreshIndicatorState>(find.byType(RefreshIndicator))
            .show(),
      );
      await harness.settle(tester);

      // The server answered, with an error: that is an answer and no silence,
      // so the line says what it can and no time.
      expect(find.text("Can't reach the server."), findsOne);
      Finder inRows(Finder finder) => find.descendant(
        of: find.byType(RequesterRequestRow),
        matching: finder,
      );
      expect(inRows(find.text(WorldTitles.spriteFright.title)), findsOne);
      expect(find.text('62%'), findsNothing);
      expect(inRows(find.text('On its way')), findsNWidgets(2));

      await harness.unmount(tester);
    });
  });

  group('her page of requests', () {
    testWidgets('how many are ready and coming; the one that waits, with '
        'its steps and Cancel request; then the rest', (tester) async {
      final harness = await pump(tester, const RequestsScreen());

      expect(find.text('Requests'), findsOne);
      expect(find.text('1 ready to watch'), findsOne);
      expect(find.text('3 on the way'), findsOne);

      final card = find.byType(RequesterWaitingCard);
      expect(card, findsOne);
      expect(
        find.descendant(
          of: card,
          matching: find.text(WorldTitles.charge.title),
        ),
        findsOne,
      );
      for (final step in ['Asked', 'Approval', 'Ready to watch']) {
        expect(
          find.descendant(of: card, matching: find.text(step)),
          findsOne,
          reason: step,
        );
      }
      expect(find.text('Cancel request'), findsOne);

      final rows = tester
          .widgetList<RequesterRequestRow>(find.byType(RequesterRequestRow))
          .map((row) => row.mine.title)
          .toList();
      expect(rows, [
        WorldTitles.spriteFright.title,
        WorldTitles.cosmosLaundromat.title,
        WorldTitles.sintel.title,
        WorldTitles.tearsOfSteel.title,
      ]);
      expect(find.text('Downloading 62%'), findsOne);
      expect(find.text('Since Wednesday'), findsOne);
      expect(find.text('Since Mon 14 Sep'), findsOne);
      expect(find.text('On the server'), findsOne);
      // Watch on what is on the server and has Seerr's link to it.
      expect(find.text('Watch'), findsNWidgets(2));
      // Nobody else's request.
      expect(find.text(WorldTitles.metropolis.title), findsNothing);

      await harness.unmount(tester);
    });

    testWidgets('Cancel request asks first, then takes it back', (
      tester,
    ) async {
      final harness = await pump(tester, const RequestsScreen());

      await tester.tap(find.text('Cancel request'));
      await tester.pumpAndSettle();
      expect(find.text('Cancel request?'), findsOne);
      expect(find.text('Keep it'), findsOne);

      await tester.tap(find.text('Cancel request').last);
      await harness.settle(tester);

      expect(find.text('Request canceled'), findsOne);
      expect(
        harness.network
            .requestsTo(WorldIds.seerr)
            .where(
              (r) => r.method == 'DELETE' && r.uri.path == '/api/v1/request/1',
            ),
        hasLength(1),
      );

      await harness.unmount(tester);
    });

    testWidgets('a server that does not answer: one line and Retry', (
      tester,
    ) async {
      final harness = await pump(
        tester,
        const RequestsScreen(),
        profile: Profiles.p2.withBehaviour(
          WorldIds.seerr,
          ConnectionBehaviour.didNotAnswer,
        ),
      );

      expect(
        find.textContaining(RegExp(r"^Can't reach the server since")),
        findsOne,
      );
      expect(find.text('Retry'), findsOne);
      expect(find.byType(RequesterRequestRow), findsNothing);

      await harness.unmount(tester);
    });
  });
}
