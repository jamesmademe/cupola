import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/discover/presentation/seerr_overview_screen.dart';
import 'package:cupola/features/services/presentation/service_all_screens.dart';

import '../../../test_helpers/profiles/profiles.dart';

/// Both "N waiting" headers link to lists that can answer what they list.
///
/// P6's Seerr has two requests waiting (Charge, Metropolis) and five already
/// approved. The Seerr Overview's Needs a decision rows and the Requests tab
/// listed the waiting ones without Approve or Decline.
void main() {
  Iterable<String> seerrWrites(ProfileHarness harness) => harness.network
      .requestsTo(WorldIds.seerr)
      .where((r) => r.method != 'GET')
      .map((r) => '${r.method} ${r.uri.path}');

  Future<void> answer(
    WidgetTester tester,
    ProfileHarness harness, {
    required String tooltip,
    required String confirm,
  }) async {
    final button = find.byTooltip(tooltip);
    await tester.ensureVisible(button);
    await tester.tap(button);
    await harness.settle(tester);
    await tester.tap(find.widgetWithText(FilledButton, confirm));
    await harness.settle(tester);
  }

  group('Seerr Overview, Needs a decision', () {
    Future<ProfileHarness> pump(WidgetTester tester) => pumpWithProfile(
      tester,
      Profiles.p6,
      child: const SeerrOverviewScreen(topPadding: 0),
      // A phone: the narrowest the pair has to fit beside a row.
      surfaceSize: const Size(375, 812),
    );

    testWidgets('P6: each waiting request has its two answers', (tester) async {
      final harness = await pump(tester);

      for (final title in ['Charge', 'Metropolis']) {
        expect(find.byTooltip('Approve request for $title'), findsOneWidget);
        expect(find.byTooltip('Decline request for $title'), findsOneWidget);
      }
      // Processing is not a decision.
      expect(find.byTooltip('Approve request for Sprite Fright'), findsNothing);

      await harness.unmount(tester);
    });

    testWidgets('P6: Approve names the server, then approves that request', (
      tester,
    ) async {
      final harness = await pump(tester);

      final button = find.byTooltip('Approve request for Charge');
      await tester.ensureVisible(button);
      await tester.tap(button);
      await harness.settle(tester);
      expect(
        find.text('Charge goes to Radarr and starts downloading.'),
        findsOneWidget,
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Approve request'));
      await harness.settle(tester);

      expect(seerrWrites(harness), ['POST /api/v1/request/1/approve']);

      await harness.unmount(tester);
    });

    testWidgets('P6: Decline asks, neutrally, then declines', (tester) async {
      final harness = await pump(tester);

      await answer(
        tester,
        harness,
        tooltip: 'Decline request for Metropolis',
        confirm: 'Decline request',
      );

      expect(seerrWrites(harness), ['POST /api/v1/request/2/decline']);

      await harness.unmount(tester);
    });
  });

  group('Requests tab', () {
    Future<ProfileHarness> pump(WidgetTester tester) => pumpWithProfile(
      tester,
      Profiles.p6,
      child: const ServiceAllRequestsScreen(),
      // A phone. The requester line overflowed the row by 68px here, which
      // fails the pump.
      surfaceSize: const Size(375, 812),
    );

    testWidgets('P6: a waiting request has its two answers, an approved one '
        'none', (tester) async {
      final harness = await pump(tester);

      for (final title in ['Charge', 'Metropolis']) {
        expect(find.byTooltip('Approve request for $title'), findsOneWidget);
        expect(find.byTooltip('Decline request for $title'), findsOneWidget);
      }
      expect(find.byTooltip('Approve request for Sprite Fright'), findsNothing);
      expect(
        find.byTooltip('Delete request for Sprite Fright'),
        findsOneWidget,
      );

      await harness.unmount(tester);
    });

    testWidgets('P6: Approve approves the request on the lens Seerr', (
      tester,
    ) async {
      final harness = await pump(tester);

      await answer(
        tester,
        harness,
        tooltip: 'Approve request for Metropolis',
        confirm: 'Approve request',
      );

      expect(seerrWrites(harness), ['POST /api/v1/request/2/approve']);

      await harness.unmount(tester);
    });
  });
}
