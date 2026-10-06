/// The Discover tab's search on the profiles' fake network: the operator's
/// answer by kind, folded across every source, and the requester's, from
/// Seerr alone and in her words.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/discover/presentation/discover_atrium.dart';
import 'package:cupola/features/discover/presentation/discover_page.dart';
import 'package:cupola/features/search/presentation/global_search_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import '../../../test_helpers/profiles/profiles.dart';

Future<ProfileHarness> _search(
  WidgetTester tester,
  ConfigProfile profile, {
  String query = 'sprite',
}) async {
  final harness = await pumpWithProfile(
    tester,
    profile,
    child: const DiscoverPage(),
    overrides: [globalSearchQueryProvider.overrideWith((ref) => query)],
    surfaceSize: const Size(430, 2400),
  );
  await tester.pumpAndSettle();
  return harness;
}

void main() {
  testWidgets('P1: the answer is by kind, each title once, whoever found it', (
    tester,
  ) async {
    final harness = await _search(tester, Profiles.p1);

    // Seerr, Radarr and Jellyfin each find Sprite Fright: one row.
    expect(find.text('Sprite Fright'), findsOneWidget);
    expect(find.text('On your server'), findsOneWidget);
    // Bazarr and Lidarr are not asked; nothing is drawn by service.
    expect(find.text('Bazarr'), findsNothing);
    expect(find.text('All services'), findsNothing);
    // Music is Lidarr's own search.
    expect(find.text('Search Lidarr for “sprite”'), findsOneWidget);
    // Every source answered on a household where everything is up.
    expect(find.textContaining('did not answer'), findsNothing);

    await harness.unmount(tester);
  });

  testWidgets('P2: her answer comes from Seerr, and Seerr is named nowhere', (
    tester,
  ) async {
    final harness = await _search(tester, Profiles.p2);

    expect(find.text('Sprite Fright'), findsOneWidget);
    expect(find.textContaining('Seerr'), findsNothing);
    // No Lidarr for her, and no plus: asking is on the title's page.
    expect(find.textContaining('Lidarr'), findsNothing);
    expect(find.bySemanticsLabel(RegExp('^Add ')), findsNothing);

    await harness.unmount(tester);
  });

  testWidgets('P2: nothing found says so, never whose', (tester) async {
    final harness = await _search(
      tester,
      Profiles.p2,
      query: 'nothing in the world',
    );

    expect(find.text('Nothing called “nothing in the world”'), findsOneWidget);
    expect(find.textContaining('Seerr'), findsNothing);

    await harness.unmount(tester);
  });

  testWidgets('P2, before a word: the catalogue, never which service', (
    tester,
  ) async {
    final harness = await _search(tester, Profiles.p2, query: '');

    expect(find.byType(DiscoverAtrium), findsOneWidget);
    expect(find.textContaining('Seerr'), findsNothing);

    await harness.unmount(tester);
  });

  testWidgets('P2 with her Jellyfin: her search still asks Seerr alone', (
    tester,
  ) async {
    final harness = await _search(tester, Profiles.p2WithJellyfin);

    final legs = ProviderScope.containerOf(
      tester.element(find.byType(DiscoverPage)),
    ).read(globalSearchLegsProvider);
    expect(legs.map((leg) => leg.instance.service), [ServiceKey.seerr]);
    expect(find.textContaining('Seerr'), findsNothing);

    await harness.unmount(tester);
  });
}
