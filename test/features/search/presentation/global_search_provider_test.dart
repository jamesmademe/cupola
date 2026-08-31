import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
// ignore: implementation_imports
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/models/media_preview.dart';
import 'package:cupola/features/bazarr/data/bazarr_service.dart';
import 'package:cupola/features/bazarr/presentation/bazarr_provider.dart';
import 'package:cupola/features/discover/data/seerr_service.dart';
import 'package:cupola/features/movies/data/radarr_service.dart';
import 'package:cupola/features/movies/domain/models/radarr_movie.dart';
import 'package:cupola/features/music/data/lidarr_service.dart';
import 'package:cupola/features/music/domain/models/lidarr_artist.dart';
import 'package:cupola/features/search/domain/arr_add_request.dart';
import 'package:cupola/features/search/domain/global_search_result.dart';
import 'package:cupola/features/search/presentation/global_search_provider.dart';
import 'package:cupola/features/series/data/sonarr_service.dart';
import 'package:cupola/features/series/domain/models/sonarr_series.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';

import '../../../test_helpers/fake_services.dart';
import '../../../test_helpers/model_builders.dart';

import '../../../test_helpers/settings_scope.dart';

void main() {
  test('returns no grouped results for an empty query', () async {
    final container = _container();
    addTearDown(container.dispose);

    final results = await container.read(globalSearchResultsProvider.future);

    expect(results, isEmpty);
  });

  test('normalizes mixed service results into grouped search rows', () async {
    final container = _container(
      seerr: _SearchSeerrService(
        results: const [
          MediaPreview(
            id: 101,
            title: 'Dune: Part Two',
            releaseDate: '2024-03-01',
            mediaType: 'movie',
          ),
        ],
      ),
      radarr: _SearchRadarrService(
        results: [buildMovie(id: 10, title: 'Dune', year: 2024)],
      ),
      sonarr: _SearchSonarrService(
        results: [buildSeries(id: 20, title: 'The Boys', year: 2024)],
      ),
      lidarr: _SearchLidarrService(
        results: [
          buildArtist(
            id: 30,
            artistName: 'Charli XCX',
            statistics: const {'albumCount': 6, 'trackFileCount': 90},
          ),
        ],
      ),
    );
    addTearDown(container.dispose);
    container.read(globalSearchQueryProvider.notifier).state = 'dune';

    final groups = await container.read(globalSearchResultsProvider.future);

    expect(
      groups.map((group) => group.service),
      ServiceKey.values.where((s) => s.isSearchable),
    );
    expect(groups.expand((group) => group.results).map((item) => item.title), [
      'Dune: Part Two',
      'Dune',
      'The Boys',
      'Charli XCX',
    ]);
    // Each route carries its poster's shared-element tag, so the detail page it
    // opens has a matching Hero destination to fly into.
    final routes = groups
        .expand((group) => group.results)
        .map((item) => Uri.parse(item.route))
        .toList(growable: false);
    expect(routes.map((uri) => uri.path), [
      '/services/seerr/movie/101',
      '/services/radarr/movie/10',
      '/services/sonarr/series/20',
      '/services/lidarr/artist/30',
    ]);
    // Keyed on the CONNECTION and on the row's position, not on the service:
    // the same id names different things on two servers, and a lookup result
    // that is not in the library carries `id == 0`, so two of those in one
    // section used to produce the identical tag — an assert in debug.
    expect(routes.map((uri) => uri.queryParameters['heroTag']), [
      'search_seerr_movie_101_0',
      'search_radarr_movie_10_0',
      'search_sonarr_series_20_0',
      'search_lidarr_artist_30_0',
    ]);
    // And the connection travels with the row, so the detail page it opens
    // reads the server that listed it.
    expect(routes.map((uri) => uri.queryParameters['i']), [
      // Seerr carries none: Discover resolves through the lens end to end, so a
      // connection in its URL would be a claim the page cannot honour. Its
      // section is the lens's, singular and unlabelled — see
      // `ServiceKeyExtension.searchesPerConnection`.
      null,
      'radarr',
      'sonarr',
      'lidarr',
    ]);
    // The tag on the model and the tag in its route are the same string —
    // a mismatch would silently produce a flightless navigation.
    for (final result in groups.expand((group) => group.results)) {
      expect(
        Uri.parse(result.route).queryParameters['heroTag'],
        result.heroTag,
      );
    }
  });

  test('two connections of one service answer as two sections', () async {
    final container = _container(
      radarr: _SearchRadarrService(
        results: [buildMovie(id: 10, title: 'Dune', year: 2024)],
      ),
      // The second connection needs its own fake: `radarrServiceForProvider`
      // only collapses onto the plain provider for the LENS's id, which is
      // exactly the distinction being tested.
      extra: [
        radarrServiceForProvider('radarr-away111').overrideWithValue(
          _SearchRadarrService(
            results: [buildMovie(id: 11, title: 'Dune', year: 2024)],
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    container.read(_testSettings.notifier).state = container
        .read(_testSettings)
        .copyWithInstance(
          const ServiceInstance(
            id: 'radarr-away111',
            service: ServiceKey.radarr,
            label: 'Away',
            url: 'http://away.local:7878',
            credential: 'key-away',
          ),
        );
    container.read(globalSearchQueryProvider.notifier).state = 'dune';

    final groups = await container.read(globalSearchResultsProvider.future);
    final radarrGroups = groups
        .where((group) => group.service == ServiceKey.radarr)
        .toList();

    // One section per connection, so nothing has to be reconciled between them
    // — which is what makes the missing external id on Lidarr and Bazarr stop
    // mattering.
    expect(radarrGroups, hasLength(2));
    expect(radarrGroups.map((g) => g.instanceLabel), ['radarr', 'Away']);
    // And the row's route names the server that listed it.
    expect(
      radarrGroups
          .expand((g) => g.results)
          .map((r) => Uri.parse(r.route).queryParameters['i']),
      ['radarr', 'radarr-away111'],
    );
  });

  test('the library marker is derived from the id, not from hasFile', () async {
    // `/movie/lookup` is a TMDB proxy: it stamps the library id onto a title
    // the server already has, and leaves `hasFile` false for every row. So the
    // fixture says what the wire says — a movie in the library, with a file on
    // disk, arriving with `hasFile: false`. Deriving the marker from that field
    // is what made "Aladdin (2019)" read as Missing in search while its own
    // detail page said "Available, 1 file".
    final container = _container(
      radarr: _SearchRadarrService(
        results: [
          buildMovie(id: 42, title: 'Aladdin', year: 2019, hasFile: false),
          buildMovie(id: 0, title: 'Aladdin', year: 1992, hasFile: false),
        ],
      ),
      // Same endpoint shape: Sonarr and Lidarr attach `statistics` in the
      // library controller, never in the lookup one, so anything read off it
      // is false for every row here too.
      sonarr: _SearchSonarrService(
        results: [
          buildSeries(id: 7, title: 'Foundation', year: 2021),
          buildSeries(id: 0, title: 'Foundation', year: 1988),
        ],
      ),
      lidarr: _SearchLidarrService(
        results: [
          buildArtist(id: 9, artistName: 'Boards of Canada'),
          buildArtist(id: 0, artistName: 'Boards of Canada Tribute'),
          // The one shape that does carry statistics: an album count only
          // appears when the payload actually has one.
          buildArtist(
            id: 11,
            artistName: 'Bibio',
            statistics: const {'albumCount': 3},
          ),
        ],
      ),
    );
    addTearDown(container.dispose);
    container.read(globalSearchQueryProvider.notifier).state = 'aladdin';

    final groups = await container.read(globalSearchResultsProvider.future);
    GlobalSearchServiceResults group(ServiceKey service) =>
        groups.singleWhere((g) => g.service == service);

    final movies = group(ServiceKey.radarr).results;
    expect(movies.first.tags, ['Movie', 'In library']);
    expect(movies.first.subtitle, '2019 · In library');
    expect(movies.map((r) => r.inLibrary), [true, false]);
    // Nothing claimed about the one the server does not have: the section it
    // sits under already names the library that was asked.
    expect(movies.last.tags, ['Movie']);
    expect(movies.last.subtitle, '1992');

    final series = group(ServiceKey.sonarr).results;
    expect(series.map((r) => r.inLibrary), [true, false]);
    expect(series.first.tags, ['Series', 'continuing', 'In library']);
    expect(series.last.tags, ['Series', 'continuing']);

    final artists = group(ServiceKey.lidarr).results;
    expect(artists.map((r) => r.inLibrary), [true, false, true]);
    expect(artists.first.tags, ['Artist', 'In library']);
    expect(artists[1].tags, ['Artist']);
    // `albumCount` is 0 for every statistics-less lookup row, so "0 albums"
    // was a fact about the endpoint rather than about the artist.
    expect(artists.first.subtitle, '');
    expect(artists.last.subtitle, '3 albums');
  });

  test('the plus is offered only where an add can really happen', () async {
    final container = _container(
      radarr: _SearchRadarrService(
        results: [
          buildMovie(id: 42, title: 'Aladdin'),
          buildMovie(id: 0, title: 'Aladdin'),
        ],
      ),
      lidarr: _SearchLidarrService(
        results: [
          // Lidarr keys an artist on its MusicBrainz id and refuses an add
          // without one, so a lookup row that arrives without it gets no
          // affordance rather than one that cannot be honoured.
          buildArtist(id: 0, artistName: 'Nameless'),
          buildArtist(id: 0, artistName: 'Bibio', foreignArtistId: 'mbid-9'),
        ],
      ),
    );
    addTearDown(container.dispose);
    container.read(globalSearchQueryProvider.notifier).state = 'aladdin';

    final groups = await container.read(globalSearchResultsProvider.future);
    GlobalSearchServiceResults group(ServiceKey service) =>
        groups.singleWhere((g) => g.service == service);

    final movies = group(ServiceKey.radarr).results;
    // Nothing to add on a row the server already holds.
    expect(movies.first.addRequest, isNull);
    expect(movies.last.addRequest, isA<RadarrAddRequest>());
    // Bound to the CONNECTION that listed it, which is what the sheet posts to.
    expect(movies.last.addRequest!.instanceId, 'radarr');

    final artists = group(ServiceKey.lidarr).results;
    expect(artists.first.addRequest, isNull);
    expect(artists.last.addRequest, isA<LidarrAddRequest>());
    expect(artists.last.addRequest!.externalId, 'mbid-9');

    // Seerr's rows are untouched: its request flow lives on its detail page.
    for (final row in group(ServiceKey.seerr).results) {
      expect(row.addRequest, isNull);
    }
  });

  test('a row whose metadata source could not match it offers no add', () async {
    // TWO of them per section, which is the whole point: `libraryKey` is built
    // from the external id, so a pair of unmatched rows shared `…:0` and
    // adding either flipped both to owned. The same collision `_heroTag`
    // documents, one field over. Closed at the source — no id, no add — since
    // the missing id is also why the server would refuse the post.
    final container = _container(
      radarr: _SearchRadarrService(
        results: [
          buildMovie(id: 0, tmdbId: 0, title: 'Aladdin'),
          buildMovie(id: 0, tmdbId: 0, title: 'Aladdin II'),
        ],
      ),
      sonarr: _SearchSonarrService(
        results: [
          // Sonarr really does return these, for shows it can only match on
          // TMDB.
          buildSeries(id: 0, tvdbId: 0, title: 'Unmatched One'),
          buildSeries(id: 0, tvdbId: 0, title: 'Unmatched Two'),
        ],
      ),
    );
    addTearDown(container.dispose);
    container.read(globalSearchQueryProvider.notifier).state = 'aladdin';

    final groups = await container.read(globalSearchResultsProvider.future);
    List<GlobalSearchResult> rows(ServiceKey service) =>
        groups.singleWhere((g) => g.service == service).results;

    final movies = rows(ServiceKey.radarr);
    expect(movies, hasLength(2));
    expect(movies.map((row) => row.addRequest), everyElement(isNull));

    final series = rows(ServiceKey.sonarr);
    expect(series, hasLength(2));
    expect(series.map((row) => row.addRequest), everyElement(isNull));

    // Not in the library either, so nothing else on the row is standing in for
    // the missing affordance: these are addable-looking rows that cannot be
    // added.
    expect(
      [...movies, ...series].map((row) => row.inLibrary),
      everyElement(isFalse),
    );
  });

  test('a dead connection is told apart from an empty one', () async {
    // The distinction the whole fan-out rests on: with a section per
    // connection, "No Radarr · Away results" reads as "that library does not
    // have it". It must not also mean "the box is off".
    final container = _container(
      radarr: _SearchRadarrService(throwOnLookup: true),
      sonarr: _SearchSonarrService(results: const []),
    );
    addTearDown(container.dispose);
    container.read(globalSearchQueryProvider.notifier).state = 'dune';

    final groups = await container.read(globalSearchResultsProvider.future);

    expect(
      groups.singleWhere((g) => g.service == ServiceKey.radarr).hasError,
      isTrue,
      reason: 'the lookup used to swallow this and return an empty list',
    );
    expect(
      groups.singleWhere((g) => g.service == ServiceKey.sonarr).hasError,
      isFalse,
    );
  });

  test('preserves partial service failures', () async {
    final container = _container(
      radarr: _SearchRadarrService(throwOnLookup: true),
      sonarr: _SearchSonarrService(
        results: [buildSeries(id: 20, title: 'Foundation')],
      ),
    );
    addTearDown(container.dispose);
    container.read(globalSearchQueryProvider.notifier).state = 'foundation';

    final groups = await container.read(globalSearchResultsProvider.future);
    final radarr = groups.singleWhere(
      (group) => group.service == ServiceKey.radarr,
    );
    final sonarr = groups.singleWhere(
      (group) => group.service == ServiceKey.sonarr,
    );

    expect(radarr.hasError, isTrue);
    expect(radarr.results, isEmpty);
    expect(sonarr.hasError, isFalse);
    expect(sonarr.results.single.title, 'Foundation');
  });

  test('hands every service leg of one round the same cancel token', () async {
    final seerr = _SearchSeerrService();
    final radarr = _SearchRadarrService();
    final sonarr = _SearchSonarrService();
    final lidarr = _SearchLidarrService();
    final bazarr = _SearchBazarrService();
    final container = _container(
      seerr: seerr,
      radarr: radarr,
      sonarr: sonarr,
      lidarr: lidarr,
      bazarr: bazarr,
    );
    addTearDown(container.dispose);
    container.read(globalSearchQueryProvider.notifier).state = 'dune';

    await container.read(globalSearchResultsProvider.future);

    final token = radarr.leg.tokens.single;
    expect(token, isNotNull);
    for (final leg in [seerr.leg, sonarr.leg, lidarr.leg, bazarr.leg]) {
      expect(leg.tokens.single, same(token));
    }
  });

  test('cancels the superseded round when the query moves on', () async {
    // Every leg parks here, so the first round is genuinely still in flight
    // when the second query arrives — which is the only state in which
    // cancelling means anything.
    final gate = Completer<void>();
    addTearDown(() {
      if (!gate.isCompleted) gate.complete();
    });
    final seerr = _SearchSeerrService(gate: gate);
    final radarr = _SearchRadarrService(gate: gate);
    final sonarr = _SearchSonarrService(gate: gate);
    final lidarr = _SearchLidarrService(gate: gate);
    final bazarr = _SearchBazarrService(gate: gate);
    final container = _container(
      seerr: seerr,
      radarr: radarr,
      sonarr: sonarr,
      lidarr: lidarr,
      bazarr: bazarr,
    );
    addTearDown(container.dispose);

    // A live listener is what keeps the autoDispose provider alive between the
    // two rounds; without it the first build would be torn down on its own and
    // the cancellation would prove nothing.
    final sub = container.listen(globalSearchResultsProvider, (_, _) {});
    addTearDown(sub.close);

    container.read(globalSearchQueryProvider.notifier).state = 'du';
    container.read(globalSearchResultsProvider);
    await Future<void>.delayed(Duration.zero);

    container.read(globalSearchQueryProvider.notifier).state = 'dune';
    container.read(globalSearchResultsProvider);
    await Future<void>.delayed(Duration.zero);

    // The first four legs only, because the pool is four wide and every one of
    // them is parked at the gate — which is the semaphore doing its job rather
    // than a gap in the test.
    for (final leg in [seerr.leg, radarr.leg, sonarr.leg, lidarr.leg]) {
      expect(leg.tokens, hasLength(2));
      expect(leg.tokens.first!.isCancelled, isTrue);
      expect(leg.tokens.last!.isCancelled, isFalse);
    }
    expect(
      bazarr.leg.tokens,
      isEmpty,
      reason:
          'the fifth leg waits for a slot rather than opening a fifth '
          'connection to somebody\'s home server',
    );
  });

  test(
    'a settings write it does not depend on leaves the round alone',
    () async {
      // The fan-out watches the five connections, not the whole model. With the
      // cancel token above, watching the model meant a theme-mode toggle aborted
      // five in-flight requests and re-issued them.
      final radarr = _SearchRadarrService();
      final container = _container(radarr: radarr);
      addTearDown(container.dispose);

      final sub = container.listen(globalSearchResultsProvider, (_, _) {});
      addTearDown(sub.close);

      container.read(globalSearchQueryProvider.notifier).state = 'dune';
      await container.read(globalSearchResultsProvider.future);
      expect(radarr.leg.tokens, hasLength(1));

      container.read(_testSettings.notifier).state = container
          .read(_testSettings)
          .copyWith(themeMode: AppThemeMode.dark);
      await Future<void>.delayed(Duration.zero);

      expect(radarr.leg.tokens, hasLength(1));
      expect(radarr.leg.tokens.single!.isCancelled, isFalse);

      // A connection it *does* depend on still re-runs it.
      container.read(_testSettings.notifier).state = container
          .read(_testSettings)
          .copyWithService(ServiceKey.radarr, apiKey: 'rotated');
      await container.read(globalSearchResultsProvider.future);

      expect(radarr.leg.tokens, hasLength(2));
    },
  );
}

/// The settings the fan-out reads, mutable so a test can write to a field the
/// search does not depend on.
final _testSettings = StateProvider<SettingsModel>(
  (ref) => settingsWith(
    seerrUrl: 'http://seerr.local:5055',
    seerrApiKey: 'key',
    radarrUrl: 'http://radarr.local:7878',
    radarrApiKey: 'key',
    sonarrUrl: 'http://sonarr.local:8989',
    sonarrApiKey: 'key',
    lidarrUrl: 'http://lidarr.local:8686',
    lidarrApiKey: 'key',
    // Configured like the rest: the fan-out only runs a leg per CONFIGURED
    // connection, so a service left out of here has no section to assert on.
    bazarrUrl: 'http://bazarr.local:6767',
    bazarrApiKey: 'key',
  ),
);

ProviderContainer _container({
  SeerrService? seerr,
  RadarrService? radarr,
  SonarrService? sonarr,
  LidarrService? lidarr,
  BazarrService? bazarr,
  List<Override> extra = const [],
}) {
  return ProviderContainer(
    overrides: [
      ...extra,
      bazarrServiceProvider.overrideWithValue(bazarr ?? _SearchBazarrService()),
      currentSettingsProvider.overrideWith((ref) => ref.watch(_testSettings)),
      seerrServiceProvider.overrideWith(
        (ref) => seerr ?? _SearchSeerrService(),
      ),
      radarrServiceProvider.overrideWith(
        (ref) => radarr ?? _SearchRadarrService(),
      ),
      sonarrServiceProvider.overrideWith(
        (ref) => sonarr ?? _SearchSonarrService(),
      ),
      lidarrServiceProvider.overrideWith(
        (ref) => lidarr ?? _SearchLidarrService(),
      ),
    ],
  );
}

/// Records the cancel token every search leg is handed, and — when a [gate] is
/// supplied — parks there so a round can still be in flight when the next
/// query supersedes it.
class _LegRecorder {
  final List<CancelToken?> tokens = [];
  final Completer<void>? gate;

  _LegRecorder(this.gate);

  Future<void> record(CancelToken? cancelToken) async {
    tokens.add(cancelToken);
    if (gate != null) await gate!.future;
  }
}

class _SearchSeerrService extends FakeSeerrService {
  final List<MediaPreview> results;
  final _LegRecorder leg;

  _SearchSeerrService({this.results = const [], Completer<void>? gate})
    : leg = _LegRecorder(gate);

  @override
  Future<List<MediaPreview>> search(
    String query, {
    int page = 1,
    CancelToken? cancelToken,
  }) async {
    await leg.record(cancelToken);
    return results;
  }
}

class _SearchRadarrService extends FakeRadarrService {
  final List<RadarrMovie> results;
  final bool throwOnLookup;
  final _LegRecorder leg;

  _SearchRadarrService({
    this.results = const [],
    this.throwOnLookup = false,
    Completer<void>? gate,
  }) : leg = _LegRecorder(gate);

  @override
  Future<List<RadarrMovie>> lookupMovies(
    String term, {
    CancelToken? cancelToken,
    bool reportFailure = false,
  }) async {
    await leg.record(cancelToken);
    if (throwOnLookup) throw Exception('radarr down');
    return results;
  }
}

class _SearchSonarrService extends FakeSonarrService {
  final List<SonarrSeries> results;
  final _LegRecorder leg;

  _SearchSonarrService({this.results = const [], Completer<void>? gate})
    : leg = _LegRecorder(gate);

  @override
  Future<List<SonarrSeries>> lookupSeries(
    String term, {
    CancelToken? cancelToken,
    bool reportFailure = false,
  }) async {
    await leg.record(cancelToken);
    return results;
  }
}

class _SearchLidarrService extends FakeLidarrService {
  final List<LidarrArtist> results;
  final _LegRecorder leg;

  _SearchLidarrService({this.results = const [], Completer<void>? gate})
    : leg = _LegRecorder(gate);

  @override
  Future<List<LidarrArtist>> lookupArtists(
    String term, {
    CancelToken? cancelToken,
    bool reportFailure = false,
  }) async {
    await leg.record(cancelToken);
    return results;
  }
}

class _SearchBazarrService extends FakeBazarrService {
  final _LegRecorder leg;

  _SearchBazarrService({Completer<void>? gate}) : leg = _LegRecorder(gate);

  @override
  Future<List<BazarrSearchHit>> searchLibrary(
    String query, {
    int length = 500,
    CancelToken? cancelToken,
  }) async {
    await leg.record(cancelToken);
    return const [];
  }
}
