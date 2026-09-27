import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/api/base_arr_service.dart';
import 'package:cupola/core/status/media_status.dart';
import 'package:cupola/features/movies/data/radarr_service.dart';
import 'package:cupola/features/movies/domain/models/radarr_movie.dart';
import 'package:cupola/features/movies/presentation/radarr_overview_provider.dart';

import '../../../test_helpers/fake_services.dart';

/// A [FakeRadarrService] with a scripted library, queue, history and cutoff
/// list.
///
/// Extends the shared fake rather than editing it: every other test that builds
/// a `FakeRadarrService` keeps the empty defaults it relies on.
class _ScriptedRadarr extends FakeRadarrService {
  _ScriptedRadarr({
    this.movies = const [],
    this.queue = const [],
    this.history = const [],
    this.cutoffTotal,
  });

  final List<RadarrMovie> movies;
  final List<dynamic> queue;
  final List<dynamic> history;

  /// What `wanted/cutoff` reports as its `totalRecords` — **null** for a fork
  /// that does not serve the endpoint, which is what
  /// `ArrRecordPage.fromEnvelope` degrades an unreadable envelope to.
  final int? cutoffTotal;

  /// How many requests the cutoff figure cost.
  int cutoffPageCalls = 0;

  /// How many times the figure was taken by downloading every record.
  int allCutoffCalls = 0;

  @override
  Future<List<RadarrMovie>> getMovies() async => movies;

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
  Future<List<dynamic>> getAllCutoff({
    Map<String, dynamic>? queryParameters,
  }) async {
    allCutoffCalls++;
    // What the real one answers: every record, a page of 250 at a time — and
    // `[]` when the fork does not serve the endpoint, which is why a caller
    // that counts these cannot tell "none" from "never answered".
    return List<dynamic>.generate(
      cutoffTotal ?? 0,
      (index) => {'id': index + 1},
    );
  }

  @override
  Future<ArrRecordPage> getCutoffPage({
    int page = 1,
    int pageSize = 20,
    Map<String, dynamic>? queryParameters,
  }) async {
    cutoffPageCalls++;
    return ArrRecordPage(records: const [], total: cutoffTotal);
  }
}

/// A Radarr that does not answer: the degrading read still says `[]`, the
/// throwing one says what happened.
class _UnreachableRadarr extends _ScriptedRadarr {
  @override
  Future<List<RadarrMovie>> getMoviesOrThrow() async =>
      throw Exception('Radarr unreachable');
}

ProviderContainer _container(_ScriptedRadarr service) {
  final container = ProviderContainer(
    // Riverpod re-runs a failed provider on an exponential backoff; a test that
    // deliberately fails one would otherwise wait out the whole sequence.
    retry: (_, _) => null,
    overrides: [radarrServiceProvider.overrideWith((ref) => service)],
  );
  addTearDown(container.dispose);
  return container;
}

/// A movie carrying only the fields this screen reads.
///
/// Built here rather than through `buildMovie`, which models none of the four
/// dates the Overview is derived from.
RadarrMovie _movie({
  required int id,
  String title = 'Film',
  bool monitored = true,
  String? added,
  String? inCinemas,
  String? digitalRelease,
  String? physicalRelease,
}) => RadarrMovie(
  id: id,
  title: title,
  sortTitle: title.toLowerCase(),
  sizeOnDisk: 0,
  status: 'released',
  hasFile: true,
  monitored: monitored,
  year: 2024,
  images: const [],
  tmdbId: id,
  runtime: 100,
  genres: const [],
  added: added,
  inCinemas: inCinemas,
  digitalRelease: digitalRelease,
  physicalRelease: physicalRelease,
);

/// Local-time ISO, so the window's local calendar days are what the test is
/// actually exercising — a `Z` suffix would move the boundary by the runner's
/// offset and make the assertion pass or fail by timezone.
String _iso(DateTime date) => date.toIso8601String();

void main() {
  test('a Radarr that did not answer is a failure, not an empty week', () {
    // `getMovies` degrades to `[]`, which drew "0 releases" over "Nothing
    // releasing this week" under an identity band that read Unreachable.
    final container = _container(_UnreachableRadarr());

    expect(
      container.read(radarrComingUpProvider.future),
      throwsA(isA<Exception>()),
    );
    expect(
      container.read(radarrRecentlyAddedProvider.future),
      throwsA(isA<Exception>()),
    );
  });

  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);

  group('radarrUpcomingReleases', () {
    test('opens the window at local midnight today, inclusive', () {
      final releases = radarrUpcomingReleases([
        _movie(id: 1, title: 'Boundary', digitalRelease: _iso(today)),
      ], now: now);

      expect(releases, hasLength(1));
      expect(releases.single.movie.title, 'Boundary');
      expect(releases.single.kind, RadarrReleaseKind.digital);
    });

    test('closes it at local midnight seven days out, exclusive', () {
      final releases = radarrUpcomingReleases([
        _movie(
          id: 1,
          title: 'Last minute',
          digitalRelease: _iso(
            DateTime(today.year, today.month, today.day + 6, 23, 59),
          ),
        ),
        _movie(
          id: 2,
          title: 'Next week',
          digitalRelease: _iso(
            DateTime(today.year, today.month, today.day + 7),
          ),
        ),
      ], now: now);

      expect(releases.map((release) => release.movie.title), ['Last minute']);
    });

    test('excludes yesterday', () {
      final releases = radarrUpcomingReleases([
        _movie(
          id: 1,
          title: 'Gone',
          inCinemas: _iso(today.subtract(const Duration(seconds: 1))),
        ),
      ], now: now);

      expect(releases, isEmpty);
    });

    test('a film with two dates in the window is two releases', () {
      final releases = radarrUpcomingReleases([
        _movie(
          id: 1,
          title: 'Twice',
          digitalRelease: _iso(
            DateTime(today.year, today.month, today.day + 1, 9),
          ),
          physicalRelease: _iso(
            DateTime(today.year, today.month, today.day + 3, 9),
          ),
        ),
      ], now: now);

      expect(releases.map((release) => release.kind), [
        RadarrReleaseKind.digital,
        RadarrReleaseKind.physical,
      ]);
    });

    test('is ordered soonest first', () {
      final releases = radarrUpcomingReleases([
        _movie(
          id: 1,
          title: 'Later',
          digitalRelease: _iso(
            DateTime(today.year, today.month, today.day + 4, 9),
          ),
        ),
        _movie(
          id: 2,
          title: 'Sooner',
          digitalRelease: _iso(
            DateTime(today.year, today.month, today.day + 1, 9),
          ),
        ),
      ], now: now);

      expect(releases.map((release) => release.movie.title), [
        'Sooner',
        'Later',
      ]);
    });
  });

  group('radarrRecentlyAdded', () {
    test('is newest first and capped at six', () {
      final movies = [
        for (var day = 1; day <= 9; day++)
          _movie(
            id: day,
            title: 'Film $day',
            added: _iso(DateTime(today.year, today.month, today.day - day)),
          ),
      ];

      final recent = radarrRecentlyAdded(movies);

      expect(recent, hasLength(radarrRecentlyAddedLimit));
      expect(recent.map((movie) => movie.title), [
        'Film 1',
        'Film 2',
        'Film 3',
        'Film 4',
        'Film 5',
        'Film 6',
      ]);
    });

    test('drops a film whose arrival time is missing or unreadable', () {
      final recent = radarrRecentlyAdded([
        _movie(id: 1, title: 'Dated', added: _iso(today)),
        _movie(id: 2, title: 'Undated'),
        _movie(id: 3, title: 'Nonsense', added: 'not a date'),
      ]);

      expect(recent.map((movie) => movie.title), ['Dated']);
    });
  });

  group('radarrHistoryToday', () {
    Map<String, dynamic> record(DateTime date, String title) => {
      'date': _iso(date),
      'eventType': 'downloadFolderImported',
      'quality': {
        'quality': {'name': 'Bluray-2160p'},
      },
      'movie': {'title': title},
    };

    test('excludes yesterday', () {
      final entries = radarrHistoryToday([
        record(DateTime(today.year, today.month, today.day, 9), 'Today'),
        record(
          DateTime(today.year, today.month, today.day - 1, 23, 59),
          'Yesterday',
        ),
      ], now: now);

      expect(entries.map((entry) => entry.title), ['Today']);
    });

    test('is newest first and capped at three', () {
      final entries = radarrHistoryToday([
        for (var hour = 0; hour < 5; hour++)
          record(
            DateTime(today.year, today.month, today.day, hour),
            'Film $hour',
          ),
      ], now: now);

      expect(entries, hasLength(radarrHistoryTodayLimit));
      expect(entries.map((entry) => entry.title), [
        'Film 4',
        'Film 3',
        'Film 2',
      ]);
    });

    test('resolves the event through the shared history vocabulary', () {
      final entries = radarrHistoryToday([
        record(DateTime(today.year, today.month, today.day, 9), 'Imported'),
      ], now: now);

      expect(entries.single.event, 'Imported');
      expect(entries.single.tone, StatusTone.success);
      expect(entries.single.detail, contains('Bluray-2160p'));
    });
  });

  group('radarrQueueFaults', () {
    test('reads a failed import off the raw record', () {
      final faults = radarrQueueFaults([
        {
          'title': 'Nickel.Boys.2024.mkv',
          'movie': {'title': 'Nickel Boys'},
          'trackedDownloadState': 'importFailed',
          'errorMessage': 'Radarr could not match the file',
          'added': _iso(now.subtract(const Duration(hours: 2))),
        },
      ], now: now);

      expect(faults.single.kind, RadarrAttentionKind.importFailed);
      expect(faults.single.headline, 'Import failed · Nickel Boys');
      expect(faults.single.detail, contains('Radarr could not match the file'));
      expect(faults.single.detail, contains('2 h ago'));
    });

    test('reads a stalled grab, and a stall is never an import fault', () {
      final faults = radarrQueueFaults([
        {
          'movie': {'title': 'The Zone of Interest'},
          'status': 'warning',
          'trackedDownloadState': 'importPending',
          'errorMessage': 'The download is stalled with no connections',
          'downloadClient': 'qBittorrent',
          'added': _iso(now.subtract(const Duration(minutes: 42))),
        },
      ], now: now);

      expect(faults.single.kind, RadarrAttentionKind.stalled);
      expect(faults.single.headline, 'Stalled · The Zone of Interest');
      expect(faults.single.detail, contains('qBittorrent'));
    });

    test('a healthy record is not a fault', () {
      final faults = radarrQueueFaults([
        {
          'movie': {'title': 'Fine'},
          'trackedDownloadState': 'downloading',
          'trackedDownloadStatus': 'ok',
        },
      ], now: now);

      expect(faults, isEmpty);
    });

    test('an import Radarr flagged for a human is a fault', () {
      final faults = radarrQueueFaults([
        {
          'movie': {'title': 'Blocked'},
          'trackedDownloadState': 'importPending',
          'trackedDownloadStatus': 'warning',
          'statusMessages': [
            {'title': 'Unable to Import Automatically'},
          ],
        },
      ], now: now);

      expect(faults.single.kind, RadarrAttentionKind.importFailed);
    });
  });

  group('radarrBelowCutoffItem', () {
    test('is backlog, and backlog is neutral', () {
      final item = radarrBelowCutoffItem(34)!;

      expect(item.kind, RadarrAttentionKind.belowCutoff);
      expect(item.tone, StatusTone.neutral);
      expect(item.headline, '34 films below your quality cutoff');
    });

    test('no backlog, no row', () {
      expect(radarrBelowCutoffItem(0), isNull);
    });

    test('a figure the server never gave draws no row either', () {
      // Null is "we could not ask", and it has to read as no row rather than
      // as a zero backlog.
      expect(radarrBelowCutoffItem(null), isNull);
    });
  });

  group('the providers', () {
    test('coming up reads the library, not a calendar endpoint', () async {
      final container = _container(
        _ScriptedRadarr(
          movies: [
            _movie(
              id: 1,
              title: 'Soon',
              digitalRelease: _iso(
                DateTime(today.year, today.month, today.day + 2, 9),
              ),
            ),
            _movie(
              id: 2,
              title: 'Never',
              digitalRelease: _iso(
                DateTime(today.year, today.month, today.day + 40),
              ),
            ),
          ],
        ),
      );

      final releases = await container.read(radarrComingUpProvider.future);

      expect(releases.map((release) => release.movie.title), ['Soon']);
    });

    test('recently added comes back newest first', () async {
      final container = _container(
        _ScriptedRadarr(
          movies: [
            _movie(
              id: 1,
              title: 'Older',
              added: _iso(DateTime(today.year, today.month, today.day - 3)),
            ),
            _movie(id: 2, title: 'Newer', added: _iso(today)),
          ],
        ),
      );

      final recent = await container.read(radarrRecentlyAddedProvider.future);

      expect(recent.map((movie) => movie.title), ['Newer', 'Older']);
    });

    test("history today is filtered to today's records", () async {
      final container = _container(
        _ScriptedRadarr(
          history: [
            {
              'date': _iso(DateTime(today.year, today.month, today.day, 9)),
              'eventType': 'downloadFolderImported',
              'movie': {'title': 'Today'},
            },
            {
              'date': _iso(DateTime(today.year, today.month, today.day - 1, 9)),
              'eventType': 'downloadFolderImported',
              'movie': {'title': 'Yesterday'},
            },
          ],
        ),
      );

      final entries = await container.read(radarrHistoryTodayProvider.future);

      expect(entries.map((entry) => entry.title), ['Today']);
    });

    test(
      'needs attention puts the faults first and the backlog last',
      () async {
        final container = _container(
          _ScriptedRadarr(
            queue: [
              {
                'movie': {'title': 'Broken'},
                'trackedDownloadState': 'importFailed',
                'errorMessage': 'Could not import',
              },
            ],
            cutoffTotal: 2,
          ),
        );

        final items = await container.read(radarrNeedsAttentionProvider.future);

        expect(items.map((item) => item.kind), [
          RadarrAttentionKind.importFailed,
          RadarrAttentionKind.belowCutoff,
        ]);
      },
    );

    test('the cutoff figure is the total the server reports', () async {
      final service = _ScriptedRadarr(cutoffTotal: 3);
      final container = _container(service);

      expect(await container.read(radarrCutoffUnmetCountProvider.future), 3);
      // One request, and not one record downloaded. `getAllCutoff` walks up to
      // fifty pages of 250 records to answer with `records.length` — a figure
      // the envelope hands over in a field, and one that silently caps at
      // 12,500.
      expect(service.cutoffPageCalls, 1);
      expect(service.allCutoffCalls, 0);
    });

    test(
      'a fork that does not serve wanted/cutoff answers null, not 0',
      () async {
        final container = _container(_ScriptedRadarr());

        // `getAllCutoff` swallows its own failure into `[]`, so counting it made
        // "the server never answered" and "there is no backlog" the same figure.
        // Sonarr's equivalent already carries the null through.
        expect(
          await container.read(radarrCutoffUnmetCountProvider.future),
          isNull,
        );
      },
    );
  });
}
