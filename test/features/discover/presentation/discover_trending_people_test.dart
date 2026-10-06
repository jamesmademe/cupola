/// Trending is a rail of titles, and TMDB's trending, which Seerr relays,
/// mixes people in with them.
///
/// A person kept in it opened as the movie her TMDB id happens to name, and
/// when she trended first she led the featured banner: a person's name over a
/// "Request" for a film that is not hers.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/discover/presentation/discover_provider.dart';
import 'package:cupola/features/discover/presentation/discover_page.dart';

import '../../../test_helpers/profiles/profiles.dart';

void main() {
  test('P1: trending holds the titles and no person', () async {
    final harness = await ProfileHarness.start(Profiles.p1);
    final container = harness.container(retry: (_, _) => null);

    final trending = await container.read(discoverTrendingProvider.future);

    expect(trending.map((item) => item.title), isNot(contains('Elena Varga')));
    expect(
      trending.map((item) => item.mediaType).toSet(),
      everyElement(isIn(const {'movie', 'tv'})),
    );
    expect(trending.first.title, WorldTitles.spriteFright.title);
  });

  testWidgets('P1: the featured banner is a title, never the person who '
      'trends first', (tester) async {
    final harness = await pumpWithProfile(
      tester,
      Profiles.p1,
      child: const DiscoverPage(),
      surfaceSize: const Size(430, 3000),
    );

    expect(find.text('Elena Varga'), findsNothing);
    expect(find.text(WorldTitles.spriteFright.title), findsWidgets);

    await harness.unmount(tester);
  });
}
