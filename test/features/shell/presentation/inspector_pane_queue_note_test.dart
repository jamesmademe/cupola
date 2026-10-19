/// The inspector's queue note says what answered.
///
/// The pane's failure note hung off `AsyncError`, and a queue load never
/// produces one: every connection's failure is caught and carried on its own
/// result. So three \*arrs that all failed read "Nothing downloading right
/// now", the one sentence the pane could not know to be true.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/activity/presentation/activity_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/shell/domain/stack_health.dart';
import 'package:cupola/features/shell/presentation/desktop/inspector_pane.dart';

import '../../../test_helpers/profiles/profiles.dart';
import '../../../test_helpers/settings_scope.dart';

Widget _pane() => const Scaffold(
  body: Row(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [SizedBox(width: 360, child: InspectorPane())],
  ),
);

void main() {
  testWidgets('P1 with every *arr down: the queue could not be read', (
    tester,
  ) async {
    final harness = await pumpWithProfile(
      tester,
      Profiles.p1
          .withBehaviour(WorldIds.radarr, ConnectionBehaviour.didNotAnswer)
          .withBehaviour(WorldIds.radarr4k, ConnectionBehaviour.didNotAnswer)
          .withBehaviour(WorldIds.sonarr, ConnectionBehaviour.refusesKey)
          .withBehaviour(WorldIds.lidarr, ConnectionBehaviour.didNotAnswer),
      // The dark-service line is the Dashboard probe's, and not what this is
      // about.
      overrides: [unreachableServicesProvider.overrideWithValue(const [])],
      child: _pane(),
    );

    expect(
      find.text('The queue could not be read. Open Activity to retry.'),
      findsOneWidget,
    );
    expect(find.text('Nothing downloading right now.'), findsNothing);

    await harness.unmount(tester);
  });

  testWidgets('an empty queue beside a failure names what it left out', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...await settingsScopeOverrides(),
          globalNowItemsProvider.overrideWith(
            (ref) async => const ActivityFeed(
              items: [],
              results: [
                ActivityServiceResult(
                  service: ServiceKey.radarr,
                  items: [],
                  total: 0,
                  configured: true,
                ),
                ActivityServiceResult(
                  service: ServiceKey.sonarr,
                  instanceId: 'anime',
                  label: 'Anime',
                  items: [],
                  configured: true,
                  error: SocketException('Connection refused'),
                ),
              ],
            ),
          ),
          unreachableServicesProvider.overrideWithValue(const []),
        ],
        child: MaterialApp(home: _pane()),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Nothing downloading right now. Sonarr Anime not counted.'),
      findsOneWidget,
    );

    // The pane polls while it is mounted, and a test that ends with it mounted
    // ends with a timer pending: the poll stops a frame behind the pane.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
}
