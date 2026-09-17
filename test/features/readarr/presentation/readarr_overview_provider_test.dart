import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/api/base_arr_service.dart';
import 'package:cupola/core/status/media_status.dart';
import 'package:cupola/features/readarr/data/readarr_service.dart';
import 'package:cupola/features/readarr/domain/models/readarr_models.dart';
import 'package:cupola/features/readarr/presentation/readarr_overview_provider.dart';
import 'package:cupola/features/readarr/presentation/readarr_provider.dart';

import '../../../test_helpers/fake_api_client.dart';

/// A [ReadarrService] with a scripted queue, history, author list and root
/// folder list.
///
/// Written here rather than added to `test_helpers/fake_services.dart`: that
/// file is shared with every other suite and is being edited by other work in
/// flight, and nothing outside this file needs a Readarr fake yet.
class _ScriptedReadarr extends ReadarrService {
  _ScriptedReadarr({
    this.authors = const [],
    this.queue = const [],
    this.history = const [],
    this.rootFolders = const [],
    this.cutoffTotal,
  }) : super(FakeApiClient());

  final List<ReadarrAuthor> authors;
  final List<dynamic> queue;
  final List<dynamic> history;
  final List<Map<String, dynamic>> rootFolders;

  /// The envelope total `wanted/cutoff` answers with. Null is the shape of a
  /// fork that does not serve the endpoint at all.
  final int? cutoffTotal;

  @override
  Future<List<ReadarrAuthor>> getAuthors() async => authors;

  @override
  Future<List<dynamic>> getQueue({
    Map<String, dynamic>? queryParameters,
  }) async => queue;

  @override
  Future<List<dynamic>> getHistory({
    int page = 1,
    int pageSize = 20,
    Map<String, dynamic>? queryParameters,
  }) async => history;

  @override
  Future<List<Map<String, dynamic>>> fetchRootFolders() async => rootFolders;

  @override
  Future<ArrRecordPage> getCutoffPage({
    int page = 1,
    int pageSize = 20,
    Map<String, dynamic>? queryParameters,
  }) async {
    return ArrRecordPage(records: const [], total: cutoffTotal);
  }
}

ProviderContainer _container(_ScriptedReadarr service) {
  final container = ProviderContainer(
    // A failed provider would otherwise be retried on a backoff and leave a
    // pending timer behind the test that asked for the failure.
    retry: (_, _) => null,
    overrides: [readarrServiceProvider.overrideWith((ref) => service)],
  );
  addTearDown(container.dispose);
  return container;
}

ReadarrAuthor _author({int id = 1, int books = 0, int files = 0}) =>
    ReadarrAuthor(
      id: id,
      authorName: 'Author $id',
      monitored: true,
      bookCount: books,
      bookFileCount: files,
    );

void main() {
  // A fixed clock. Every window on this screen is a run of local calendar days,
  // so the tests state the day rather than inheriting whichever one the suite
  // happens to run on.
  final now = DateTime(2026, 9, 16, 14, 30);

  group('readarrRecordTitle', () {
    test('names the book, not the author or the raw release', () {
      expect(
        readarrRecordTitle(const {
          'book': {'title': 'Orbital'},
          'author': {'authorName': 'Samantha Harvey'},
          'sourceTitle': 'Orbital.2023.RETAIL.EPUB-XYZ',
        }),
        'Orbital',
      );
    });

    test('falls back to the author when the record carries no book', () {
      expect(
        readarrRecordTitle(const {
          'author': {'authorName': 'Samantha Harvey'},
          'sourceTitle': 'Orbital.2023.RETAIL.EPUB-XYZ',
        }),
        'Samantha Harvey',
      );
    });

    test('falls back to the release name when the server matched nothing', () {
      expect(
        readarrRecordTitle(const {
          'sourceTitle': 'Orbital.2023.RETAIL.EPUB-XYZ',
        }),
        'Orbital.2023.RETAIL.EPUB-XYZ',
      );
    });

    test('never answers empty', () {
      expect(readarrRecordTitle(const {}), 'Unknown release');
    });
  });

  group('readarrQueueFaults', () {
    test('reads an import failure as a fault, named by its book', () {
      final items = readarrQueueFaults([
        {
          'book': {'title': 'Orbital'},
          'trackedDownloadState': 'importFailed',
          'errorMessage': 'epub could not be matched',
          'added': now.subtract(const Duration(hours: 3)).toIso8601String(),
        },
      ], now: now);

      expect(items, hasLength(1));
      expect(items.single.kind, ReadarrAttentionKind.importFailed);
      expect(items.single.tone, StatusTone.warning);
      expect(items.single.headline, 'Import failed · Orbital');
      expect(items.single.detail, 'epub could not be matched · 3 h ago');
    });

    test('a stalled transfer wins over the import arm it also matches', () {
      // Readarr marks both with the same `trackedDownloadStatus: warning`, and
      // a transfer that is not moving has not reached the import stage at all.
      final items = readarrQueueFaults([
        {
          'book': {'title': 'James'},
          'trackedDownloadState': 'importPending',
          'trackedDownloadStatus': 'warning',
          'downloadClient': 'qBittorrent',
          'errorMessage': 'The download is stalled with no connections',
        },
      ], now: now);

      expect(items.single.kind, ReadarrAttentionKind.stalled);
      expect(items.single.headline, 'Stalled · James');
      expect(items.single.detail, startsWith('qBittorrent · '));
    });

    test('a healthy record produces no row at all', () {
      final items = readarrQueueFaults([
        {
          'book': {'title': 'Intermezzo'},
          'trackedDownloadState': 'downloading',
          'trackedDownloadStatus': 'ok',
        },
      ], now: now);

      expect(items, isEmpty);
    });

    test('a record with no timestamp simply omits the age', () {
      final items = readarrQueueFaults([
        {
          'book': {'title': 'Martyr!'},
          'trackedDownloadState': 'failed',
          'errorMessage': 'no match',
        },
      ], now: now);

      // Not "unknown", not an epoch date: the part is absent, so it is absent.
      expect(items.single.detail, 'no match');
    });

    test('the row is spoken as one sentence, with the dots as pauses', () {
      final items = readarrQueueFaults([
        {
          'book': {'title': 'Orbital'},
          'trackedDownloadState': 'importFailed',
          'errorMessage': 'epub could not be matched',
        },
      ], now: now);

      expect(
        items.single.spoken,
        'Import failed, Orbital, epub could not be matched',
      );
      expect(items.single.spoken, isNot(contains('·')));
    });
  });

  group('readarrMissingBooksItem', () {
    test('is absent when the library has no gap', () {
      expect(readarrMissingBooksItem([_author(books: 20, files: 20)]), isNull);
    });

    test('counts books across the library and names the authors', () {
      final item = readarrMissingBooksItem([
        _author(id: 1, books: 20, files: 15),
        _author(id: 2, books: 10, files: 10),
        _author(id: 3, books: 8, files: 2),
      ]);

      expect(item!.headline, '11 books missing a file');
      expect(item.detail, 'across 2 authors');
    });

    test('the backlog is NEUTRAL, never the amber of a fault', () {
      // The single most common way the five-arm tone rule gets broken: nothing
      // is wrong with a library that has books still to fetch.
      final item = readarrMissingBooksItem([_author(books: 4, files: 1)]);
      expect(item!.tone, StatusTone.neutral);
    });

    test('speaks singulars as singulars', () {
      final item = readarrMissingBooksItem([_author(books: 2, files: 1)]);
      expect(item!.spoken, '1 book missing a file, across 1 author');
    });

    test('matches the KPI rail arithmetic on odd statistics', () {
      // The rail sums both columns and clamps once; so does this. An author
      // reporting more files than books must not push the total negative here
      // while the rail shows zero two inches above.
      final item = readarrMissingBooksItem([
        _author(id: 1, books: 3, files: 9),
        _author(id: 2, books: 4, files: 0),
      ]);
      expect(item, isNull);
    });
  });

  group('readarrBelowCutoffItem', () {
    test('is absent when the server did not answer the question', () {
      // `getCutoffPage` degrades a fork that does not serve `wanted/cutoff` to
      // a null total. "We could not ask" is not "none", and a row is a claim.
      expect(readarrBelowCutoffItem(null), isNull);
      expect(readarrBelowCutoffItem(0), isNull);
    });

    test('prints the envelope total and speaks singulars as singulars', () {
      expect(
        readarrBelowCutoffItem(3)!.headline,
        '3 books below your quality cutoff',
      );
      expect(
        readarrBelowCutoffItem(1)!.headline,
        '1 book below your quality cutoff',
      );
    });

    test('the upgrade backlog is NEUTRAL, never the amber of a fault', () {
      // The book is on disk and readable today; Readarr is merely still
      // looking for a better copy.
      expect(readarrBelowCutoffItem(3)!.tone, StatusTone.neutral);
    });
  });

  group("readarrHistoryToday's vocabulary", () {
    // Readarr writes one history record per **book file**, under names no
    // other fork uses. These spellings live in the shared table
    // (`global_activity_status.dart`), not in a private switch here: the
    // Activity feed reads the same records through the same table, and a local
    // override kept this one screen honest while the feed one tab away still
    // drew a completed import grey.
    Map<String, dynamic> record(String eventType) => {
      'book': {'title': 'James'},
      'eventType': eventType,
      'date': DateTime(2026, 9, 16, 12).toIso8601String(),
    };

    ReadarrHistoryEntry entry(String eventType) =>
        readarrHistoryToday([record(eventType)], now: now).single;

    test('Readarr spells an import its own way, and it is GREEN', () {
      // The most common row on a book history, and the one event on the page
      // that is unambiguously good news: before the shared table knew these
      // two it fell through to `humanizeCamelCase` and drew neutral grey.
      expect(entry('bookFileImported').event, 'Imported');
      expect(entry('bookFileImported').tone, StatusTone.success);
      // The same event on an older Readarr.
      expect(entry('authorFolderImported').tone, StatusTone.success);
    });

    test('an incomplete import is a FAULT, and it is amber', () {
      expect(entry('bookImportIncomplete').event, 'Import incomplete');
      expect(entry('bookImportIncomplete').tone, StatusTone.warning);
    });

    test('maintenance and bookkeeping stay neutral', () {
      expect(entry('bookFileRetagged').event, 'Retagged');
      expect(entry('bookFileRetagged').tone, StatusTone.neutral);
      expect(entry('bookFileDeleted').event, 'Deleted');
      expect(entry('bookFileDeleted').tone, StatusTone.neutral);
      expect(entry('bookFileRenamed').event, 'Renamed');
      expect(entry('bookFileRenamed').tone, StatusTone.neutral);
    });

    test(
      'the events every arr fork shares are spelled and toned as before',
      () {
        expect(entry('downloadFailed').event, 'Failed');
        expect(entry('downloadFailed').tone, StatusTone.warning);
        expect(entry('grabbed').event, 'Grabbed');
        expect(entry('grabbed').tone, StatusTone.neutral);
      },
    );
  });

  group('readarrRootFolders', () {
    test('a folder whose free space is absent reads "—", never 0 B', () {
      final folders = readarrRootFolders([
        {'path': '/data/books'},
      ]);

      expect(folders.single.freeBytes, isNull);
      expect(folders.single.freeLabel, '—');
      // The em dash is a typographic shrug; read aloud it says nothing.
      expect(folders.single.spoken, '/data/books, free space unknown');
    });

    test('renders a free figure it was given', () {
      final folders = readarrRootFolders([
        {'path': '/data/books', 'freeSpace': 902_000_000_000},
      ]);

      // Binary units, as `byte_format.dart` fixed for the whole app: 902 GB
      // on the wire is 840 GB on screen, and that is the figure Readarr's own
      // web UI prints beside it.
      expect(folders.single.freeLabel, '840 GB free');
    });

    test('drops a record that cannot name what it reports on', () {
      final folders = readarrRootFolders([
        {'freeSpace': 1000},
        {'path': '', 'freeSpace': 1000},
        {'path': '/data/books'},
      ]);

      expect(folders.map((folder) => folder.path), ['/data/books']);
    });
  });

  group('readarrHistoryToday', () {
    Map<String, dynamic> record(DateTime date, {String title = 'James'}) => {
      'book': {'title': title},
      'eventType': 'downloadFolderImported',
      'date': date.toIso8601String(),
      'quality': {
        'quality': {'name': 'epub'},
      },
      'size': 2_200_000,
    };

    test('keeps the local calendar day of now and nothing else', () {
      final entries = readarrHistoryToday([
        record(DateTime(2026, 9, 16, 0, 5), title: 'Just after midnight'),
        record(DateTime(2026, 9, 15, 23, 50), title: 'Twenty minutes ago'),
        record(DateTime(2026, 9, 17, 0, 1), title: 'Tomorrow'),
      ], now: now);

      // Twenty minutes old and still out: the heading says "today", and a
      // heading is a promise.
      expect(entries.map((entry) => entry.title), ['Just after midnight']);
    });

    test('is newest first and capped at the limit', () {
      final entries = readarrHistoryToday(
        [
          record(DateTime(2026, 9, 16, 9), title: 'Morning'),
          record(DateTime(2026, 9, 16, 13), title: 'Afternoon'),
          record(DateTime(2026, 9, 16, 11), title: 'Midday'),
          record(DateTime(2026, 9, 16, 8), title: 'Early'),
        ],
        now: now,
        limit: 2,
      );

      expect(entries.map((entry) => entry.title), ['Afternoon', 'Midday']);
    });

    test('drops a record with no readable date rather than guessing one', () {
      final entries = readarrHistoryToday([
        {'eventType': 'grabbed', 'date': 'not a date'},
        <String, dynamic>{'eventType': 'grabbed'},
        'a string where a record should be',
      ], now: now);

      expect(entries, isEmpty);
    });

    test('carries the format, the size and the age as one spoken sentence', () {
      final entries = readarrHistoryToday([
        record(DateTime(2026, 9, 16, 12, 30)),
      ], now: now);

      expect(entries.single.event, 'Imported');
      expect(entries.single.tone, StatusTone.success);
      expect(entries.single.detail, startsWith('epub · '));
      expect(entries.single.detail, endsWith('2 h ago'));
      expect(entries.single.spoken, startsWith('James, Imported, epub, '));
    });

    test('a grab is neutral: the system doing its job is not news', () {
      final entries = readarrHistoryToday([
        {
          'book': {'title': 'Martyr!'},
          'eventType': 'grabbed',
          'date': DateTime(2026, 9, 16, 10).toIso8601String(),
        },
      ], now: now);

      expect(entries.single.tone, StatusTone.neutral);
    });
  });

  group('readarrNeedsAttentionProvider', () {
    test('puts the faults first, then the backlog in its own order', () async {
      final container = _container(
        _ScriptedReadarr(
          authors: [_author(books: 10, files: 4)],
          queue: [
            {
              'book': {'title': 'Orbital'},
              'trackedDownloadState': 'importFailed',
              'errorMessage': 'no match',
            },
          ],
          cutoffTotal: 3,
        ),
      );

      final items = await container.read(readarrNeedsAttentionProvider.future);

      // What needs a decision before what is merely outstanding, and within
      // the backlog a book with no file at all before one in the wrong format.
      expect(items.map((item) => item.kind), [
        ReadarrAttentionKind.importFailed,
        ReadarrAttentionKind.missingBooks,
        ReadarrAttentionKind.belowCutoff,
      ]);
    });

    test('a healthy Readarr can reach the resting state', () async {
      // The reason the standing "upstream is archived" row is gone: it was
      // pushed onto the head of this list on every load, so the section's
      // count could never read below 1 and "Nothing needs you" was
      // unreachable by construction.
      final container = _container(
        _ScriptedReadarr(authors: [_author(books: 20, files: 20)]),
      );

      expect(
        await container.read(readarrNeedsAttentionProvider.future),
        isEmpty,
      );
    });

    test('a cutoff endpoint the fork does not serve costs no row', () async {
      // `getCutoffPage` degrades to a null total there, and "we could not ask"
      // must not come out as "20 books below cutoff" — or as any row at all.
      // The rest of the section is unaffected.
      final container = _container(
        _ScriptedReadarr(authors: [_author(books: 4, files: 1)]),
      );

      expect(
        (await container.read(
          readarrNeedsAttentionProvider.future,
        )).map((item) => item.kind),
        [ReadarrAttentionKind.missingBooks],
      );
    });

    test(
      'a queue that could not be read takes the section, not the page',
      () async {
        final container = _container(_FailingQueueReadarr());

        await expectLater(
          container.read(readarrNeedsAttentionProvider.future),
          throwsA(isA<Exception>()),
        );
        // The other regions are separate providers and are unaffected.
        expect(
          await container.read(readarrHistoryTodayProvider.future),
          isEmpty,
        );
      },
    );
  });

  group('readarrHistoryTodayProvider', () {
    test('reads one page and keeps only today', () async {
      final container = _container(
        _ScriptedReadarr(
          history: [
            {
              'book': {'title': 'Today'},
              'eventType': 'downloadFolderImported',
              'date': DateTime.now().toIso8601String(),
            },
            {
              'book': {'title': 'Last week'},
              'eventType': 'downloadFolderImported',
              'date': DateTime.now()
                  .subtract(const Duration(days: 7))
                  .toIso8601String(),
            },
          ],
        ),
      );

      final entries = await container.read(readarrHistoryTodayProvider.future);

      expect(entries.map((entry) => entry.title), ['Today']);
    });
  });

  group('readarrRootFoldersProvider', () {
    test('reads the folders the service answers with', () async {
      final container = _container(
        _ScriptedReadarr(
          rootFolders: const [
            {'path': '/data/books', 'freeSpace': 902_000_000_000},
          ],
        ),
      );

      final folders = await container.read(readarrRootFoldersProvider.future);

      expect(folders.single.path, '/data/books');
    });
  });
}

/// A Readarr whose queue does not answer.
class _FailingQueueReadarr extends _ScriptedReadarr {
  @override
  Future<List<dynamic>> getQueue({
    Map<String, dynamic>? queryParameters,
  }) async => throw Exception('queue failed');
}
