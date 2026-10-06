import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/activity/presentation/arr_calendar_screen.dart';
import 'package:cupola/features/discover/presentation/library_calendar_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import '../../../test_helpers/profiles/profiles.dart';

/// An arr's Calendar tab is Discover's calendar filtered to the connection
/// the lens is on: the same rows, a movie as many as its releases in the
/// thirty days, and no connection named, the room being the connection's.
void main() {
  final now = DateTime(2026, 9, 29, 20, 53);

  testWidgets("P1, Radarr: both of a movie's releases, each its own row", (
    tester,
  ) async {
    final harness = await pumpWithProfile(
      tester,
      Profiles.p1,
      child: const Scaffold(
        body: ArrCalendarScreen(service: ServiceKey.radarr),
      ),
      now: now,
      overrides: [calendarClockProvider.overrideWithValue(() => now)],
      surfaceSize: const Size(430, 2000),
    );

    expect(find.text('Sprite Fright'), findsNWidgets(2));
    expect(find.text('Digital'), findsOneWidget);
    expect(find.text('Disc'), findsOneWidget);
    expect(find.text('Out today · downloading 62%'), findsOneWidget);
    expect(find.text('Not out yet'), findsOneWidget);
    // The room is Radarr's: no row names it.
    expect(find.text('Radarr 1'), findsNothing);
    expect(find.text('Nothing more in the next 30 days'), findsOneWidget);

    await harness.unmount(tester);
  });
}
