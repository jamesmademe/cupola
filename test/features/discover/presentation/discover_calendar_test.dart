import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/discover/presentation/calendar_page.dart';
import 'package:cupola/features/discover/presentation/discover_atrium.dart';
import 'package:cupola/features/discover/presentation/discover_page.dart';
import 'package:cupola/features/discover/presentation/library_calendar_provider.dart';

import '../../../test_helpers/profiles/profiles.dart';

/// The calendar of everything the household's arrs date: the atrium's band
/// that opens it, and its page, on the world of the boards (Tuesday 29
/// September, 20:53).
void main() {
  final now = DateTime(2026, 9, 29, 20, 53);

  Future<ProfileHarness> pump(
    WidgetTester tester,
    ConfigProfile profile,
    Widget child,
  ) => pumpWithProfile(
    tester,
    profile,
    child: child,
    now: now,
    overrides: [calendarClockProvider.overrideWithValue(() => now)],
    surfaceSize: const Size(430, 4000),
  );

  String band(WidgetTester tester) => tester
      .getSemantics(find.bySemanticsLabel(RegExp(r'^Calendar')).first)
      .label;

  testWidgets('P1: the band leads the atrium, names today and dots the week', (
    tester,
  ) async {
    final harness = await pump(
      tester,
      Profiles.p1,
      const Scaffold(body: DiscoverAtrium()),
    );

    expect(find.text('Calendar'), findsOneWidget);
    expect(
      band(tester),
      'Calendar: today Sprite Fright, on digital, and 3 more days this week '
      'have something',
    );
    // Above the doors.
    expect(
      tester.getTopLeft(find.text('Calendar')).dy,
      lessThan(tester.getTopLeft(find.text('Trending')).dy),
    );

    await harness.unmount(tester);
  });

  testWidgets('P1: the page, its answer, the rows of every arr and the '
      'kinds', (tester) async {
    final harness = await pump(tester, Profiles.p1, const CalendarPage());

    expect(
      find.textContaining('things come out or air this week. Today:'),
      findsOneWidget,
    );
    expect(
      find.text('From Radarr 1, Radarr 4K, Sonarr and Lidarr at 20:53'),
      findsOneWidget,
    );
    expect(find.text('Out today · downloading 62%'), findsOneWidget);
    // The first Radarr, unnamed, is called by its place.
    expect(find.text('Radarr 1'), findsWidgets);
    expect(find.text('Tomorrow'), findsOneWidget);
    expect(find.text('S2 E5 · not aired'), findsOneWidget);
    expect(find.text('Nothing more in the next 30 days'), findsOneWidget);
    expect(
      find.text('Books appear here when Readarr is set up.'),
      findsOneWidget,
    );

    // A row is one sentence.
    expect(
      find.bySemanticsLabel(
        RegExp(r'^Today, Sprite Fright, movie out on digital, downloading'),
      ),
      findsOneWidget,
    );

    // Series only: the movie goes.
    await tester.tap(find.text('Series'));
    await tester.pumpAndSettle();
    expect(find.text('Out today · downloading 62%'), findsNothing);
    expect(find.text('S2 E5 · not aired'), findsOneWidget);

    await harness.unmount(tester);
  });

  testWidgets('P7, Lidarr home-only: its rows go, it is named once with '
      'what may be missing, and the count is not stated', (tester) async {
    final harness = await pump(tester, Profiles.p7, const CalendarPage());

    expect(
      find.textContaining('Lidarr did not answer · albums may be missing here'),
      findsOneWidget,
    );
    expect(find.textContaining('— things come out'), findsOneWidget);

    await harness.unmount(tester);
  });

  testWidgets('P4, no Seerr: the band stands over the catalogue slab', (
    tester,
  ) async {
    final harness = await pump(tester, Profiles.p4, const DiscoverPage());

    expect(find.text('Calendar'), findsOneWidget);
    expect(find.text('The catalogue comes from Seerr'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Calendar')).dy,
      lessThan(tester.getTopLeft(find.text('The catalogue comes from Seerr')).dy),
    );

    await harness.unmount(tester);
  });

  testWidgets('P2, the requester: no band from the arrs', (tester) async {
    final harness = await pump(
      tester,
      Profiles.p2,
      const Scaffold(body: DiscoverAtrium()),
    );

    expect(find.text('Calendar'), findsNothing);

    await harness.unmount(tester);
  });
}
