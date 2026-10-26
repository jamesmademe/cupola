import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/capability/audience.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/floating_bottom_nav_bar.dart';
import 'package:cupola/core/widgets/floating_nav_rail.dart';
import 'package:cupola/features/settings/domain/nav_tab.dart';

/// The phone's bar on its side, as a tablet draws it.
void main() {
  List<FloatingNavDestination> destinationsOf(
    Audience audience, {
    int activity = 0,
  }) => [
    for (final tab in NavTab.barFor(audience))
      FloatingNavDestination(
        icon: tab.icon,
        selectedIcon: tab.selectedIcon,
        label: tab.label,
        badgeCount: tab == NavTab.activity ? activity : 0,
        badgeSemanticLabel: tab == NavTab.activity && activity > 0
            ? '$activity finished searches to look at'
            : null,
      ),
  ];

  Future<void> pump(
    WidgetTester tester, {
    Audience audience = Audience.operator,
    int selected = 0,
    int activity = 0,
    double textScale = 1,
    ValueChanged<int>? onSelected,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme(),
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
          child: Scaffold(
            body: Align(
              alignment: Alignment.centerLeft,
              child: FloatingNavRail(
                destinations: destinationsOf(audience, activity: activity),
                selectedIndex: selected,
                onDestinationSelected: onSelected ?? (_) {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder surface() => find.byKey(const ValueKey('floating-nav-rail-surface'));

  testWidgets('each section is its glyph over its name, in the bar\'s '
      'order', (tester) async {
    await pump(tester);

    final tops = [
      for (final tab in NavTab.barFor(Audience.operator))
        tester.getTopLeft(find.text(tab.label)).dy,
    ];
    expect(tops, orderedEquals([...tops]..sort()));
    for (final tab in NavTab.barFor(Audience.operator)) {
      final glyph = tester.getCenter(
        find.byWidgetPredicate(
          (w) =>
              w is Icon && (w.icon == tab.icon || w.icon == tab.selectedIcon),
        ),
      );
      expect(
        glyph.dy,
        lessThan(tester.getTopLeft(find.text(tab.label)).dy),
        reason: tab.label,
      );
    }
  });

  testWidgets('the requester\'s rail is her three sections', (tester) async {
    await pump(tester, audience: Audience.requester, selected: 2);

    expect(find.text('Requests'), findsOne);
    expect(find.text('Activity'), findsNothing);
    expect(find.text('Stack'), findsNothing);
  });

  testWidgets('at least the 60pt disc and its glass, wider as the names '
      'grow', (tester) async {
    // 72pt in the app's faces; the test face draws every glyph a full em
    // wide, so here the longest name already widens it.
    await pump(tester);
    final normal = tester.getSize(surface()).width;
    expect(normal, greaterThanOrEqualTo(72));

    await pump(tester, textScale: 2);
    final wide = tester.getSize(surface()).width;
    expect(wide, greaterThan(normal));
    // Every name still fits on its one line.
    expect(tester.takeException(), isNull);
  });

  testWidgets('the lit section is the one selected, and a tap reports its '
      'place', (tester) async {
    final handle = tester.ensureSemantics();
    final taps = <int>[];
    await pump(tester, selected: 1, onSelected: taps.add);

    expect(
      tester.getSemantics(find.bySemanticsLabel(RegExp(r'^Discover\n'))),
      matchesSemantics(
        label: 'Discover\nTab 2 of 4',
        isButton: true,
        isSelected: true,
        hasSelectedState: true,
        isEnabled: true,
        hasEnabledState: true,
        hasTapAction: true,
      ),
    );
    await tester.tap(find.text('Stack'));
    await tester.tap(find.text('Home'));
    expect(taps, [3, 0]);
    handle.dispose();
  });

  testWidgets('a count is drawn in ink and spoken with its section', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pump(tester, activity: 12);

    expect(
      find.descendant(
        of: find.byKey(const ValueKey('floating-nav-badge')),
        matching: find.text('9+'),
      ),
      findsOne,
    );
    expect(
      find.bySemanticsLabel(
        'Activity, 12 finished searches to look at\nTab 3 of 4',
      ),
      findsOne,
    );
    handle.dispose();
  });

  testWidgets('in Settings no section is lit', (tester) async {
    await pump(tester, selected: -1);

    expect(
      find.byKey(const ValueKey('floating-nav-rail-indicator')),
      findsNothing,
    );
  });
}
