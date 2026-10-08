import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/capability/audience.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/floating_bottom_nav_bar.dart';
import 'package:cupola/features/settings/domain/nav_tab.dart';
import 'package:cupola/features/shell/domain/shell_shortcuts.dart';
import 'package:cupola/features/shell/presentation/desktop/desktop_nav_rail.dart';

void main() {
  FloatingNavDestination destinationFor(NavTab tab, {int badge = 0}) =>
      FloatingNavDestination(
        icon: tab.icon,
        selectedIcon: tab.selectedIcon,
        railIcon: tab.railIcon,
        label: tab.label,
        badgeCount: badge,
      );

  // The operator's bar, which is what the rail draws above Settings.
  final bar = NavTab.barFor(Audience.operator);

  Future<void> pumpRail(
    WidgetTester tester, {
    int count = 0,
    bool settingsSelected = false,
    ValueChanged<int>? onDestinationSelected,
    VoidCallback? onSettings,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme(),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              height: 480,
              child: DesktopNavRail(
                selectedIndex: settingsSelected
                    ? -1
                    : bar.indexOf(NavTab.activity),
                onDestinationSelected: onDestinationSelected ?? (_) {},
                onCommandDeck: () {},
                destinations: [
                  for (final tab in bar)
                    destinationFor(
                      tab,
                      badge: tab == NavTab.activity ? count : 0,
                    ),
                ],
                settings: destinationFor(NavTab.settings),
                settingsSelected: settingsSelected,
                onSettings: onSettings ?? () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder badge() => find.byKey(const ValueKey('desktop-rail-badge'));

  Finder railItem(String label) => find.byWidgetPredicate(
    (w) => w is IconButton && (w.tooltip ?? '').startsWith('$label  '),
  );

  group('DesktopNavRail sections', () {
    testWidgets('draws the bar, then Settings at the foot', (tester) async {
      await pumpRail(tester);

      final tops = [
        for (final tab in bar) tester.getTopLeft(railItem(tab.label)).dy,
      ];
      expect(tops, orderedEquals([...tops]..sort()), reason: 'bar order');
      // Four sections, and the settings key below the last of them.
      expect(tops, hasLength(4));
      final settings = tester.getTopLeft(railItem('Settings')).dy;
      expect(settings, greaterThan(tops.last));
      // Settings is no section: the rail has five buttons beside the deck's.
      expect(railItem('Requests'), findsNothing);
    });

    testWidgets(
      'the sections carry the bar\'s shortcuts, Settings carries ⌘,',
      (tester) async {
        await pumpRail(tester);

        for (final (index, tab) in bar.indexed) {
          expect(
            tester.widget<IconButton>(railItem(tab.label)).tooltip,
            '${tab.label}  ${ShellShortcuts.section(index)}',
          );
        }
        expect(
          tester.widget<IconButton>(railItem('Settings')).tooltip,
          'Settings  ${ShellShortcuts.settings}',
        );
      },
    );

    testWidgets('Settings is selected by its own flag, and no section is', (
      tester,
    ) async {
      await pumpRail(tester, settingsSelected: true);

      expect(
        tester.widget<IconButton>(railItem('Settings')).isSelected,
        isTrue,
      );
      for (final tab in bar) {
        expect(
          tester.widget<IconButton>(railItem(tab.label)).isSelected,
          isNot(isTrue),
          reason: tab.label,
        );
      }
    });

    testWidgets('a section reports its place in the bar, Settings its own', (
      tester,
    ) async {
      final selected = <int>[];
      var settings = 0;
      await pumpRail(
        tester,
        onDestinationSelected: selected.add,
        onSettings: () => settings++,
      );

      await tester.tap(railItem('Stack'));
      await tester.tap(railItem('Home'));
      await tester.tap(railItem('Settings'));

      expect(selected, [bar.indexOf(NavTab.stack), bar.indexOf(NavTab.home)]);
      expect(settings, 1);
    });
  });

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
