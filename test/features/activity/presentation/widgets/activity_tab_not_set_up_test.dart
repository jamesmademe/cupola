import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/activity/domain/service_type.dart';
import 'package:cupola/features/activity/presentation/activity_screen.dart';
import 'package:cupola/features/activity/presentation/widgets/activity_tab.dart';

import '../../../../test_helpers/profiles/profiles.dart';

/// `/activity/{type}` asks whether the arr is set up before it reads one.
///
/// The tab used to read its service in `initState`, and the service provider
/// throws for a connection that is not set up, so the route was a build that
/// failed rather than a page that said why.
void main() {
  // P5 knows its Radarr and Sonarr only through Seerr: Cupola has no
  // connection to either, so the Movies activity has nothing of its own to
  // read.
  testWidgets('P5: Movies activity says Radarr is not set up', (tester) async {
    final harness = await pumpWithProfile(
      tester,
      Profiles.p5,
      child: const ActivityScreen(serviceType: ServiceType.movies),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Radarr is not set up'), findsOneWidget);
    expect(
      find.ancestor(
        of: find.text('Set up Radarr'),
        matching: find.byWidgetPredicate((widget) => widget is FilledButton),
      ),
      findsOneWidget,
    );
    // Not even the Radarr Seerr knows: that one is Seerr's, not Cupola's.
    expect(harness.network.requestsTo(WorldIds.radarr), isEmpty);

    await harness.unmount(tester);
  });

  testWidgets('P3: Series activity reads the Sonarr it has', (tester) async {
    final harness = await pumpWithProfile(
      tester,
      Profiles.p3,
      child: const Scaffold(body: ActivityTab(serviceType: ServiceType.series)),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Sonarr is not set up'), findsNothing);
    expect(harness.network.requestsTo(WorldIds.sonarr), isNotEmpty);

    await harness.unmount(tester);
  });
}
