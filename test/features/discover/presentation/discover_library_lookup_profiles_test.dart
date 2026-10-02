/// A Discover title page asks Radarr and Sonarr about the one title it shows.
///
/// To say whether a title is in the library, the page downloaded the whole
/// library and looked for one id in it, and a Radarr that did not answer read
/// as "not in the library", which offered to add a film the server may hold.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/discover/presentation/discover_detail_extras_provider.dart';

import '../../../test_helpers/profiles/profiles.dart';

void main() {
  test('P1: a film\'s page asks Radarr for that film by its TMDB id, and '
      'never for the library', () async {
    final harness = await ProfileHarness.start(Profiles.p1);
    final container = harness.container(retry: (_, _) => null);
    final tmdbId = WorldTitles.spriteFright.tmdbId;

    final extras = await container.read(
      discoverDetailExtrasProvider((
        mediaId: tmdbId,
        mediaType: 'movie',
        tvdbId: null,
        voteAverage: 7.1,
      )).future,
    );

    final reads = harness.network
        .requestsTo(WorldIds.radarr)
        .where((r) => r.path == '/api/v3/movie')
        .toList();
    expect(extras.isInLibrary, isTrue);
    expect(reads.map((r) => r.query['tmdbId']), ['$tmdbId']);
  });

  test(
    'P1: a series\' page asks Sonarr for that series by its TVDB id',
    () async {
      final harness = await ProfileHarness.start(Profiles.p1);
      final container = harness.container(retry: (_, _) => null);
      final tvdbId = WorldTitles.cosmosLaundromat.tvdbId!;

      final extras = await container.read(
        discoverDetailExtrasProvider((
          mediaId: WorldTitles.cosmosLaundromat.tmdbId,
          mediaType: 'tv',
          tvdbId: tvdbId,
          voteAverage: 7.1,
        )).future,
      );

      final reads = harness.network
          .requestsTo(WorldIds.sonarr)
          .where((r) => r.path == '/api/v3/series')
          .toList();
      expect(extras.isInLibrary, isTrue);
      expect(reads.map((r) => r.query['tvdbId']), ['$tvdbId']);
    },
  );

  test('P1: a Radarr that answered with an error leaves the question open, '
      'never "not in the library"', () async {
    final harness = await ProfileHarness.start(Profiles.p1);
    harness.network.on(
      WorldIds.radarr,
      'GET',
      '/api/v3/movie',
      (_) => NetworkReply.json({'message': 'boom'}, status: 500),
    );
    final container = harness.container(retry: (_, _) => null);

    final extras = await container.read(
      discoverDetailExtrasProvider((
        mediaId: WorldTitles.spriteFright.tmdbId,
        mediaType: 'movie',
        tvdbId: null,
        voteAverage: 7.1,
      )).future,
    );

    expect(extras.isInLibrary, isNull);
  });
}
