/// Seerr's own room, as the gate of the lens's Seerr says: the requester
/// decides nothing and reads nobody's name or profile, and an account that
/// may not see issues or manage users is told so instead of being refused.
library;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/discover/domain/seerr_permission.dart';
import 'package:cupola/features/discover/presentation/seerr_admin_screens.dart';
import 'package:cupola/features/discover/presentation/seerr_overview_screen.dart';
import 'package:cupola/features/services/presentation/service_all_screens.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import '../../../test_helpers/profiles/profiles.dart';

const _tall = Size(430, 3000);

final _friend = Profiles.p9.withLens(ServiceKey.seerr, WorldIds.seerrFriend);

void main() {
  group('the Overview', () {
    testWidgets('P2: nothing to decide, and nobody named', (tester) async {
      final harness = await pumpWithProfile(
        tester,
        Profiles.p2,
        child: const SeerrOverviewScreen(topPadding: 0),
        surfaceSize: _tall,
      );

      expect(find.text('Needs a decision'), findsNothing);
      // Her approved requests are still on their way, said without her
      // name or their quality profile.
      expect(find.textContaining('Sprite Fright'), findsWidgets);
      expect(find.textContaining(WorldPeople.anna), findsNothing);
      expect(find.textContaining('HD-1080p'), findsNothing);

      await harness.unmount(tester);
    });

    testWidgets('P1: the key reads who asked, and the profile', (tester) async {
      final harness = await pumpWithProfile(
        tester,
        Profiles.p1,
        child: const SeerrOverviewScreen(topPadding: 0),
        surfaceSize: _tall,
      );

      expect(find.text('Needs a decision'), findsOneWidget);
      expect(find.textContaining(WorldPeople.anna), findsWidgets);
      expect(find.textContaining('HD-1080p'), findsWidgets);

      await harness.unmount(tester);
    });
  });

  group('every request', () {
    /// The actions [title]'s row offers beside opening it: on a long press,
    /// and among a screen reader's.
    List<String> actionsOf(WidgetTester tester, String title) {
      final semantics = tester.ensureSemantics();
      final data = tester
          .getSemantics(find.bySemanticsLabel(title).first)
          .getSemanticsData();
      semantics.dispose();
      return [
        for (final id in data.customSemanticsActionIds ?? const <int>[])
          CustomSemanticsAction.getAction(id)!.label!,
      ];
    }

    testWidgets('P2: her own waiting request is hers to cancel', (
      tester,
    ) async {
      final harness = await pumpWithProfile(
        tester,
        Profiles.p2,
        child: const ServiceAllRequestsScreen(),
        surfaceSize: _tall,
      );

      expect(actionsOf(tester, 'Charge'), ['Cancel request']);
      // Approved already: not hers to take back from here.
      expect(actionsOf(tester, 'Sprite Fright'), isEmpty);
      expect(find.textContaining(WorldPeople.anna), findsNothing);
      expect(find.byTooltip('Approve Charge'), findsNothing);

      await harness.unmount(tester);
    });

    testWidgets('P1: the key deletes any request it does not answer, and '
        'names who asked', (tester) async {
      final harness = await pumpWithProfile(
        tester,
        Profiles.p1,
        child: const ServiceAllRequestsScreen(),
        surfaceSize: _tall,
      );

      expect(actionsOf(tester, 'Sprite Fright'), ['Delete request']);
      // A waiting one is answered: Decline, not a delete.
      expect(find.byTooltip('Decline Charge'), findsOneWidget);
      expect(find.textContaining(WorldPeople.anna), findsWidgets);

      await harness.unmount(tester);
    });
  });

  group('Issues and Users', () {
    for (final (name, profile, issues, users) in [
      (
        'P2',
        Profiles.p2,
        "You can't see issues on this server.",
        "You can't manage users on this server.",
      ),
      (
        "P9, on Sara's Seerr",
        _friend,
        "Your account on Jellyseerr can't see issues.",
        "Your account on Jellyseerr can't manage users.",
      ),
    ]) {
      testWidgets('$name: said, and nothing asked that would be refused', (
        tester,
      ) async {
        final harness = await pumpWithProfile(
          tester,
          profile,
          child: const SeerrIssuesScreen(),
        );
        expect(find.text(issues), findsOneWidget);
        await harness.unmount(tester);

        final again = await pumpWithProfile(
          tester,
          profile,
          child: const SeerrUsersScreen(),
        );
        expect(find.text(users), findsOneWidget);

        final seerr = profile == _friend
            ? WorldIds.seerrFriend
            : WorldIds.seerr;
        for (final h in [harness, again]) {
          expect(
            h.network
                .requestsTo(seerr)
                .where(
                  (r) =>
                      r.path.startsWith('/api/v1/issue') ||
                      r.path == '/api/v1/user',
                ),
            isEmpty,
          );
        }

        await again.unmount(tester);
      });
    }

    group('Resolve', () {
      Iterable<Object> resolveCalls(ProfileHarness harness) => harness.network
          .requestsTo(WorldIds.seerrFriend)
          .where(
            (r) => r.method == 'POST' && r.path.startsWith('/api/v1/issue'),
          );

      testWidgets(
        "P9, seeing the issues only: Resolve on somebody else's is dimmed and "
        'says why',
        (tester) async {
          final harness = await pumpWithProfile(
            tester,
            _friend.withSeerrPermissions(
              SeerrPermission.request.value | SeerrPermission.viewIssues.value,
            ),
            child: const SeerrIssuesScreen(),
          );

          final resolve = find.byTooltip('Resolve issue');
          expect(resolve, findsOneWidget);
          await tester.tap(resolve);
          await tester.pumpAndSettle();

          expect(find.text('Resolve this issue?'), findsNothing);
          expect(
            find.text("Your account on Jellyseerr can't manage issues."),
            findsOneWidget,
          );
          expect(resolveCalls(harness), isEmpty);

          await harness.unmount(tester);
        },
      );

      testWidgets('P9, managing issues: Resolve asks, then resolves', (
        tester,
      ) async {
        final harness = await pumpWithProfile(
          tester,
          _friend.withSeerrPermissions(
            SeerrPermission.request.value | SeerrPermission.manageIssues.value,
          ),
          child: const SeerrIssuesScreen(),
        );

        await tester.tap(find.byTooltip('Resolve issue'));
        await tester.pumpAndSettle();
        expect(find.text('Resolve this issue?'), findsOneWidget);
        await tester.tap(find.text('Resolve issue'));
        await tester.pumpAndSettle();

        expect(find.text('Issue resolved'), findsOneWidget);
        expect(resolveCalls(harness), hasLength(1));

        await harness.unmount(tester);
      });
    });

    testWidgets('P1: the key reads the issues', (tester) async {
      final harness = await pumpWithProfile(
        tester,
        Profiles.p1,
        child: const SeerrIssuesScreen(),
      );

      expect(find.textContaining("can't see issues"), findsNothing);
      expect(
        harness.network
            .requestsTo(WorldIds.seerr)
            .where((r) => r.path.startsWith('/api/v1/issue')),
        isNotEmpty,
      );

      await harness.unmount(tester);
    });
  });
}
