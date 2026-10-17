/// Needs you, whole, on P1: what its heading says, every fault on a card of
/// its own with its evidence, and the two ways in, the heading on All and the
/// Home's Review.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/router.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/features/activity/presentation/activity_needs_you_page.dart';
import 'package:cupola/features/activity/presentation/widgets/activity_section.dart';
import 'package:cupola/features/activity/presentation/widgets/fault_card.dart';
import 'package:cupola/features/home/presentation/widgets/needs_you_banner.dart';
import 'package:cupola/features/services/presentation/dashboard_sections.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';

import '../../../test_helpers/profiles/profiles.dart';

/// Friday 9 October 2026, 20:53: the evening the world is drawn in.
final _now = DateTime(2026, 10, 9, 20, 53);

/// The whole app, on [profile]'s household, with its own router.
Future<(ProfileHarness, GoRouter, ProviderContainer)> _app(
  WidgetTester tester,
  ConfigProfile profile,
) async {
  tester.view.physicalSize = const Size(390, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final harness = await ProfileHarness.start(
    profile,
    now: _now,
    overrides: [
      arrivalsClockProvider.overrideWith(
        (ref) =>
            () => _now,
      ),
      stallClockProvider.overrideWith(
        (ref) =>
            () => _now,
      ),
    ],
  );
  harness.network.followFakeTime(tester.binding);
  final container = harness.container();
  final router = container.read(routerProvider);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        theme: AppTheme.darkTheme(),
        routerConfig: router,
      ),
    ),
  );
  await _answer(tester);
  return (harness, router, container);
}

/// Lets the household's servers answer.
Future<void> _answer(WidgetTester tester) async {
  for (var i = 0; i < 25; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// The app down, then its providers: the whole app keeps timers of its own
/// that only the container's end cancels.
Future<void> _close(
  WidgetTester tester,
  ProfileHarness harness,
  ProviderContainer container,
) async {
  await tester.pumpWidget(const SizedBox.shrink());
  container.dispose();
  await harness.unmount(tester);
}

Future<void> _tap(WidgetTester tester, Finder row) async {
  await tester.ensureVisible(row.first);
  await tester.pump();
  await tester.tap(row.first);
  await _answer(tester);
}

void main() {
  testWidgets('P1: the heading counts faults and requests apart and says '
      'who answered, then each fault is a card of its own', (tester) async {
    final (harness, router, container) = await _app(tester, Profiles.p1);
    router.go(ServiceRoutes.activityNeedsYou);
    await _answer(tester);

    expect(find.byType(ActivityNeedsYouPage), findsOneWidget);
    expect(find.text('3 faults'), findsOneWidget);
    expect(find.text('3 requests'), findsOneWidget);
    expect(
      find.textContaining(RegExp(r'^All \d+ services answered at 20:53$')),
      findsOneWidget,
    );
    expect(find.byType(FaultCard), findsNWidgets(3));
    // The pool's evidence, whole, and TrueNAS's own words already open.
    expect(find.text('Pool tank\u00A0· Healthy\u00A0· 72%'), findsOneWidget);
    expect(find.text('Disk sdd\u00A0· 8 errors'), findsOneWidget);
    expect(
      find.text('8 uncorrectable errors reported for sdd (ZL2PQR7T).'),
      findsOneWidget,
    );
    // The requests, after the faults, with Approve and Decline.
    expect(find.text('3 requests wait for your approval'), findsOneWidget);
    expect(find.byType(DecisionRow), findsNWidgets(3));

    await _close(tester, harness, container);
  });

  testWidgets('P1: a stuck card says how long nothing arrived once, in its '
      'explanation, and its route once, in its proof', (tester) async {
    final (harness, router, container) = await _app(tester, Profiles.p1);
    router.go(ServiceRoutes.activityNeedsYou);
    await _answer(tester);

    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Text &&
            (widget.data ?? '').startsWith('Nothing has arrived for '),
      ),
      findsOneWidget,
    );
    expect(find.text('Radarr 1 → qBittorrent'), findsOneWidget);
    expect(find.text('Radarr 1\u00A0· qBittorrent'), findsNothing);
    expect(find.textContaining('Nothing for '), findsNothing);

    await _close(tester, harness, container);
  });

  testWidgets('the heading of Needs you on All opens the page, and Back '
      'returns to All', (tester) async {
    final (harness, router, container) = await _app(tester, Profiles.p1);
    router.go(ServiceRoutes.activity);
    await _answer(tester);

    await _tap(
      tester,
      find.descendant(
        of: find.byWidgetPredicate(
          (widget) => widget is ActivitySection && widget.title == 'Needs you',
        ),
        matching: find.text('3 faults\u00A0· 3 requests'),
      ),
    );
    expect(router.state.uri.path, ServiceRoutes.activityNeedsYou);
    expect(find.byType(ActivityNeedsYouPage), findsOneWidget);

    router.pop();
    await _answer(tester);
    expect(router.state.uri.path, ServiceRoutes.activity);

    await _close(tester, harness, container);
  });

  testWidgets("the Home's Review opens Needs you", (tester) async {
    final (harness, router, container) = await _app(tester, Profiles.p1);
    router.go(ServiceRoutes.home);
    await _answer(tester);

    await _tap(
      tester,
      find.descendant(
        of: find.byType(NeedsYouBanner),
        matching: find.text('Review'),
      ),
    );

    expect(router.state.uri.path, ServiceRoutes.activityNeedsYou);
    expect(find.byType(ActivityNeedsYouPage), findsOneWidget);

    await _close(tester, harness, container);
  });
}
