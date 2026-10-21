@Tags(['e2e'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Lidarr through the testlab's API, for the arr rows of the flow catalogue.
///
/// The lab is arranged by `arr-actions-lidarr` (A-04, A-06, A-07) and
/// `arr-library-lidarr` (A-08, A-09, A-10, A-11, A-12) and put back in
/// `tearDownAll`; each scenario's own `verify` asserts the same state, and this
/// test is the second reader. It talks HTTP the way the app's client does: the
/// same paths, the same `X-Api-Key`, the same embeds (`includeArtist`,
/// `includeAlbum`) the service adds before it hands the records to a screen.
///
/// What the golden lab cannot show is asserted as the field the filter reads,
/// not as a row that does not exist: no artist is fully filed (so Available has
/// no row), Lidarr has no download client (so In queue has none), and no file
/// is below a cutoff (so Cutoff unmet has none). The docstrings of the two
/// scenarios say why.
void main() {
  const lidarr = 'http://127.0.0.1:8686/api/v1';

  setUpAll(() async {
    await _scenario('apply', 'arr-actions-lidarr');
    await _scenario('apply', 'arr-library-lidarr');
  });

  tearDownAll(() async {
    await _scenario('teardown', 'arr-library-lidarr');
    await _scenario('teardown', 'arr-actions-lidarr');
  });

  test('A-04: the quality profile, the monitoring and the new items are on the '
      'artist Lidarr kept', () async {
    final artists = await _list(lidarr, '/artist');
    final air = artists.where((artist) => artist['artistName'] == 'Air');
    expect(
      air,
      isNotEmpty,
      reason: 'the lab lost the artist the scenario edits',
    );
    final artist = air.first;
    expect(artist['qualityProfileId'], isNot(1));
    expect(artist['monitored'], isFalse);
    expect(artist['monitorNewItems'], 'new');
    final profiles = await _list(lidarr, '/qualityprofile');
    expect(
      profiles.map((profile) => profile['id']),
      contains(artist['qualityProfileId']),
      reason: 'the record names a profile the server does not offer',
    );
  });

  test('A-06: the artist and album searches are on the command list', () async {
    final artists = await _list(lidarr, '/artist');
    final air = artists.firstWhere((artist) => artist['artistName'] == 'Air');
    final albums = await _list(lidarr, '/album?artistId=${air['id']}');
    expect(albums, isNotEmpty, reason: 'the lab lost the artist albums');
    final albumIds = albums.map((album) => album['id']).toList();

    final commands = await _list(lidarr, '/command');
    final artistSearch = commands.where(
      (command) =>
          command['name'] == 'ArtistSearch' &&
          (command['body'] as Map?)?['artistId'] == air['id'],
    );
    expect(artistSearch, isNotEmpty, reason: 'no ArtistSearch for the artist');
    expect(const [
      'queued',
      'started',
      'completed',
      'failed',
      'aborted',
    ], contains(artistSearch.first['status']));
    final albumSearch = commands.where(
      (command) =>
          command['name'] == 'AlbumSearch' &&
          ((command['body'] as Map?)?['albumIds'] as List?)?.any(
                (id) => albumIds.contains(id),
              ) ==
              true,
    );
    expect(albumSearch, isNotEmpty, reason: 'no AlbumSearch for an album');
  });

  test('A-07: the throwaway artist is gone, its folder with it, and the '
      'exclusion stays', () async {
    final artists = await _list(lidarr, '/artist');
    expect(
      artists.where((artist) => artist['artistName'] == 'James Cupola'),
      isEmpty,
      reason: 'the removed artist is listed again',
    );
    final exclusions = await _list(lidarr, '/importlistexclusion');
    expect(
      exclusions.where(
        (exclusion) => exclusion['artistName'] == 'James Cupola',
      ),
      isNotEmpty,
      reason: 'the removal did not leave the import list exclusion',
    );
    final state =
        Platform.environment['CUPOLA_TESTLAB_STATE_DIR'] ??
        '.ai/scratch/zz_testlab/state';
    expect(
      Directory('$state/media/music/James Cupola').existsSync(),
      isFalse,
      reason: 'deleteFiles left the artist folder on disk',
    );
  });

  test(
    'A-08: the Unmonitored row and the wanted pages the filters read',
    () async {
      final artists = await _list(lidarr, '/artist');
      expect(
        artists.where((artist) => artist['monitored'] == false),
        isNotEmpty,
        reason: 'no artist is unmonitored, so that filter has no row',
      );
      final withStatistics = artists.where(
        (artist) => artist['statistics'] is Map,
      );
      expect(withStatistics, isNotEmpty);
      for (final artist in withStatistics) {
        final statistics = artist['statistics'] as Map;
        final files = statistics['trackFileCount'];
        final tracks = statistics['trackCount'];
        expect(files, isA<int>());
        expect(tracks, isA<int>());
        expect(
          files as int,
          lessThanOrEqualTo(tracks as int),
          reason: '${artist['artistName']} counts more files than tracks',
        );
      }

      final missing = await _page(
        lidarr,
        '/wanted/missing?page=1&pageSize=50&includeArtist=true',
      );
      expect(missing['totalRecords'], greaterThan(0));
      final records = (missing['records'] as List).cast<Map>();
      expect(records, isNotEmpty);
      for (final record in records) {
        expect(record['id'], isA<int>());
        expect(record['artistId'], isA<int>());
        expect(
          record['artist'],
          isA<Map>(),
          reason: 'the client asks includeArtist=true and got no artist',
        );
      }

      final cutoff = await _page(
        lidarr,
        '/wanted/cutoff?page=1&pageSize=50&includeArtist=false',
      );
      expect(cutoff['records'], isA<List>());
      expect(cutoff['totalRecords'], (cutoff['records'] as List).length);
    },
  );

  test('A-09: the calendar dates the albums it returns, and only those in the '
      'window asked', () async {
    final historical = await _list(
      lidarr,
      '/calendar?start=2000-01-01&end=2003-12-31&includeArtist=true',
    );
    expect(historical, isNotEmpty);
    for (final row in historical) {
      final date = _parse(row['releaseDate']);
      expect(
        date.isBefore(DateTime.utc(2000)) || date.isAfter(DateTime.utc(2004)),
        isFalse,
        reason: '${row['title']} is dated outside the window asked',
      );
      expect(
        row['artist'],
        isA<Map>(),
        reason: 'the client asks includeArtist=true and got no artist',
      );
    }
    final drukqs = historical.where((row) => row['title'] == 'Drukqs');
    expect(drukqs, isNotEmpty, reason: 'the calendar lost a release of 2001');
    expect(_parse(drukqs.first['releaseDate']), DateTime.utc(2001, 10, 22));

    // The app's own window: thirty days from today, local. The lab's releases
    // are historical plus one album of 2026, so this is usually empty, and an
    // empty answer is still an answer: a list, not a fault.
    final today = DateTime.now();
    final end = today.add(const Duration(days: 30));
    final upcoming = await _list(
      lidarr,
      '/calendar?start=${_day(today)}&end=${_day(end)}&includeArtist=true',
    );
    for (final row in upcoming) {
      final date = _parse(row['releaseDate']).toLocal();
      expect(
        date.isBefore(DateTime(today.year, today.month, today.day)),
        isFalse,
      );
      expect(date.isAfter(DateTime(end.year, end.month, end.day)), isFalse);
    }
  });

  test('A-10: the queue answers its envelope, and an empty one because the lab '
      'has no download client', () async {
    final queue = await _page(lidarr, '/queue?page=1&pageSize=50');
    expect(queue['page'], isA<int>());
    expect(queue['pageSize'], isA<int>());
    expect(queue['totalRecords'], isA<int>());
    expect(queue['records'], isA<List>());
    for (final row in (queue['records'] as List).cast<Map>()) {
      expect(row['title'], isNotNull);
      expect(
        row.containsKey('trackedDownloadState'),
        isTrue,
        reason: 'the app reads the row state from trackedDownloadState',
      );
    }
    final clients = await _list(lidarr, '/downloadclient');
    if (clients.isEmpty) {
      expect(
        queue['totalRecords'],
        0,
        reason: 'a queue without a download client cannot have rows',
      );
    }
  });

  test('A-11: the wanted walk pages, the cutoff envelope answers, and the '
      'missing search is on the command list', () async {
    final first = await _page(
      lidarr,
      '/wanted/missing?page=1&pageSize=5&includeArtist=true',
    );
    final total = first['totalRecords'] as int;
    final firstRecords = (first['records'] as List).cast<Map>();
    expect(total, greaterThan(0));
    if (total > 5) {
      final second = await _page(
        lidarr,
        '/wanted/missing?page=2&pageSize=5&includeArtist=true',
      );
      final firstIds = firstRecords.map((record) => record['id']).toSet();
      expect(
        (second['records'] as List).cast<Map>().where(
          (record) => firstIds.contains(record['id']),
        ),
        isEmpty,
        reason: 'two wanted pages repeat a row',
      );
    }

    final cutoff = await _page(lidarr, '/wanted/cutoff?page=1&pageSize=5');
    expect(cutoff['records'], isA<List>());

    final missingIds = firstRecords.map((record) => record['id']).toSet();
    final commands = await _list(lidarr, '/command');
    final albumSearch = commands.where(
      (command) =>
          command['name'] == 'AlbumSearch' &&
          ((command['body'] as Map?)?['albumIds'] as List?)?.any(
                (id) => missingIds.contains(id),
              ) ==
              true,
    );
    expect(
      albumSearch,
      isNotEmpty,
      reason: 'the Wanted tab posted no AlbumSearch for a missing album',
    );
  });

  test('A-12: the history envelope, and the embeds the app reads when it has '
      'rows', () async {
    final history = await _page(
      lidarr,
      '/history?page=1&pageSize=20&includeArtist=true&includeAlbum=true',
    );
    expect(history['totalRecords'], isA<int>());
    expect(history['records'], isA<List>());
    for (final row in (history['records'] as List).cast<Map>()) {
      expect(row['eventType'], isA<String>());
      expect(row['eventType'] as String, isNotEmpty);
      _parse(row['date']);
      if (row['albumId'] is int) {
        expect(
          row['album'],
          isA<Map>(),
          reason: 'the client asks includeAlbum=true and got no album',
        );
        expect(
          row['artist'],
          isA<Map>(),
          reason: 'the client asks includeArtist=true and got no artist',
        );
      }
    }
  });
}

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
    reason: 'scenario $action $name failed: ${result.stderr}',
  );
}

Future<(int, Object?)> _answer(
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
      request.headers.contentType = ContentType.json;
      final bytes = utf8.encode(jsonEncode(payload));
      request.contentLength = bytes.length;
      request.add(bytes);
    }
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    return (response.statusCode, body.isEmpty ? null : jsonDecode(body));
  } finally {
    client.close(force: true);
  }
}

Future<Object?> _json(
  String base,
  String path, {
  String method = 'GET',
  Object? payload,
}) async {
  final (status, body) = await _answer(
    base,
    path,
    method: method,
    payload: payload,
  );
  if (status < 200 || status >= 300) {
    fail('$method $path answered $status: $body');
  }
  return body;
}

Future<List<Map>> _list(String base, String path) async {
  final body = await _json(base, path);
  expect(body, isA<List>(), reason: '$path did not answer with a list');
  return (body as List).cast<Map>();
}

Future<Map> _page(String base, String path) async {
  final body = await _json(base, path);
  expect(body, isA<Map>(), reason: '$path did not answer with a page envelope');
  return body as Map;
}

DateTime _parse(Object? value) {
  expect(value, isA<String>(), reason: 'a record carries no date');
  return DateTime.parse(value as String);
}

String _day(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';
