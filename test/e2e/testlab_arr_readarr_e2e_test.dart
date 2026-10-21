@Tags(['e2e'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Readarr through the testlab's API, for the arr rows of the flow catalogue.
///
/// The lab is arranged by `arr-actions-readarr` (A-04, A-06) and
/// `arr-library-readarr` (A-08, A-09, A-10, A-11, A-12) and put back in
/// `tearDownAll`. The requests are the ones the app's `ReadarrService` makes:
/// `/api/v1` with `X-Api-Key`, `includeAuthor` and `includeBook` on the reads
/// that embed a parent.
///
/// Three rows are declared rather than covered, and the last test holds the
/// evidence instead of pretending otherwise:
///
/// * **A-03** adding an author: the app offers no action, because Readarr says
///   authors are added in Readarr itself.
/// * **A-07** removing an author: the client has `deleteAuthor`, but the lab
///   cannot create a throwaway author, and deleting one of the six seeded
///   authors cannot be undone without stopping the container.
/// * **A-08** the library filters: the author wall draws no status badge, so
///   `MediaBrowseScaffold` draws no status chips either. All is the only
///   filter Readarr has; the test proves the library and the counts the
///   author's caption reads.
void main() {
  const readarr = 'http://127.0.0.1:8787/api/v1';

  setUpAll(() async {
    await _scenario('apply', 'arr-actions-readarr');
    await _scenario('apply', 'arr-library-readarr');
  });

  tearDownAll(() async {
    await _scenario('teardown', 'arr-library-readarr');
    await _scenario('teardown', 'arr-actions-readarr');
  });

  test('A-04: the quality profile and the monitoring are on the author Readarr '
      'kept, and the rest of the record did not move', () async {
    final authors = await _list(readarr, '/author');
    final verne = authors.where(
      (author) => author['authorName'] == 'Jules Verne',
    );
    expect(
      verne,
      isNotEmpty,
      reason: 'the lab lost the author the scenario edits',
    );
    final author = verne.first;
    expect(author['qualityProfileId'], isNot(1));
    expect(author['monitored'], isFalse);
    expect(author['metadataProfileId'], 1);
    expect(author['monitorNewItems'], 'all');
    final profiles = await _list(readarr, '/qualityprofile');
    expect(
      profiles.map((profile) => profile['id']),
      contains(author['qualityProfileId']),
      reason: 'the record names a profile the server does not offer',
    );
  });

  test('A-06: the author and book searches are on the command list', () async {
    final authors = await _list(readarr, '/author');
    final verne = authors.firstWhere(
      (author) => author['authorName'] == 'Jules Verne',
    );
    final books = await _list(readarr, '/book?authorId=${verne['id']}');
    expect(books, isNotEmpty, reason: 'the lab lost the author books');
    final bookIds = books.map((book) => book['id']).toList();

    final commands = await _list(readarr, '/command');
    final authorSearch = commands.where(
      (command) =>
          command['name'] == 'AuthorSearch' &&
          (command['body'] as Map?)?['authorId'] == verne['id'],
    );
    expect(authorSearch, isNotEmpty, reason: 'no AuthorSearch for the author');
    expect(const [
      'queued',
      'started',
      'completed',
      'failed',
      'aborted',
    ], contains(authorSearch.first['status']));
    final bookSearch = commands.where(
      (command) =>
          command['name'] == 'BookSearch' &&
          ((command['body'] as Map?)?['bookIds'] as List?)?.any(
                (id) => bookIds.contains(id),
              ) ==
              true,
    );
    expect(bookSearch, isNotEmpty, reason: 'no BookSearch for a book');
  });

  test('A-07 and A-03: an author cannot be added offline, so the removal has '
      'no throwaway record', () async {
    final before = await _list(readarr, '/author');
    final lookup = await _answer(readarr, '/author/lookup?term=Cupola');
    expect(
      lookup.$1,
      greaterThanOrEqualTo(400),
      reason:
          'Readarr\'s metadata host answered: the lab is no longer offline, '
          'so A-07 could have a throwaway author',
    );

    final source = before.firstWhere(
      (author) => author['authorName'] == 'Jane Austen',
    );
    final payload = Map<String, Object?>.from(source)
      ..remove('id')
      ..['foreignAuthorId'] = 'cupola-testlab-disposable'
      ..['authorName'] = 'Cupola Testlab Disposable'
      ..['path'] = '/media/books/Cupola Testlab Disposable'
      ..['monitored'] = false
      ..['addOptions'] = <String, Object?>{
        'monitor': 'none',
        'booksToMonitor': <int>[],
        'monitored': false,
        'searchForMissingBooks': false,
      };
    final added = await _answer(
      readarr,
      '/author',
      method: 'POST',
      payload: payload,
    );
    expect(
      added.$1,
      greaterThanOrEqualTo(400),
      reason: 'Readarr accepted an author it could not resolve',
    );

    final after = await _list(readarr, '/author');
    expect(
      after.length,
      before.length,
      reason: 'a refused add changed the library',
    );
    expect(
      after.where(
        (author) => author['authorName'] == 'Cupola Testlab Disposable',
      ),
      isEmpty,
    );
  });

  test('A-08: the library and the counts its caption reads, and the '
      'unmonitored author out of the wanted list', () async {
    final authors = await _list(readarr, '/author');
    expect(authors.length, greaterThanOrEqualTo(6));
    final ids = <Object?>{};
    for (final author in authors) {
      ids.add(author['id']);
      final statistics = author['statistics'];
      expect(
        statistics,
        isA<Map>(),
        reason: '${author['authorName']} has no counts',
      );
      for (final key in ['bookCount', 'bookFileCount', 'totalBookCount']) {
        expect(
          (statistics as Map)[key],
          isA<int>(),
          reason: '${author['authorName']} has no $key',
        );
      }
    }
    final stoker = authors.where(
      (author) => author['authorName'] == 'Bram Stoker',
    );
    expect(stoker, isNotEmpty);
    expect(stoker.first['monitored'], isFalse);

    final books = await _list(readarr, '/book');
    expect(books, isNotEmpty);
    for (final book in books) {
      expect(book['id'], isA<int>());
      expect(book['title'], isA<String>());
      expect(ids, contains(book['authorId']));
      _parse(book['releaseDate']);
    }

    final ownBooks = await _list(
      readarr,
      '/book?authorId=${stoker.first['id']}',
    );
    final ownTitles = ownBooks.map((book) => book['title']).toSet();
    expect(ownTitles, isNotEmpty);
    final wanted = await _page(
      readarr,
      '/wanted/missing?page=1&pageSize=50&includeAuthor=true',
    );
    final records = (wanted['records'] as List).cast<Map>();
    expect(records, isNotEmpty);
    for (final record in records) {
      expect(
        record['author'],
        isA<Map>(),
        reason: 'the client asks includeAuthor=true and got no author',
      );
    }
    final wantedTitles = records.map((record) => record['title']).toSet();
    expect(
      ownTitles.where(wantedTitles.contains),
      isEmpty,
      reason: 'an unmonitored author is still in wanted/missing',
    );
  });

  test('A-09: the calendar dates the books it returns, and only those in the '
      'window asked', () async {
    final historical = await _list(
      readarr,
      '/calendar?start=1800-01-01&end=1910-12-31&includeAuthor=true',
    );
    expect(historical, isNotEmpty);
    for (final row in historical) {
      final date = _parse(row['releaseDate']);
      expect(
        date.isBefore(DateTime.utc(1800)) || date.isAfter(DateTime.utc(1911)),
        isFalse,
        reason: '${row['title']} is dated outside the window asked',
      );
      expect(
        row['author'],
        isA<Map>(),
        reason: 'the client asks includeAuthor=true and got no author',
      );
    }
    final austen = historical.where(
      (row) => row['title'] == 'Pride and Prejudice',
    );
    expect(austen, isNotEmpty, reason: 'the calendar lost a book of 1813');
    expect(_parse(austen.first['releaseDate']), DateTime.utc(1813, 1, 1));

    // The app's own window: thirty days from today. The six books are dated
    // 1813 to 1902, so the answer is usually an empty list, which the tab draws
    // as "Nothing scheduled"; an empty list is still an answer.
    final today = DateTime.now();
    final end = today.add(const Duration(days: 30));
    final upcoming = await _list(
      readarr,
      '/calendar?start=${_day(today)}&end=${_day(end)}&includeAuthor=true',
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
    final queue = await _page(readarr, '/queue?page=1&pageSize=50');
    expect(queue['page'], isA<int>());
    expect(queue['pageSize'], isA<int>());
    expect(queue['totalRecords'], isA<int>());
    expect(queue['records'], isA<List>());
    for (final row in (queue['records'] as List).cast<Map>()) {
      expect(row['title'], isNotNull);
      expect(row.containsKey('trackedDownloadState'), isTrue);
    }
    final clients = await _list(readarr, '/downloadclient');
    if (clients.isEmpty) {
      expect(queue['totalRecords'], 0);
    }
  });

  test('A-11: the wanted page embeds its author, the cutoff envelope answers, '
      'and the missing search is on the command list', () async {
    final wanted = await _page(
      readarr,
      '/wanted/missing?page=1&pageSize=5&includeAuthor=true',
    );
    final total = wanted['totalRecords'] as int;
    expect(total, greaterThan(0));
    final records = (wanted['records'] as List).cast<Map>();
    final missingIds = records.map((record) => record['id']).toSet();
    for (final record in records) {
      expect(record['id'], isA<int>());
      expect(record['title'], isA<String>());
      expect(record['author'], isA<Map>());
    }

    final cutoff = await _page(readarr, '/wanted/cutoff?page=1&pageSize=5');
    expect(cutoff['records'], isA<List>());

    final commands = await _list(readarr, '/command');
    final bookSearch = commands.where(
      (command) =>
          command['name'] == 'BookSearch' &&
          ((command['body'] as Map?)?['bookIds'] as List?)?.any(
                (id) => missingIds.contains(id),
              ) ==
              true,
    );
    expect(
      bookSearch,
      isNotEmpty,
      reason: 'the Wanted tab posted no BookSearch for a missing book',
    );
  });

  test('A-12: the history envelope, and the embeds the app reads when it has '
      'rows', () async {
    final history = await _page(
      readarr,
      '/history?page=1&pageSize=20&includeAuthor=true&includeBook=true',
    );
    expect(history['totalRecords'], isA<int>());
    expect(history['records'], isA<List>());
    for (final row in (history['records'] as List).cast<Map>()) {
      expect(row['eventType'], isA<String>());
      expect(row['eventType'] as String, isNotEmpty);
      _parse(row['date']);
      if (row['bookId'] is int) {
        expect(
          row['book'],
          isA<Map>(),
          reason: 'the client asks includeBook=true and got no book',
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
