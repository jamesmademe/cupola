/// A Bazarr detail page asks Bazarr for the one title it shows.
///
/// To find one series, movie or Wanted entry, the page walked Bazarr's whole
/// list, 500 rows a page, on every open.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/bazarr/presentation/bazarr_provider.dart';

import '../../../test_helpers/profiles/profiles.dart';

void main() {
  List<NetworkRequest> readsOf(ProfileHarness harness, String path) => harness
      .network
      .requestsTo(WorldIds.bazarr)
      .where((r) => r.path == path)
      .toList();

  test('P1: a series page asks for that series and its wanted episodes, by '
      'id', () async {
    final harness = await ProfileHarness.start(Profiles.p1);
    final container = harness.container(retry: (_, _) => null);

    final series = await container.read(bazarrSeriesByIdProvider(1).future);
    final wanted = await container.read(
      bazarrWantedEpisodesForSeriesProvider(1).future,
    );

    expect(series?.title, WorldTitles.cosmosLaundromat.title);
    expect(wanted.map((w) => w.sonarrEpisodeId), [1011, 1012, 1013]);

    final seriesReads = readsOf(harness, '/api/series');
    expect(seriesReads, hasLength(1));
    expect(seriesReads.single.uri.queryParametersAll['seriesid[]'], ['1']);

    // The series' episodes, then Wanted for the three that miss a subtitle:
    // two reads, never a walk of the whole Wanted list.
    final episodeReads = readsOf(harness, '/api/episodes');
    expect(episodeReads, hasLength(1));
    expect(episodeReads.single.uri.queryParametersAll['seriesid[]'], ['1']);
    final wantedReads = readsOf(harness, '/api/episodes/wanted');
    expect(wantedReads, hasLength(1));
    expect(wantedReads.single.uri.queryParametersAll['episodeid[]'], [
      '1011',
      '1012',
      '1013',
    ]);
  });

  test(
    'P1: a movie page asks for that movie and its Wanted entry, by id',
    () async {
      final harness = await ProfileHarness.start(Profiles.p1);
      final container = harness.container(retry: (_, _) => null);

      final movie = await container.read(bazarrMovieByIdProvider(5).future);
      final wanted = await container.read(
        bazarrWantedMovieByIdProvider(5).future,
      );

      expect(movie?.title, WorldTitles.tearsOfSteel.title);
      expect(wanted?.missingLanguages.single.code2, 'de');

      for (final path in ['/api/movies', '/api/movies/wanted']) {
        final reads = readsOf(harness, path);
        expect(reads, hasLength(1), reason: path);
        expect(reads.single.uri.queryParametersAll['radarrid[]'], [
          '5',
        ], reason: path);
      }
    },
  );

  test('P1: a series with nothing missing asks Wanted nothing', () async {
    final harness = await ProfileHarness.start(Profiles.p1);
    final container = harness.container(retry: (_, _) => null);

    final wanted = await container.read(
      bazarrWantedEpisodesForSeriesProvider(2).future,
    );

    expect(wanted, isEmpty);
    expect(readsOf(harness, '/api/episodes'), hasLength(1));
    expect(readsOf(harness, '/api/episodes/wanted'), isEmpty);
  });

  test('P1: a long series asks Wanted in chunks a proxy takes', () async {
    final harness = await ProfileHarness.start(Profiles.p1);
    harness.network.on(
      WorldIds.bazarr,
      'GET',
      '/api/episodes',
      (_) => NetworkReply.json({
        'data': [
          for (var e = 1; e <= 250; e++)
            {
              'sonarrSeriesId': 1,
              'sonarrEpisodeId': 5000 + e,
              'missing_subtitles': [
                {'name': 'Italian', 'code2': 'it', 'code3': 'ita'},
              ],
            },
        ],
      }),
    );
    final container = harness.container(retry: (_, _) => null);

    await container.read(bazarrWantedEpisodesForSeriesProvider(1).future);

    final asked = [
      for (final r in readsOf(harness, '/api/episodes/wanted'))
        r.uri.queryParametersAll['episodeid[]']!.length,
    ];
    expect(asked, [100, 100, 50]);
  });
}
