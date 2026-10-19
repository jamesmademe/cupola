import 'dart:async';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/movies/data/radarr_service.dart';

import '../../test_helpers/fake_api_client.dart';

/// A client whose every page waits on a gate the test opens, so a walk can be
/// watched while it is in the air: which pages are asked, how many at once.
class _GatedClient extends FakeApiClient {
  final _gates = <int, Completer<Map<String, dynamic>>>{};
  final requested = <int>[];
  int inFlight = 0;
  int peak = 0;

  Completer<Map<String, dynamic>> _gate(int page) =>
      _gates.putIfAbsent(page, Completer.new);

  void answer(int page, Map<String, dynamic> body) =>
      _gate(page).complete(body);

  void fail(int page) => _gate(page).completeError(Exception('page $page'));

  @override
  Future<Response<dynamic>> get(
    String path, {
    Map<String, dynamic>? queryParameters,
    CancelToken? cancelToken,
    Duration? receiveTimeout,
  }) async {
    final page = queryParameters!['page'] as int;
    requested.add(page);
    inFlight++;
    peak = math.max(peak, inFlight);
    try {
      final data = await _gate(page).future;
      return Response<dynamic>(
        requestOptions: RequestOptions(path: path),
        data: data,
      );
    } finally {
      inFlight--;
    }
  }
}

/// One page of a blocklist: [count] rows tagged with their page, so the order
/// the walk hands them back in can be read off the rows.
Map<String, dynamic> _page(int page, int count, {required int total}) => {
  'records': [
    for (var row = 0; row < count; row++) {'page': page, 'row': row},
  ],
  'totalRecords': total,
};

void main() {
  late _GatedClient client;
  late RadarrService service;

  setUp(() {
    client = _GatedClient();
    service = RadarrService(client);
  });

  test('after the first page, the rest are asked three at a time', () async {
    // Ten pages of two hundred: the blocklist's page size.
    final walk = service.getBlocklistPage();

    await pumpEventQueue();
    // Page one goes alone: only its envelope says how many pages there are.
    expect(client.requested, [1]);

    client.answer(1, _page(1, 200, total: 2000));
    await pumpEventQueue();
    expect(client.requested, [1, 2, 3, 4]);
    expect(client.inFlight, 3);

    // The slowest page is the first one asked: each answer frees one lane for
    // the next page, never a fourth request.
    client.answer(4, _page(4, 200, total: 2000));
    await pumpEventQueue();
    expect(client.requested, [1, 2, 3, 4, 5]);
    expect(client.inFlight, 3);

    for (final page in [3, 5, 2]) {
      client.answer(page, _page(page, 200, total: 2000));
      await pumpEventQueue();
    }
    for (var page = 6; page <= 10; page++) {
      client.answer(page, _page(page, 200, total: 2000));
      await pumpEventQueue();
    }

    final result = await walk;
    expect(client.peak, 3);
    expect(client.requested, [for (var page = 1; page <= 10; page++) page]);
    expect(result.total, 2000);
    expect(result.cutShort, isFalse);
    expect(result.records, hasLength(2000));
  });

  test(
    'the rows come back in page order whichever page answered first',
    () async {
      final walk = service.getBlocklistPage();
      await pumpEventQueue();
      client.answer(1, _page(1, 200, total: 600));
      await pumpEventQueue();
      expect(client.requested, [1, 2, 3]);

      client.answer(3, _page(3, 200, total: 600));
      client.answer(2, _page(2, 200, total: 600));

      final pages = [
        for (final row in (await walk).records.cast<Map<String, dynamic>>())
          row['page'] as int,
      ];
      expect(pages, [
        for (var page = 1; page <= 3; page++) ...List.filled(200, page),
      ]);
    },
  );

  test('a page that fails fails the read, and no lane asks for another '
      'after it', () async {
    final walk = service.getBlocklistPage();
    await pumpEventQueue();
    client.answer(1, _page(1, 200, total: 2000));
    await pumpEventQueue();
    expect(client.requested, [1, 2, 3, 4]);

    final outcome = expectLater(walk, throwsException);
    client.fail(3);
    await outcome;

    // The pages still in the air answer, one of them with a second failure of
    // its own: neither starts a new request, and the second is not left
    // unhandled (the test would fail on an uncaught async error).
    client.answer(2, _page(2, 200, total: 2000));
    client.fail(4);
    await pumpEventQueue();
    expect(client.requested, [1, 2, 3, 4]);
  });

  test(
    'a count that grew under the walk is followed one page at a time',
    () async {
      // Page one promises 450 rows, so pages 2 and 3 are asked together. Page two
      // then says 650: page three leaves the rows at 600, and the fourth is the
      // tail the batch did not cover.
      final walk = service.getBlocklistPage();
      await pumpEventQueue();
      client.answer(1, _page(1, 200, total: 450));
      await pumpEventQueue();
      expect(client.requested, [1, 2, 3]);

      client.answer(2, _page(2, 200, total: 650));
      client.answer(3, _page(3, 200, total: 650));
      await pumpEventQueue();
      expect(client.requested, [1, 2, 3, 4]);
      expect(client.inFlight, 1);

      client.answer(4, _page(4, 50, total: 650));
      final result = await walk;

      expect(result.records, hasLength(650));
      expect(result.total, 650);
      expect(result.cutShort, isFalse);
    },
  );

  test(
    'a server that caps the page lays the batch out by what it sent',
    () async {
      // Asked for 200 a page, answers 100: the page count is the count over a
      // hundred, not over the two hundred that were asked for.
      final walk = service.getBlocklistPage();
      await pumpEventQueue();
      client.answer(1, _page(1, 100, total: 450));
      await pumpEventQueue();
      expect(client.requested, [1, 2, 3, 4]);

      for (var page = 2; page <= 4; page++) {
        client.answer(page, _page(page, 100, total: 450));
      }
      await pumpEventQueue();
      expect(client.requested, [1, 2, 3, 4, 5]);
      client.answer(5, _page(5, 50, total: 450));

      final result = await walk;
      expect(result.records, hasLength(450));
      expect(result.cutShort, isFalse);
    },
  );

  test('a first page that holds the whole count is the only request', () async {
    final walk = service.getBlocklistPage();
    await pumpEventQueue();
    client.answer(1, _page(1, 12, total: 12));

    final result = await walk;
    expect(client.requested, [1]);
    expect(result.total, 12);
  });

  test(
    'a walk past the page limit still stops at it, three at a time',
    () async {
      // 12 000 rows at 200 a page is sixty pages; the walk allows fifty.
      final walk = service.getBlocklistPage();
      await pumpEventQueue();
      client.answer(1, _page(1, 200, total: 12000));
      for (var page = 2; page <= 50; page++) {
        await pumpEventQueue();
        client.answer(page, _page(page, 200, total: 12000));
      }

      final result = await walk;
      expect(client.requested, hasLength(50));
      expect(client.peak, 3);
      expect(result.records, hasLength(10000));
      expect(result.total, 12000);
      expect(result.cutShort, isTrue);
    },
  );
}
