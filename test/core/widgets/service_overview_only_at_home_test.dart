/// Away from home, the Overview of a connection reached only at home says so
/// once, under its identity line, instead of once per section.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/discover/presentation/seerr_overview_screen.dart';
import 'package:cupola/features/movies/presentation/radarr_overview_screen.dart';
import 'package:cupola/features/settings/data/connection_reach_provider.dart';
import 'package:cupola/features/settings/domain/connection_address.dart';

import '../../test_helpers/profiles/profiles.dart';

const _seerrLine =
    'Seerr has no address away, so Cupola reaches it only on your home Wi-Fi.';

void main() {
  testWidgets('one line and one remedy, not one per section', (tester) async {
    final harness = await pumpWithProfile(
      tester,
      Profiles.p3,
      overrides: [awayFromHomeProvider.overrideWithValue(true)],
      surfaceSize: const Size(430, 1600),
      child: const SeerrOverviewScreen(topPadding: 0),
    );

    expect(find.text(_seerrLine), findsOneWidget);
    expect(find.text('Add an address away'), findsOneWidget);
    expect(find.textContaining('is not shown'), findsNothing);
    expect(find.text('Needs a decision'), findsNothing);

    await harness.unmount(tester);
  });

  testWidgets('at home the sections are drawn as ever', (tester) async {
    final harness = await pumpWithProfile(
      tester,
      Profiles.p3,
      surfaceSize: const Size(430, 1600),
      child: const SeerrOverviewScreen(topPadding: 0),
    );

    expect(find.text(_seerrLine), findsNothing);
    expect(find.text('Needs a decision'), findsOneWidget);

    await harness.unmount(tester);
  });

  testWidgets('a connection with an address away keeps its sections away', (
    tester,
  ) async {
    final harness = await pumpWithProfile(
      tester,
      Profiles.p3.withConnection(
        ProfileConnection(
          WorldConnections.radarr.instance.copyWith(
            away: const ConnectionAddress(url: 'https://radarr.example.net'),
          ),
        ),
      ),
      overrides: [awayFromHomeProvider.overrideWithValue(true)],
      surfaceSize: const Size(430, 1600),
      child: const RadarrOverviewScreen(topPadding: 0),
    );

    expect(find.textContaining('has no address away'), findsNothing);
    expect(find.text('Add an address away'), findsNothing);

    await harness.unmount(tester);
  });
}
