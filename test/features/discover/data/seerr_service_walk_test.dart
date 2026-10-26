import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/discover/data/seerr_service.dart';
import 'package:cupola/features/discover/domain/models/seerr_request.dart';

import '../../../test_helpers/fake_api_client.dart';

/// A client that answers every read after a beat, so reads started together
/// overlap, and remembers how many were open at once.
class _OverlapClient extends FakeApiClient {
  _OverlapClient({required this.requests, this.titleOf});

  /// How many requests the server holds.
  final int requests;

  /// The name a request's title page answers with, or null for no title page.
  final String Function(int tmdbId)? titleOf;

  int open = 0;
  int peakOpen = 0;
  final List<String> paths = [];

  @override
  Future<Response<dynamic>> get(
    String path, {
    Map<String, dynamic>? queryParameters,
    CancelToken? cancelToken,
    Duration? receiveTimeout,
  }) async {
    paths.add(path);
    open++;
    if (open > peakOpen) peakOpen = open;
    await Future<void>.delayed(const Duration(milliseconds: 5));
    open--;

    final data = switch (path) {
      '/api/v1/request' => _page(queryParameters!['skip'] as int),
      _ when path.startsWith('/api/v1/movie/') => {
        'title': titleOf!(int.parse(path.split('/').last)),
        'releaseDate': '2022-05-01',
        'posterPath': '/p.jpg',
      },
      _ => null,
    };
    return Response<dynamic>(
      requestOptions: RequestOptions(path: path),
      data: data,
    );
  }

  Map<String, dynamic> _page(int skip) => {
    'pageInfo': {'results': requests},
    'results': [
      for (var id = skip + 1; id <= skip + 50 && id <= requests; id++)
        {
          'id': id,
          'status': 2,
          'createdAt': '2024-01-01T00:00:00.000Z',
          'type': 'movie',
          'is4k': false,
          'media': {
            'id': id,
            'tmdbId': titleOf == null ? id : 1 + (id % 12),
            'status': 5,
            'mediaType': 'movie',
            if (titleOf == null) ...{
              'title': 'Title $id',
              'posterPath': '/p$id.jpg',
            } else
              'title': 'Unknown Media',
          },
        },
    ],
  };
}

void main() {
  test(
    'a long request history is read four pages at a time, in order',
    () async {
      final client = _OverlapClient(requests: 700);
      final service = SeerrService(client, numbering: SeerrNumbering.seerr);

      final list = await service.getRequests() as SeerrRequestList;

      // 14 pages: the first alone, then thirteen behind it.
      expect(client.paths.where((p) => p == '/api/v1/request'), hasLength(14));
      expect(client.peakOpen, lessThanOrEqualTo(4));
      expect(client.peakOpen, greaterThan(1));
      expect([for (final r in list) r.id], [for (var i = 1; i <= 700; i++) i]);
      expect(list.total, 700);
      expect(list.isPartial, isFalse);
    },
  );

  test('two requests for one title share a single read of it', () async {
    // 120 requests over twelve titles: one read of each, however many rows
    // ask for it at the same time.
    final client = _OverlapClient(
      requests: 120,
      titleOf: (tmdbId) => 'Movie $tmdbId',
    );
    final service = SeerrService(client, numbering: SeerrNumbering.seerr);

    final list = await service.getRequests();

    final titleReads = client.paths.where(
      (p) => p.startsWith('/api/v1/movie/'),
    );
    expect(titleReads, hasLength(12));
    expect(titleReads.toSet(), hasLength(12));
    expect(list, hasLength(120));
    expect(
      list.every((r) => r.media?.title?.startsWith('Movie ') ?? false),
      isTrue,
    );
  });

  test('title reads are four at a time', () async {
    final client = _OverlapClient(
      requests: 120,
      titleOf: (tmdbId) => 'Movie $tmdbId',
    );
    final service = SeerrService(client, numbering: SeerrNumbering.seerr);

    await service.getRequests();

    // Pages of three and four overlap too, so the ceiling is the larger.
    expect(client.peakOpen, lessThanOrEqualTo(4));
  });

  test(
    'the rows come without a title read, and hydrate names them after',
    () async {
      final client = _OverlapClient(
        requests: 120,
        titleOf: (tmdbId) => 'Movie $tmdbId',
      );
      final service = SeerrService(client, numbering: SeerrNumbering.seerr);

      final rows = await service.getRequestRows();

      expect(
        client.paths.where((p) => p.startsWith('/api/v1/movie/')),
        isEmpty,
      );
      expect(rows, hasLength(120));
      expect(rows.first.media?.title, 'Unknown Media');

      // Only the rows handed over are named: five rows, five titles at most.
      final named = await service.hydrate(rows.take(5).toList());
      expect(
        named.every((r) => r.media?.title?.startsWith('Movie ') ?? false),
        isTrue,
      );
      expect(
        client.paths.where((p) => p.startsWith('/api/v1/movie/')).length,
        lessThanOrEqualTo(5),
      );

      // A list keeps what the server said of its size.
      final whole = await service.hydrate(rows);
      expect((whole as SeerrRequestList).total, 120);
    },
  );
}
