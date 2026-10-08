/// One smoke test per profile: the Stack — the screen that reaches every
/// configured service, through its own probe and its own clients — builds and
/// settles under each configuration without an exception.
///
/// Deliberately asserts nothing about what the Stack says. Some of what it
/// says under these profiles is known to be wrong today (a missing figure reads
/// 0); the packages that fix those assert them — the probe's own verdicts are
/// in `test/features/services/presentation/probe_classification_test.dart`. This only guarantees the profile itself is sound enough to
/// test on.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/services/presentation/stack_screen.dart';

import '../../test_helpers/profiles/profiles.dart';

void main() {
  for (final profile in Profiles.all) {
    testWidgets('${profile.id} (${profile.title}): the Stack settles', (
      tester,
    ) async {
      final harness = await pumpWithProfile(
        tester,
        profile,
        child: const StackScreen(),
        surfaceSize: const Size(430, 2400),
      );

      expect(find.byType(StackScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
      // Every configured connection was asked something.
      for (final connection in profile.connections) {
        expect(
          harness.network.requestsTo(connection.id),
          isNotEmpty,
          reason: '${connection.id} was never reached',
        );
      }
      await harness.unmount(tester);
    });
  }
}
