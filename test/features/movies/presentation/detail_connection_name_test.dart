/// A detail page says which connection it reads, once there are two. (A
/// film's page names each connection in its own row: see the Media page's
/// tests.)
///
/// The connection a page belongs to travels in its `?i=`, and the tab bar
/// that carries the lens is covered by the page. So a film opened from the
/// 4K's row was the 4K's film with nothing on it saying so, beside the HD's
/// copy of the same film that looks identical.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/widgets/connection_badge.dart';
import 'package:cupola/features/music/presentation/music_detail_screen.dart';
import 'package:cupola/features/series/presentation/series_detail_screen.dart';

import '../../../test_helpers/profiles/profiles.dart';

const _tall = Size(800, 3000);

Finder _badge(String label) => find.byWidgetPredicate(
  (widget) => widget is ConnectionBadge && widget.label == label,
);

void main() {
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
}
