/// The global search as the requester reads it: her Seerr's lane is
/// `Requests`, and no service is named but the players she watches with.
library;

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

    await harness.unmount(tester);
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

    await harness.unmount(tester);
  });
}
