import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/floating_bottom_nav_bar.dart';
import 'package:cupola/features/settings/domain/nav_tab.dart';
import 'package:cupola/features/shell/presentation/desktop/desktop_nav_rail.dart';

void main() {
  Future<void> pumpRail(WidgetTester tester, {required int count}) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme(),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              height: 480,
              child: DesktopNavRail(
                selectedIndex: NavTab.activity.index,
                onDestinationSelected: (_) {},
                onCommandDeck: () {},
                destinations: [
                  for (final tab in NavTab.values)
                    FloatingNavDestination(
                      icon: tab.icon,
                      selectedIcon: tab.selectedIcon,
                      railIcon: tab.railIcon,
                      label: tab.label,
                      badgeCount: tab == NavTab.activity ? count : 0,
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

  Finder badge() => find.byKey(const ValueKey('desktop-rail-badge'));

  group('DesktopNavRail badge', () {
    // Anchored by its right edge 2pt past a 20pt glyph, the 18pt badge covered
    // most of the Activity glyph, and "12" hid it outright.
    for (final count in [1, 9, 12, 150]) {
      testWidgets('leaves the glyph recognisable with $count waiting', (
        tester,
      ) async {
        await pumpRail(tester, count: count);

        final glyph = tester.getRect(
          find.byWidgetPredicate(
            (w) => w is Icon && w.icon == NavTab.activity.railIcon,
          ),
        );
        final badgeRect = tester.getRect(badge());
        final overlap = glyph.intersect(badgeRect);
        final covered = overlap.isEmpty
            ? 0.0
            : overlap.width * overlap.height / (glyph.width * glyph.height);
        expect(
          covered,
          lessThanOrEqualTo(0.3),
          reason: 'the badge covers ${(covered * 100).round()}% of the glyph',
        );
        // The glyph's whole left half stays uncovered.
        expect(badgeRect.left, greaterThanOrEqualTo(glyph.center.dx));

        // And the badge stays inside the rail, short of its hairline. Only
        // asserted for one figure: the test font draws every glyph a full em
        // wide, nearly twice the mono face's advance, so "9+" measures wider
        // here than it ever draws (the catalog sheet shows it ending 4pt short
        // of the hairline in the real face).
        final rail = tester.getRect(find.byType(DesktopNavRail));
        expect(badgeRect.top, greaterThanOrEqualTo(rail.top));
        if (count <= 9) {
          expect(badgeRect.right, lessThanOrEqualTo(rail.right - 1));
        }
      });
    }

    testWidgets('past nine the count reads 9+, as on the phone', (
      tester,
    ) async {
      await pumpRail(tester, count: 12);
      expect(
        find.descendant(of: badge(), matching: find.text('9+')),
        findsOneWidget,
      );
    });
  });
}
