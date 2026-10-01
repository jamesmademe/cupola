import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/activity/presentation/global_activity_screen.dart';

import '../../../test_helpers/profiles/profiles.dart';

void main() {
  // Both lines of the strip carried the one `activity-fault-line` key, so a
  // load with a silent connection and a refusing one at the same time threw
  // "Duplicate keys found" and the page drew the framework's error instead.
  testWidgets('P7: a silent and a refusing connection share the strip', (
    tester,
  ) async {
    final harness = await pumpWithProfile(
      tester,
      // Lidarr is away from home in P7; Sonarr refusing its key adds the
      // amber line beside the red one.
      Profiles.p7.withBehaviour(
        WorldIds.sonarr,
        ConnectionBehaviour.refusesKey,
      ),
      child: const GlobalActivityScreen(),
    );

    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('activity-fault-line')), findsNWidgets(2));
    expect(find.text('Lidarr did not answer'), findsOneWidget);
    expect(find.text('Sonarr answered but refused the key'), findsOneWidget);

    await harness.unmount(tester);
  });
}
