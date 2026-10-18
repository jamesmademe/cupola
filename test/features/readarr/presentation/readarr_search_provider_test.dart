import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/providers/provider_retry.dart';
import 'package:cupola/features/readarr/domain/models/readarr_models.dart';
import 'package:cupola/features/readarr/presentation/readarr_provider.dart';
import 'package:cupola/features/readarr/presentation/readarr_search_provider.dart';

ReadarrAuthor _author(int id, String name) => ReadarrAuthor(
  id: id,
  authorName: name,
  monitored: true,
  bookCount: 1,
  bookFileCount: 1,
);

final _authors = [
  _author(1, 'Jules Verne'),
  _author(2, 'Brandon Sanderson'),
  _author(3, 'Jules Renard'),
];

List<String> _names(List<ReadarrAuthor> authors) => [
  for (final author in authors) author.authorName,
];

void main() {
  group('readarrAuthorsMatching', () {
    test('finds a name by any of its words, whatever the case, by name', () {
      expect(_names(readarrAuthorsMatching(_authors, 'JULES')), [
        'Jules Renard',
        'Jules Verne',
      ]);
      expect(_names(readarrAuthorsMatching(_authors, 'sand')), [
        'Brandon Sanderson',
      ]);
    });

    test('takes every word, in either order, with or without a comma', () {
      expect(_names(readarrAuthorsMatching(_authors, 'verne jules')), [
        'Jules Verne',
      ]);
      expect(_names(readarrAuthorsMatching(_authors, 'Verne, Jules')), [
        'Jules Verne',
      ]);
      // A word that is in no name is no match, not a looser one.
      expect(readarrAuthorsMatching(_authors, 'jules sanderson'), isEmpty);
    });

    test('a blank query matches nothing and no name matches a stranger', () {
      expect(readarrAuthorsMatching(_authors, ''), isEmpty);
      expect(readarrAuthorsMatching(_authors, '  , '), isEmpty);
      expect(readarrAuthorsMatching(_authors, 'tolkien'), isEmpty);
    });
  });

  group('readarrSearchResultsProvider', () {
    ProviderContainer containerOver(
      Future<List<ReadarrAuthor>> Function() library,
    ) {
      final container = ProviderContainer(
        overrides: [readarrAuthorsProvider.overrideWith((ref) => library())],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('answers null while nothing is typed: nothing was asked', () async {
      final container = containerOver(() async => _authors);

      expect(await container.read(readarrSearchResultsProvider.future), isNull);

      container.read(readarrSearchQueryProvider.notifier).state = '   ';
      expect(await container.read(readarrSearchResultsProvider.future), isNull);
    });

    test(
      'answers from the library it already has, not from a lookup',
      () async {
        final container = containerOver(() async => _authors);

        container.read(readarrSearchQueryProvider.notifier).state = 'verne';
        final found = await container.read(readarrSearchResultsProvider.future);

        expect(_names(found!), ['Jules Verne']);
      },
    );

    test('a search with no match is an empty answer, not a failure', () async {
      final container = containerOver(() async => _authors);

      container.read(readarrSearchQueryProvider.notifier).state = 'zzz';

      expect(
        await container.read(readarrSearchResultsProvider.future),
        isEmpty,
      );
    });

    test('a Readarr that did not answer is the failure it is, never no '
        'results', () async {
      final container = containerOver(
        () async => throw DioException.connectionError(
          requestOptions: RequestOptions(path: '/api/v1/author'),
          reason: 'Connection refused',
        ),
      );

      container.read(readarrSearchQueryProvider.notifier).state = 'verne';

      await expectLater(
        container.read(readarrSearchResultsProvider.future),
        throwsA(isA<DioException>()),
      );
      expect(container.read(readarrSearchResultsProvider).hasError, isTrue);
    });

    test('carries the library\'s own refusal to retry', () {
      // A provider derived from one that carries `noProviderRetry` carries it
      // too: a retry is the user's call.
      expect(readarrSearchResultsProvider.retry, same(noProviderRetry));
    });
  });
}
