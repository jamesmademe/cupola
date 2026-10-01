/// The release-search card on a series page finds the search the page
/// started.
///
/// The card's target was the only one on the page not stamped with its
/// connection, and target equality includes the connection, so the whole-series
/// search the menu started matched nothing and the card stayed blank while it
/// ran. The movie and artist pages stamp theirs.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/release_search/presentation/release_search_entry.dart';
import 'package:cupola/features/release_search/presentation/release_search_jobs_provider.dart';
import 'package:cupola/features/release_search/presentation/widgets/release_search_status_card.dart';
import 'package:cupola/features/series/presentation/series_detail_screen.dart';

import '../../../test_helpers/profiles/profiles.dart';

void main() {
  for (final (label, profile, instanceId) in [
    ('P1, the lens', Profiles.p1, WorldIds.sonarr),
    ('P6, the anime Sonarr', Profiles.p6, WorldIds.sonarrAnime),
  ]) {
    testWidgets('$label: a running whole-series search shows on the card', (
      tester,
    ) async {
      final harness = await pumpWithProfile(
        tester,
        profile,
        surfaceSize: const Size(430, 4000),
        child: SeriesDetailScreen(
          seriesId: 1,
          heroTag: 'series-1',
          instanceId: instanceId == WorldIds.sonarr ? null : instanceId,
        ),
      );

      final container = ProviderScope.containerOf(
        tester.element(find.byType(SeriesDetailScreen)),
      );
      final jobs = container.read(releaseSearchJobsProvider.notifier);
      jobs.configure(runner: (_, _) => Completer<List<dynamic>>().future);
      // The target the series menu hands `showReleaseSearch`, stamped there
      // with the page's connection.
      jobs.start(
        sonarrSeasonTarget(
          seriesId: 1,
          seasonNumber: null,
          label: 'Series',
        ).stampedWith(instanceId),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        find.descendant(
          of: find.byType(ReleaseSearchStatusCard),
          matching: find.textContaining('Searching'),
        ),
        findsOneWidget,
      );

      await harness.unmount(tester);
    });
  }
}
