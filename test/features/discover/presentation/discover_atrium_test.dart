import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/models/media_preview.dart';
import 'package:cupola/core/widgets/shimmer_placeholder.dart';
import 'package:cupola/features/discover/data/seerr_service.dart';
import 'package:cupola/features/discover/domain/catalog_query.dart';
import 'package:cupola/features/discover/domain/models/seerr_genre.dart';
import 'package:cupola/features/discover/domain/models/seerr_request.dart';
import 'package:cupola/features/discover/presentation/catalog_providers.dart';
import 'package:cupola/features/discover/presentation/discover_atrium.dart';
import 'package:cupola/features/discover/presentation/discover_details_provider.dart';
import 'package:cupola/features/discover/presentation/discover_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import '../../../test_helpers/fake_services.dart';
import '../../../test_helpers/settings_scope.dart';

const _trending = [
  MediaPreview(id: 20, title: 'Trending One', mediaType: 'movie'),
  MediaPreview(id: 21, title: 'Trending Two', mediaType: 'tv'),
];

const _best = [MediaPreview(id: 30, title: 'Metropolis', mediaType: 'movie')];

const _soon = [MediaPreview(id: 40, title: 'Coming One', mediaType: 'movie')];

void main() {
  group('DiscoverAtrium', () {
    testWidgets('six doors, the two quiet links, then the shelves', (
      tester,
    ) async {
      await _pumpAtrium(tester);
      await tester.pumpAndSettle();

      for (final door in [
        'Trending, This week',
        'Genres, 1',
        'Networks, Series',
        'Studios, Movies',
        'People, Directors, cast',
        'Decades, 1920s to now',
      ]) {
        expect(find.bySemanticsLabel(door), findsOneWidget, reason: door);
      }
      expect(find.text('Moods'), findsOneWidget);
      expect(find.text('Languages'), findsOneWidget);
      expect(find.text('The best you’re missing'), findsOneWidget);
      expect(find.text('Trending this week'), findsOneWidget);
      expect(find.text('Coming soon'), findsOneWidget);
    });

    testWidgets('at twice the reading size on a phone the two quiet links '
        'go one under the other', (tester) async {
      await _pumpAtrium(tester, size: const Size(390, 3000), textScale: 2);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      final moods = tester.getTopLeft(find.text('Moods'));
      final languages = tester.getTopLeft(find.text('Languages'));
      expect(languages.dy, greaterThan(moods.dy));
      expect(
        tester.getTopRight(find.text('Languages')).dx,
        lessThanOrEqualTo(390),
      );
    });

    testWidgets('a shelf with no titles is not drawn', (tester) async {
      await _pumpAtrium(tester, best: const []);
      await tester.pumpAndSettle();

      expect(find.text('The best you’re missing'), findsNothing);
      expect(find.text('Trending this week'), findsOneWidget);
    });

    testWidgets('shows a skeleton while the shelves load', (tester) async {
      await _pumpAtrium(
        tester,
        trending: (ref) => Completer<List<MediaPreview>>().future,
      );
      await tester.pump();

      expect(find.byType(ShimmerPlaceholder), findsWidgets);
    });

    testWidgets('the approvals are not the catalogue\'s', (tester) async {
      // They lived at the head of Seerr's catalogue; they are Seerr's room's
      // and the title pages' now, and the catalogue does not read the
      // request list at all.
      await _pumpAtrium(
        tester,
        requests: [
          SeerrRequest(
            id: 1,
            status: RequestStatus.pendingApproval,
            media: const RequestMedia(title: 'Dune', tmdbId: 1),
            createdAt: '2026-09-15T00:00:00Z',
            type: 'movie',
          ),
        ],
      );
      await tester.pumpAndSettle();

      expect(find.text('Needs a decision'), findsNothing);
      expect(find.text('Dune'), findsNothing);
    });

    testWidgets('a Seerr that did not answer is said once, with nothing of '
        'Seerr\'s under it', (tester) async {
      // Every rail used to say it, one line per rail and per genre: seven
      // failures and more for one fact.
      await _pumpAtrium(
        tester,
        trending: (ref) => Future<List<MediaPreview>>.error(
          const SocketException('Connection refused'),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Seerr did not answer, so the catalogue is missing.'),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('Genres, 1'), findsNothing);
      expect(find.text('Coming soon'), findsNothing);
    });

    testWidgets('a door opens its index in place, and the way back is the '
        'lobby', (tester) async {
      await _pumpAtrium(tester);
      await tester.pumpAndSettle();

      await tester.tap(find.bySemanticsLabel('Networks, Series'));
      await tester.pumpAndSettle();

      expect(find.text('Series by where they first aired'), findsOneWidget);
      expect(find.text('Netflix'), findsOneWidget);
      expect(find.text('Coming soon'), findsNothing);

      // The row switches to another index without going back.
      await tester.tap(find.text('Decades').first);
      await tester.pumpAndSettle();
      expect(
        find.text('Movies and series by the decade they came out'),
        findsOneWidget,
      );
      expect(find.text('1990s'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('Back to Discover'));
      await tester.pumpAndSettle();
      expect(find.text('Coming soon'), findsOneWidget);
    });

    testWidgets('the system back closes an index before it leaves the tab', (
      tester,
    ) async {
      final container = await _pumpAtrium(tester);
      await tester.pumpAndSettle();
      container.read(discoverIndexProvider.notifier).open(DiscoverIndex.moods);
      await tester.pumpAndSettle();
      expect(find.text('Time travel'), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(container.read(discoverIndexProvider), isNull);
      expect(find.text('Coming soon'), findsOneWidget);
    });

    testWidgets('the genres of either half, each a way into its page', (
      tester,
    ) async {
      final container = await _pumpAtrium(tester);
      await tester.pumpAndSettle();
      container.read(discoverIndexProvider.notifier).open(DiscoverIndex.genres);
      await tester.pumpAndSettle();

      expect(find.bySemanticsLabel('Animation'), findsOneWidget);
      await tester.tap(find.text('Series'));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Sci-Fi & Fantasy'), findsOneWidget);
    });
  });

  group('the shelves\' reads', () {
    test('the best you\'re missing leaves out what the server holds', () async {
      final container = ProviderContainer(
        overrides: [
          seerrServiceProvider.overrideWithValue(
            _PagesSeerrService({
              CatalogKind.movie: const [
                MediaPreview(
                  id: 1,
                  title: 'Held',
                  mediaType: 'movie',
                  mediaInfo: {'status': 5},
                ),
                MediaPreview(
                  id: 2,
                  title: 'Part held',
                  mediaType: 'movie',
                  mediaInfo: {'status': 4},
                ),
                MediaPreview(
                  id: 3,
                  title: 'Requested',
                  mediaType: 'movie',
                  mediaInfo: {'status': 2},
                ),
                MediaPreview(id: 4, title: 'Unknown', mediaType: 'movie'),
              ],
              CatalogKind.tv: const [
                MediaPreview(id: 9, title: 'A series', mediaType: 'tv'),
              ],
            }),
          ),
          seerrNumberingProvider.overrideWith((ref) async => null),
        ],
      );
      addTearDown(container.dispose);

      final best = await container.read(bestMissingProvider.future);

      // Woven a title from each half in turn.
      expect(best.map((item) => item.title), [
        'Requested',
        'A series',
        'Unknown',
      ]);
    });

    test('a title that comes twice is woven in once', () {
      const a = MediaPreview(id: 1, title: 'A', mediaType: 'movie');
      const b = MediaPreview(id: 2, title: 'B', mediaType: 'movie');
      const sameIdSeries = MediaPreview(id: 1, title: 'S', mediaType: 'tv');
      expect(
        interleave([
          [a, b],
          [a, sameIdSeries],
        ]).map((item) => item.title),
        ['A', 'B', 'S'],
      );
    });
  });
}

/// Seerr answering every catalogue page of a kind with [pages]' titles.
class _PagesSeerrService extends FakeSeerrService {
  _PagesSeerrService(this.pages);

  final Map<CatalogKind, List<MediaPreview>> pages;

  @override
  Future<CatalogPageResult> getCatalogPage(
    CatalogQuery query, {
    int page = 1,
    DateTime? today,
  }) async {
    final items = pages[query.kind] ?? const <MediaPreview>[];
    return CatalogPageResult(
      items: items,
      page: page,
      totalPages: 1,
      totalResults: items.length,
    );
  }
}

Future<ProviderContainer> _pumpAtrium(
  WidgetTester tester, {
  Future<List<MediaPreview>> Function(Ref ref)? trending,
  List<MediaPreview> best = _best,
  List<SeerrRequest> requests = const [],
  Size size = const Size(1200, 3000),
  double textScale = 1,
}) async {
  // Tall viewport so every shelf builds (the vertical ListView is lazy).
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  final container = ProviderContainer(
    overrides: [
      // Which numbering Seerr's codes follow: asked of the service, which
      // this test has none of.
      seerrNumberingProvider.overrideWith((ref) async => null),
      // The catalogue is drawn only once there is a Seerr to ask.
      currentSettingsProvider.overrideWith(
        (ref) => settingsWithServices([ServiceKey.seerr]),
      ),
      atriumTrendingProvider.overrideWith(trending ?? (ref) async => _trending),
      bestMissingProvider.overrideWith((ref) async => best),
      comingSoonProvider.overrideWith((ref) async => _soon),
      catalogGenresProvider.overrideWith(
        (ref, kind) async => kind == CatalogKind.movie
            ? const [SeerrGenre(id: 16, name: 'Animation')]
            : const [SeerrGenre(id: 10765, name: 'Sci-Fi & Fantasy')],
      ),
      requestsProvider.overrideWith((ref) async => requests),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: const Scaffold(body: DiscoverAtrium()),
      ),
    ),
  );
  return container;
}
