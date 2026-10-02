import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cupola/core/app_breakpoints.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/status/media_status.dart';
import 'package:cupola/core/widgets/media_grid.dart';

void main() {
  group('MediaGrid', () {
    testWidgets('shows empty message when items list is empty', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MediaGrid<String>(
              items: const [],
              imagesExtractor: (_) => null,
              idExtractor: (_) => 0,
              baseUrl: 'http://localhost',
              apiKey: 'test',
              heroTagPrefix: 'test',
            ),
          ),
        ),
      );

      expect(find.text('No items found'), findsOneWidget);
    });

    testWidgets('renders correct number of items', (tester) async {
      final items = ['Item 1', 'Item 2', 'Item 3'];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MediaGrid<String>(
              items: items,
              imagesExtractor: (_) => null,
              idExtractor: (item) => items.indexOf(item),
              baseUrl: 'http://localhost',
              apiKey: 'test',
              heroTagPrefix: 'test',
            ),
          ),
        ),
      );

      // Should have GridView with items
      expect(find.byType(GridView), findsOneWidget);
    });

    testWidgets('calls onItemTap when item is tapped', (tester) async {
      String? tappedItem;
      String? tappedHeroTag;

      final items = ['Item 1', 'Item 2'];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MediaGrid<String>(
              items: items,
              imagesExtractor: (_) => null,
              idExtractor: (item) => items.indexOf(item),
              baseUrl: 'http://localhost',
              apiKey: 'test',
              heroTagPrefix: 'test',
              onItemTap: (item, heroTag) {
                tappedItem = item;
                tappedHeroTag = heroTag;
              },
            ),
          ),
        ),
      );

      // Tap on first item
      await tester.tap(find.byType(GestureDetector).first);
      await tester.pump();

      expect(tappedItem, 'Item 1');
      expect(tappedHeroTag, contains('test_0'));
    });

    testWidgets('uses statusExtractor when provided', (tester) async {
      final items = ['Available', 'Missing'];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MediaGrid<String>(
              items: items,
              imagesExtractor: (_) => null,
              idExtractor: (item) => items.indexOf(item),
              statusExtractor: (item) => MediaStatusInfo(
                availability: item == 'Available'
                    ? MediaAvailability.available
                    : MediaAvailability.missing,
              ),
              baseUrl: 'http://localhost',
              apiKey: 'test',
              heroTagPrefix: 'test',
            ),
          ),
        ),
      );

      // Grid should render with status badges
      expect(find.byType(GridView), findsOneWidget);
    });

    testWidgets('handles null statusExtractor result', (tester) async {
      final items = ['Item 1'];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MediaGrid<String>(
              items: items,
              imagesExtractor: (_) => null,
              idExtractor: (item) => items.indexOf(item),
              statusExtractor: (_) => null,
              baseUrl: 'http://localhost',
              apiKey: 'test',
              heroTagPrefix: 'test',
            ),
          ),
        ),
      );

      // Should render without throwing
      expect(find.byType(GridView), findsOneWidget);
    });

    group('the column floor rule', () {
      /// The widest a tile can be at [columns] in [width], gaps included.
      double tileWidth(double width, int columns) =>
          (width - (columns - 1) * AppSpacing.gridGap) / columns;

      test('a narrower frame drops a column, it does not shrink the tiles', () {
        // The measured failure this rule exists to forbid: a 640pt well drawn
        // with five columns gives 118pt posters, under the 130pt floor the
        // tile's own layout is built on. Four is the answer, at 151.
        final columns = MediaGrid.columnsFor(640, 3);
        expect(columns, 4);
        expect(
          tileWidth(640, columns),
          greaterThanOrEqualTo(MediaGrid.tileWidthFloor),
        );
        // And the rejected arrangement really is the one that breaks the floor,
        // so the assertion above is not passing by coincidence.
        expect(tileWidth(640, 5), lessThan(MediaGrid.tileWidthFloor));
      });

      test('the count never produces a tile under the floor, at any width', () {
        // The old form divided by the tile width alone and ignored the gaps
        // entirely, so it could answer with a count whose tiles could not
        // actually be that wide. Swept rather than spot-checked, because the
        // arithmetic was wrong in a band of widths rather than at one.
        for (var width = 320.0; width <= 2000.0; width += 1) {
          final columns = MediaGrid.columnsFor(width, 1);
          expect(
            tileWidth(width, columns),
            greaterThanOrEqualTo(MediaGrid.tileWidthFloor),
            reason: '$columns columns in ${width}pt',
          );
        }
      });

      test('a full content well fills with eight full-size posters', () {
        expect(MediaGrid.columnsFor(AppBreakpoints.contentWell, 3), 8);
      });

      test('a 390pt phone draws three columns of about 111 (F-grid)', () {
        // The phone is the product: its library is three posters wide, as the
        // canvas draws it, the floor winning over the 130 the width alone
        // would ask for. 390 less the grid's 16 on each side is 358.
        const well = 390.0 - 2 * 16;
        final columns = MediaGrid.columnsFor(well, 3);
        expect(columns, 3);
        expect(tileWidth(well, columns), closeTo(111, 1));
        // Above the floor a column is added only while it keeps 130.
        expect(MediaGrid.columnsFor(well, 1), 2);
      });

      test('minColumns is a floor on the count, for the phone', () {
        // Two enormous posters would be a worse answer than three correct ones,
        // so a narrow frame keeps its three even though the arithmetic would
        // give fewer.
        expect(MediaGrid.columnsFor(360, 3), 3);
      });
    });

    testWidgets('columns come from the grid\'s constraints, not the window', (
      tester,
    ) async {
      // The defect: `MediaQuery.sizeOf` is the whole window, and on a desktop
      // shell the grid is nothing like the whole window — a 1920pt frame with a
      // rail and an open inspector leaves this widget about 500pt, and
      // measuring the window answered fourteen columns of 24pt posters.
      tester.view.physicalSize = const Size(1920, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Row(
              children: [
                // Everything the shell puts beside the grid.
                const SizedBox(width: 1420),
                Expanded(
                  child: MediaGrid<String>(
                    items: const ['a', 'b', 'c'],
                    imagesExtractor: (_) => null,
                    idExtractor: (_) => 0,
                    baseUrl: 'http://localhost',
                    apiKey: 'test',
                    heroTagPrefix: 'test',
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      final delegate =
          tester.widget<GridView>(find.byType(GridView)).gridDelegate
              as SliverGridDelegateWithFixedCrossAxisCount;
      // 500pt of grid, minus its own 16pt gutters: three columns, not fourteen.
      expect(delegate.crossAxisCount, 3);
    });

    testWidgets('generates unique heroTags with index', (tester) async {
      final items = ['Same', 'Same']; // Same items but different indices

      String? heroTag1;
      String? heroTag2;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MediaGrid<String>(
              items: items,
              imagesExtractor: (_) => null,
              idExtractor: (_) => 0, // Same ID for both
              baseUrl: 'http://localhost',
              apiKey: 'test',
              heroTagPrefix: 'test',
              onItemTap: (item, heroTag) {
                if (heroTag1 == null) {
                  heroTag1 = heroTag;
                } else {
                  heroTag2 = heroTag;
                }
              },
            ),
          ),
        ),
      );

      // Tap both items
      await tester.tap(find.byType(GestureDetector).first);
      await tester.pump();
      await tester.tap(find.byType(GestureDetector).last);
      await tester.pump();

      // Hero tags should be different due to index
      expect(heroTag1, isNot(equals(heroTag2)));
    });
  });
}
