import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/discover/presentation/discover_atrium.dart';
import 'package:cupola/features/discover/presentation/widgets/collection_tally.dart';

import '../../../test_helpers/profiles/fakes/media_fakes.dart';
import '../../../test_helpers/profiles/profiles.dart';

/// The atrium's shelves that know the library: the collection the operator
/// is part way through, from Radarr and Seerr, and TMDB's recommendations
/// for what the household finished last on its media server.
Future<ProfileHarness> _atrium(WidgetTester tester, ConfigProfile profile) =>
    pumpWithProfile(
      tester,
      profile,
      child: const Scaffold(body: DiscoverAtrium()),
      surfaceSize: const Size(430, 3200),
    );

void main() {
  testWidgets('P1: the collection nearest to whole, then what follows the '
      'last thing watched', (tester) async {
    final harness = await _atrium(tester, Profiles.p1);

    expect(find.text(CollectionTally.invitationTitle), findsOneWidget);
    expect(
      find.text('${SeerrFake.collectionName} · 5 of 8 on your server'),
      findsOneWidget,
    );
    expect(find.text('2 on the way'), findsOneWidget);
    expect(find.text('1 waiting for approval'), findsOneWidget);
    // The slab is one button, and says the whole of it once.
    expect(
      find.bySemanticsLabel(
        'Complete the collection, ${SeerrFake.collectionName}, '
        '5 of 8 on your server, 2 on the way, 1 waiting for approval',
      ),
      findsOneWidget,
    );
    // The approval is the collection's page's, not the atrium's.
    expect(find.text('Approve'), findsNothing);

    expect(find.text('Because you watched Tears of Steel'), findsOneWidget);
    // Above the shelves that do not know the library.
    expect(
      tester.getTopLeft(find.text('Because you watched Tears of Steel')).dy,
      lessThan(tester.getTopLeft(find.text('The best you’re missing')).dy),
    );
    expect(
      tester.getTopLeft(find.text(CollectionTally.invitationTitle)).dy,
      lessThan(
        tester.getTopLeft(find.text('Because you watched Tears of Steel')).dy,
      ),
    );

    await harness.unmount(tester);
  });

  testWidgets('P2: her atrium does not read Radarr, and names no service', (
    tester,
  ) async {
    final harness = await _atrium(tester, Profiles.p2);

    expect(find.text(CollectionTally.invitationTitle), findsNothing);
    expect(find.textContaining('Radarr'), findsNothing);
    expect(find.textContaining('Seerr'), findsNothing);

    await harness.unmount(tester);
  });

  testWidgets('P3, no media server: nothing watched to recommend from', (
    tester,
  ) async {
    final harness = await _atrium(tester, Profiles.p3);

    expect(find.textContaining('Because you watched'), findsNothing);

    await harness.unmount(tester);
  });
}
