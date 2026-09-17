import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
// ignore: implementation_imports
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/models/media_preview.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/features/bazarr/data/bazarr_service.dart';
import 'package:cupola/features/bazarr/presentation/bazarr_provider.dart';
import 'package:cupola/features/discover/data/seerr_service.dart';
import 'package:cupola/features/movies/data/radarr_service.dart';
import 'package:cupola/features/movies/domain/models/radarr_movie.dart';
import 'package:cupola/features/music/data/lidarr_service.dart';
import 'package:cupola/features/music/domain/models/lidarr_artist.dart';
import 'package:cupola/features/jellyfin/presentation/jellyfin_provider.dart';
import 'package:cupola/features/plex/presentation/plex_provider.dart';
import 'package:cupola/features/stream/domain/models/stream_item.dart';
import 'package:cupola/features/stream/domain/models/stream_search_group.dart';
import 'package:cupola/features/stream/domain/stream_server_client.dart';
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
  test('returns no lanes for an empty query', () async {
    final container = _container();
    addTearDown(container.dispose);

    expect(container.read(globalSearchLanesProvider), isEmpty);
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

    final lanes = await _settledLanes(container);

    // One lane per CONFIGURED connection, in the registry's own order — not one
    // per searchable service. `globalSearchServices` now also names Jellyfin and
    // Plex, which this container does not set up, and a lane for a connection
    // nobody has configured would be a section that can only ever be empty.
    expect(lanes.map((lane) => lane.service), [
      ServiceKey.seerr,
      ServiceKey.radarr,
      ServiceKey.sonarr,
      ServiceKey.lidarr,
      ServiceKey.bazarr,
    ]);
    expect(lanes.expand((lane) => lane.results).map((item) => item.title), [
      'Dune: Part Two',
      'Dune',
      'The Boys',
      'Charli XCX',
    ]);
    // Each route carries its poster's shared-element tag, so the detail page it
    // opens has a matching Hero destination to fly into.
    final routes = lanes
        .expand((lane) => lane.results)
        .map((item) => Uri.parse(item.route))
        .toList(growable: false);
    // The arr rows point inside their Library tab's branch: on the tab model
    // the record is a page pushed from the library list, not a sibling of it.
    expect(routes.map((uri) => uri.path), [
      '/dashboard/seerr/discover/movie/101',
      '/dashboard/radarr/library/movie/10',
      '/dashboard/sonarr/library/series/20',
      '/dashboard/lidarr/library/artist/30',
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
    for (final result in lanes.expand((lane) => lane.results)) {
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

    final lanes = await _settledLanes(container);
    final radarrLanes = lanes
        .where((lane) => lane.service == ServiceKey.radarr)
        .toList();

    // One section per connection, so nothing has to be reconciled between them
    // — which is what makes the missing external id on Lidarr and Bazarr stop
    // mattering.
    expect(radarrLanes, hasLength(2));
    expect(radarrLanes.map((lane) => lane.instanceLabel), ['radarr', 'Away']);
    // And the row's route names the server that listed it.
    expect(
      radarrLanes
          .expand((lane) => lane.results)
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

    final lanes = await _settledLanes(container);
    GlobalSearchServiceResults lane(ServiceKey service) =>
        lanes.singleWhere((l) => l.service == service);

    final movies = lane(ServiceKey.radarr).results;
    expect(movies.first.tags, ['Movie', 'In library']);
    expect(movies.first.subtitle, '2019 · In library');
    expect(movies.map((r) => r.inLibrary), [true, false]);
    // Nothing claimed about the one the server does not have: the section it
    // sits under already names the library that was asked.
    expect(movies.last.tags, ['Movie']);
    expect(movies.last.subtitle, '1992');

    final series = lane(ServiceKey.sonarr).results;
    expect(series.map((r) => r.inLibrary), [true, false]);
    expect(series.first.tags, ['Series', 'continuing', 'In library']);
    expect(series.last.tags, ['Series', 'continuing']);

    final artists = lane(ServiceKey.lidarr).results;
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

    final lanes = await _settledLanes(container);
    GlobalSearchServiceResults lane(ServiceKey service) =>
        lanes.singleWhere((l) => l.service == service);

    final movies = lane(ServiceKey.radarr).results;
    // Nothing to add on a row the server already holds.
    expect(movies.first.addRequest, isNull);
    expect(movies.last.addRequest, isA<RadarrAddRequest>());
    // Bound to the CONNECTION that listed it, which is what the sheet posts to.
    expect(movies.last.addRequest!.instanceId, 'radarr');

    final artists = lane(ServiceKey.lidarr).results;
    expect(artists.first.addRequest, isNull);
    expect(artists.last.addRequest, isA<LidarrAddRequest>());
    expect(artists.last.addRequest!.externalId, 'mbid-9');

    // Seerr's rows are untouched: its request flow lives on its detail page.
    for (final row in lane(ServiceKey.seerr).results) {
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

    final lanes = await _settledLanes(container);
    List<GlobalSearchResult> rows(ServiceKey service) =>
        lanes.singleWhere((l) => l.service == service).results;

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

    final lanes = await _settledLanes(container);

    // The lane state, not a bare `hasError`: the screen draws four different
    // things in this slot and three of them are not the same fault.
    expect(
      lanes.singleWhere((l) => l.service == ServiceKey.radarr).hasFault,
      isTrue,
      reason: 'the lookup used to swallow this and return an empty list',
    );
    expect(
      lanes.singleWhere((l) => l.service == ServiceKey.sonarr).state,
      SearchLaneState.answered,
    );
  });

  test('one lane failing leaves every other lane answered', () async {
    final container = _container(
      radarr: _SearchRadarrService(throwOnLookup: true),
      sonarr: _SearchSonarrService(
        results: [buildSeries(id: 20, title: 'Foundation')],
      ),
    );
    addTearDown(container.dispose);
    container.read(globalSearchQueryProvider.notifier).state = 'foundation';

    final lanes = await _settledLanes(container);
    final radarr = lanes.singleWhere((l) => l.service == ServiceKey.radarr);
    final sonarr = lanes.singleWhere((l) => l.service == ServiceKey.sonarr);

    expect(radarr.hasFault, isTrue);
    expect(radarr.results, isEmpty);
    expect(sonarr.state, SearchLaneState.answered);
    expect(sonarr.results.single.title, 'Foundation');
  });

  test('a lane still in flight does not hold the lanes that answered', () async {
    // The promise the whole per-leg model exists to keep. This used to be one
    // `Future.wait`, so a single configured-but-switched-off server held every
    // other section behind its timeout and the page could not be drawn at all.
    final gate = Completer<void>();
    addTearDown(() {
      if (!gate.isCompleted) gate.complete();
    });
    final container = _container(
      radarr: _SearchRadarrService(
        results: [buildMovie(id: 10, title: 'Dune', year: 2024)],
      ),
      bazarr: _SearchBazarrService(gate: gate),
    );
    addTearDown(container.dispose);

    final sub = container.listen(globalSearchLanesProvider, (_, _) {});
    addTearDown(sub.close);
    container.read(globalSearchQueryProvider.notifier).state = 'dune';

    // Everything except the parked Bazarr leg.
    for (final leg in container.read(globalSearchLegsProvider)) {
      if (leg.instance.service == ServiceKey.bazarr) continue;
      await container.read(globalSearchLegProvider(leg).future);
    }
    await _settle();

    final lanes = container.read(globalSearchLanesProvider);
    expect(
      lanes
          .where((lane) => lane.service != ServiceKey.bazarr)
          .map((lane) => lane.state),
      everyElement(SearchLaneState.answered),
    );
    expect(
      lanes.singleWhere((l) => l.service == ServiceKey.bazarr).state,
      SearchLaneState.searching,
    );
    // And the answered lane really carries its rows while the other is out.
    expect(
      lanes
          .singleWhere((l) => l.service == ServiceKey.radarr)
          .results
          .single
          .title,
      'Dune',
    );
  });

  test('Retry re-runs one lane and leaves the rest alone', () async {
    final radarr = _SearchRadarrService(throwOnLookup: true);
    final sonarr = _SearchSonarrService(
      results: [buildSeries(id: 20, title: 'Foundation')],
    );
    final container = _container(radarr: radarr, sonarr: sonarr);
    addTearDown(container.dispose);

    final sub = container.listen(globalSearchLanesProvider, (_, _) {});
    addTearDown(sub.close);
    container.read(globalSearchQueryProvider.notifier).state = 'foundation';
    await _settledLanes(container);

    expect(radarr.leg.tokens, hasLength(1));
    expect(sonarr.leg.tokens, hasLength(1));

    final radarrLeg = container
        .read(globalSearchLegsProvider)
        .singleWhere((leg) => leg.instance.service == ServiceKey.radarr);
    container.invalidate(globalSearchLegProvider(radarrLeg));
    await _settle();

    // Retry is a per-leg invalidate and never a whole-screen one: the lane the
    // user pressed asked again, and nothing else on the page did.
    expect(radarr.leg.tokens, hasLength(2));
    expect(sonarr.leg.tokens, hasLength(1));
  });

  test('each leg carries a cancel token of its own', () async {
    // CHANGED from "hands every service leg of one round the same cancel
    // token". One token per round belonged to the round: there was one provider
    // and it owned the whole fan-out. A leg is its own provider now, so the
    // token's life is the leg's — which is precisely what makes a per-lane
    // Retry able to abort one request without touching the other six.
    final seerr = _SearchSeerrService();
    final radarr = _SearchRadarrService();
    final sonarr = _SearchSonarrService();
    final lidarr = _SearchLidarrService();
    final container = _container(
      seerr: seerr,
      radarr: radarr,
      sonarr: sonarr,
      lidarr: lidarr,
    );
    addTearDown(container.dispose);
    container.read(globalSearchQueryProvider.notifier).state = 'dune';

    await _settledLanes(container);

    final tokens = [
      seerr.leg.tokens.single,
      radarr.leg.tokens.single,
      sonarr.leg.tokens.single,
      lidarr.leg.tokens.single,
    ];
    expect(tokens, everyElement(isNotNull));
    expect(tokens.toSet(), hasLength(tokens.length));
  });

  test('a fifth leg waits for a slot rather than opening a fifth socket', () async {
    // The bound used to be a worker loop inside the one provider that owned the
    // fan-out. With a leg per provider every member fires at once, so the bound
    // has to be a gate the legs share — and this is the test that it still is
    // one.
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

    final sub = container.listen(globalSearchLanesProvider, (_, _) {});
    addTearDown(sub.close);
    container.read(globalSearchQueryProvider.notifier).state = 'dune';
    await _settle();

    for (final leg in [seerr.leg, radarr.leg, sonarr.leg, lidarr.leg]) {
      expect(leg.tokens, hasLength(1));
    }
    expect(
      bazarr.leg.tokens,
      isEmpty,
      reason:
          'the fifth leg waits for a slot rather than opening a fifth '
          'connection to somebody\'s home server',
    );
  });

  test('a superseded query cancels the leg that was in flight', () async {
    // Every leg parks here, so the first round is genuinely still in flight
    // when the second query arrives — which is the only state in which
    // cancelling means anything.
    final gate = Completer<void>();
    addTearDown(() {
      if (!gate.isCompleted) gate.complete();
    });
    final radarr = _SearchRadarrService(gate: gate);
    final sonarr = _SearchSonarrService(gate: gate);
    final container = _container(radarr: radarr, sonarr: sonarr);
    addTearDown(container.dispose);

    // A live listener is what keeps the autoDispose providers alive between the
    // two rounds; without it the first build would be torn down on its own and
    // the cancellation would prove nothing.
    final sub = container.listen(globalSearchLanesProvider, (_, _) {});
    addTearDown(sub.close);

    container.read(globalSearchQueryProvider.notifier).state = 'du';
    await _settle();
    expect(radarr.leg.tokens, hasLength(1));

    container.read(globalSearchQueryProvider.notifier).state = 'dune';
    await _settle();

    for (final leg in [radarr.leg, sonarr.leg]) {
      expect(leg.tokens, hasLength(2));
      expect(leg.tokens.first!.isCancelled, isTrue);
      expect(leg.tokens.last!.isCancelled, isFalse);
    }
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

      final sub = container.listen(globalSearchLanesProvider, (_, _) {});
      addTearDown(sub.close);

      container.read(globalSearchQueryProvider.notifier).state = 'dune';
      await _settledLanes(container);
      expect(radarr.leg.tokens, hasLength(1));

      container.read(_testSettings.notifier).state = container
          .read(_testSettings)
          .copyWith(themeMode: AppThemeMode.dark);
      await _settle();

      expect(radarr.leg.tokens, hasLength(1));
      expect(radarr.leg.tokens.single!.isCancelled, isFalse);

      // A connection it *does* depend on still re-runs it.
      container.read(_testSettings.notifier).state = container
          .read(_testSettings)
          .copyWithService(ServiceKey.radarr, apiKey: 'rotated');
      await _settledLanes(container);

      expect(radarr.leg.tokens, hasLength(2));
    },
  );

  group('the media servers', () {
    /// Configures Jellyfin and Plex on top of the shared settings and points
    /// both lanes at scripted servers.
    ProviderContainer streamContainer({
      required _ScriptedStreamServer jellyfin,
      required _ScriptedStreamServer plex,
    }) {
      final container = _container(
        extra: [
          jellyfinServerProvider.overrideWithValue(jellyfin),
          plexServerProvider.overrideWithValue(plex),
        ],
      );
      container.read(_testSettings.notifier).state = container
          .read(_testSettings)
          .copyWithInstance(
            const ServiceInstance(
              id: 'jellyfin',
              service: ServiceKey.jellyfin,
              url: 'http://jellyfin.local:8096',
              credential: 'key',
            ),
          )
          .copyWithInstance(
            const ServiceInstance(
              id: 'plex',
              service: ServiceKey.plex,
              url: 'http://plex.local:32400',
              credential: 'token',
            ),
          );
      return container;
    }

    test('both media servers get a lane of their own', () async {
      final container = streamContainer(
        jellyfin: _ScriptedStreamServer(const []),
        plex: _ScriptedStreamServer(const []),
      );
      addTearDown(container.dispose);
      container.read(globalSearchQueryProvider.notifier).state = 'dune';

      final lanes = await _settledLanes(container);

      // A title lookup is something both servers can now answer, so both are in
      // the fan-out. Prowlarr still is not: an indexer search is a release
      // search against trackers, and it belongs on Prowlarr's own page.
      expect(
        lanes.map((lane) => lane.service),
        containsAll([ServiceKey.jellyfin, ServiceKey.plex]),
      );
      expect(
        lanes.map((lane) => lane.service),
        isNot(contains(ServiceKey.prowlarr)),
      );
    });

    test("the server's own band order survives, in the server's own words", () async {
      // Plex ranks its hubs and the rows inside them with a relevance model this
      // app cannot reproduce, so the lane must render what it is given. The
      // alphabet here is deliberately against the given order: sorting anything
      // would show up immediately.
      final plex = _ScriptedStreamServer([
        _band('Movies', StreamItemKind.movie, ['Zulu', 'Alien']),
        _band('Episodes', StreamItemKind.episode, const []),
        _band('Actors', null, ['Bob Anderson']),
      ]);
      final container = streamContainer(
        jellyfin: _ScriptedStreamServer(const []),
        plex: plex,
      );
      addTearDown(container.dispose);
      container.read(globalSearchQueryProvider.notifier).state = 'dune';

      final lanes = await _settledLanes(container);
      final lane = lanes.firstWhere((l) => l.service == ServiceKey.plex);

      expect(lane.state, SearchLaneState.answered);
      expect(lane.results.map((r) => r.title), [
        'Zulu',
        'Alien',
        'Bob Anderson',
      ]);
      // The band's name rides on the row, verbatim. The lane heading names the
      // connection, so without this nothing on screen says what kind of hit it
      // is — and deriving a word from the kind would rename a localised Plex's
      // own hubs.
      expect(lane.results.map((r) => r.tags.single), [
        'Movies',
        'Movies',
        'Actors',
      ]);
    });

    test(
      'a server that could not be asked is not a server holding nothing',
      () async {
        // `StreamServerClient.search` degrades to `[]` instead of throwing, and
        // its contract makes the shape carry the meaning: no bands at all means
        // the question never landed. Read as an answer it would put "0 results"
        // on a media server that is switched off — the one confusion the
        // per-connection fan-out exists to end.
        final container = streamContainer(
          jellyfin: _ScriptedStreamServer(const []),
          plex: _ScriptedStreamServer(const []),
        );
        addTearDown(container.dispose);
        container.read(globalSearchQueryProvider.notifier).state = 'dune';

        final lanes = await _settledLanes(container);
        final lane = lanes.firstWhere((l) => l.service == ServiceKey.jellyfin);

        expect(lane.state, isNot(SearchLaneState.answered));
        expect(lane.hasFault, isTrue);
        expect(lane.state.canRetry, isTrue);
      },
    );

    test('bands that came back empty are an answer, and say so', () async {
      // The other half of the same contract: bands present but empty mean the
      // server was asked and holds nothing. That is a real, retry-free answer.
      final container = streamContainer(
        jellyfin: _ScriptedStreamServer([
          _band('Movies', StreamItemKind.movie, const []),
          _band('Series', StreamItemKind.series, const []),
        ]),
        plex: _ScriptedStreamServer(const []),
      );
      addTearDown(container.dispose);
      container.read(globalSearchQueryProvider.notifier).state = 'dune';

      final lanes = await _settledLanes(container);
      final lane = lanes.firstWhere((l) => l.service == ServiceKey.jellyfin);

      expect(lane.state, SearchLaneState.answered);
      expect(lane.results, isEmpty);
      expect(lane.hasFault, isFalse);
    });

    test(
      'a row opens the item it names and offers nothing it cannot honour',
      () async {
        final container = streamContainer(
          jellyfin: _ScriptedStreamServer([
            _band('Movies', StreamItemKind.movie, ['Dune']),
          ]),
          plex: _ScriptedStreamServer(const []),
        );
        addTearDown(container.dispose);
        container.read(globalSearchQueryProvider.notifier).state = 'dune';

        final lanes = await _settledLanes(container);
        final row = lanes
            .firstWhere((l) => l.service == ServiceKey.jellyfin)
            .results
            .single;

        // Spelled by the constant, not by hand: the item detail lives inside the
        // Libraries branch, and where exactly it sits is asserted in
        // service_routes_test. What this case is about is that the row opens the
        // item it names — a literal here only makes it break the next time the
        // route moves, which is how it broke this time.
        expect(row.route, ServiceRoutes.jellyfinItem('id-Dune'));
        // No plus and no "In library": every row here is already on the server
        // that listed it, and a media server is not a library this app writes to.
        expect(row.addRequest, isNull);
        expect(row.inLibrary, isFalse);
        expect(
          row.imageUrl,
          isNotEmpty,
          reason: 'the client resolves the poster',
        );
      },
    );
  });
}

/// Drives every leg to completion and returns the lanes as they then stand.
///
/// There is no page-wide future to await any more — that is the point of the
/// change — so a test that wants the settled page asks each leg for its own.
Future<List<GlobalSearchServiceResults>> _settledLanes(
  ProviderContainer container,
) async {
  final sub = container.listen(globalSearchLanesProvider, (_, _) {});
  try {
    for (final leg in container.read(globalSearchLegsProvider)) {
      await container.read(globalSearchLegProvider(leg).future);
    }
    await _settle();
    return container.read(globalSearchLanesProvider);
  } finally {
    sub.close();
  }
}

/// Lets the queued microtasks and the pool hand-offs unwind.
Future<void> _settle() async {
  for (var i = 0; i < 8; i++) {
    await Future<void>.delayed(Duration.zero);
  }
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
    final parked = gate;
    if (parked == null) return;
    // A real request completes the moment its token is cancelled, and that is
    // what hands the leg's slot back to the pool. A fake that parked straight
    // through cancellation would hold the bound closed, so the next round would
    // queue behind a request nobody is waiting for and the test would be
    // measuring the fake rather than the code.
    await Future.any([
      parked.future,
      if (cancelToken != null) cancelToken.whenCancel,
    ]);
    if (cancelToken != null && cancelToken.isCancelled) {
      throw cancelToken.cancelError ?? Exception('cancelled');
    }
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
    bool reportFailure = false,
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

/// One scripted band, with the items named by title alone.
StreamSearchGroup _band(
  String label,
  StreamItemKind? kind,
  List<String> titles,
) => StreamSearchGroup(
  label: label,
  kind: kind,
  items: [
    for (final title in titles)
      StreamItem(
        id: 'id-$title',
        title: title,
        subtitle: null,
        kind: kind ?? StreamItemKind.other,
        posterPath: '/poster/$title',
        year: null,
        runtimeMs: null,
        isPlayed: false,
        resumeOffsetMs: null,
        unplayedChildCount: null,
      ),
  ],
);

/// Stands in for both media servers.
///
/// The leg asks exactly two things of a [StreamServerClient] — `search` and, per
/// row, `imageFor` — so `noSuchMethod` covers the other eleven futures rather
/// than the test pretending to implement a media server.
class _ScriptedStreamServer implements StreamServerClient {
  _ScriptedStreamServer(this.groups);

  final List<StreamSearchGroup> groups;
  final List<String> queries = [];

  @override
  Future<List<StreamSearchGroup>> search(
    String query, {
    int? limit,
    CancelToken? cancelToken,
  }) async {
    queries.add(query);
    return groups;
  }

  @override
  StreamImageSource? imageFor(String posterPath, {int? width}) =>
      (url: 'http://stream.local$posterPath?w=$width', headers: null);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
