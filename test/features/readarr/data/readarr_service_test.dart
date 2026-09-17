import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/readarr/data/readarr_service.dart';

import '../../../test_helpers/fake_api_client.dart';
import '../../../test_helpers/fixtures.dart';

void main() {
  group('ReadarrService', () {
    test('getAuthors parses the author list from /api/v1/author', () async {
      final client = FakeApiClient()
        ..getResponseData = jsonFixtureList('readarr/author_list.json');
      final service = ReadarrService(client);

      final authors = await service.getAuthors();

      expect(client.lastGetPath, '/api/v1/author');
      expect(authors, hasLength(2));
      expect(authors.first.authorName, 'Brandon Sanderson');
      expect(authors.first.bookCount, 20);
      expect(authors.first.bookFileCount, 15);
      expect(authors.first.missingBookCount, 5);
      expect(authors[1].monitored, isFalse);
    });

    test('getRecentHistory maps records from /api/v1/history', () async {
      final client = FakeApiClient()
        ..getResponseData = jsonFixtureMap('readarr/history.json');
      final service = ReadarrService(client);

      final items = await service.getRecentHistory();

      expect(client.lastGetPath, '/api/v1/history');
      expect(items, hasLength(2));
      expect(items.first.eventType, 'grabbed');
      expect(items.first.authorName, 'Brandon Sanderson');
    });

    test('the queue asks for the book and the author', () async {
      // A Readarr queue record on its own carries `bookId`/`authorId` and the
      // raw release name, nothing else, so a row built from it could only
      // print `Orbital.2023.RETAIL.EPUB-XYZ`. The embeds only ride along when
      // the request asks for them.
      final client = FakeApiClient()..getResponseData = const <dynamic>[];
      await ReadarrService(client).getQueue();

      expect(client.lastGetPath, '/api/v1/queue');
      expect(client.lastGetQueryParameters?['includeBook'], isTrue);
      expect(client.lastGetQueryParameters?['includeAuthor'], isTrue);
    });

    test(
      'the history page asks for them too, and so does getHistory',
      () async {
        // Hung off `getHistory` instead, a caller reaching for `getHistoryPage`
        // — the one carrying the envelope's total, and therefore the only one a
        // count may be derived from — would get records with no embedded book.
        final client = FakeApiClient()..getResponseData = const <dynamic>[];
        final service = ReadarrService(client);

        await service.getHistoryPage();
        expect(client.lastGetPath, '/api/v1/history');
        expect(client.lastGetQueryParameters?['includeBook'], isTrue);
        expect(client.lastGetQueryParameters?['includeAuthor'], isTrue);

        client.lastGetQueryParameters = null;
        await service.getHistory();
        expect(client.lastGetQueryParameters?['includeBook'], isTrue);
        expect(client.lastGetQueryParameters?['includeAuthor'], isTrue);
      },
    );

    test('a caller can still add parameters of its own', () async {
      final client = FakeApiClient()..getResponseData = const <dynamic>[];
      await ReadarrService(
        client,
      ).getHistoryPage(queryParameters: const {'eventType': 3});

      expect(client.lastGetQueryParameters?['eventType'], 3);
      expect(client.lastGetQueryParameters?['includeBook'], isTrue);
    });
  });
}
