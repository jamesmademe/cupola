/// A detail page says which connection it reads, once there are two.
///
/// The connection a page belongs to travels in its `?i=`, and the tab bar
/// that carries the lens is covered by the page. So a film opened from the
/// 4K's row was the 4K's film with nothing on it saying so, beside the HD's
/// copy of the same film that looks identical.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/widgets/connection_badge.dart';
import 'package:cupola/features/movies/presentation/movie_detail_screen.dart';
import 'package:cupola/features/music/presentation/music_detail_screen.dart';
import 'package:cupola/features/series/presentation/series_detail_screen.dart';

import '../../../test_helpers/profiles/profiles.dart';

const _tall = Size(800, 3000);

Finder _badge(String label) => find.byWidgetPredicate(
  (widget) => widget is ConnectionBadge && widget.label == label,
);

void main() {
  testWidgets('P1, lens on the HD: a film opened on the 4K says 4K', (
    tester,
  ) async {
    final harness = await pumpWithProfile(
      tester,
      Profiles.p1,
      surfaceSize: _tall,
      child: const MovieDetailScreen(
        movieId: 1,
        heroTag: 'movie-1',
        instanceId: WorldIds.radarr4k,
      ),
    );

    expect(find.text('Elephants Dream'), findsWidgets);
    expect(_badge('4K'), findsOne);

    await harness.unmount(tester);
  });

  testWidgets('P1: the lens is named too, the one nobody named by its place', (
    tester,
  ) async {
    final harness = await pumpWithProfile(
      tester,
      Profiles.p1,
      surfaceSize: _tall,
      child: const MovieDetailScreen(movieId: 1, heroTag: 'movie-1'),
    );

    expect(find.text('Sprite Fright'), findsWidgets);
    expect(_badge('Radarr 1'), findsOne);

    await harness.unmount(tester);
  });

  testWidgets('P6: a series on the anime Sonarr says Anime', (tester) async {
    final harness = await pumpWithProfile(
      tester,
      Profiles.p6,
      surfaceSize: _tall,
      child: const SeriesDetailScreen(
        seriesId: 1,
        heroTag: 'series-1',
        instanceId: WorldIds.sonarrAnime,
      ),
    );

    expect(_badge('Anime'), findsOne);

    await harness.unmount(tester);
  });

  testWidgets('P1 + the vinyl Lidarr: an artist on it says Vinyl', (
    tester,
  ) async {
    final harness = await pumpWithProfile(
      tester,
      Profiles.p1.withConnection(WorldConnections.lidarrVinyl),
      surfaceSize: _tall,
      child: const MusicDetailScreen(
        artistId: 1,
        heroTag: 'artist-1',
        instanceId: WorldIds.lidarrVinyl,
      ),
    );

    expect(_badge('Vinyl'), findsOne);

    await harness.unmount(tester);
  });

  testWidgets('P4, one Radarr: no connection named', (tester) async {
    final harness = await pumpWithProfile(
      tester,
      Profiles.p4,
      surfaceSize: _tall,
      child: const MovieDetailScreen(movieId: 1, heroTag: 'movie-1'),
    );

    expect(find.byType(ConnectionBadge), findsNothing);

    await harness.unmount(tester);
  });
}
