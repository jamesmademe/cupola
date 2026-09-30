import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/models/media_preview.dart';
import 'package:cupola/features/discover/data/seerr_service.dart';
import 'package:cupola/features/discover/presentation/discover_search_provider.dart';
import 'package:cupola/features/movies/data/radarr_service.dart';
import 'package:cupola/features/movies/domain/models/radarr_movie.dart';
import 'package:cupola/features/movies/presentation/movies_search_provider.dart';
import 'package:cupola/features/music/data/lidarr_service.dart';
import 'package:cupola/features/music/domain/models/lidarr_artist.dart';
import 'package:cupola/features/music/presentation/music_search_provider.dart';
import 'package:cupola/features/series/data/sonarr_service.dart';
import 'package:cupola/features/series/domain/models/sonarr_series.dart';
import 'package:cupola/features/series/presentation/series_search_provider.dart';

import '../../../test_helpers/fake_services.dart';

/// The per-section search surfaces (`/movies`, `/series`, `/music`,
/// `/discover`) each mint their own [CancelToken], the same way the global
/// fan-out does. Every one of them re-runs on each keystroke against services
/// that can take seconds to answer, so the round a keystroke supersedes has to
/// stop rather than run to completion.
///
/// Discover is covered here because it was the one that did not: it hand-rolled
/// the query/try/catch shape instead of going through
/// `loadNullableSearchResults`, and passed no token at all, in breach of
/// CONTEXT.md rule 8.
void main() {
  group('movies', () {
    test('hands the lookup a cancel token', () async {
      final radarr = _GateRadarrService();
      final container = ProviderContainer(
        overrides: [radarrServiceProvider.overrideWithValue(radarr)],
      );
      addTearDown(container.dispose);

      container.read(moviesSearchQueryProvider.notifier).state = 'dune';
      await container.read(moviesSearchResultsProvider.future);

      expect(radarr.tokens.single, isNotNull);
    });

    test('cancels the superseded round when the query moves on', () async {
      final gate = Completer<void>();
      addTearDown(() {
        if (!gate.isCompleted) gate.complete();
      });
      final radarr = _GateRadarrService(gate: gate);
      final container = ProviderContainer(
        overrides: [radarrServiceProvider.overrideWithValue(radarr)],
      );
      addTearDown(container.dispose);

      final sub = container.listen(moviesSearchResultsProvider, (_, _) {});
      addTearDown(sub.close);

      container.read(moviesSearchQueryProvider.notifier).state = 'du';
      await Future<void>.delayed(Duration.zero);
      container.read(moviesSearchQueryProvider.notifier).state = 'dune';
      await Future<void>.delayed(Duration.zero);

      expect(radarr.tokens, hasLength(2));
      expect(radarr.tokens.first!.isCancelled, isTrue);
      expect(radarr.tokens.last!.isCancelled, isFalse);
    });
  });

  group('series', () {
    test('hands the lookup a cancel token', () async {
      final sonarr = _GateSonarrService();
      final container = ProviderContainer(
        overrides: [sonarrServiceProvider.overrideWithValue(sonarr)],
      );
      addTearDown(container.dispose);

      container.read(seriesSearchQueryProvider.notifier).state = 'severance';
      await container.read(seriesSearchResultsProvider.future);

      expect(sonarr.tokens.single, isNotNull);
    });

    test('cancels the superseded round when the query moves on', () async {
      final gate = Completer<void>();
      addTearDown(() {
        if (!gate.isCompleted) gate.complete();
      });
      final sonarr = _GateSonarrService(gate: gate);
      final container = ProviderContainer(
        overrides: [sonarrServiceProvider.overrideWithValue(sonarr)],
      );
      addTearDown(container.dispose);

      final sub = container.listen(seriesSearchResultsProvider, (_, _) {});
      addTearDown(sub.close);

      container.read(seriesSearchQueryProvider.notifier).state = 'sev';
      await Future<void>.delayed(Duration.zero);
      container.read(seriesSearchQueryProvider.notifier).state = 'severance';
      await Future<void>.delayed(Duration.zero);

      expect(sonarr.tokens, hasLength(2));
      expect(sonarr.tokens.first!.isCancelled, isTrue);
      expect(sonarr.tokens.last!.isCancelled, isFalse);
    });
  });

  group('music', () {
    test('hands the lookup a cancel token', () async {
      final lidarr = _GateLidarrService();
      final container = ProviderContainer(
        overrides: [lidarrServiceProvider.overrideWithValue(lidarr)],
      );
      addTearDown(container.dispose);

      container.read(musicSearchQueryProvider.notifier).state = 'charli';
      await container.read(musicSearchResultsProvider.future);

      expect(lidarr.tokens.single, isNotNull);
    });

    test('cancels the superseded round when the query moves on', () async {
      final gate = Completer<void>();
      addTearDown(() {
        if (!gate.isCompleted) gate.complete();
      });
      final lidarr = _GateLidarrService(gate: gate);
      final container = ProviderContainer(
        overrides: [lidarrServiceProvider.overrideWithValue(lidarr)],
      );
      addTearDown(container.dispose);

      final sub = container.listen(musicSearchResultsProvider, (_, _) {});
      addTearDown(sub.close);

      container.read(musicSearchQueryProvider.notifier).state = 'char';
      await Future<void>.delayed(Duration.zero);
      container.read(musicSearchQueryProvider.notifier).state = 'charli';
      await Future<void>.delayed(Duration.zero);

      expect(lidarr.tokens, hasLength(2));
      expect(lidarr.tokens.first!.isCancelled, isTrue);
      expect(lidarr.tokens.last!.isCancelled, isFalse);
    });
  });

  group('a section search that failed', () {
    // "No results" only after the arr answered: the loader used to catch
    // every failure into `[]`, and a Radarr that did not answer drew exactly
    // what an empty answer draws.
    test('movies: the failure reaches the page, never an empty list', () async {
      final container = ProviderContainer(
        overrides: [
          radarrServiceProvider.overrideWithValue(
            _GateRadarrService(fails: true),
          ),
        ],
      );
      addTearDown(container.dispose);

      container.read(moviesSearchQueryProvider.notifier).state = 'dune';
      await expectLater(
        container.read(moviesSearchResultsProvider.future),
        throwsA(isA<SocketException>()),
      );
    });

    test('series: the failure reaches the page, never an empty list', () async {
      final container = ProviderContainer(
        overrides: [
          sonarrServiceProvider.overrideWithValue(
            _GateSonarrService(fails: true),
          ),
        ],
      );
      addTearDown(container.dispose);

      container.read(seriesSearchQueryProvider.notifier).state = 'severance';
      await expectLater(
        container.read(seriesSearchResultsProvider.future),
        throwsA(isA<SocketException>()),
      );
    });

    test('music: the failure reaches the page, never an empty list', () async {
      final container = ProviderContainer(
        overrides: [
          lidarrServiceProvider.overrideWithValue(
            _GateLidarrService(fails: true),
          ),
        ],
      );
      addTearDown(container.dispose);

      container.read(musicSearchQueryProvider.notifier).state = 'charli';
      await expectLater(
        container.read(musicSearchResultsProvider.future),
        throwsA(isA<SocketException>()),
      );
    });
  });

  group('discover', () {
    test('hands the lookup a cancel token', () async {
      final seerr = _GateSeerrService();
      final container = ProviderContainer(
        overrides: [seerrServiceProvider.overrideWithValue(seerr)],
      );
      addTearDown(container.dispose);

      container.read(discoverSearchQueryProvider.notifier).state = 'arrival';
      await container.read(discoverSearchResultsProvider.future);

      expect(seerr.tokens.single, isNotNull);
    });

    test('cancels the superseded round when the query moves on', () async {
      final gate = Completer<void>();
      addTearDown(() {
        if (!gate.isCompleted) gate.complete();
      });
      final seerr = _GateSeerrService(gate: gate);
      final container = ProviderContainer(
        overrides: [seerrServiceProvider.overrideWithValue(seerr)],
      );
      addTearDown(container.dispose);

      final sub = container.listen(discoverSearchResultsProvider, (_, _) {});
      addTearDown(sub.close);

      container.read(discoverSearchQueryProvider.notifier).state = 'arr';
      await Future<void>.delayed(Duration.zero);
      container.read(discoverSearchQueryProvider.notifier).state = 'arrival';
      await Future<void>.delayed(Duration.zero);

      expect(seerr.tokens, hasLength(2));
      expect(seerr.tokens.first!.isCancelled, isTrue);
      expect(seerr.tokens.last!.isCancelled, isFalse);
    });

    test(
      'an empty query resolves to null without reaching the service',
      () async {
        final seerr = _GateSeerrService();
        final container = ProviderContainer(
          overrides: [seerrServiceProvider.overrideWithValue(seerr)],
        );
        addTearDown(container.dispose);

        expect(
          await container.read(discoverSearchResultsProvider.future),
          isNull,
        );
        expect(seerr.tokens, isEmpty);
      },
    );

    test('a failing lookup is a failure, never "no results"', () async {
      // It used to degrade to `[]`, and the page said "No results found"
      // about a search Seerr never answered.
      final seerr = _GateSeerrService(fails: true);
      final container = ProviderContainer(
        overrides: [seerrServiceProvider.overrideWithValue(seerr)],
      );
      addTearDown(container.dispose);

      container.read(discoverSearchQueryProvider.notifier).state = 'arrival';

      await expectLater(
        container.read(discoverSearchResultsProvider.future),
        throwsException,
      );
      expect(seerr.reportedFailure, isTrue);
    });

    test('an answer with nothing in it is "no results"', () async {
      final seerr = _GateSeerrService();
      final container = ProviderContainer(
        overrides: [seerrServiceProvider.overrideWithValue(seerr)],
      );
      addTearDown(container.dispose);

      container.read(discoverSearchQueryProvider.notifier).state = 'arrival';

      expect(
        await container.read(discoverSearchResultsProvider.future),
        isEmpty,
      );
    });
  });
}

/// Records the token of every lookup and, with a [gate], parks the request so
/// the first round is genuinely still in flight when the second arrives —
/// which is the only state in which cancelling means anything.
class _GateRadarrService extends FakeRadarrService {
  _GateRadarrService({this.gate, this.fails = false});

  final Completer<void>? gate;
  final bool fails;
  final List<CancelToken?> tokens = [];

  @override
  Future<List<RadarrMovie>> lookupMovies(
    String term, {
    CancelToken? cancelToken,
    bool reportFailure = false,
  }) async {
    tokens.add(cancelToken);
    await gate?.future;
    // The real service's contract: a failure travels only when asked.
    if (fails && reportFailure) {
      throw const SocketException('Connection refused');
    }
    return const [];
  }
}

class _GateSonarrService extends FakeSonarrService {
  _GateSonarrService({this.gate, this.fails = false});

  final Completer<void>? gate;
  final bool fails;
  final List<CancelToken?> tokens = [];

  @override
  Future<List<SonarrSeries>> lookupSeries(
    String term, {
    CancelToken? cancelToken,
    bool reportFailure = false,
  }) async {
    tokens.add(cancelToken);
    await gate?.future;
    // The real service's contract: a failure travels only when asked.
    if (fails && reportFailure) {
      throw const SocketException('Connection refused');
    }
    return const [];
  }
}

class _GateLidarrService extends FakeLidarrService {
  _GateLidarrService({this.gate, this.fails = false});

  final Completer<void>? gate;
  final bool fails;
  final List<CancelToken?> tokens = [];

  @override
  Future<List<LidarrArtist>> lookupArtists(
    String term, {
    CancelToken? cancelToken,
    bool reportFailure = false,
  }) async {
    tokens.add(cancelToken);
    await gate?.future;
    // The real service's contract: a failure travels only when asked.
    if (fails && reportFailure) {
      throw const SocketException('Connection refused');
    }
    return const [];
  }
}

class _GateSeerrService extends FakeSeerrService {
  _GateSeerrService({this.gate, this.fails = false});

  final Completer<void>? gate;
  final bool fails;
  final List<CancelToken?> tokens = [];

  /// Whether the last caller asked for the failure to travel.
  bool reportedFailure = false;

  @override
  Future<List<MediaPreview>> search(
    String query, {
    int page = 1,
    CancelToken? cancelToken,
    bool reportFailure = false,
  }) async {
    tokens.add(cancelToken);
    reportedFailure = reportFailure;
    await gate?.future;
    // The real service's contract: a failure travels only when asked.
    if (fails && reportFailure) throw Exception('Seerr unreachable');
    return const [];
  }
}
