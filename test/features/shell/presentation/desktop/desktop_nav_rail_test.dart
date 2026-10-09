import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/capability/audience.dart';
import 'package:cupola/core/status/media_status.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/floating_bottom_nav_bar.dart';
import 'package:cupola/features/settings/domain/nav_tab.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
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
    bool compact = true,
    List<DesktopRailService> services = const [],
    ServiceKey? selectedService,
    ValueChanged<ServiceKey>? onService,
    double height = 480,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme(),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              height: height,
              child: DesktopNavRail(
                compact: compact,
                services: services,
                selectedService: selectedService,
                onService: onService,
                selectedIndex: settingsSelected
                    ? -1
                    : bar.indexOf(NavTab.activity),
                onDestinationSelected: onDestinationSelected ?? (_) {},
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

  group('the full sidebar', () {
    Finder item(String spoken) => find.bySemanticsLabel(spoken);

    const services = <DesktopRailService>[
      (
        service: ServiceKey.seerr,
        tone: StatusTone.info,
        state: '2 requests wait for approval',
      ),
      (service: ServiceKey.radarr, tone: null, state: null),
      (service: ServiceKey.sonarr, tone: StatusTone.warning, state: 'a fault'),
      (
        service: ServiceKey.truenas,
        tone: StatusTone.error,
        state: 'did not answer',
      ),
    ];

    testWidgets('names each section with its key, then the services, then '
        'Settings', (tester) async {
      await pumpRail(tester, compact: false, services: services, height: 800);

      expect(
        tester.getSize(find.byType(DesktopNavRail)).width,
        DesktopNavRail.fullWidth,
      );
      for (final (index, tab) in bar.indexed) {
        expect(find.text(tab.label), findsOne, reason: tab.label);
        expect(find.text(ShellShortcuts.section(index)), findsOne);
      }
      expect(find.text('Services'), findsOne);
      expect(find.text(ShellShortcuts.settings), findsOne);
      final stack = tester.getTopLeft(find.text('Stack')).dy;
      final heading = tester.getTopLeft(find.text('Services')).dy;
      final seerr = tester.getTopLeft(find.text('Seerr')).dy;
      final settings = tester.getTopLeft(find.text('Settings')).dy;
      expect(stack < heading && heading < seerr && seerr < settings, isTrue);
      // The deck carries its own key; the sidebar does not repeat it.
      expect(find.text(ShellShortcuts.commandDeck), findsNothing);
    });

    testWidgets('a light only where a service needs a look, and it says so', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpRail(tester, compact: false, services: services, height: 800);

      Finder light(String title) =>
          find.byKey(ValueKey('desktop-rail-light-$title'));
      expect(light('Seerr'), findsOne);
      expect(light('Sonarr'), findsOne);
      expect(light('TrueNAS'), findsOne);
      expect(light('Radarr'), findsNothing);
      expect(item('Seerr, 2 requests wait for approval'), findsOne);
      expect(item('Sonarr, a fault'), findsOne);
      expect(item('TrueNAS, did not answer'), findsOne);
      expect(item('Radarr'), findsOne);
      handle.dispose();
    });

    testWidgets('a service opens its room, and lights in Stack\'s place', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final opened = <ServiceKey>[];
      await pumpRail(
        tester,
        compact: false,
        services: services,
        selectedService: ServiceKey.sonarr,
        onService: opened.add,
        height: 800,
      );

      await tester.tap(find.text('Radarr'));
      expect(opened, [ServiceKey.radarr]);
      expect(
        tester.getSemantics(item('Sonarr, a fault')),
        matchesSemantics(
          isButton: true,
          isSelected: true,
          hasSelectedState: true,
          isEnabled: true,
          hasEnabledState: true,
          hasTapAction: true,
          label: 'Sonarr, a fault',
        ),
      );
      // Activity is the bar's selection here; in a room it gives way.
      expect(
        tester.getSemantics(item('Activity')),
        isNot(matchesSemantics(isSelected: true)),
      );
      handle.dispose();
    });

    testWidgets('the requester\'s sidebar has no services', (tester) async {
      await pumpRail(tester, compact: false, height: 800);

      expect(find.text('Services'), findsNothing);
      expect(find.text('Settings'), findsOne);
    });

    testWidgets('folded, it keeps the sections and Settings and no service', (
      tester,
    ) async {
      await pumpRail(tester, services: services, height: 800);

      expect(
        tester.getSize(find.byType(DesktopNavRail)).width,
        DesktopNavRail.compactWidth,
      );
      expect(find.text('Services'), findsNothing);
      expect(find.text('Seerr'), findsNothing);
      expect(railItem('Settings'), findsOne);
    });
  });

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
      // Settings is no section: the rail has five buttons.
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
