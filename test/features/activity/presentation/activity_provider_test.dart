import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:cupola/core/api/base_arr_service.dart';

import 'package:cupola/core/status/media_status.dart';
import 'package:cupola/features/activity/domain/service_type.dart';
import 'package:cupola/features/activity/presentation/activity_provider.dart';
import 'package:cupola/features/activity/presentation/widgets/activity_tab.dart';
import 'package:cupola/features/activity/presentation/widgets/wanted_tab.dart';
import 'package:cupola/features/discover/data/seerr_service.dart';
import 'package:cupola/features/discover/domain/models/seerr_request.dart';
import 'package:cupola/features/discover/presentation/discover_provider.dart';
import 'package:cupola/features/movies/data/radarr_service.dart';
import 'package:cupola/features/music/data/lidarr_service.dart';
import 'package:cupola/features/series/data/sonarr_service.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import '../../../test_helpers/fake_services.dart';
import '../../../test_helpers/settings_scope.dart';

void main() {
  late List<Override> settingsOverrides;

  setUp(() async {
    // The feed distinguishes "not configured" from "did not answer", so it reads
    // settings — which throw unless overridden.
    settingsOverrides = await settingsScopeOverrides(
      configured: activityServiceKeys,
    );
  });

  ProviderContainer createContainer({
    SeerrService? seerrService,
    RadarrService? radarrService,
    SonarrService? sonarrService,
    LidarrService? lidarrService,
    List<SeerrRequest>? requests,
  }) {
    final container = ProviderContainer(
      overrides: [
        ...settingsOverrides,
        if (seerrService != null)
          seerrServiceProvider.overrideWith((ref) => seerrService),
        if (requests != null)
          requestsProvider.overrideWith((ref) async => requests),
        if (radarrService != null)
          radarrServiceProvider.overrideWith((ref) => radarrService),
        if (sonarrService != null)
          sonarrServiceProvider.overrideWith((ref) => sonarrService),
        if (lidarrService != null)
          lidarrServiceProvider.overrideWith((ref) => lidarrService),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('ServiceType.displayTitle returns the expected label per type', () {
    const expected = {
      ServiceType.movies: 'Movies',
      ServiceType.series: 'Series',
      ServiceType.music: 'Music',
      ServiceType.discover: 'Requests',
    };
    for (final entry in expected.entries) {
      expect(entry.key.displayTitle, entry.value, reason: '${entry.key}');
    }
  });

  test('ServiceType.supportsArrActivity is true only for *arr services', () {
    expect(ServiceType.movies.supportsArrActivity, isTrue);
    expect(ServiceType.series.supportsArrActivity, isTrue);
    expect(ServiceType.music.supportsArrActivity, isTrue);
    expect(ServiceType.discover.supportsArrActivity, isFalse);
  });

  group('resolveArrService', () {
    test('returns the Radarr/Sonarr/Lidarr service for its matching type', () {
      final radarr = FakeRadarrService();
      final sonarr = FakeSonarrService();
      final lidarr = FakeLidarrService();
      final container = createContainer(
        radarrService: radarr,
        sonarrService: sonarr,
        lidarrService: lidarr,
      );

      expect(
        identical(
          container.read(resolvedArrServiceProvider(ServiceType.movies)),
          radarr,
        ),
        isTrue,
      );
      expect(
        identical(
          container.read(resolvedArrServiceProvider(ServiceType.series)),
          sonarr,
        ),
        isTrue,
      );
      expect(
        identical(
          container.read(resolvedArrServiceProvider(ServiceType.music)),
          lidarr,
        ),
        isTrue,
      );
    });

    test('throws for discover', () {
      final container = createContainer();

      expect(
        () => container.read(resolvedArrServiceProvider(ServiceType.discover)),
        throwsA(
          predicate<Object>(
            (error) => error.toString().contains(
              'only supports movies, series, and music',
            ),
            'provider error for unsupported discover service type',
          ),
        ),
      );
    });
  });

  test('ActivityTab and WantedTab reject the discover service type', () {
    expect(
      () => ActivityTab(serviceType: ServiceType.discover),
      throwsA(isA<AssertionError>()),
    );
    expect(
      () => WantedTab(serviceType: ServiceType.discover),
      throwsA(isA<AssertionError>()),
    );
  });

  group('global activity providers', () {
    test('combines requests, queue, and history sorted newest first', () async {
      final container = createContainer(
        requests: const [
          SeerrRequest(
            id: 1,
            status: RequestStatus.approved,
            media: RequestMedia(title: 'Shogun'),
            createdAt: '2026-04-03T09:05:00Z',
            type: 'tv',
            requestedBy: RequestedBy(id: 1, displayName: 'sarah'),
          ),
        ],
        radarrService: _ActivityRadarrService(
          queue: const [
            {
              'title': 'Furiosa.2024.2160p.WEB-DL-GROUP',
              'status': 'downloading',
              'estimatedCompletionTime': '2026-04-03T14:32:00Z',
              'size': 100,
              'sizeleft': 25,
              'movie': {'title': 'Furiosa', 'year': 2024},
            },
          ],
          history: const [
            {
              'sourceTitle': 'Dune.Part.Two.2024',
              'eventType': 'downloadImported',
              'date': '2026-04-02T11:18:00Z',
              'movie': {'title': 'Dune: Part Two'},
            },
          ],
        ),
      );

      final feed = await container.read(globalActivityFeedProvider.future);
      final items = feed.items;

      expect(items.map((item) => item.title), [
        'Furiosa',
        'Shogun',
        'Dune: Part Two',
      ]);
      expect(items.first.subtitle, contains('Furiosa.2024.2160p.WEB-DL-GROUP'));
      expect(items.first.kind, GlobalActivityKind.queue);
      expect(items.first.service, ServiceKey.radarr);
      expect(items.first.progress, 0.75);
      expect(items[1].kind, GlobalActivityKind.request);
      expect(items[1].service, ServiceKey.seerr);
      expect(items[2].kind, GlobalActivityKind.history);
    });

    test('keeps global queue available when one service fails', () async {
      final container = createContainer(
        radarrService: _ThrowingQueueRadarrService(),
        sonarrService: _ActivitySonarrService(
          queue: const [
            {
              'title': 'House.of.the.Dragon.S02E03.1080p.WEB-DL-GROUP',
              'status': 'downloading',
              'series': {'title': 'House of the Dragon'},
              'episode': {'seasonNumber': 2, 'episodeNumber': 3},
            },
          ],
        ),
      );

      final feed = await container.read(globalQueueItemsProvider.future);
      final items = feed.items;

      expect(items, hasLength(1));
      expect(items.single.service, ServiceKey.sonarr);
      expect(items.single.title, 'House of the Dragon');
      expect(
        items.single.subtitle,
        contains('House.of.the.Dragon.S02E03.1080p.WEB-DL-GROUP'),
      );

      // The surviving services still render — but the failure is carried, not
      // swallowed, so the screen can say the list is incomplete instead of
      // implying Radarr had nothing.
      expect(feed.isPartial, isTrue);
      expect(feed.allConfiguredFailed, isFalse);
      expect(
        feed.failures.map((result) => result.service),
        contains(ServiceKey.radarr),
      );
      expect(feed.firstError, isNotNull);
    });

    test(
      'reports every configured service failing as a failure, not empty',
      () async {
        final container = createContainer(
          radarrService: _ThrowingQueueRadarrService(),
          sonarrService: _ThrowingQueueSonarrService(),
          lidarrService: _ThrowingQueueLidarrService(),
        );

        final feed = await container.read(globalQueueItemsProvider.future);

        // Nothing was reached, so "no items" means "we have no idea" — the case
        // that used to render as "Nothing downloading right now".
        expect(feed.items, isEmpty);
        expect(feed.allConfiguredFailed, isTrue);
        expect(feed.hasConfiguredService, isTrue);
        expect(feed.firstError, isNotNull);
      },
    );

    test('an unconfigured service is not reported as a failure', () async {
      settingsOverrides = await settingsScopeOverrides(
        configured: const [ServiceKey.sonarr],
      );
      final container = createContainer(
        sonarrService: _ActivitySonarrService(
          queue: const [
            {
              'title': 'House.of.the.Dragon.S02E03',
              'status': 'downloading',
              'series': {'title': 'House of the Dragon'},
            },
          ],
        ),
      );

      final feed = await container.read(globalQueueItemsProvider.future);

      expect(feed.items, hasLength(1));
      expect(feed.failures, isEmpty);
      expect(feed.isPartial, isFalse);
      expect(
        feed.unconfigured.map((result) => result.service),
        containsAll(const [ServiceKey.radarr, ServiceKey.lidarr]),
      );
    });

    test('deduplicates release subtitle in global history feed', () async {
      final container = createContainer(
        radarrService: _ActivityRadarrService(
          history: const [
            {
              'sourceTitle': 'Imported.Release',
              'eventType': 'grabbed',
              'date': '2026-04-02T11:18:00Z',
            },
          ],
        ),
      );

      final feed = await _loadPagedFeed(container, globalHistoryFeedProvider);
      final items = feed.items;

      expect(items, hasLength(1));
      expect(items.single.title, 'Imported.Release');
      expect(items.single.subtitle, isEmpty);
    });

    test('wanted provider combines missing and cutoff items', () async {
      final container = createContainer(
        radarrService: _ActivityRadarrService(
          missing: const [
            {'title': 'Kingdom of the Planet of the Apes', 'year': 2024},
          ],
          cutoff: const [
            {'title': 'Inception', 'year': 2010},
          ],
        ),
      );

      final feed = await _loadPagedFeed(container, globalWantedFeedProvider);
      final items = feed.items;

      expect(items.map((item) => item.kind), [
        GlobalActivityKind.missing,
        GlobalActivityKind.cutoff,
      ]);
      expect(items.map((item) => item.title), [
        'Kingdom of the Planet of the Apes',
        'Inception',
      ]);
    });

    test('history loads a window and reports hasMore on a full page', () async {
      final container = createContainer(
        radarrService: _PagedHistoryRadarrService(
          records: [
            for (var i = 0; i < 50; i++)
              {
                'sourceTitle': 'Release $i',
                'eventType': 'grabbed',
                'date': '2026-04-02T11:18:00Z',
              },
          ],
        ),
      );

      final notifier = container.read(globalHistoryFeedProvider.notifier);
      await notifier.loading;

      final state = container.read(globalHistoryFeedProvider);
      expect(state.feed!.items, hasLength(50));
      expect(state.hasMore, isTrue);
    });

    // The whole point of moving onto the page primitives. `history` serves a
    // window; the envelope says how big the set is. Read off the window, the
    // figure answered "how many did we fetch" — 50, forever, for a server with
    // 340 records — and it looked exactly like an answer to the question the
    // user asked.
    test('a bucket reports the size of the set, not of the window', () async {
      final container = createContainer(
        radarrService: _TotalledHistoryRadarrService(pageSize: 50, total: 340),
      );

      final notifier = container.read(globalHistoryFeedProvider.notifier);
      await notifier.loading;

      final state = container.read(globalHistoryFeedProvider);
      final radarr = state.feed!.results.firstWhere(
        (result) => result.service == ServiceKey.radarr,
      );
      expect(radarr.items, hasLength(50));
      expect(radarr.total, 340);
      // And the total, once the server has given one, is what decides whether
      // there is more — so a list ending exactly on a page boundary no longer
      // costs an empty round trip to discover it.
      expect(state.hasMore, isTrue);
      final radarrCursor = state.cursors.entries
          .firstWhere((entry) => entry.key.$2 == ServiceType.movies)
          .value;
      expect(radarrCursor.total, 340);
      expect(radarrCursor.hasMore, isTrue, reason: '50 of 340 fetched');
    });

    // Null is not zero. A server that did not send `totalRecords` — an older
    // build, a proxy that rewrote the body — has told us nothing about the size
    // of the set, and falling back to the row count here would reinstate the
    // defect one layer up while looking like a sensible default.
    test(
      'a server that named no total says nothing rather than guessing',
      () async {
        final container = createContainer(
          radarrService: _PagedHistoryRadarrService(
            records: [
              for (var i = 0; i < 10; i++)
                {
                  'sourceTitle': 'Release $i',
                  'eventType': 'grabbed',
                  'date': '2026-04-02T11:18:00Z',
                },
            ],
          ),
        );

        final notifier = container.read(globalHistoryFeedProvider.notifier);
        await notifier.loading;

        final radarr = container
            .read(globalHistoryFeedProvider)
            .feed!
            .results
            .firstWhere((result) => result.service == ServiceKey.radarr);
        expect(radarr.items, hasLength(10));
        expect(radarr.total, isNull);
      },
    );

    test('history load more appends the next page and finishes', () async {
      final radarr = _PagedHistoryRadarrService(
        records: [
          for (var i = 0; i < 60; i++)
            {
              'sourceTitle': 'Release $i',
              'eventType': 'grabbed',
              'date': '2026-04-02T11:18:00Z',
            },
        ],
      );
      final container = createContainer(radarrService: radarr);

      final notifier = container.read(globalHistoryFeedProvider.notifier);
      await notifier.loading;
      expect(container.read(globalHistoryFeedProvider).hasMore, isTrue);

      await notifier.loadMore();

      final state = container.read(globalHistoryFeedProvider);
      expect(state.feed!.items, hasLength(60));
      expect(state.hasMore, isFalse);
      // The first page asked for the initial window; the load-more page asks
      // for the big page size.
      expect(radarr.historyCalls, 2);
      expect(radarr.lastPage, 2);
      expect(radarr.lastPageSize, 200);
    });

    test('a failed load-more page stays retryable and says so', () async {
      // The page that never arrived used to be read as the page that proved the
      // list had ended: `lastPageFull` was derived from the missing result,
      // came out false, and took `hasMore` with it — so one unreachable
      // connection closed its own half of the feed for good, looking exactly
      // like a list that had run out. `loadMoreFailed` was never set by
      // anything either, which left the footer's retry unreachable code.
      final radarr = _FlakySecondPageRadarrService(
        firstPage: [
          for (var i = 0; i < 50; i++)
            {
              'sourceTitle': 'Release $i',
              'eventType': 'grabbed',
              'date': '2026-04-02T11:18:00Z',
            },
        ],
      );
      final container = createContainer(radarrService: radarr);

      final notifier = container.read(globalHistoryFeedProvider.notifier);
      await notifier.loading;
      expect(container.read(globalHistoryFeedProvider).hasMore, isTrue);

      await notifier.loadMore();

      final state = container.read(globalHistoryFeedProvider);
      expect(state.loadMoreFailed, isTrue, reason: 'the footer offers a retry');
      expect(
        state.hasMore,
        isTrue,
        reason:
            'a page that did not arrive says nothing about whether one is '
            'there',
      );
      expect(state.feed!.items, hasLength(50), reason: 'page one still stands');

      // And the retry actually reaches the server again rather than being a
      // button over an exhausted cursor.
      radarr.failNext = false;
      await notifier.loadMore();

      final recovered = container.read(globalHistoryFeedProvider);
      expect(recovered.loadMoreFailed, isFalse);
      expect(recovered.feed!.items, hasLength(60));
    });

    test('a failed first page is reported, not swallowed', () async {
      final container = createContainer(
        radarrService: _ThrowingHistoryRadarrService(),
      );

      final notifier = container.read(globalHistoryFeedProvider.notifier);
      await notifier.loading;

      final feed = container.read(globalHistoryFeedProvider).feed!;
      expect(feed.allConfiguredFailed, isTrue);
      expect(feed.firstError, isNotNull);
    });

    test('a queue row carries measurements, not the release name', () async {
      // The desktop table's right-aligned tabular cell was fed `subtitle`,
      // which is prose — the release filename, the episode code, the artist —
      // so a numeric column printed an ellipsised release title and the size
      // and time left appeared nowhere on the row. `figures` is the separate
      // field that fixes it, and the two must stay different facts.
      final container = createContainer(radarrService: _QueueRadarrService());

      final feed = await container.read(globalQueueItemsProvider.future);
      final item = feed.items.single;

      expect(item.figures, contains('7.45 GB'));
      expect(item.figures, contains('left'));
      // The prose stays where prose belongs.
      expect(item.figures, isNot(contains('Dune.Part.Two')));
      expect(item.subtitle, contains('Dune.Part.Two'));
    });

    test('a kind with no measurement carries no figures', () async {
      // An em dash per row would draw a ladder of nothing down the column. A
      // wanted row is a title and a date; it has no measurement to line up.
      final container = createContainer(radarrService: _MissingRadarrService());

      final feed = await _loadPagedFeed(container, globalMissingFeedProvider);

      expect(feed.items.single.figures, isEmpty);
    });
  });

  group('finishedTodayProvider', () {
    test('keeps today, drops yesterday, and stops at the cap', () {
      // One provider rather than a filter inside each widget: the Activity page
      // and the desktop inspector both draw this band, and two hand-rolled
      // "is it today" comparisons are how two readouts of one day start
      // disagreeing at midnight.
      final now = DateTime.now();
      final container = ProviderContainer(
        overrides: [
          globalHistoryFeedProvider.overrideWith(
            () => _StubHistoryFeed([
              for (var i = 0; i < 9; i++)
                _historyItem('Landed $i', now.subtract(Duration(minutes: i))),
              _historyItem('Yesterday', now.subtract(const Duration(days: 1))),
            ]),
          ),
        ],
      );
      addTearDown(container.dispose);

      final today = container.read(finishedTodayProvider);

      expect(today, hasLength(finishedTodayLimit));
      expect(today.map((i) => i.title), isNot(contains('Yesterday')));
    });

    test('an unloaded history feed is empty rather than absent', () {
      // The band renders nothing until the feed has something, which is what
      // keeps a surface nobody opened from costing a round of history requests
      // per service.
      final container = ProviderContainer(
        overrides: [
          globalHistoryFeedProvider.overrideWith(() => _StubHistoryFeed(null)),
        ],
      );
      addTearDown(container.dispose);

      expect(container.read(finishedTodayProvider), isEmpty);
    });
  });
}

GlobalActivityItem _historyItem(String title, DateTime at) =>
    GlobalActivityItem(
      kind: GlobalActivityKind.history,
      service: ServiceKey.radarr,
      serviceType: ServiceType.movies,
      title: title,
      subtitle: '',
      status: const MediaStatusInfo.unknown(),
      sortDate: at,
    );

/// A history feed whose contents the test dictates, so "today" can be asserted
/// without three services and a clock.
class _StubHistoryFeed extends PagedArrFeedNotifier {
  _StubHistoryFeed(this.items)
    : super(kinds: const [GlobalActivityKind.history]);

  /// Null stands for "the first page has not landed yet".
  final List<GlobalActivityItem>? items;

  @override
  PagedArrFeedState build() {
    final loaded = items;
    return PagedArrFeedState(
      feed: loaded == null
          ? null
          : ActivityFeed(items: loaded, results: const []),
    );
  }
}

class _QueueRadarrService extends FakeRadarrService {
  @override
  Future<List<dynamic>> getQueue({
    Map<String, dynamic>? queryParameters,
  }) async => [
    {
      'id': 11,
      'title': 'Dune.Part.Two.2024.2160p.WEB-DL-GROUP',
      'movie': {'title': 'Dune: Part Two', 'year': 2024},
      'status': 'downloading',
      'size': 8003897815,
      'sizeleft': 2001000000,
      'timeleft': '00:12:00',
    },
  ];
}

class _MissingRadarrService extends FakeRadarrService {
  @override
  Future<List<dynamic>> getMissing({int page = 1, int pageSize = 20}) async =>
      page == 1
      ? [
          {'id': 3, 'title': 'Cool Movie', 'year': 2024, 'monitored': true},
        ]
      : const [];
}

Future<ActivityFeed> _loadPagedFeed(
  ProviderContainer container,
  NotifierProvider<PagedArrFeedNotifier, PagedArrFeedState> provider,
) async {
  final notifier = container.read(provider.notifier);
  await notifier.loading;
  return container.read(provider).feed!;
}

class _ActivityRadarrService extends FakeRadarrService {
  _ActivityRadarrService({
    this.queue = const [],
    this.history = const [],
    this.missing = const [],
    this.cutoff = const [],
  });

  final List<dynamic> queue;
  final List<dynamic> history;
  final List<dynamic> missing;
  final List<dynamic> cutoff;

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
  Future<List<dynamic>> getAllHistory({
    Map<String, dynamic>? queryParameters,
  }) async => history;

  @override
  Future<List<dynamic>> getBlocklist() async => const [];

  @override
  Future<List<dynamic>> getMissing({int page = 1, int pageSize = 20}) async {
    expect(page, 1);
    expect(pageSize, 50);
    return missing;
  }

  @override
  Future<List<dynamic>> getAllMissing() async => missing;

  @override
  Future<List<dynamic>> getCutoff({int page = 1, int pageSize = 20}) async {
    expect(page, 1);
    expect(pageSize, 50);
    return cutoff;
  }

  @override
  Future<List<dynamic>> getAllCutoff() async => cutoff;
}

class _ActivitySonarrService extends FakeSonarrService {
  _ActivitySonarrService({this.queue = const []});

  final List<dynamic> queue;

  @override
  Future<List<dynamic>> getQueue({
    Map<String, dynamic>? queryParameters,
  }) async => queue;
}

class _ThrowingQueueRadarrService extends FakeRadarrService {
  @override
  Future<List<dynamic>> getQueue({
    Map<String, dynamic>? queryParameters,
  }) async => throw Exception('Radarr down');
}

class _ThrowingQueueSonarrService extends FakeSonarrService {
  @override
  Future<List<dynamic>> getQueue({
    Map<String, dynamic>? queryParameters,
  }) async => throw Exception('Sonarr down');
}

class _ThrowingQueueLidarrService extends FakeLidarrService {
  @override
  Future<List<dynamic>> getQueue({
    Map<String, dynamic>? queryParameters,
  }) async => throw Exception('Lidarr down');
}

/// History that pages for real, so the paged-bucket tests can prove the window
/// mechanics rather than the fake's willingness to answer everything at once.
///
/// Page sizes vary between the first page (50) and load-more pages (200), so
/// the slice boundary is tracked as a running cursor — like a real server,
/// which pages from its own position rather than deriving it from a page
/// number times a page size.
class _PagedHistoryRadarrService extends FakeRadarrService {
  _PagedHistoryRadarrService({required this.records});

  final List<dynamic> records;
  int historyCalls = 0;
  int? lastPage;
  int? lastPageSize;
  int _served = 0;

  @override
  Future<List<dynamic>> getHistory({
    int page = 1,
    int pageSize = 20,
    Map<String, dynamic>? queryParameters,
  }) async {
    historyCalls++;
    lastPage = page;
    lastPageSize = pageSize;
    if (_served >= records.length) return const [];
    final end = (_served + pageSize).clamp(0, records.length);
    final slice = records.sublist(_served, end);
    _served = end;
    return slice;
  }
}

/// Serves page one, then throws once before serving the rest.
class _FlakySecondPageRadarrService extends FakeRadarrService {
  _FlakySecondPageRadarrService({required this.firstPage});

  final List<dynamic> firstPage;
  bool failNext = true;
  bool _servedFirst = false;

  @override
  Future<List<dynamic>> getHistory({
    int page = 1,
    int pageSize = 20,
    Map<String, dynamic>? queryParameters,
  }) async {
    if (!_servedFirst) {
      _servedFirst = true;
      return firstPage;
    }
    if (failNext) throw Exception('Radarr went away mid-scroll');
    return [
      for (var i = 0; i < 10; i++)
        {
          'sourceTitle': 'Late release $i',
          'eventType': 'grabbed',
          'date': '2026-04-02T11:18:00Z',
        },
    ];
  }
}

class _ThrowingHistoryRadarrService extends FakeRadarrService {
  @override
  Future<List<dynamic>> getHistory({
    int page = 1,
    int pageSize = 20,
    Map<String, dynamic>? queryParameters,
  }) async => throw Exception('Radarr history down');
}

/// A Radarr whose history endpoint answers with a real envelope: a window of
/// rows *and* the size of the set behind them.
///
/// It overrides the **page** primitive rather than `getHistory`, which is the
/// layering the shared fakes invert for everyone else — here the total is the
/// thing under test, so this one has to speak the envelope itself.
class _TotalledHistoryRadarrService extends FakeRadarrService {
  _TotalledHistoryRadarrService({required this.pageSize, required this.total});

  final int pageSize;
  final int total;

  @override
  Future<ArrRecordPage> getHistoryPage({
    int page = 1,
    int pageSize = 20,
    Map<String, dynamic>? queryParameters,
  }) async {
    final start = (page - 1) * pageSize;
    final end = (start + pageSize).clamp(0, total);
    return ArrRecordPage(
      records: [
        for (var i = start; i < end; i++)
          {
            'sourceTitle': 'Release $i',
            'eventType': 'grabbed',
            'date': '2026-04-02T11:18:00Z',
          },
      ],
      total: total,
    );
  }
}
