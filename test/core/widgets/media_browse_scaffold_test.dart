import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// ignore: implementation_imports
import 'package:flutter_riverpod/legacy.dart';

import 'package:cupola/core/providers/navigation_refresh_provider.dart';
import 'package:cupola/core/service_theme.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/connection_access.dart';
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

        // Exactly one, never both and never neither; otherwise an item is
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

      expect(find.byIcon(Icons.history_rounded), findsOneWidget);
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
      expect(find.text('In queue'), findsOneWidget);
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

      expect(find.byIcon(Icons.arrow_back_rounded), findsOneWidget);
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

        expect(find.byIcon(Icons.arrow_back_rounded), findsOneWidget);

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

    testWidgets('a chip that hides every title says so and offers Show all', (
      tester,
    ) async {
      final libraryProvider = FutureProvider<List<String>>(
        (ref) async => ['Available Item'],
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
          statusExtractor: (_) =>
              const MediaStatusInfo(availability: MediaAvailability.available),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Missing'));
      await tester.pumpAndSettle();

      expect(find.text('Nothing is missing'), findsOneWidget);
      expect(find.textContaining('library is empty'), findsNothing);

      await tester.tap(find.text('Show all'));
      await tester.pumpAndSettle();

      expect(find.text('Available Item'), findsOneWidget);
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
            // Nothing on disk *and* in the queue: the case that used to be
            // flattened to "Missing".
            _ => const MediaStatusInfo(
              availability: MediaAvailability.missing,
              pipeline: MediaPipeline.queued,
            ),
          },
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('In queue'));
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

      expect(find.textContaining('found nothing for'), findsOneWidget);
      expect(find.byType(MediaGrid<String>), findsNothing);
    });

    testWidgets('a search that failed says why in plain words, never the '
        'exception', (tester) async {
      final searchQueryProvider = StateProvider<String>((ref) => 'query');
      final libraryProvider = FutureProvider<List<String>>(
        (ref) async => ['Library Item'],
      );
      final searchResultsProvider = FutureProvider<List<String>?>(
        (ref) async => throw const SocketException('Connection refused'),
      );
      final container = ProviderContainer(
        overrides: [
          currentSettingsProvider.overrideWith((ref) => const SettingsModel()),
        ],
        retry: (_, _) => null,
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

      // It printed `Error: SocketException: Connection refused`.
      expect(find.textContaining('Error:'), findsNothing);
      expect(find.textContaining('SocketException'), findsNothing);
      expect(find.text('The server did not answer'), findsOneWidget);
      expect(find.textContaining('found nothing for'), findsNothing);
      expect(find.text('Retry'), findsOneWidget);
    });

    // Drawn in the theme's `primary`, the search spinner put Seerr's indigo in
    // Radarr's amber room while every other control there took the accent.
    testWidgets('the search spinner draws in the service accent', (
      tester,
    ) async {
      final searchQueryProvider = StateProvider<String>((ref) => 'nos');
      final pending = Completer<List<String>?>();
      final searchResultsProvider = FutureProvider<List<String>?>(
        (ref) => pending.future,
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
          libraryProvider: testLibraryProvider,
          searchQueryProvider: searchQueryProvider,
          searchResultsProvider: searchResultsProvider,
          accentColor: AppColors.radarr,
        ),
      );
      await tester.pump();

      final spinner = find.byType(CircularProgressIndicator);
      expect(spinner, findsOneWidget);
      final surface = Theme.of(tester.element(spinner)).colorScheme.surface;
      expect(
        tester.widget<CircularProgressIndicator>(spinner).color,
        ServiceTheme.onTint(AppColors.radarr, surface: surface, tintAlpha: 0),
      );
    });

    testWidgets('the library spinner draws in the service accent too', (
      tester,
    ) async {
      final pending = Completer<List<String>>();
      final libraryProvider = FutureProvider<List<String>>(
        (ref) => pending.future,
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
          accentColor: AppColors.radarr,
        ),
      );
      await tester.pump();

      final spinner = find.byType(CircularProgressIndicator);
      expect(spinner, findsOneWidget);
      final surface = Theme.of(tester.element(spinner)).colorScheme.surface;
      expect(
        tester.widget<CircularProgressIndicator>(spinner).color,
        ServiceTheme.onTint(AppColors.radarr, surface: surface, tintAlpha: 0),
      );
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

        expect(find.byIcon(Icons.arrow_back_rounded), findsOneWidget);
        expect(libraryLoadCount, 1);

        container
            .read(navigationRefreshProvider(NavigationSection.stack).notifier)
            .state++;
        await tester.pump();
        await tester.pumpAndSettle();

        expect(container.read(searchQueryProvider), '');
        expect(find.byIcon(Icons.arrow_back_rounded), findsNothing);
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
      // completeness is in the caption instead, and the caption is what the
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
      // had computed to absorb the slack, so every row ended in dead space:
      // 46pt of it at phone width. The boards are `repeat(N, minmax(0, 1fr))`.
      await _pumpBrowseWall(tester, const Size(390, 900));

      // The row a tile sits in spans the wall's whole content width.
      final wall = tester.getRect(
        find.ancestor(of: find.text('A00'), matching: find.byType(Row)).first,
      );
      expect(wall.left, 16);
      expect(wall.right, 390 - 16);
      final rows = _browseRows(tester, 12);
      final fullRows = rows.values.where(
        (row) => row.length == rows.values.first.length,
      );

      for (final row in fullRows) {
        row.sort((left, right) => left.left.compareTo(right.left));
        expect(row.first.left, moreOrLessEquals(wall.left, epsilon: 0.5));
        expect(row.last.right, moreOrLessEquals(wall.right, epsilon: 0.5));
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

      // And the column count it chose is one every tile clears the floor at:
      // the rule is fewer tiles, never smaller ones.
      for (final rect in rows.values.expand((row) => row)) {
        expect(
          rect.width,
          greaterThanOrEqualTo(MediaGrid.tileWidthFloor - 0.5),
        );
      }
    });
  });

  group('the browse wall is built as it scrolls', () {
    // The wall used to be one list item per section, each a `Wrap` of every
    // tile in it, lazy across sections only. Any order but Title A–Z is ONE
    // section, so a 2 000-title library built 2 000 tiles, and started 2 000
    // poster loads, the moment the wall appeared.
    testWidgets('a 2 000-title run builds a screenful, not the library', (
      tester,
    ) async {
      await _pumpLargeWall(tester, count: 2000);

      // Title A–Z over titles that all start with one letter: one section.
      expect(find.text('A'), findsOneWidget);
      final lettered = find.byType(ContentCard).evaluate().length;
      expect(lettered, greaterThan(0));
      expect(lettered, lessThan(60));

      // An unheaded order: the whole library in one run, the audit's case.
      await tester.tap(find.text('Title A–Z'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reverse').last);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('media-browse-section-flat')),
        findsOneWidget,
      );
      final flat = find.byType(ContentCard).evaluate().length;
      expect(flat, greaterThan(0));
      expect(flat, lessThan(60));
      expect(find.text('A1999'), findsOneWidget);
      expect(find.text('A0000'), findsNothing);
    });

    testWidgets('the far end is still reachable, with its own hero tag', (
      tester,
    ) async {
      final taps = <String>[];
      await _pumpLargeWall(tester, count: 300, onTap: taps.add);

      await tester.dragUntilVisible(
        find.text('A0299'),
        find.byType(NestedScrollView),
        const Offset(0, -800),
        maxIteration: 200,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('A0299'));
      await tester.pump();

      // The index in the visible list, exactly as the eager wall numbered it.
      expect(taps, ['A0299|test_${'A0299'.hashCode}_299']);
      // And the top of the library has been let go.
      expect(find.text('A0000'), findsNothing);
    });

    testWidgets('a row is one Wrap run: top-aligned, tallest tile, 16 apart', (
      tester,
    ) async {
      for (final scale in const [1.0, 2.0]) {
        await tester.pumpWidget(const SizedBox.shrink());
        await _pumpLargeWall(
          tester,
          count: 6,
          textScale: scale,
          // Only the first tile of each row carries a subtitle line.
          subtitle: (item) => item == 'A0000' || item == 'A0003' ? '1922' : '',
        );

        final first = [
          for (final title in const ['A0000', 'A0001', 'A0002'])
            _tileRect(tester, title),
        ];
        final second = _tileRect(tester, 'A0003');

        // Three across a 390 phone, filling the 358 row with two 12pt gaps.
        const tileWidth = (358 - 2 * 12) / 3;
        for (final (column, rect) in first.indexed) {
          expect(rect.left, moreOrLessEquals(16 + column * (tileWidth + 12)));
          expect(rect.width, moreOrLessEquals(tileWidth));
          expect(rect.top, first.first.top, reason: 'top-aligned at $scale');
        }
        // A tile's height is its own content, and grows with the reading size.
        expect(first[0].height, greaterThan(first[1].height));
        // The next row starts 16 under the tallest tile of this one.
        expect(second.top, moreOrLessEquals(first[0].bottom + 16));
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('a section heading keeps its gaps', (tester) async {
      await _pumpLargeWall(tester, titles: const ['A0000', 'A0001', 'B0000']);

      final headingA = tester.getRect(find.text('A'));
      final headingB = tester.getRect(find.text('B'));
      final tallestA = [
        _tileRect(tester, 'A0000'),
        _tileRect(tester, 'A0001'),
      ].map((rect) => rect.bottom).reduce((a, b) => a > b ? a : b);

      // space-md under a heading, space-xl between sections.
      expect(_tileRect(tester, 'A0000').top, headingA.bottom + 12);
      expect(headingB.top, tallestA + 24);
    });

    testWidgets('a screen reader counts tiles, not rows', (tester) async {
      await _pumpLargeWall(tester, count: 9);

      // The fourth tile opens the second row and is still item four.
      final indexed = tester.widget<IndexedSemantics>(
        find
            .ancestor(
              of: find.text('A0003'),
              matching: find.byType(IndexedSemantics),
            )
            .first,
      );
      expect(indexed.index, 3);
      expect(
        tester.getSemantics(find.text('A0003')),
        containsSemantics(label: 'A0003', isButton: true, hasTapAction: true),
      );
    });
  });
}

Rect _tileRect(WidgetTester tester, String title) => tester.getRect(
  find.ancestor(of: find.text(title), matching: find.byType(SizedBox)).first,
);

Future<void> _pumpLargeWall(
  WidgetTester tester, {
  int count = 0,
  List<String>? titles,
  double textScale = 1.0,
  String Function(String item)? subtitle,
  void Function(String tap)? onTap,
}) async {
  final library = [
    ...?titles,
    for (var index = 0; index < count; index++)
      'A${index.toString().padLeft(4, '0')}',
  ];
  final libraryProvider = FutureProvider<List<String>>((ref) async => library);
  final container = ProviderContainer(
    overrides: [
      currentSettingsProvider.overrideWith((ref) => const SettingsModel()),
    ],
  );
  addTearDown(container.dispose);

  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: MediaBrowseScaffold<String>(
              title: 'Test Title',
              searchHint: 'Search test...',
              activityRoute: '/activity/test',
              navigationSection: NavigationSection.stack,
              serviceName: 'Test Service',
              heroTagPrefix: 'test',
              searchHeroTagPrefix: 'test_search',
              libraryProvider: libraryProvider,
              searchQueryProvider: testSearchQueryProvider,
              searchResultsProvider: testSearchResultsProvider,
              titleExtractor: (item) => item,
              subtitleExtractor: subtitle ?? (_) => '',
              imagesExtractor: (_) => null,
              idExtractor: (item) => item.hashCode,
              settingsSelector: (settings) =>
                  (settings.radarrUrl, settings.radarrApiKey, const NoAccess()),
              onItemTap: (_, item, heroTag) => onTap?.call('$item|$heroTag'),
              sorts: [
                MediaBrowseSort<String>(
                  label: 'Reverse',
                  compare: (left, right) => right.compareTo(left),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
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
    navigationSection: NavigationSection.stack,
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
    settingsSelector: (settings) =>
        (settings.radarrUrl, settings.radarrApiKey, const NoAccess()),
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
  Color? accentColor,
}) {
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      home: MediaBrowseScaffold<String>(
        title: 'Test Title',
        searchHint: 'Search test...',
        activityRoute: '/activity/test',
        navigationSection: NavigationSection.stack,
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
            (settings.radarrUrl, settings.radarrApiKey, const NoAccess()),
        onItemTap: onItemTap ?? (_, _, _) {},
        sorts: sorts,
        cutoffUnmetIds: cutoffUnmetIds,
        tileShape: tileShape,
        accentColor: accentColor,
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
