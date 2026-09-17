import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/api/api_client.dart';
import 'package:cupola/core/api/base_arr_service.dart';

import '../../test_helpers/fake_api_client.dart';

void main() {
  group('ArrActivityMixin helpers', () {
    late FakeApiClient client;
    late TestArrService service;

    setUp(() {
      client = FakeApiClient();
      service = TestArrService(client, ArrServiceConfig.radarr);
    });

    test('fetchAllItems maps list responses', () async {
      client.getResponseData = [
        {'id': 1, 'title': 'One'},
        {'id': 2, 'title': 'Two'},
      ];

      final items = await service.fetchAllItems('movie', TestItem.fromJson);

      expect(client.lastGetPath, '/api/v3/movie');
      expect(items, [
        const TestItem(id: 1, title: 'One'),
        const TestItem(id: 2, title: 'Two'),
      ]);

      items.add(const TestItem(id: 3, title: 'Three'));
      expect(items, hasLength(3));
    });

    test('fetchAllItems returns empty list on error', () async {
      client.getException = Exception('boom');

      final items = await service.fetchAllItems('movie', TestItem.fromJson);

      expect(items, isEmpty);
    });

    test('lookupItems returns empty list for empty term', () async {
      final items = await service.lookupItems(
        'movie/lookup',
        '',
        TestItem.fromJson,
      );

      expect(items, isEmpty);
      expect(client.lastGetPath, isNull);
    });

    test('lookupItems encodes term and maps results', () async {
      client.getResponseData = [
        {'id': 3, 'title': 'Lookup'},
      ];

      final items = await service.lookupItems(
        'movie/lookup',
        'tmdb:123 some title',
        TestItem.fromJson,
      );

      expect(client.lastGetPath, '/api/v3/movie/lookup');
      expect(client.lastGetQueryParameters, {
        'term': 'tmdb%3A123%20some%20title',
      });
      expect(items, [const TestItem(id: 3, title: 'Lookup')]);

      items.add(const TestItem(id: 4, title: 'Growable'));
      expect(items, hasLength(2));
    });

    test('lookupItems forwards the cancel token to ApiClient', () async {
      // The three arr lookups delegate here now, so this is where the
      // superseded-search abort either happens or silently does not.
      client.getResponseData = <dynamic>[];
      final cancelToken = CancelToken();

      await service.lookupItems(
        'movie/lookup',
        'dune',
        TestItem.fromJson,
        cancelToken: cancelToken,
      );

      expect(client.lastGetCancelToken, same(cancelToken));
    });

    test('lookupItems returns empty list on error', () async {
      client.getException = Exception('boom');

      final items = await service.lookupItems(
        'movie/lookup',
        'tmdb:123',
        TestItem.fromJson,
      );

      expect(items, isEmpty);
    });

    test('fetchQualityProfiles returns mapped profiles', () async {
      client.getResponseData = [
        {'id': 1, 'name': 'HD-1080p'},
      ];

      final profiles = await service.fetchQualityProfiles();

      expect(client.lastGetPath, '/api/v3/qualityprofile');
      expect(profiles, [
        {'id': 1, 'name': 'HD-1080p'},
      ]);
    });

    test('updateItemProfile fetches, mutates, and saves item', () async {
      client.getResponseData = {
        'id': 7,
        'title': 'Movie',
        'qualityProfileId': 1,
      };

      await service.updateItemProfile('movie', 7, 4);

      expect(client.lastGetPath, '/api/v3/movie/7');
      expect(client.lastPutPath, '/api/v3/movie/7');
      expect(client.lastPutData, {
        'id': 7,
        'title': 'Movie',
        'qualityProfileId': 4,
      });
    });

    test(
      'fetchReleases raises the receive timeout for the slow search',
      () async {
        // The server fans out to every enabled indexer and answers only once the
        // slowest has, so this is the one arr GET that legitimately runs for
        // minutes. Under the client's 15s default it never returned at all.
        client.getResponseData = [
          {'guid': 'a', 'indexerId': 1},
        ];

        final releases = await service.fetchReleases({'movieId': 7});

        expect(client.lastGetPath, '/api/v3/release');
        expect(client.lastGetQueryParameters, {'movieId': 7});
        expect(client.lastGetReceiveTimeout, kReleaseSearchReceiveTimeout);
        expect(releases, hasLength(1));
      },
    );

    test('the release search timeout clears every common gateway ceiling', () {
      // Not an arbitrary number: it has to sit above nginx's 60s default and
      // Cloudflare's unraisable 100s cap, because that is what makes a failure
      // attributable to the proxy rather than to us.
      expect(
        kReleaseSearchReceiveTimeout,
        greaterThan(const Duration(seconds: 100)),
      );
    });

    test('grabReleaseByGuid posts release payload', () async {
      await service.grabReleaseByGuid(guid: 'guid-123', indexerId: 9);

      expect(client.lastPostPath, '/api/v3/release');
      expect(client.lastPostData, {'guid': 'guid-123', 'indexerId': 9});
    });

    test('getQueue returns records with optional query parameters', () async {
      client.getResponseData = {
        'records': [
          {'id': 1, 'title': 'Queued'},
        ],
      };

      final items = await service.getQueue(
        queryParameters: const {'includeMovie': true},
      );

      expect(client.lastGetPath, '/api/v3/queue');
      expect(client.lastGetQueryParameters, const {
        'page': 1,
        'pageSize': 200,
        'includeMovie': true,
      });
      expect(items, [
        {'id': 1, 'title': 'Queued'},
      ]);
    });

    test('getQueue pages through until totalRecords is reached', () async {
      client.getResponseQueue.addAll([
        {
          'records': [
            for (var id = 0; id < 200; id++) {'id': id, 'title': 'Queued'},
          ],
          'totalRecords': 250,
        },
        {
          'records': [
            for (var id = 200; id < 250; id++) {'id': id, 'title': 'Queued'},
          ],
          'totalRecords': 250,
        },
      ]);

      final items = await service.getQueue();

      expect(items, hasLength(250));
      expect(client.getCallCount, 2);
      expect(client.lastGetQueryParameters, containsPair('page', 2));
      expect(items.last['id'], 249);
    });

    test('getBlocklist returns every page', () async {
      client.getResponseQueue.addAll([
        {
          'records': [
            for (var id = 0; id < 200; id++) {'id': id, 'sourceTitle': 'X'},
          ],
          'totalRecords': 210,
        },
        {
          'records': [
            for (var id = 200; id < 210; id++) {'id': id, 'sourceTitle': 'X'},
          ],
          'totalRecords': 210,
        },
      ]);

      final items = await service.getBlocklist();

      expect(items, hasLength(210));
      expect(client.lastGetPath, '/api/v3/blocklist');
      expect(client.getCallCount, 2);
    });

    test('getHistory forwards optional query parameters', () async {
      client.getResponseData = {
        'records': [
          {'id': 2, 'sourceTitle': 'Imported.Release'},
        ],
      };

      final items = await service.getHistory(
        page: 2,
        pageSize: 10,
        queryParameters: const {'includeMovie': true},
      );

      expect(client.lastGetPath, '/api/v3/history');
      expect(client.lastGetQueryParameters, {
        'page': 2,
        'pageSize': 10,
        'includeMovie': true,
      });
      expect(items, [
        {'id': 2, 'sourceTitle': 'Imported.Release'},
      ]);
    });

    // The defect the page variants exist for: every paged endpoint answers with
    // `{page, pageSize, totalRecords, records}` and the app kept only the last
    // field, so every count derived from history / missing / cutoff was the size
    // of the *page*. A library with 340 gaps read "20 missing", because 20 is
    // the default page size — not an approximation, an answer to a different
    // question that happened to look like an answer to this one.
    test('getMissingPage carries the set size, not the page size', () async {
      client.getResponseData = {
        'records': [
          for (var id = 0; id < 20; id++) {'id': id, 'title': 'Gap \$id'},
        ],
        'totalRecords': 340,
      };

      final page = await service.getMissingPage();

      expect(page.records, hasLength(20));
      expect(page.total, 340);
      // And the records-only getter is unchanged, because two \*arr services
      // override it and a dozen callers still read it.
      expect(await service.getMissing(), hasLength(20));
    });

    // The wanted primitives take a caller's parameters for the same reason the
    // history one does: an \*arr whose wanted record needs an embed
    // (`includeArtist` on Lidarr, as `includeMovie` is on the queue) can only
    // ask for it here. Without this the service override has nowhere to hang,
    // and the figure derived from the page is computed over rows the embed
    // would have filled.
    test('the wanted pages carry a caller\'s own parameters', () async {
      client.getResponseData = {'records': const [], 'totalRecords': 0};

      await service.getMissingPage(queryParameters: const {'x': 'missing'});
      expect(client.lastGetQueryParameters?['x'], 'missing');
      expect(client.lastGetQueryParameters?['page'], 1);
      expect(client.lastGetQueryParameters?['pageSize'], 20);

      await service.getCutoffPage(queryParameters: const {'x': 'cutoff'});
      expect(client.lastGetQueryParameters?['x'], 'cutoff');
    });

    // And the record-only and walk-every-page spellings too: the Activity
    // Wanted tab reads `getAllMissing`, not the page primitive, so an embed
    // that only rode the page would leave that list unnamed.
    test('the wanted walks carry them as well', () async {
      client.getResponseData = {'records': const [], 'totalRecords': 0};

      await service.getAllMissing(queryParameters: const {'x': 'all-missing'});
      expect(client.lastGetQueryParameters?['x'], 'all-missing');

      await service.getAllCutoff(queryParameters: const {'x': 'all-cutoff'});
      expect(client.lastGetQueryParameters?['x'], 'all-cutoff');
    });

    test('getHistoryPage and getCutoffPage carry it too', () async {
      client.getResponseData = {
        'records': [
          {'id': 1, 'sourceTitle': 'A'},
        ],
        'totalRecords': 7421,
      };
      expect((await service.getHistoryPage()).total, 7421);
      expect((await service.getCutoffPage()).total, 7421);
    });

    // A server that did not send a total has told us nothing about the size of
    // the set, and `records.length` would be the same lie with a fresh coat on
    // it. Null is the honest answer, and it is what lets a caller print "20
    // shown" instead of a confident wrong number.
    test('a missing total reads as null, never as the page length', () async {
      client.getResponseData = {
        'records': [
          {'id': 1, 'title': 'One'},
        ],
      };

      final page = await service.getMissingPage();

      expect(page.records, hasLength(1));
      expect(page.total, isNull);
    });

    test('a total sent as a string or a double still reads', () async {
      client.getResponseData = {'records': const [], 'totalRecords': '128'};
      expect((await service.getMissingPage()).total, 128);

      client.getResponseData = {'records': const [], 'totalRecords': 128.0};
      expect((await service.getMissingPage()).total, 128);

      // Anything else is absent rather than coerced.
      client.getResponseData = {'records': const [], 'totalRecords': 'many'};
      expect((await service.getMissingPage()).total, isNull);
    });

    // Not every \*arr fork serves `wanted/cutoff`, and a service that cannot
    // answer the question has not answered "none". A zero would put a confident
    // "0 to upgrade" on a dashboard for a server that was never asked.
    test('an unavailable cutoff endpoint yields no total, not zero', () async {
      client.getException = Exception('404');

      final page = await service.getCutoffPage();

      expect(page.records, isEmpty);
      expect(page.total, isNull, reason: 'zero would be a claim, null is not');
    });

    test('fetchRootFolders reads the server\'s configured libraries', () async {
      client.getResponseData = [
        {'id': 1, 'path': '/data/movies', 'accessible': true},
        {'id': 2, 'path': '/data/movies-4k', 'accessible': true},
      ];

      final folders = await service.fetchRootFolders();

      expect(client.lastGetPath, '/api/v3/rootfolder');
      expect(folders.map((folder) => folder['path']), [
        '/data/movies',
        '/data/movies-4k',
      ]);
    });

    test('fetchRootFolders lets a failure through', () async {
      // Deliberately unlike [fetchQualityProfiles], which degrades to `[]`.
      // An add sheet that cannot reach the server must say so: an empty list
      // here would render as "this server has no libraries configured", which
      // is D13's lesson — offline made indistinguishable from empty.
      client.getException = Exception('connection refused');

      expect(service.fetchRootFolders(), throwsA(isA<Exception>()));
    });
  });
}

class TestArrService with ArrActivityMixin {
  @override
  final ApiClient client;

  @override
  final ArrServiceConfig config;

  TestArrService(this.client, this.config);
}

class TestItem {
  final int id;
  final String title;

  const TestItem({required this.id, required this.title});

  factory TestItem.fromJson(Map<String, dynamic> json) {
    return TestItem(
      id: json['id'] as int? ?? 0,
      title: json['title'] as String? ?? 'Unknown',
    );
  }

  @override
  bool operator ==(Object other) {
    return other is TestItem && other.id == id && other.title == title;
  }

  @override
  int get hashCode => Object.hash(id, title);
}
