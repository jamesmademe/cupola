import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/discover/presentation/discover_detail_screen.dart';

import '../../../test_helpers/profiles/profiles.dart';

/// A Seerr page reads both copies of a title: the standard one and the 4K
/// one, each in its own state.
///
/// P1 is the household with Radarr and Radarr 4K side by side, and Seerr
/// sending to both. Elephants Dream is on disk in HD while its 4K copy is
/// downloading on Radarr 4K; Coffee Run has no 4K copy at all.
void main() {
  List<String> badges(WidgetTester tester) => tester
      .widgetList<StatusBadge>(
        find.descendant(
          of: find.byType(MediaDetailPosterRow),
          matching: find.byType(StatusBadge),
        ),
      )
      .map((badge) => badge.info.label)
      .toList();

  Future<ProfileHarness> pump(WidgetTester tester, WorldTitle title) async {
    final harness = await ProfileHarness.start(Profiles.p1);
    await tester.pumpWidget(
      ProviderScope(
        overrides: harness.overrides,
        child: MaterialApp(
          theme: AppTheme.darkTheme(),
          home: Scaffold(
            body: DiscoverDetailScreen(
              mediaId: title.tmdbId,
              mediaType: 'movie',
              heroTag: 'discover_movie_${title.key}',
            ),
          ),
        ),
      ),
    );
    await harness.settle(tester);
    return harness;
  }

  testWidgets('P1: a title on disk in HD and downloading in 4K reads both', (
    tester,
  ) async {
    final harness = await pump(tester, WorldTitles.elephantsDream);

    // It read "Available" alone: the 4K copy on its way was not on the page.
    expect(badges(tester), ['Available', '4K: Downloading']);

    await harness.unmount(tester);
  });

  testWidgets('P1: a title with no 4K copy reads one badge', (tester) async {
    final harness = await pump(tester, WorldTitles.coffeeRun);

    expect(badges(tester), ['Available']);

    await harness.unmount(tester);
  });

  testWidgets('P1: a title only in 4K reads its 4K state alone', (
    tester,
  ) async {
    // Spring: no standard copy (Seerr's 1), on disk on Radarr 4K.
    final harness = await pump(tester, WorldTitles.spring);

    // It read "Unknown" beside the 4K state.
    expect(badges(tester), ['4K: Available']);

    await harness.unmount(tester);
  });
}
