import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// ignore: implementation_imports
import 'package:flutter_riverpod/legacy.dart';

import 'package:cupola/core/providers/navigation_refresh_provider.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';

final testSearchQueryProvider = StateProvider<String>((ref) => '');
final testLibraryProvider = FutureProvider<List<String>>(
  (ref) async => ['Alpha', 'Beta'],
);
final testSearchResultsProvider = FutureProvider<List<String>?>(
  (ref) async => null,
);

void main() {
  group('mediaBrowseFilterMatches', () {
    test('every availability answers to a chip, the unreleased one aside', () {
      for (final availability in MediaAvailability.values) {
        final status = MediaStatusInfo(availability: availability);
        final underAvailable = mediaBrowseFilterMatches(
          MediaBrowseFilter.available,
          status,
        );
        final underMissing = mediaBrowseFilterMatches(
          MediaBrowseFilter.missing,
          status,
        );

        if (availability == MediaAvailability.unavailable) {
          // The one deliberate exception: an unreleased title is not a gap
          // anyone can close, so it answers to `All` alone.
          expect(underAvailable, isFalse, reason: '$availability');
          expect(underMissing, isFalse, reason: '$availability');
          continue;
        }

        // Exactly one, never both and never neither — otherwise an item is
        // either double-counted or invisible under every chip but `All`.
        expect(underAvailable ^ underMissing, isTrue, reason: '$availability');
      }
    });

    test('an unresolved or departed item is a gap, not nothing at all', () {
      // `sonarrSeriesAvailability` returns `unknown` whenever the server omits
      // `statistics`, which is what a freshly added series looks like.
      for (final availability in const [
        MediaAvailability.unknown,
        MediaAvailability.deleted,
        MediaAvailability.notTracked,
        MediaAvailability.missing,
      ]) {
        expect(
          mediaBrowseBucketOf(MediaStatusInfo(availability: availability)),
          MediaBrowseBucket.gap,
          reason: '$availability',
        );
      }
    });

    test('a partial manifest counts as on disk', () {
      for (final availability in const [
        MediaAvailability.available,
        MediaAvailability.upgradable,
        MediaAvailability.partial,
      ]) {
        expect(
          mediaBrowseBucketOf(MediaStatusInfo(availability: availability)),
          MediaBrowseBucket.onDisk,
          reason: '$availability',
        );
      }
    });

    test('a screen with no status extractor sees gaps', () {
      expect(mediaBrowseFilterMatches(MediaBrowseFilter.all, null), isTrue);
      expect(mediaBrowseFilterMatches(MediaBrowseFilter.missing, null), isTrue);
      expect(
        mediaBrowseFilterMatches(MediaBrowseFilter.available, null),
        isFalse,
      );
      expect(
        mediaBrowseFilterMatches(MediaBrowseFilter.inQueue, null),
        isFalse,
      );
    });

    test('below cutoff is on disk, and never a gap', () {
      // A file that is present but under the profile's cutoff is not missing.
      // The chip is its own question and must not be folded into either bucket,
      // or the Available/Missing partition stops being one.
      const belowCutoff = MediaStatusInfo(
        availability: MediaAvailability.upgradable,
      );
      expect(
        mediaBrowseFilterMatches(
          MediaBrowseFilter.cutoffUnmet,
          belowCutoff,
          belowCutoff: true,
        ),
        isTrue,
      );
      expect(
        mediaBrowseFilterMatches(MediaBrowseFilter.available, belowCutoff),
        isTrue,
      );
      expect(
        mediaBrowseFilterMatches(MediaBrowseFilter.missing, belowCutoff),
        isFalse,
      );
      // And with no id set the chip claims nothing rather than everything.
      expect(
        mediaBrowseFilterMatches(MediaBrowseFilter.cutoffUnmet, belowCutoff),
        isFalse,
      );
    });

    test('unmonitored says nothing about the file', () {
      for (final availability in MediaAvailability.values) {
        expect(
          mediaBrowseFilterMatches(
            MediaBrowseFilter.unmonitored,
            MediaStatusInfo(availability: availability, unmonitored: true),
          ),
          isTrue,
          reason: '$availability',
        );
        expect(
          mediaBrowseFilterMatches(
            MediaBrowseFilter.unmonitored,
            MediaStatusInfo(availability: availability),
          ),
          isFalse,
          reason: '$availability',
        );
      }
    });

    test('what is moving is a different question from what is on disk', () {
      const downloading = MediaStatusInfo(
        availability: MediaAvailability.missing,
        pipeline: MediaPipeline.downloading,
      );
      expect(
        mediaBrowseFilterMatches(MediaBrowseFilter.inQueue, downloading),
        isTrue,
      );
      expect(
        mediaBrowseFilterMatches(MediaBrowseFilter.missing, downloading),
        isTrue,
      );
    });
  });

  group('MediaBrowseScaffold', () {
    testWidgets('renders title in AppBar', (tester) async {
      await tester.pumpWidget(_buildTestApp());

      expect(find.text('Test Title'), findsOneWidget);
    });

    testWidgets('renders SearchBarHeader', (tester) async {
      await tester.pumpWidget(_buildTestApp());

      expect(find.byType(SearchBarHeader), findsOneWidget);
    });

    testWidgets('shows activity button', (tester) async {
      await tester.pumpWidget(_buildTestApp());

      expect(find.byIcon(Icons.history), findsOneWidget);
    });

    testWidgets('shows grouped browse content and filters by default', (
      tester,
    ) async {
      await tester.pumpWidget(_buildTestApp());
      await tester.pumpAndSettle();

      expect(find.byType(MediaGrid<String>), findsNothing);
      expect(find.text('All'), findsOneWidget);
      expect(find.text('Available'), findsOneWidget);
      expect(find.text('Missing'), findsOneWidget);
      expect(find.text('In Queue'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('media-browse-section-A')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('media-browse-section-B')),
        findsOneWidget,
      );
      expect(find.text('Alpha'), findsOneWidget);
      expect(find.text('Beta'), findsOneWidget);
    });

    testWidgets('shows back arrow when searching', (tester) async {
      final container = ProviderContainer(
        overrides: [
          currentSettingsProvider.overrideWith((ref) => const SettingsModel()),
        ],
      );
      addTearDown(container.dispose);
      container.read(testSearchQueryProvider.notifier).state = 'test query';

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(home: _buildTestScaffold()),
        ),
      );

      expect(find.byIcon(Icons.arrow_back), findsOneWidget);
    });

    testWidgets(
      'switches from library mode to search results when query becomes non-empty',
      (tester) async {
        final searchQueryProvider = StateProvider<String>((ref) => '');
        final libraryProvider = FutureProvider<List<String>>(
          (ref) async => ['Library Item'],
        );
        final searchResultsProvider = FutureProvider<List<String>?>((
          ref,
        ) async {
          final query = ref.watch(searchQueryProvider);
          return query.isEmpty ? null : ['Search Result'];
        });
        final container = ProviderContainer(
          overrides: [
            currentSettingsProvider.overrideWith(
              (ref) => const SettingsModel(),
            ),
          ],
        );
        addTearDown(container.dispose);

        String? tappedItem;
        String? tappedHeroTag;

        await tester.pumpWidget(
          _buildCustomTestApp(
            container: container,
            libraryProvider: libraryProvider,
            searchQueryProvider: searchQueryProvider,
            searchResultsProvider: searchResultsProvider,
            titleExtractor: (item) => item,
            onItemTap: (_, item, heroTag) {
              tappedItem = item;
              tappedHeroTag = heroTag;
            },
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Library Item'));
        await tester.pump();

        expect(tappedItem, 'Library Item');
        expect(tappedHeroTag, contains('test_'));

        container.read(searchQueryProvider.notifier).state = 'matrix';
        await tester.pump();
        await tester.pumpAndSettle();

        expect(find.byIcon(Icons.arrow_back), findsOneWidget);

        tappedItem = null;
        tappedHeroTag = null;

        await tester.tap(_gridItemGestureDetectorFinder());
        await tester.pump();

        expect(tappedItem, 'Search Result');
        expect(tappedHeroTag, contains('test_search_'));
      },
    );

    testWidgets('filters grouped browse content by availability', (
      tester,
    ) async {
      final libraryProvider = FutureProvider<List<String>>(
        (ref) async => ['Available Item', 'Missing Item'],
      );
      final container = ProviderContainer(
        overrides: [
          currentSettingsProvider.overrideWith((ref) => const SettingsModel()),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        _buildCustomTestApp(
          container: container,
          libraryProvider: libraryProvider,
          searchQueryProvider: testSearchQueryProvider,
          searchResultsProvider: testSearchResultsProvider,
          titleExtractor: (item) => item,
          statusExtractor: (item) => switch (item) {
            'Available Item' => const MediaStatusInfo(
              availability: MediaAvailability.available,
            ),
            _ => const MediaStatusInfo(availability: MediaAvailability.missing),
          },
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Available'));
      await tester.pumpAndSettle();

      expect(find.text('Available Item'), findsOneWidget);
      expect(find.text('Missing Item'), findsNothing);

      await tester.tap(find.text('Missing'));
      await tester.pumpAndSettle();

      expect(find.text('Available Item'), findsNothing);
      expect(find.text('Missing Item'), findsOneWidget);
    });

    testWidgets('lists a series the server never resolved under Missing', (
      tester,
    ) async {
      final libraryProvider = FutureProvider<List<String>>(
        (ref) async => ['Available Item', 'Unresolved Item'],
      );
      final container = ProviderContainer(
        overrides: [
          currentSettingsProvider.overrideWith((ref) => const SettingsModel()),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        _buildCustomTestApp(
          container: container,
          libraryProvider: libraryProvider,
          searchQueryProvider: testSearchQueryProvider,
          searchResultsProvider: testSearchResultsProvider,
          titleExtractor: (item) => item,
          statusExtractor: (item) => switch (item) {
            'Available Item' => const MediaStatusInfo(
              availability: MediaAvailability.available,
            ),
            // Sonarr omitting `statistics` on a freshly added series, which
            // used to leave the row visible under `All` and under nothing else.
            _ => const MediaStatusInfo(availability: MediaAvailability.unknown),
          },
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Missing'));
      await tester.pumpAndSettle();

      expect(find.text('Unresolved Item'), findsOneWidget);
      expect(find.text('Available Item'), findsNothing);

      await tester.tap(find.text('Available'));
      await tester.pumpAndSettle();

      expect(find.text('Unresolved Item'), findsNothing);
      expect(find.text('Available Item'), findsOneWidget);
    });

    testWidgets('filters grouped browse content by pipeline state', (
      tester,
    ) async {
      final libraryProvider = FutureProvider<List<String>>(
        (ref) async => ['Queued Item', 'Available Item'],
      );
      final container = ProviderContainer(
        overrides: [
          currentSettingsProvider.overrideWith((ref) => const SettingsModel()),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        _buildCustomTestApp(
          container: container,
          libraryProvider: libraryProvider,
          searchQueryProvider: testSearchQueryProvider,
          searchResultsProvider: testSearchResultsProvider,
          titleExtractor: (item) => item,
          statusExtractor: (item) => switch (item) {
            'Available Item' => const MediaStatusInfo(
              availability: MediaAvailability.available,
            ),
            // Nothing on disk *and* in the queue — the case that used to be
            // flattened to "Missing".
            _ => const MediaStatusInfo(
              availability: MediaAvailability.missing,
              pipeline: MediaPipeline.queued,
            ),
          },
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('In Queue'));
      await tester.pumpAndSettle();

      expect(find.text('Queued Item'), findsOneWidget);
      expect(find.text('Available Item'), findsNothing);
    });

    testWidgets('shows empty search state when search returns no results', (
      tester,
    ) async {
      final searchQueryProvider = StateProvider<String>((ref) => 'query');
      final libraryProvider = FutureProvider<List<String>>(
        (ref) async => ['Library Item'],
      );
      final searchResultsProvider = FutureProvider<List<String>?>((ref) async {
        final query = ref.watch(searchQueryProvider);
        return query.isEmpty ? null : <String>[];
      });
      final container = ProviderContainer(
        overrides: [
          currentSettingsProvider.overrideWith((ref) => const SettingsModel()),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        _buildCustomTestApp(
          container: container,
          libraryProvider: libraryProvider,
          searchQueryProvider: searchQueryProvider,
          searchResultsProvider: searchResultsProvider,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('No results found'), findsOneWidget);
      expect(find.byType(MediaGrid<String>), findsNothing);
    });

    testWidgets(
      'navigation refresh clears search query and invalidates library provider',
      (tester) async {
        var libraryLoadCount = 0;
        final searchQueryProvider = StateProvider<String>((ref) => '');
        final libraryProvider = FutureProvider<List<String>>((ref) async {
          libraryLoadCount++;
          return ['Library $libraryLoadCount'];
        });
        final searchResultsProvider = FutureProvider<List<String>?>((
          ref,
        ) async {
          final query = ref.watch(searchQueryProvider);
          return query.isEmpty ? null : ['Search Result'];
        });
        final container = ProviderContainer(
          overrides: [
            currentSettingsProvider.overrideWith(
              (ref) => const SettingsModel(),
            ),
          ],
        );
        addTearDown(container.dispose);

        await tester.pumpWidget(
          _buildCustomTestApp(
            container: container,
            libraryProvider: libraryProvider,
            searchQueryProvider: searchQueryProvider,
            searchResultsProvider: searchResultsProvider,
          ),
        );
        await tester.pumpAndSettle();

        expect(libraryLoadCount, 1);

        container.read(searchQueryProvider.notifier).state = 'searching';
        await tester.pump();
        await tester.pumpAndSettle();

        expect(find.byIcon(Icons.arrow_back), findsOneWidget);
        expect(libraryLoadCount, 1);

        container
            .read(
              navigationRefreshProvider(NavigationSection.dashboard).notifier,
            )
            .state++;
        await tester.pump();
        await tester.pumpAndSettle();

        expect(container.read(searchQueryProvider), '');
        expect(find.byIcon(Icons.arrow_back), findsNothing);
        expect(libraryLoadCount, 2);
      },
    );
  });

  group('sort and the chips it decides', () {
    testWidgets('letter headings appear only under Title A–Z', (tester) async {
      final container = ProviderContainer(
        overrides: [
          currentSettingsProvider.overrideWith((ref) => const SettingsModel()),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        _buildCustomTestApp(
          container: container,
          libraryProvider: testLibraryProvider,
          searchQueryProvider: testSearchQueryProvider,
          searchResultsProvider: testSearchResultsProvider,
          sorts: [
            MediaBrowseSort<String>(
              label: 'Date added',
              compare: (left, right) => right.compareTo(left),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('media-browse-section-A')),
        findsOneWidget,
      );

      await tester.tap(find.text('Title A–Z'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Date added').last);
      await tester.pumpAndSettle();

      // The order changed, so the headings went with it: an "A" over a
      // date-added run describes nothing.
      expect(
        find.byKey(const ValueKey('media-browse-section-A')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('media-browse-section-flat')),
        findsOneWidget,
      );
      expect(find.text('Beta'), findsOneWidget);
    });

    testWidgets('the Cutoff unmet chip is only offered with a source', (
      tester,
    ) async {
      final container = ProviderContainer(
        overrides: [
          currentSettingsProvider.overrideWith((ref) => const SettingsModel()),
        ],
      );
      addTearDown(container.dispose);

      // No source: the chip must not exist. An empty set and an unasked
      // question would otherwise draw the same control.
      await tester.pumpWidget(
        _buildCustomTestApp(
          container: container,
          libraryProvider: testLibraryProvider,
          searchQueryProvider: testSearchQueryProvider,
          searchResultsProvider: testSearchResultsProvider,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Cutoff unmet'), findsNothing);
      // Unmonitored rides on the status every screen already resolves, so it
      // is never conditional.
      expect(find.text('Unmonitored'), findsOneWidget);

      final withSource = ProviderContainer(
        overrides: [
          currentSettingsProvider.overrideWith((ref) => const SettingsModel()),
        ],
      );
      addTearDown(withSource.dispose);

      await tester.pumpWidget(
        _buildCustomTestApp(
          container: withSource,
          libraryProvider: testLibraryProvider,
          searchQueryProvider: testSearchQueryProvider,
          searchResultsProvider: testSearchResultsProvider,
          cutoffUnmetIds: {'Alpha'.hashCode},
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Cutoff unmet'), findsOneWidget);

      await tester.tap(find.text('Cutoff unmet'));
      await tester.pumpAndSettle();

      expect(find.text('Alpha'), findsOneWidget);
      expect(find.text('Beta'), findsNothing);
    });

    testWidgets('the sort control clears a 44pt target', (tester) async {
      final container = ProviderContainer(
        overrides: [
          currentSettingsProvider.overrideWith((ref) => const SettingsModel()),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        _buildCustomTestApp(
          container: container,
          libraryProvider: testLibraryProvider,
          searchQueryProvider: testSearchQueryProvider,
          searchResultsProvider: testSearchResultsProvider,
          sorts: [
            MediaBrowseSort<String>(
              label: 'Date added',
              compare: (left, right) => right.compareTo(left),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      final target = tester.getSize(
        find.ancestor(
          of: find.text('Title A–Z'),
          matching: find.byType(PopupMenuButton<int>),
        ),
      );
      expect(target.height, greaterThanOrEqualTo(44));
      expect(target.width, greaterThanOrEqualTo(44));
    });

    testWidgets('one order is no choice, so no control is drawn', (
      tester,
    ) async {
      await tester.pumpWidget(_buildTestApp());
      await tester.pumpAndSettle();

      expect(find.byType(PopupMenuButton<int>), findsNothing);
    });
  });

  group('the tile shape is a claim about the artwork', () {
    testWidgets('the circular wall clips oval and paints no status dot', (
      tester,
    ) async {
      final container = ProviderContainer(
        overrides: [
          currentSettingsProvider.overrideWith((ref) => const SettingsModel()),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        _buildCustomTestApp(
          container: container,
          libraryProvider: testLibraryProvider,
          searchQueryProvider: testSearchQueryProvider,
          searchResultsProvider: testSearchResultsProvider,
          subtitleExtractor: (_) => '6 albums \u00b7 complete',
          statusExtractor: (_) =>
              const MediaStatusInfo(availability: MediaAvailability.available),
          tileShape: MediaBrowseTileShape.circle,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(ClipOval), findsWidgets);
      // A circle has no corner to hold a dot without covering the face, so the
      // completeness is in the caption instead — and the caption is what the
      // screen reader was already given.
      expect(find.byType(StatusBadge), findsNothing);
      expect(find.text('6 albums \u00b7 complete'), findsWidgets);
    });

    testWidgets('the poster wall keeps its dot', (tester) async {
      final container = ProviderContainer(
        overrides: [
          currentSettingsProvider.overrideWith((ref) => const SettingsModel()),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        _buildCustomTestApp(
          container: container,
          libraryProvider: testLibraryProvider,
          searchQueryProvider: testSearchQueryProvider,
          searchResultsProvider: testSearchResultsProvider,
          statusExtractor: (_) =>
              const MediaStatusInfo(availability: MediaAvailability.available),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(StatusBadge), findsWidgets);
    });
  });

  group('the browse wall holds the column floor', () {
    testWidgets('tiles fill the row they were given, leaving no gutter', (
      tester,
    ) async {
      // The wall used to pin a 96pt tile and then clamp away the spacing it
      // had computed to absorb the slack, so every row ended in dead space —
      // 46pt of it at phone width. The boards are `repeat(N, minmax(0, 1fr))`.
      await _pumpBrowseWall(tester, const Size(390, 900));

      final wrap = tester.getRect(find.byType(Wrap).first);
      final rows = _browseRows(tester, 12);
      final fullRows = rows.values.where(
        (row) => row.length == rows.values.first.length,
      );

      for (final row in fullRows) {
        row.sort((left, right) => left.left.compareTo(right.left));
        expect(row.first.left, moreOrLessEquals(wrap.left, epsilon: 0.5));
        expect(row.last.right, moreOrLessEquals(wrap.right, epsilon: 0.5));
      }
    });

    testWidgets('a wider frame adds a column instead of stretching three', (
      tester,
    ) async {
      await _pumpBrowseWall(tester, const Size(1280, 900));

      final rows = _browseRows(tester, 12);
      final widest = rows.values
          .map((row) => row.length)
          .reduce((a, b) => a > b ? a : b);
      expect(widest, greaterThan(3));

      // And the column count it chose is one every tile clears the floor at —
      // the rule is fewer tiles, never smaller ones.
      for (final rect in rows.values.expand((row) => row)) {
        expect(
          rect.width,
          greaterThanOrEqualTo(MediaGrid.tileWidthFloor - 0.5),
        );
      }
    });
  });
}

Widget _buildTestApp() {
  return ProviderScope(
    overrides: [
      currentSettingsProvider.overrideWith((ref) => const SettingsModel()),
    ],
    child: MaterialApp(home: _buildTestScaffold()),
  );
}

Widget _buildTestScaffold() {
  return MediaBrowseScaffold<String>(
    title: 'Test Title',
    searchHint: 'Search test...',
    activityRoute: '/activity/test',
    navigationSection: NavigationSection.dashboard,
    serviceName: 'Test Service',
    heroTagPrefix: 'test',
    searchHeroTagPrefix: 'test_search',
    libraryProvider: testLibraryProvider,
    searchQueryProvider: testSearchQueryProvider,
    searchResultsProvider: testSearchResultsProvider,
    titleExtractor: (item) => item,
    subtitleExtractor: (_) => '',
    imagesExtractor: (_) => null,
    idExtractor: (item) => item.hashCode,
    settingsSelector: (settings) => (settings.radarrUrl, settings.radarrApiKey),
    onItemTap: (_, _, _) {},
  );
}

Widget _buildCustomTestApp({
  required ProviderContainer container,
  required FutureProvider<List<String>> libraryProvider,
  required StateProvider<String> searchQueryProvider,
  required FutureProvider<List<String>?> searchResultsProvider,
  String Function(String item)? titleExtractor,
  String Function(String item)? subtitleExtractor,
  StatusExtractor<String>? statusExtractor,
  void Function(BuildContext context, String item, String heroTag)? onItemTap,
  List<MediaBrowseSort<String>> sorts = const [],
  Set<int>? cutoffUnmetIds,
  MediaBrowseTileShape tileShape = MediaBrowseTileShape.poster,
}) {
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      home: MediaBrowseScaffold<String>(
        title: 'Test Title',
        searchHint: 'Search test...',
        activityRoute: '/activity/test',
        navigationSection: NavigationSection.dashboard,
        serviceName: 'Test Service',
        heroTagPrefix: 'test',
        searchHeroTagPrefix: 'test_search',
        libraryProvider: libraryProvider,
        searchQueryProvider: searchQueryProvider,
        searchResultsProvider: searchResultsProvider,
        titleExtractor: titleExtractor ?? (item) => item,
        subtitleExtractor: subtitleExtractor ?? (_) => '',
        imagesExtractor: (_) => null,
        idExtractor: (item) => item.hashCode,
        statusExtractor: statusExtractor,
        settingsSelector: (settings) =>
            (settings.radarrUrl, settings.radarrApiKey),
        onItemTap: onItemTap ?? (_, _, _) {},
        sorts: sorts,
        cutoffUnmetIds: cutoffUnmetIds,
        tileShape: tileShape,
      ),
    ),
  );
}

Finder _gridItemGestureDetectorFinder() {
  return find
      .descendant(
        of: find.byType(MediaGrid<String>),
        matching: find.byType(GestureDetector),
      )
      .first;
}

/// The row of the browse wall a tile was laid out in, keyed by its top edge.
Map<double, List<Rect>> _browseRows(WidgetTester tester, int itemCount) {
  final rows = <double, List<Rect>>{};
  for (var index = 0; index < itemCount; index++) {
    final title = 'A${index.toString().padLeft(2, '0')}';
    // Closest `SizedBox` ancestor of the title is the tile's own root box.
    final tile = find
        .ancestor(of: find.text(title), matching: find.byType(SizedBox))
        .first;
    final rect = tester.getRect(tile);
    rows.putIfAbsent(rect.top, () => <Rect>[]).add(rect);
  }
  return rows;
}

Future<void> _pumpBrowseWall(WidgetTester tester, Size surface) async {
  const itemCount = 12;
  final libraryProvider = FutureProvider<List<String>>(
    (ref) async => [
      for (var index = 0; index < itemCount; index++)
        'A${index.toString().padLeft(2, '0')}',
    ],
  );
  final container = ProviderContainer(
    overrides: [
      currentSettingsProvider.overrideWith((ref) => const SettingsModel()),
    ],
  );
  addTearDown(container.dispose);

  tester.view.physicalSize = surface;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    _buildCustomTestApp(
      container: container,
      libraryProvider: libraryProvider,
      searchQueryProvider: testSearchQueryProvider,
      searchResultsProvider: testSearchResultsProvider,
    ),
  );
  await tester.pumpAndSettle();
}
