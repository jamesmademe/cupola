/// A decision on a request, and who asked for it, as the gate of the Seerr
/// it came off says: the requester's app decides nothing and names nobody,
/// and an account of the operator's that may not approve keeps the answers,
/// dimmed, saying why.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/theme.dart';
import 'package:cupola/features/home/presentation/widgets/requests_module.dart';
import 'package:cupola/features/activity/presentation/activity_provider.dart';
import 'package:cupola/features/activity/presentation/widgets/requests_list.dart';
import 'package:cupola/features/discover/domain/seerr_permission.dart';
import 'package:cupola/features/discover/presentation/widgets/seerr_decisions_section.dart';
import 'package:cupola/features/home/presentation/home_screen.dart';

import '../../../test_helpers/profiles/profiles.dart';

/// P9, where the operator's account on Sara's Seerr may also see everyone's
/// requests there: Anna's waiting Charge reaches him, and he may not decide
/// on it.
final _p9Sees = Profiles.p9.withSeerrPermissions(
  SeerrPermission.request.value | SeerrPermission.requestView.value,
);

const _friendReason = "Your account on Jellyseerr can't approve requests.";

Future<ProfileHarness> _pump(
  WidgetTester tester,
  ConfigProfile profile,
  Widget child, {
  Size size = const Size(430, 4000),
}) async {
  final harness = await ProfileHarness.start(profile);
  harness.network.followFakeTime(tester.binding);
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: harness.overrides,
      child: MaterialApp(
        theme: AppTheme.darkTheme(),
        home: Scaffold(body: child),
      ),
    ),
  );
  await harness.settle(tester);
  return harness;
}

Finder _inRequests(Finder matching) =>
    find.descendant(of: find.byType(HomeRequestsModule), matching: matching);

void main() {
  group('Home', () {
    testWidgets('P2: her own waiting request is no decision of hers', (
      tester,
    ) async {
      // The module itself, not the Home around it: the requester's Home
      // draws two shelves in its place, so only the module can say that
      // the gate, and not the page, keeps her own request out of it.
      final harness = await _pump(
        tester,
        Profiles.p2,
        const SingleChildScrollView(child: HomeRequestsModule()),
      );

      expect(_inRequests(find.text('Charge')), findsNothing);
      expect(find.byTooltip('Approve Charge'), findsNothing);

      await harness.unmount(tester);
    });

    testWidgets(
      "Sara's request reaches the operator with its answers dimmed, his own "
      'live',
      (tester) async {
        // P5's stack, where requests are all Home has to decide, beside
        // Sara's Seerr as P9 has it.
        final harness = await _pump(
          tester,
          Profiles.p5
              .withConnection(WorldConnections.seerrFriend)
              .withSeerrPermissions(
                SeerrPermission.request.value |
                    SeerrPermission.requestView.value,
              ),
          const HomeScreen(),
        );

        Finder row(String seerr) =>
            find.byKey(ValueKey('decision-seerr-$seerr-2'));
        Finder approveIn(String seerr) => find.descendant(
          of: row(seerr),
          matching: find.byTooltip('Approve Metropolis'),
        );

        // Luca's Metropolis waits on both: the household's, and Sara's.
        expect(approveIn(WorldIds.seerr), findsOneWidget);
        expect(approveIn(WorldIds.seerrFriend), findsOneWidget);
        // Who asked is named on both: his account there sees everyone's.
        for (final seerr in [WorldIds.seerr, WorldIds.seerrFriend]) {
          expect(
            find.descendant(
              of: row(seerr),
              matching: find.textContaining(WorldPeople.luca),
            ),
            findsOneWidget,
          );
        }

        await tester.ensureVisible(approveIn(WorldIds.seerrFriend));
        await tester.tap(approveIn(WorldIds.seerrFriend));
        await tester.pump();
        expect(find.text(_friendReason), findsOneWidget);
        // Nothing was asked of Sara's Seerr: no confirmation, no approval.
        expect(find.text('Approve this request?'), findsNothing);
        expect(
          harness.network
              .requestsTo(WorldIds.seerrFriend)
              .where((r) => r.method == 'POST'),
          isEmpty,
        );

        await harness.unmount(tester);
      },
    );
  });

  group('Activity', () {
    Future<List<GlobalActivityItem>> requestRows(ConfigProfile profile) async {
      final harness = await ProfileHarness.start(profile);
      final container = harness.container(retry: (_, _) => null);
      final feed = await container.read(globalActivityFeedProvider.future);
      return [
        for (final row in feed.items)
          if (row.kind == GlobalActivityKind.request) row,
      ];
    }

    test('P2: a request row names nobody', () async {
      final rows = await requestRows(Profiles.p2);

      expect(rows, isNotEmpty);
      for (final row in rows) {
        expect(row.subtitle, isNot(contains(WorldPeople.anna)));
      }
    });

    test('P1: the key still names who asked', () async {
      final rows = await requestRows(Profiles.p1);
      final charge = rows.firstWhere((row) => row.title == 'Charge');

      expect(charge.subtitle, contains(WorldPeople.anna));
    });
  });

  group('the requests list', () {
    testWidgets('P2: her own waiting request can be cancelled, nothing else', (
      tester,
    ) async {
      final harness = await _pump(tester, Profiles.p2, const RequestsList());

      // Charge waits: hers to take back. Sprite Fright was approved: not.
      expect(find.byTooltip('Cancel request'), findsOneWidget);
      expect(find.byTooltip('Delete request'), findsNothing);
      expect(find.text('Approve'), findsNothing);
      expect(find.text('Decline'), findsNothing);
      // No quality profile: the destination is not hers to read.
      expect(find.textContaining('HD-1080p'), findsNothing);

      await tester.tap(find.byTooltip('Cancel request'));
      await harness.settle(tester);
      expect(find.text('Cancel request?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Cancel request'));
      await harness.settle(tester);

      expect(
        harness.network
            .requestsTo(WorldIds.seerr)
            .where((r) => r.method == 'DELETE'),
        hasLength(1),
      );
      expect(find.text('Request canceled'), findsOneWidget);

      await harness.unmount(tester);
    });

    testWidgets('P1: the key decides and deletes, as it always has', (
      tester,
    ) async {
      final harness = await _pump(tester, Profiles.p1, const RequestsList());

      expect(find.text('Approve'), findsWidgets);
      expect(find.byTooltip('Delete request'), findsWidgets);
      expect(find.byTooltip('Cancel request'), findsNothing);
      expect(find.textContaining('HD-1080p'), findsWidgets);

      await harness.unmount(tester);
    });

    testWidgets("P9: on Sara's list the decision is dimmed and says why", (
      tester,
    ) async {
      final harness = await _pump(
        tester,
        _p9Sees,
        const RequestsList(instanceId: WorldIds.seerrFriend),
      );

      final approve = find.text('Approve').first;
      await tester.ensureVisible(approve);
      await tester.tap(approve);
      await tester.pump();

      expect(find.text(_friendReason), findsOneWidget);
      expect(find.text('Approve this request?'), findsNothing);

      await harness.unmount(tester);
    });
  });

  group("the Seerr home's Needs a decision", () {
    testWidgets('P2: the requester has none', (tester) async {
      final harness = await _pump(
        tester,
        Profiles.p2,
        const SingleChildScrollView(child: SeerrDecisionsSection()),
      );

      expect(find.text('Needs a decision'), findsNothing);
      expect(
        harness.network
            .requestsTo(WorldIds.seerr)
            .where((r) => r.path == '/api/v1/request'),
        isEmpty,
      );

      await harness.unmount(tester);
    });
  });
}
