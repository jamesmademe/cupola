/// How a title's Seerr record is read, and how the series id Sonarr is asked
/// by is found: in parallel, and without a download of its own.
library;

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/discover/data/seerr_service.dart';
import 'package:cupola/features/media/domain/media_key.dart';
import 'package:cupola/features/media/presentation/media_sources_provider.dart';
import 'package:cupola/features/series/data/sonarr_service.dart';
import 'package:cupola/features/series/presentation/series_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import '../../test_helpers/fake_api_client.dart';
import '../../test_helpers/settings_scope.dart';

/// A client whose every path waits on a gate the test opens, so the reads of
/// one record can be watched while they are all in the air.
class _GatedClient extends FakeApiClient {
  final _gates = <String, Completer<dynamic>>{};
  final requested = <String>[];

  Completer<dynamic> _gate(String path) =>
      _gates.putIfAbsent(path, Completer.new);

  void answer(String path, dynamic body) => _gate(path).complete(body);

  void fail(String path) => _gate(path).completeError(Exception(path));

  @override
  Future<Response<dynamic>> get(
    String path, {
    Map<String, dynamic>? queryParameters,
    CancelToken? cancelToken,
    Duration? receiveTimeout,
  }) async {
    requested.add(path);
    final data = await _gate(path).future;
    return Response<dynamic>(
      requestOptions: RequestOptions(path: path),
      data: data,
    );
  }
}

void main() {
  group('a title\'s Seerr record', () {
    late _GatedClient client;
    late ProviderContainer container;

    setUp(() {
      client = _GatedClient();
      container = ProviderContainer(
        overrides: [
          seerrServiceForProvider.overrideWith(
            (ref, id) => SeerrService(client),
          ),
        ],
      );
      addTearDown(container.dispose);
    });

    const movie = (key: MediaKey.movie(653), connectionId: 'seerr');
    const series = (key: MediaKey.tv(1399), connectionId: 'seerr');

    test('a movie\'s four reads leave together', () async {
      final record = container.read(mediaSeerrRecordProvider(movie).future);
      await pumpEventQueue();

      // Nothing has answered yet, and the record, the servers, the scores
      // and the numbering have all been asked.
      expect(client.requested, unorderedEquals(_movieReads));

      client.answer('/api/v1/movie/653', {'id': 653, 'title': 'Nosferatu'});
      client.answer('/api/v1/settings/radarr', const []);
      client.answer('/api/v1/movie/653/ratingscombined', {
        'rt': {'criticsScore': 97},
        'imdb': {'criticsScore': 7.8},
      });
      client.answer('/api/v1/status', {'version': '2.1.0'});

      final answer = (await record).value;
      expect(answer.details['title'], 'Nosferatu');
      expect(answer.arrServers, isEmpty);
      expect(answer.rottenTomatoes, 97);
      expect(answer.imdb, 7.8);
      expect(answer.numbering, isNotNull);
    });

    test('a series\' four reads leave together', () async {
      final record = container.read(mediaSeerrRecordProvider(series).future);
      await pumpEventQueue();

      expect(client.requested, unorderedEquals(_seriesReads));

      client.answer('/api/v1/tv/1399', {'id': 1399, 'name': 'Severance'});
      client.answer('/api/v1/settings/sonarr', const []);
      client.answer('/api/v1/tv/1399/ratings', {'criticsScore': 94});
      client.answer('/api/v1/status', {'version': '2.1.0'});

      final answer = (await record).value;
      expect(answer.rottenTomatoes, 94);
      expect(answer.imdb, isNull);
    });

    test('a read that fails before the record answers is no answer, and '
        'not an unhandled error', () async {
      final record = container.read(mediaSeerrRecordProvider(movie).future);
      await pumpEventQueue();

      // The three side reads fail while the record is still on its way: the
      // old order never started them until the record was in, so none could
      // fail early. A failure with nobody awaiting it yet would reach the
      // zone, and the test would fail on it.
      client.fail('/api/v1/settings/radarr');
      client.fail('/api/v1/movie/653/ratingscombined');
      client.fail('/api/v1/status');
      await pumpEventQueue();
      client.answer('/api/v1/movie/653', {'id': 653, 'title': 'Nosferatu'});

      final answer = (await record).value;
      expect(answer.details['title'], 'Nosferatu');
      expect(answer.arrServers, isNull);
      expect(answer.rottenTomatoes, isNull);
      expect(answer.imdb, isNull);
      expect(answer.numbering, isNull);
    });

    test('the record\'s own failure is still the read\'s failure', () async {
      final record = container.read(mediaSeerrRecordProvider(movie).future);
      final outcome = expectLater(record, throwsException);
      await pumpEventQueue();

      client.fail('/api/v1/movie/653');
      await outcome;

      // The rest still answer, one of them with a failure of its own, into
      // nothing: neither is left unhandled.
      client.answer('/api/v1/settings/radarr', const []);
      client.fail('/api/v1/movie/653/ratingscombined');
      client.fail('/api/v1/status');
      await pumpEventQueue();
    });
  });

  group('the series id Sonarr is asked by', () {
    late FakeApiClient sonarr;

    setUp(() {
      sonarr = FakeApiClient()
        ..getResponseData = [
          {'id': 1, 'title': 'Severance', 'tmdbId': 95396, 'tvdbId': 371980},
          {'id': 2, 'title': 'Other', 'tmdbId': 1, 'tvdbId': 2},
        ];
    });

    Future<ProviderContainer> start({bool sonarrSet = true}) async {
      final container = ProviderContainer(
        overrides: [
          ...await settingsScopeOverrides(
            configured: [if (sonarrSet) ServiceKey.sonarr],
          ),
          sonarrServiceProvider.overrideWith((_) => SonarrService(sonarr)),
          sonarrServiceForProvider.overrideWith(
            (ref, id) => SonarrService(sonarr),
          ),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('comes off the library the app already holds', () async {
      final container = await start();
      final id = container
          .read(currentSettingsProvider)
          .instancesOf(ServiceKey.sonarr)
          .first
          .id;
      // The library wall opened first, as it does: one read of `series`.
      container.listen(seriesProvider, (_, _) {});
      await container.read(seriesProvider.future);
      expect(sonarr.getCallCount, 1);

      const key = MediaKey.tv(95396);
      container.listen(mediaTvdbIdProvider(key), (_, _) {});
      expect(await container.read(mediaTvdbIdProvider(key).future), 371980);

      // No second download of the library to find a number it holds.
      expect(sonarr.getCallCount, 1);
      expect(
        await container.read(seriesForProvider(id).future),
        hasLength(2),
        reason: 'the same cached read',
      );
      expect(sonarr.getCallCount, 1);
    });

    test('a library nobody has read yet is read once for both', () async {
      final container = await start();

      const key = MediaKey.tv(95396);
      container.listen(mediaTvdbIdProvider(key), (_, _) {});
      container.listen(seriesProvider, (_, _) {});
      expect(await container.read(mediaTvdbIdProvider(key).future), 371980);
      await container.read(seriesProvider.future);

      expect(sonarr.getCallCount, 1);
    });

    test('a Sonarr that is not set up is not asked at all', () async {
      final container = await start(sonarrSet: false);

      const key = MediaKey.tv(95396);
      expect(await container.read(mediaTvdbIdProvider(key).future), isNull);
      expect(sonarr.getCallCount, 0);
    });

    test(
      'a library that does not hold the series says nobody can say',
      () async {
        final container = await start();

        const key = MediaKey.tv(404);
        expect(await container.read(mediaTvdbIdProvider(key).future), isNull);
      },
    );
  });
}

const _movieReads = [
  '/api/v1/movie/653',
  '/api/v1/settings/radarr',
  '/api/v1/movie/653/ratingscombined',
  '/api/v1/status',
];

const _seriesReads = [
  '/api/v1/tv/1399',
  '/api/v1/settings/sonarr',
  '/api/v1/tv/1399/ratings',
  '/api/v1/status',
];
