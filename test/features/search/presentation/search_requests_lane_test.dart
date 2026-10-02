/// The global search as the requester reads it: her Seerr's lane is
/// `Requests`, and no service is named but the players she watches with.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/search/presentation/global_search_provider.dart';
import 'package:cupola/features/search/presentation/search_screen.dart';

import '../../../test_helpers/profiles/profiles.dart';

Future<ProfileHarness> _search(
  WidgetTester tester,
  ConfigProfile profile, {
  String query = 'sprite',
}) => pumpWithProfile(
  tester,
  profile,
  child: const SearchScreen(),
  overrides: [globalSearchQueryProvider.overrideWith((ref) => query)],
  surfaceSize: const Size(430, 2400),
);

void main() {
  testWidgets('P2: the lane is Requests, and Seerr is named nowhere', (
    tester,
  ) async {
    final harness = await _search(tester, Profiles.p2);

    expect(find.text('Requests'), findsWidgets);
    expect(find.textContaining('Sprite Fright'), findsWidgets);
    expect(find.textContaining('Seerr'), findsNothing);
    // They have no services, so the first filter does not say so.
    expect(find.text('All'), findsOneWidget);
    expect(find.text('All services'), findsNothing);
    // The heading is the word alone: they search for something to ask for.
    expect(find.text('across every service'), findsNothing);
    // And the field promises only what their Seerr finds.
    expect(find.text('Movies, series, artists'), findsNothing);

    await harness.unmount(tester);
  });

  testWidgets('P2 on a desktop: no count of the connections asked', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    // A window wide enough for the readout, which starts at 1100.
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    try {
      for (final (profile, census) in [
        (Profiles.p1, findsOneWidget),
        (Profiles.p2, findsNothing),
      ]) {
        final harness = await pumpWithProfile(
          tester,
          profile,
          child: const SearchScreen(),
          overrides: [
            globalSearchQueryProvider.overrideWith((ref) => 'sprite'),
          ],
        );
        expect(
          find.textContaining(RegExp(r'connections? asked')),
          census,
          reason: profile.id,
        );
        await harness.unmount(tester);
      }
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('P2: an empty lane says no results, not whose', (tester) async {
    final harness = await _search(
      tester,
      Profiles.p2,
      query: 'nothing in the world',
    );

    expect(find.text('No results'), findsOneWidget);
    expect(find.textContaining('Seerr'), findsNothing);

    await harness.unmount(tester);
  });

  testWidgets('P2, before a word: what she can find, never which service', (
    tester,
  ) async {
    final harness = await _search(tester, Profiles.p2, query: '');

    expect(find.text('Search movies and series'), findsOneWidget);
    expect(
      find.text('Enter a title to find something to ask for.'),
      findsOneWidget,
    );
    expect(find.textContaining('Seerr'), findsNothing);

    await harness.unmount(tester);
  });

  testWidgets('P2 with her Jellyfin: the player is named, Seerr is not', (
    tester,
  ) async {
    final harness = await _search(tester, Profiles.p2WithJellyfin, query: '');

    expect(
      find.text(
        'Enter a title to find something to ask for, or to watch on '
        'Jellyfin.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('Seerr'), findsNothing);

    await harness.unmount(tester);
  });

  testWidgets('P1: the operator reads the lane by its service', (tester) async {
    final harness = await _search(tester, Profiles.p1);

    expect(find.text('Seerr'), findsWidgets);
    expect(find.text('Requests'), findsNothing);
    expect(find.text('All services'), findsOneWidget);
    expect(find.text('across every service'), findsOneWidget);

    await harness.unmount(tester);
  });
}
