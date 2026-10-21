@Tags(['e2e'])
@Timeout(Duration(minutes: 10))
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The Sonarr rows of the flow catalogue, through the service's own API.
///
/// The lab is arranged by three scenarios (`arr-actions-sonarr`,
/// `arr-library-sonarr`, `arr-queue`), applied here and taken out again at the
/// end. The disposable series is `Firefly` (TVDB 78874), added from a real
/// lookup into `/media/tv-anime`:
///
/// * A-02 add a series with its first season monitored and its series type;
/// * A-06 the three searches (series, season, episodes);
/// * A-04 a profile, a monitoring, a season and a series type change, read back;
/// * A-08 the library chips over the fields the server answers;
/// * A-09 the calendar's episodes and their dates;
/// * A-11 wanted, missing and cutoff;
/// * A-12 the history the seeded lab carries;
/// * A-10 the queue, which in this lab answers empty and whole;
/// * A-07 the removal with its folder and an import list exclusion.
///
/// The removal runs last: it takes the disposable series out of the library.
/// A-05 (search releases and grab one) is L5's, and it covers Radarr.
void main() {
  setUpAll(() async {
    await _scenario('apply', 'arr-actions-sonarr');
    await _scenario('apply', 'arr-library-sonarr');
    await _scenario('apply', 'arr-queue');
  });

  tearDownAll(() async {
    await _scenario('teardown', 'arr-queue');
    await _scenario('teardown', 'arr-library-sonarr');
    await _scenario('teardown', 'arr-actions-sonarr');
  });

  test('A-02 the added series carries its first season and its type', () async {
    final series = await _disposableSeries();
    final profile = await _profileNamed('Cupola testlab 1080p');

    expect(series['tvdbId'], 78874);
    expect(series['qualityProfileId'], profile['id']);
    expect(series['rootFolderPath'], '/media/tv-anime');
    expect(series['monitored'], isTrue);
    expect(series['seriesType'], 'standard');
    final seasons = (series['seasons'] as List).cast<Map>();
    final first = seasons.firstWhere((season) => season['seasonNumber'] == 1);
    expect(first['monitored'], isTrue, reason: 'First season is monitored');
    expect(
      seasons
          .where((season) => season['seasonNumber'] != 1)
          .every((season) => season['monitored'] != true),
      isTrue,
      reason: 'nothing else is monitored',
    );

    // The app's "Needs episodes to monitor" and duplicate cases: a second add
    // of the same TVDB id is refused.
    final (status, body) = await _call(
      _sonarr,
      '/series',
      method: 'POST',
      payload: {
        'title': series['title'],
        'tvdbId': 78874,
        'year': series['year'],
        'qualityProfileId': profile['id'],
        'rootFolderPath': '/media/tv-anime',
        'monitored': true,
        'seasonFolder': true,
        'seriesType': 'standard',
        'seasons': seasons,
        'images': <Object>[],
        'addOptions': {
          'monitor': 'firstSeason',
          'searchForMissingEpisodes': false,
          'searchForCutoffUnmetEpisodes': false,
        },
      },
    );
    expect(status, 400, reason: 'a duplicate add answered $status: $body');
  });

  test('A-06 the three automatic searches complete', () async {
    final series = await _disposableSeries();
    final episodes = (await _getList(
      _sonarr,
      '/episode?seriesId=${series['id']}&seasonNumber=1',
    )).cast<Map>();
    expect(episodes, isNotEmpty);

    final commands = <String, Map>{
      'SeriesSearch': {'name': 'SeriesSearch', 'seriesId': series['id']},
      'SeasonSearch': {
        'name': 'SeasonSearch',
        'seriesId': series['id'],
        'seasonNumber': 1,
      },
      'EpisodeSearch': {
        'name': 'EpisodeSearch',
        'episodeIds': [episodes.first['id']],
      },
    };
    for (final entry in commands.entries) {
      final (status, command) = await _call(
        _sonarr,
        '/command',
        method: 'POST',
        payload: entry.value,
      );
      expect(status, 201, reason: '${entry.key} answered $status');
      final settled = await _settleCommand(_sonarr, command as Map);
      expect(settled['status'], 'completed', reason: entry.key);
    }
  });

  test(
    'A-04 profile, monitoring, season and series type are read back',
    () async {
      final series = await _disposableSeries();
      final profile = await _profileNamed('Cupola testlab 1080p');
      final seasons = (series['seasons'] as List).cast<Map>();

      await _write(_sonarr, '/series/${series['id']}', 'PUT', {
        ...series,
        'qualityProfileId': 3,
        'monitored': false,
        'seriesType': 'anime',
        'seasons': [
          for (final season in seasons)
            {
              ...season,
              'monitored': season['seasonNumber'] == 1
                  ? false
                  : season['monitored'],
            },
        ],
      });
      final changed = await _waitFor(
        () => _get(_sonarr, '/series/${series['id']}'),
        (record) =>
            record['qualityProfileId'] == 3 &&
            record['monitored'] == false &&
            record['seriesType'] == 'anime' &&
            (record['seasons'] as List).cast<Map>().any(
              (season) =>
                  season['seasonNumber'] == 1 && season['monitored'] == false,
            ),
        'Sonarr keeping the changed profile, monitoring and type',
      );
      expect(changed['seriesType'], 'anime');

      await _write(_sonarr, '/series/${series['id']}', 'PUT', {
        ...changed,
        'qualityProfileId': profile['id'],
        'monitored': true,
        'seriesType': 'standard',
        'seasons': [
          for (final season in (changed['seasons'] as List).cast<Map>())
            {
              ...season,
              'monitored': season['seasonNumber'] == 1
                  ? true
                  : season['monitored'],
            },
        ],
      });
      final restored = await _waitFor(
        () => _get(_sonarr, '/series/${series['id']}'),
        (record) =>
            record['qualityProfileId'] == profile['id'] &&
            record['monitored'] == true &&
            record['seriesType'] == 'standard',
        'Sonarr keeping the restored profile, monitoring and type',
      );
      expect(restored['seriesType'], 'standard');
    },
  );

  test('A-08 the library chips read the fields the server answers', () async {
    final library = (await _getList(_sonarr, '/series')).cast<Map>();
    // The actions scenario leaves its disposable Firefly (TVDB 78874) in the
    // library while this test runs; the chips are about the seeded ten.
    final seeded = library
        .where((series) => series['tvdbId'] != 78874)
        .toList(growable: false);
    final unmonitored = seeded.where((series) => series['monitored'] != true);
    final withFiles = library.where((series) {
      final statistics = series['statistics'];
      if (statistics is! Map) return false;
      final files = statistics['episodeFileCount'];
      return files is int && files > 0;
    });
    final cutoff = await _get(
      _sonarr,
      '/wanted/cutoff?page=1&pageSize=200'
      '&sortKey=airDateUtc&sortDirection=descending&includeSeries=true',
    );
    final queue = await _get(_sonarr, '/queue?pageSize=200');

    expect(seeded.length, 10);
    expect(
      withFiles,
      isEmpty,
      reason: 'the seeded Sonarr holds no episode file',
    );
    expect(
      unmonitored.map((series) => series['tvdbId']),
      contains(84912),
      reason: 'the library scenario unmonitors Parks and Recreation',
    );
    expect(cutoff['totalRecords'], 0);
    expect(queue['totalRecords'], 0);
    expect(queue['records'], isEmpty);
  });

  test('A-09 the calendar carries the episodes and their dates', () async {
    final today = DateTime.now();
    final end = today.add(const Duration(days: 30));
    final rows = (await _getList(
      _sonarr,
      '/calendar?start=${_isoDate(today)}&end=${_isoDate(end)}'
      '&includeSeries=true&includeEpisodeFile=true',
    )).cast<Map>();
    expect(rows, isNotEmpty, reason: 'the next thirty days hold episodes');

    for (final row in rows) {
      final series = row['series'];
      expect(series, isA<Map>(), reason: 'the calendar row embeds its series');
      expect((series as Map)['title'], isNotEmpty);
      final airDate = '${row['airDate']}';
      expect(
        airDate.substring(0, 10).compareTo(_isoDate(today)),
        greaterThanOrEqualTo(0),
      );
      expect(
        airDate.substring(0, 10).compareTo(_isoDate(end)),
        lessThanOrEqualTo(0),
      );
    }

    // The row's date is the episode's own date, not a copy that drifted.
    final episode = await _get(_sonarr, '/episode/${rows.first['id']}');
    expect(episode['airDate'], rows.first['airDate']);
  });

  test(
    'A-11 wanted lists the missing episodes, and nothing is below cutoff',
    () async {
      final missing = await _get(
        _sonarr,
        '/wanted/missing?page=1&pageSize=200'
        '&sortKey=airDateUtc&sortDirection=descending&includeSeries=true',
      );
      final cutoff = await _get(
        _sonarr,
        '/wanted/cutoff?page=1&pageSize=200'
        '&sortKey=airDateUtc&sortDirection=descending'
        '&includeSeries=true&includeEpisodeFile=true',
      );
      final records = (missing['records'] as List).cast<Map>();
      expect(missing['totalRecords'], greaterThan(0));
      expect(cutoff['totalRecords'], 0, reason: 'no file is below a cutoff');

      final series = records.first['series'] as Map;
      final (status, command) = await _call(
        _sonarr,
        '/command',
        method: 'POST',
        payload: {
          'name': 'SeasonSearch',
          'seriesId': series['id'],
          'seasonNumber': records.first['seasonNumber'] ?? 1,
        },
      );
      expect(status, 201);
      final settled = await _settleCommand(_sonarr, command as Map);
      expect(settled['status'], 'completed');
    },
  );

  test('A-12 the history carries the seeded rows with their series', () async {
    final history = await _get(
      _sonarr,
      '/history?page=1&pageSize=200'
      '&sortKey=date&sortDirection=descending&includeSeries=true'
      '&includeEpisode=true',
    );
    final records = (history['records'] as List).cast<Map>();
    expect(history['totalRecords'], greaterThan(0));
    expect(
      records.where(
        (record) =>
            record['series'] is Map &&
            '${(record['series'] as Map)['title']}'.isNotEmpty,
      ),
      isNotEmpty,
    );
  });

  test(
    'A-10 the queue answers empty and whole, and Sonarr has no client',
    () async {
      final queue = await _get(_sonarr, '/queue?pageSize=200');
      expect(queue['totalRecords'], 0);
      expect(queue['records'], isEmpty);
      final clients = await _getList(_sonarr, '/downloadclient');
      expect(
        clients,
        isEmpty,
        reason: 'the seeded Sonarr has no download client, so no queue record',
      );
    },
  );

  test(
    'A-07 the removal takes the folder and an import list exclusion',
    () async {
      final series = await _disposableSeries();
      final relative = '${series['path']}'.replaceFirst('/media/', '');
      final folder = Directory('${_stateDir()}/media/$relative');
      expect(folder.existsSync(), isTrue, reason: 'the series folder is there');

      final (status, body) = await _call(
        _sonarr,
        '/series/${series['id']}?deleteFiles=true&addImportListExclusion=true',
        method: 'DELETE',
      );
      expect(status, 200, reason: 'the removal answered $status: $body');

      final (afterStatus, _) = await _call(_sonarr, '/series/${series['id']}');
      expect(afterStatus, 404, reason: 'the removed series must answer 404');
      await _waitFor(
        () async => folder.existsSync(),
        (exists) => exists == false,
        'the removed series folder leaving the disk',
        timeout: const Duration(seconds: 90),
      );

      final exclusions = await _waitFor(
        () => _getList(_sonarr, '/importlistexclusion'),
        (rows) => rows.cast<Map>().any((row) => row['tvdbId'] == 78874),
        "the removal's import list exclusion",
      );
      final exclusion = exclusions.cast<Map>().firstWhere(
        (row) => row['tvdbId'] == 78874,
      );
      final (dropStatus, _) = await _call(
        _sonarr,
        '/importlistexclusion/${exclusion['id']}',
        method: 'DELETE',
      );
      expect(dropStatus, 200);
    },
  );
}

const String _sonarr = 'http://127.0.0.1:8989/api/v3';

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

Future<Map> _disposableSeries() async {
  final series = (await _getList(_sonarr, '/series?tvdbId=78874')).cast<Map>();
  expect(series, hasLength(1), reason: 'the scenario added the series');
  return series.first;
}

Future<Map> _profileNamed(String name) async {
  final profiles = (await _getList(_sonarr, '/qualityprofile')).cast<Map>();
  final profile = profiles.where((item) => item['name'] == name);
  expect(profile, isNotEmpty, reason: 'the profile $name exists');
  return profile.first;
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
