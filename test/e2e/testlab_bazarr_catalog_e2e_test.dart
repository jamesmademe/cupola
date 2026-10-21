@Tags(['e2e'])
@Timeout(Duration(minutes: 15))
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/api/api_client.dart';
import 'package:cupola/features/bazarr/data/bazarr_service.dart';
import 'package:cupola/features/bazarr/domain/models/bazarr_models.dart';

/// Bazarr's three rows of the flow catalogue, A-18 to A-20, read through the
/// app's own client against the real container on 127.0.0.1:6767.
///
/// The state is the L6a embedded-subtitle case, arranged by one scenario which
/// this file applies in `setUpAll` and takes apart again in `tearDownAll`:
///
/// ```
/// python3 test/e2e/testlab/testlab.py scenario apply bazarr-catalog
/// python3 test/e2e/testlab/testlab.py scenario teardown bazarr-catalog
/// ```
///
/// `bazarr-catalog` imports `bazarr-embedded` and does not change it: Big Buck
/// Bunny gets a real English track, Bazarr extracts it with its
/// `embeddedsubtitles` provider, and The Matrix keeps only its French track and
/// stays wanted. The scenario is idempotent, so running this file twice is safe.
void main() {
  const bunny = 'Big Buck Bunny';
  const matrix = 'The Matrix';

  ApiClient? client;
  late BazarrService service;

  setUpAll(() async {
    await _scenario('apply', 'bazarr-catalog');
    client = ApiClient(baseUrl: 'http://127.0.0.1:6767', apiKey: 'test-key');
    service = BazarrService(client!);
    final status = await client!.get('/api/system/status');
    expect(status.statusCode, 200, reason: 'Bazarr is not answering');
  });

  tearDownAll(() async {
    client?.close();
    await _scenario('teardown', 'bazarr-catalog');
  });

  test('A-18: the wanted lists are the badge counts', () async {
    final badges = await service.getBadges();
    final wantedMovies = await service.getWantedMovies(length: 100);
    final wantedEpisodes = await service.getWantedEpisodes(length: 100);

    expect(wantedMovies.total, badges.movies);
    expect(wantedEpisodes.total, badges.episodes);
    for (final item in wantedMovies.data) {
      expect(
        item.missingLanguages,
        isNotEmpty,
        reason: '${item.title} is wanted for nothing',
      );
    }
    for (final item in wantedEpisodes.data) {
      expect(
        item.missingLanguages,
        isNotEmpty,
        reason: '${item.seriesTitle} ${item.episodeCode} is wanted for nothing',
      );
    }
  });

  test(
    'A-18: the movie with only its French track is the one wanted',
    () async {
      final wanted = (await service.getWantedMovies(length: 100)).data;
      final wantedMatrix = wanted.where((item) => item.title == matrix);
      expect(wantedMatrix, hasLength(1));
      expect(
        wantedMatrix.single.missingLanguages.map((language) => language.code2),
        contains('en'),
      );
      expect(wantedMatrix.single.presentLanguages, isEmpty);
      expect(
        wanted.where((item) => item.title == bunny),
        isEmpty,
        reason: 'the extracted movie is still on the wanted list',
      );

      // The coverage the app prints: every movie has a subtitle or is wanted.
      final movies = (await service.getMovies(length: 100)).data;
      final bunnyRow = movies.where((movie) => movie.title == bunny);
      expect(bunnyRow, hasLength(1));
      expect(
        bunnyRow.single.presentLanguages.map((language) => language.code2),
        contains('en'),
      );
      expect(
        bunnyRow.single.missingLanguages.map((language) => language.code2),
        isNot(contains('en')),
      );
      for (final movie in movies) {
        expect(
          movie.presentLanguages.isNotEmpty ||
              movie.missingLanguages.isNotEmpty,
          isTrue,
          reason: '${movie.title} is neither covered nor wanted',
        );
      }
    },
  );

  test(
    'A-19: the throttles are reset and every provider reads ready',
    () async {
      final before = await service.getProviderStatuses();
      expect(before, isNotEmpty, reason: 'Bazarr lists no enabled provider');
      expect(
        before.where((provider) => provider.throttled),
        isEmpty,
        reason: 'the scenario needs a lab with no waiting provider',
      );

      await service.resetProviderStatuses();

      final after = await service.getProviderStatuses();
      expect(
        after.map((provider) => provider.name),
        before.map((provider) => provider.name),
        reason: 'the reset changed the provider list',
      );
      expect(after.where((provider) => provider.throttled), isEmpty);
      for (final provider in after) {
        expect(provider.statusLabel, 'Ready');
        expect(provider.retryLabel, isNull);
      }

      // The badge counts the throttled ones only, never the enabled.
      final badges = await service.getBadges();
      expect(
        badges.providers,
        after.where((provider) => provider.throttled).length,
      );
    },
  );

  test('A-20: the movie history carries the extraction', () async {
    final page = await service.getMovieHistoryItems(length: 100);
    expect(page.total, greaterThan(0));
    expect(page.total, greaterThanOrEqualTo(page.data.length));

    final extraction = page.data.where(
      (item) =>
          item.title == bunny &&
          item.provider == 'embeddedsubtitles' &&
          item.action == BazarrHistoryAction.downloaded,
    );
    expect(extraction, isNotEmpty, reason: 'no extraction row in the history');
    expect(
      extraction.first.subtitle,
      contains('downloaded from embeddedsubtitles'),
    );
    expect(extraction.first.languageLabel, 'en');
    expect(extraction.first.parsedTimestamp, isNotNull);

    // The episodes half is an empty page in this lab (no episode carries a
    // subtitle yet), and an empty page must say so in its own total.
    final episodes = await service.getEpisodeHistoryItems(length: 100);
    expect(episodes.total, greaterThanOrEqualTo(episodes.data.length));
    if (episodes.data.isEmpty) {
      expect(episodes.total, 0);
    }
  });
}

Future<void> _scenario(String action, String name) async {
  final result = await Process.run('python3', [
    'test/e2e/testlab/testlab.py',
    'scenario',
    action,
    name,
  ], workingDirectory: Directory.current.path);
  if (result.exitCode != 0) {
    fail(
      'testlab.py scenario $action $name failed: '
      '${result.stderr}\n${result.stdout}',
    );
  }
}
