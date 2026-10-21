@Tags(['e2e'])
@Timeout(Duration(minutes: 10))
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The Radarr rows of the flow catalogue, through the service's own API.
///
/// The lab is arranged by three scenarios (`arr-actions-radarr`,
/// `arr-library-radarr`, `arr-queue`), applied here and taken out again at the
/// end, so the test proves the same server calls the app makes on top of the
/// state the scenarios set up:
///
/// * A-01 add a movie with its profile, root folder, monitoring and tag;
/// * A-06 the automatic search and the command it starts;
/// * A-04 a profile and a monitoring change, read back;
/// * A-08 the library chips over the fields the server answers;
/// * A-09 the calendar's dates;
/// * A-11 wanted, missing and cutoff;
/// * A-12 the history the L5 grab left;
/// * A-10 the queue, which in this lab answers empty and whole;
/// * A-07 the removal with its files and an import list exclusion.
///
/// The removal runs last: it takes the disposable movie out of the library.
/// A-05 (search releases and grab one) is L5's:
/// `testlab_release_search_e2e_test.dart`.
void main() {
  setUpAll(() async {
    await _scenario('apply', 'arr-actions-radarr');
    await _scenario('apply', 'arr-library-radarr');
    await _scenario('apply', 'arr-queue');
  });

  tearDownAll(() async {
    await _scenario('teardown', 'arr-queue');
    await _scenario('teardown', 'arr-library-radarr');
    await _scenario('teardown', 'arr-actions-radarr');
  });

  test(
    'A-01 the added movie carries its profile, folder, monitoring and tag',
    () async {
      final movie = await _disposableMovie();
      final profile = await _profileNamed('Cupola testlab 1080p');
      final tag = await _tagNamed('cupola-testlab');

      expect(movie['tmdbId'], 999001);
      expect(movie['qualityProfileId'], profile['id']);
      expect(movie['rootFolderPath'], '/media/movies4k');
      expect(movie['monitored'], isTrue);
      expect(movie['hasFile'], isFalse);
      expect(movie['path'], startsWith('/media/movies4k/'));
      expect(movie['tags'], contains(tag['id']));

      // The app's "This movie has already been added": a second add of the same
      // TMDB id is refused, not merged.
      final (status, body) = await _call(
        _radarr,
        '/movie',
        method: 'POST',
        payload: {
          'title': movie['title'],
          'tmdbId': 999001,
          'year': movie['year'],
          'qualityProfileId': profile['id'],
          'rootFolderPath': '/media/movies4k',
          'monitored': true,
          'minimumAvailability': 'released',
          'addOptions': {'searchForMovie': false},
          'images': <Object>[],
          'tags': <Object>[],
        },
      );
      expect(status, 400, reason: 'a duplicate add answered $status: $body');
    },
  );

  test('A-06 an automatic search starts a command that completes', () async {
    final movie = await _disposableMovie();
    final (status, command) = await _call(
      _radarr,
      '/command',
      method: 'POST',
      payload: {
        'name': 'MoviesSearch',
        'movieIds': [movie['id']],
      },
    );
    expect(status, 201);
    final settled = await _settleCommand(_radarr, command as Map);
    expect(settled['status'], 'completed');
    expect('${settled['message']}', contains('search'));
  });

  test('A-04 a profile and a monitoring change are read back', () async {
    final movie = await _disposableMovie();
    final profile = await _profileNamed('Cupola testlab 1080p');
    final original = movie['qualityProfileId'];

    await _write(_radarr, '/movie/${movie['id']}', 'PUT', {
      ...movie,
      'qualityProfileId': 3,
      'monitored': false,
    });
    final changed = await _waitFor(
      () => _get(_radarr, '/movie/${movie['id']}'),
      (record) =>
          record['qualityProfileId'] == 3 && record['monitored'] == false,
      'Radarr keeping the changed profile and monitoring',
    );
    expect(changed['qualityProfileId'], 3);
    expect(changed['monitored'], isFalse);

    await _write(_radarr, '/movie/${movie['id']}', 'PUT', {
      ...changed,
      'qualityProfileId': original,
      'monitored': true,
    });
    final restored = await _waitFor(
      () => _get(_radarr, '/movie/${movie['id']}'),
      (record) =>
          record['qualityProfileId'] == profile['id'] &&
          record['monitored'] == true,
      'Radarr keeping the restored profile and monitoring',
    );
    expect(restored['qualityProfileId'], profile['id']);
    expect(restored['monitored'], isTrue);
  });

  test('A-08 the library chips read the fields the server answers', () async {
    final library = (await _getList(_radarr, '/movie')).cast<Map>();
    final available = library.where((movie) => movie['hasFile'] == true);
    final missing = library.where(
      (movie) =>
          movie['hasFile'] != true &&
          (movie['isAvailable'] == true ||
              const [
                'released',
                'incinemas',
              ].contains('${movie['status']}'.toLowerCase())),
    );
    final unmonitored = library.where((movie) => movie['monitored'] != true);
    final cutoff = await _get(_radarr, '/wanted/cutoff?pageSize=200');
    final cutoffRecords = (cutoff['records'] as List).cast<Map>();
    final queue = await _get(_radarr, '/queue?pageSize=200');

    expect(library.length, greaterThanOrEqualTo(40));
    expect(
      available.map((movie) => movie['tmdbId']),
      contains(550),
      reason: 'Fight Club is on disk',
    );
    expect(
      missing.map((movie) => movie['tmdbId']),
      contains(1153576),
      reason: 'Street Fighter is missing',
    );
    expect(
      unmonitored.map((movie) => movie['tmdbId']),
      contains(348),
      reason: 'Alien is unmonitored',
    );
    expect(
      cutoffRecords.map((movie) => movie['tmdbId']),
      contains(550),
      reason: 'Fight Club sits below the cutoff profile',
    );
    expect(queue['totalRecords'], 0, reason: 'nothing is in the queue');
    expect(queue['records'], isEmpty);
  });

  test('A-09 the calendar carries the dates the movies declare', () async {
    final today = DateTime.now();
    final start = today.subtract(const Duration(days: 7));
    final end = today.add(const Duration(days: 45));
    final rows = (await _getList(
      _radarr,
      '/calendar?start=${_isoDate(start)}&end=${_isoDate(end)}',
    )).cast<Map>();

    final clayface = rows.where((row) => row['tmdbId'] == 1400940);
    expect(clayface, isNotEmpty, reason: 'Clayface opens today');
    expect('${clayface.first['inCinemas']}'.substring(0, 10), _isoDate(today));
    for (final row in rows) {
      final dates = [
        row['inCinemas'],
        row['digitalRelease'],
        row['physicalRelease'],
      ].whereType<String>().toList();
      expect(dates, isNotEmpty, reason: '${row['title']} carries no date');
      expect(
        dates.any(
          (date) =>
              date.substring(0, 10).compareTo(_isoDate(start)) >= 0 &&
              date.substring(0, 10).compareTo(_isoDate(end)) <= 0,
        ),
        isTrue,
        reason: '${row['title']} falls outside the window',
      );
    }
  });

  test(
    'A-11 wanted lists the missing movies and the ones below cutoff',
    () async {
      final missing = await _get(
        _radarr,
        '/wanted/missing?page=1&pageSize=200'
        '&sortKey=airDateUtc&sortDirection=descending',
      );
      final cutoff = await _get(
        _radarr,
        '/wanted/cutoff?page=1&pageSize=200'
        '&sortKey=airDateUtc&sortDirection=descending',
      );
      final missingRecords = (missing['records'] as List).cast<Map>();

      expect(missing['totalRecords'], greaterThanOrEqualTo(20));
      expect(
        missingRecords.map((record) => record['tmdbId']),
        contains(1153576),
      );
      expect(
        (cutoff['records'] as List).cast<Map>().map(
          (record) => record['tmdbId'],
        ),
        contains(550),
      );

      // "Search the missing one": the command the pill starts.
      final target = missingRecords.firstWhere(
        (record) => record['title'] != 'Big Buck Bunny',
      );
      final (status, command) = await _call(
        _radarr,
        '/command',
        method: 'POST',
        payload: {
          'name': 'MoviesSearch',
          'movieIds': [target['id']],
        },
      );
      expect(status, 201);
      final settled = await _settleCommand(_radarr, command as Map);
      expect(settled['status'], 'completed');
    },
  );

  test(
    'A-12 the history carries the L5 grab and the import it produced',
    () async {
      final history = await _get(
        _radarr,
        '/history?page=1&pageSize=200'
        '&sortKey=date&sortDirection=descending&includeMovie=true',
      );
      final records = (history['records'] as List).cast<Map>();
      expect(history['totalRecords'], greaterThan(0));
      expect(
        records.where(
          (record) =>
              record['eventType'] == 'grabbed' &&
              '${record['sourceTitle']}'.contains('CUPOLA'),
        ),
        isNotEmpty,
        reason: 'the L5 grab of the forged release is in the history',
      );
      expect(
        records.where(
          (record) => record['eventType'] == 'downloadFolderImported',
        ),
        isNotEmpty,
        reason: 'the import that followed the grab is in the history',
      );
    },
  );

  test(
    'A-10 the queue answers empty and whole, and that is not a fault',
    () async {
      final movie = await _disposableMovie();
      final queue = await _get(_radarr, '/queue?pageSize=200');
      expect(queue['totalRecords'], 0);
      expect(queue['records'], isEmpty);
      final details = await _getList(
        _radarr,
        '/queue/details?movieId=${movie['id']}',
      );
      expect(details, isEmpty);

      // The services that would put a record there answer, so the emptiness is
      // the lab's state and not an unreachable server.
      final clients = (await _getList(_radarr, '/downloadclient')).cast<Map>();
      expect(clients.where((client) => client['enable'] == true), isNotEmpty);
    },
  );

  test(
    'A-07 the removal takes the files, the folder and an exclusion',
    () async {
      final movie = await _disposableMovie();
      final relative = '${movie['path']}'.replaceFirst('/media/', '');
      final folder = Directory('${_stateDir()}/media/$relative');
      folder.createSync(recursive: true);

      final (status, body) = await _call(
        _radarr,
        '/movie/${movie['id']}?deleteFiles=true&addImportExclusion=true',
        method: 'DELETE',
      );
      expect(status, 200, reason: 'the removal answered $status: $body');

      final (afterStatus, _) = await _call(_radarr, '/movie/${movie['id']}');
      expect(afterStatus, 404, reason: 'the removed movie must answer 404');
      await _waitFor(
        () async => folder.existsSync(),
        (exists) => exists == false,
        'the removed movie folder leaving the disk',
        timeout: const Duration(seconds: 90),
      );

      final exclusions = await _waitFor(
        () => _getList(_radarr, '/exclusions'),
        (rows) => rows.cast<Map>().any((row) => row['tmdbId'] == 999001),
        "the removal's import list exclusion",
      );
      final exclusion = exclusions.cast<Map>().firstWhere(
        (row) => row['tmdbId'] == 999001,
      );
      final (dropStatus, _) = await _call(
        _radarr,
        '/exclusions/${exclusion['id']}',
        method: 'DELETE',
      );
      expect(dropStatus, 200);
    },
  );
}

const String _radarr = 'http://127.0.0.1:7878/api/v3';

Future<void> _scenario(String action, String name) async {
  final result = await Process.run('python3', [
    'test/e2e/testlab/testlab.py',
    'scenario',
    action,
    name,
  ]);
  expect(
    result.exitCode,
    0,
    reason: 'scenario $action $name failed: ${result.stdout}\n${result.stderr}',
  );
}

Future<(int, Object?)> _call(
  String base,
  String path, {
  String method = 'GET',
  Object? payload,
}) async {
  final client = HttpClient();
  try {
    final request = await client.openUrl(method, Uri.parse('$base$path'));
    request.headers.set('X-Api-Key', 'test-key');
    request.headers.set('Accept', 'application/json');
    if (payload != null) {
      final bytes = utf8.encode(jsonEncode(payload));
      request.headers.contentType = ContentType.json;
      request.contentLength = bytes.length;
      request.add(bytes);
    }
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    if (body.isEmpty) return (response.statusCode, null);
    try {
      return (response.statusCode, jsonDecode(body));
    } on FormatException {
      return (response.statusCode, body);
    }
  } finally {
    client.close(force: true);
  }
}

Future<Map> _get(String base, String path) async {
  final (status, body) = await _call(base, path);
  expect(status, 200, reason: 'GET $path answered $status: $body');
  return body as Map;
}

Future<List<Object?>> _getList(String base, String path) async {
  final (status, body) = await _call(base, path);
  expect(status, 200, reason: 'GET $path answered $status: $body');
  return (body as List).cast<Object?>();
}

Future<void> _write(
  String base,
  String path,
  String method,
  Object payload,
) async {
  final (status, body) = await _call(
    base,
    path,
    method: method,
    payload: payload,
  );
  expect(
    status,
    anyOf(200, 201, 202),
    reason: '$method $path answered $status: $body',
  );
}

Future<Map> _disposableMovie() async {
  final movies = (await _getList(_radarr, '/movie?tmdbId=999001')).cast<Map>();
  expect(movies, hasLength(1), reason: 'the scenario added the movie');
  return movies.first;
}

Future<Map> _profileNamed(String name) async {
  final profiles = (await _getList(_radarr, '/qualityprofile')).cast<Map>();
  final profile = profiles.where((item) => item['name'] == name);
  expect(profile, isNotEmpty, reason: 'the profile $name exists');
  return profile.first;
}

Future<Map> _tagNamed(String label) async {
  final tags = (await _getList(_radarr, '/tag')).cast<Map>();
  final tag = tags.where((item) => item['label'] == label);
  expect(tag, isNotEmpty, reason: 'the tag $label exists');
  return tag.first;
}

Future<Map> _settleCommand(String base, Map command) async {
  return _waitFor(
    () => _get(base, '/command/${command['id']}'),
    (record) => const [
      'completed',
      'failed',
      'aborted',
      'cancelled',
    ].contains(record['status']),
    'the command ${command['name']} settling',
    timeout: const Duration(minutes: 3),
  );
}

Future<T> _waitFor<T>(
  Future<T> Function() read,
  bool Function(T) predicate,
  String what, {
  Duration timeout = const Duration(seconds: 60),
}) async {
  final deadline = DateTime.now().add(timeout);
  late T last;
  while (DateTime.now().isBefore(deadline)) {
    last = await read();
    if (predicate(last)) return last;
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  fail('$what did not happen within ${timeout.inSeconds}s: $last');
}

String _isoDate(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';

String _stateDir() =>
    Platform.environment['CUPOLA_TESTLAB_STATE_DIR'] ??
    '.ai/scratch/zz_testlab/state';
