import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/jellyfin/data/jellyfin_client.dart';
import 'package:cupola/features/plex/data/plex_client.dart';
import 'package:cupola/features/stream/domain/models/stream_item.dart';

import '../../test_helpers/fixtures.dart';

/// What the household finished last, as each media server is asked it: the
/// latest first, a series once for all its episodes, and nothing a server
/// sends back that it does not say was watched.
void main() {
  group('Jellyfin', () {
    const viewer = '8c4f2a1e9b7d4c3a8f5e2d1c9b8a7f6e';

    JellyfinClient client(_Adapter adapter, {String userId = viewer}) {
      final client = JellyfinClient(
        baseUrl: 'https://jf.test',
        apiKey: 'SECRET-KEY',
        userId: userId,
        clientName: 'Cupola',
        deviceName: 'macos',
        deviceId: 'DEVICE-ID-1',
        appVersion: '0.8.0',
      );
      client.dio.httpClientAdapter = adapter;
      addTearDown(client.close);
      return client;
    }

    Map<String, Object?> played(
      String id,
      String name, {
      String type = 'Movie',
      String? at,
      bool played = true,
      String? series,
      String? tmdb,
    }) => {
      'Id': id,
      'Name': name,
      'Type': type,
      'SeriesId': ?series,
      'ProviderIds': {'Tmdb': ?tmdb},
      'UserData': {'Played': played, 'LastPlayedDate': ?at},
    };

    _Adapter history() => _Adapter((uri) {
      if (uri.queryParameters['ids'] case final ids?) {
        expect(ids, 'series-1');
        return {
          'Items': [
            {
              'Id': 'series-1',
              'Name': 'The Expanse',
              'Type': 'Series',
              'ProviderIds': {'Tmdb': '63639'},
            },
          ],
        };
      }
      // Answered in no order, with an unplayed film and an undated one: a
      // server that ignores the filter must not make them history.
      return {
        'Items': [
          played('m-1', 'Sintel', at: '2026-10-01T20:00:00Z', tmdb: '45745'),
          played(
            'e-2',
            'Caliban',
            type: 'Episode',
            series: 'series-1',
            at: '2026-10-03T21:00:00Z',
          ),
          played(
            'e-1',
            'Dulcinea',
            type: 'Episode',
            series: 'series-1',
            at: '2026-10-02T21:00:00Z',
          ),
          played('m-2', 'Agent 327', played: false, tmdb: '1'),
          played('m-3', 'Spring', tmdb: '2'),
        ],
      };
    });

    test('the latest first, a series once for its episodes', () async {
      final adapter = history();
      final watched = await client(adapter).getRecentlyWatched();

      expect(
        [for (final w in watched) w.item.title],
        ['The Expanse', 'Sintel'],
      );
      expect(watched.first.item.kind, StreamItemKind.series);
      expect(watched.first.item.externalIds.tmdb, '63639');
      expect(watched.first.playedAt, DateTime.utc(2026, 10, 3, 21));

      final asked = adapter.uris.first.queryParameters;
      expect(asked['userId'], viewer);
      expect(asked['isPlayed'], 'true');
      expect(asked['sortBy'], 'DatePlayed');
      expect(asked['sortOrder'], 'Descending');
      expect(adapter.uris, hasLength(2));
    });

    test('no more than asked for', () async {
      final watched = await client(history()).getRecentlyWatched(limit: 1);
      expect([for (final w in watched) w.item.title], ['The Expanse']);
    });

    test('no viewer chosen: nothing, and nothing asked', () async {
      final adapter = history();
      expect(await client(adapter, userId: '').getRecentlyWatched(), isEmpty);
      expect(adapter.uris, isEmpty);
    });

    test('a server that does not answer has nothing to say', () async {
      final adapter = _Adapter((_) => null, status: 500);
      expect(await client(adapter).getRecentlyWatched(), isEmpty);
    });
  });

  group('Plex', () {
    PlexClient client(_Adapter adapter) {
      final client = PlexClient(
        url: 'http://plex.test:32400',
        token: 'sX7pQ2mK9vTb3nR8wLdY',
        clientIdentifier: 'f1e2d3c4-b5a6-4798-8a9b-0c1d2e3f4a5b',
        platform: 'macOS',
      );
      client.api.dio.httpClientAdapter = adapter;
      addTearDown(client.close);
      return client;
    }

    Map<String, Object?> item(
      String key,
      String title, {
      String type = 'movie',
      int? viewedAt,
      String? tmdb,
    }) => {
      'ratingKey': key,
      'key': '/library/metadata/$key',
      'type': type,
      'title': title,
      'lastViewedAt': ?viewedAt,
      'Guid': [
        if (tmdb != null) {'id': 'tmdb://$tmdb'},
      ],
    };

    final at = DateTime.utc(2026, 10, 3, 21).millisecondsSinceEpoch ~/ 1000;

    test('films and series by when they were last viewed, across the '
        'sections; music and photos are not asked', () async {
      final adapter = _Adapter((uri) {
        switch (uri.path) {
          case '/library/sections':
            return jsonFixtureMap('plex/library_sections.json');
          case '/library/sections/1/all':
            return {
              'MediaContainer': {
                'Metadata': [
                  item('11', 'Sintel', viewedAt: at - 3600, tmdb: '45745'),
                  // Sorted after the viewed ones, never out of the answer.
                  item('12', 'Spring', tmdb: '2'),
                ],
              },
            };
          case '/library/sections/2/all':
            return {
              'MediaContainer': {
                'Metadata': [
                  item(
                    '21',
                    'The Expanse',
                    type: 'show',
                    viewedAt: at,
                    tmdb: '63639',
                  ),
                ],
              },
            };
        }
        return null;
      });

      final watched = await client(adapter).getRecentlyWatched();

      expect(
        [for (final w in watched) w.item.title],
        ['The Expanse', 'Sintel'],
      );
      expect(watched.first.item.kind, StreamItemKind.series);
      expect(watched.first.playedAt, DateTime.utc(2026, 10, 3, 21));
      final sections = [
        for (final uri in adapter.uris)
          if (uri.path.endsWith('/all')) uri,
      ];
      expect(sections.map((uri) => uri.path), [
        '/library/sections/1/all',
        '/library/sections/2/all',
      ]);
      expect(sections.first.queryParameters['sort'], 'lastViewedAt:desc');
    });

    test('a server that does not answer has nothing to say', () async {
      final adapter = _Adapter((_) => null, status: 500);
      expect(await client(adapter).getRecentlyWatched(), isEmpty);
    });
  });
}

/// Answers each request with what [reply] makes of its URI, recording them.
class _Adapter implements HttpClientAdapter {
  _Adapter(this.reply, {this.status = 200});

  final Object? Function(Uri uri) reply;
  final int status;
  final List<Uri> uris = [];

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    uris.add(options.uri);
    final body = reply(options.uri);
    return ResponseBody.fromString(
      body == null ? '' : jsonEncode(body),
      body == null && status == 200 ? 404 : status,
      headers: {
        Headers.contentTypeHeader: ['application/json; charset=utf-8'],
      },
    );
  }
}
