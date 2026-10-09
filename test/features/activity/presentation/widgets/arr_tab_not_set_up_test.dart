import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/activity/domain/service_type.dart';
import 'package:cupola/features/activity/presentation/arr_tab_screen.dart';

import '../../../../test_helpers/profiles/profiles.dart';

/// A service's Queue, Wanted and History tabs ask whether it is set up before
/// they read it.
///
/// The tabs used to read their arr in `initState`, and the service provider
/// throws for a connection that is not set up, so the route was a build that
/// failed rather than a page that said why.
void main() {
  Finder setUpButton(String service) => find.ancestor(
    of: find.text('Set up $service'),
    matching: find.byWidgetPredicate((widget) => widget is FilledButton),
  );

  // P5 knows its Radarr and Sonarr only through Seerr: Cupola has no
  // connection to either, so their tabs have nothing of their own to read.
  for (final mode in ArrTabMode.values) {
    testWidgets('P5: Radarr\'s ${mode.name} tab says Radarr is not set up', (
      tester,
    ) async {
      final harness = await pumpWithProfile(
        tester,
        Profiles.p5,
        child: ArrTabScreen(serviceType: ServiceType.movies, mode: mode),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('Radarr is not set up'), findsOneWidget);
      expect(setUpButton('Radarr'), findsOneWidget);
      // Not even the Radarr Seerr knows: that one is Seerr's, not Cupola's.
      expect(harness.network.requestsTo(WorldIds.radarr), isEmpty);

      await harness.unmount(tester);
    });
  }

  testWidgets('P3: Sonarr\'s queue tab reads the Sonarr it has', (
    tester,
  ) async {
    final harness = await pumpWithProfile(
      tester,
      Profiles.p3,
      child: const Scaffold(
        body: ArrTabScreen(
          serviceType: ServiceType.series,
          mode: ArrTabMode.queue,
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Sonarr is not set up'), findsNothing);
    expect(harness.network.requestsTo(WorldIds.sonarr), isNotEmpty);

    await harness.unmount(tester);
  });
}
