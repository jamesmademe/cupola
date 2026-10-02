import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/floating_bottom_nav_bar.dart';

void main() {
  group('FloatingBottomNavBar', () {
    testWidgets('shows only the selected label in the compact nav pill', (
      tester,
    ) async {
      await _pumpNavBar(tester, selectedIndex: 0);

      expect(find.text('Services'), findsOneWidget);
      expect(find.text('Activity'), findsNothing);
      expect(find.text('Search'), findsNothing);
      expect(find.text('Settings'), findsNothing);
    });

    group('semantics', () {
      // Unselected destinations render no text at all, so `label:` on the
      // Semantics is the only thing naming them. This group is what stops that
      // wiring being deleted as dead code.
      testWidgets('each destination is a button naming its tab position', (
        tester,
      ) async {
        await _pumpNavBar(tester, selectedIndex: 0);

        expect(
          tester.getSemantics(_navItem('Services')),
          containsSemantics(
            label: 'Services\nTab 1 of 4',
            isButton: true,
            hasTapAction: true,
            hasSelectedState: true,
            isSelected: true,
          ),
        );

        // Parity with NavigationRail, which the shell uses above 840dp and which
        // appends this itself — the same app was saying two different things
        // about the same navigation.
        expect(
          tester.getSemantics(_navItem('Search')),
          containsSemantics(label: 'Search\nTab 3 of 4', isButton: true),
        );
      });

      testWidgets('an unselected destination still declares selected state', (
        tester,
      ) async {
        await _pumpNavBar(tester, selectedIndex: 0);

        // The case `selected: isSelected ? true : null` would silently break:
        // without hasSelectedState the reader cannot say "not selected".
        expect(
          tester.getSemantics(_navItem('Activity')),
          containsSemantics(hasSelectedState: true, isSelected: false),
        );
      });
    });

    testWidgets('the chrome is monochrome: ink on the strong fill', (
      tester,
    ) async {
      // Principle 3 of the brand book: the selected destination is the room's strong fill
      // under the primary ink, the rest the secondary ink, and no section
      // carries a colour of its own — so the same pill is drawn whichever tab
      // is selected.
      final scheme = AppTheme.darkTheme().colorScheme;
      for (final (index, selected, unselected) in const [
        (1, Icons.bolt_rounded, Icons.view_list_outlined),
        (3, Icons.settings_rounded, Icons.search_outlined),
      ]) {
        await _pumpNavBar(tester, selectedIndex: index);

        expect(
          tester.widget<Icon>(find.byIcon(selected)).color,
          scheme.onSurface,
        );
        expect(
          tester.widget<Icon>(find.byIcon(unselected)).color,
          scheme.onSurfaceVariant,
        );
        final pill = tester.widget<DecoratedBox>(
          find.byKey(const ValueKey('floating-nav-indicator')),
        );
        final decoration = pill.decoration as BoxDecoration;
        expect(decoration.color, CupolaRoom.dark.fillStrong);
        expect(decoration.border, isNull, reason: 'no accent edge');
      }
    });

    testWidgets('slides the selected pill between destinations', (
      tester,
    ) async {
      _setTestViewport(tester, const Size(390, 844));

      await _pumpNavBar(tester, selectedIndex: 0);

      final startRect = _indicatorRect(tester);
      final startLeft = startRect.left;

      await _pumpNavBar(tester, selectedIndex: 2, settle: false);
      await tester.pump(const Duration(milliseconds: 80));

      final midLeft = _indicatorRect(tester).left;

      expect(midLeft, greaterThan(startLeft));

      await tester.pumpAndSettle();

      final endRect = _indicatorRect(tester);
      final searchRect = _itemRect(tester, 'search');
      expect(midLeft, lessThan(endRect.left));
      expect(startRect.width, greaterThan(endRect.width));
      expect(endRect.center.dx, closeTo(searchRect.center.dx, 0.5));
      expect(endRect.left, greaterThanOrEqualTo(searchRect.left - 0.5));
      expect(endRect.right, lessThanOrEqualTo(searchRect.right + 0.5));
    });

    testWidgets(
      'uses a compact centered navbar and aligns edge selections on iPhone widths',
      (tester) async {
        _setTestViewport(tester, const Size(390, 844));

        await _pumpNavBar(tester, selectedIndex: 0);

        expect(tester.takeException(), isNull);

        final servicesRect = _itemRect(tester, 'services');
        final activityRect = _itemRect(tester, 'activity');
        final searchRect = _itemRect(tester, 'search');
        final settingsRect = _itemRect(tester, 'settings');
        final servicesIndicatorRect = _indicatorRect(tester);
        final navSurfaceRect = _navSurfaceRect(tester);
        final maxSurfaceWidth = 390.0 - (AppSpacing.lg * 2);

        expect(navSurfaceRect.width, lessThan(maxSurfaceWidth));
        expect(navSurfaceRect.center.dx, closeTo(195.0, 0.5));
        expect(servicesRect.width, greaterThan(activityRect.width));
        expect(servicesRect.width, greaterThan(searchRect.width));
        expect(servicesRect.width, greaterThan(settingsRect.width));
        expect(activityRect.width, closeTo(searchRect.width, 0.5));
        expect(
          servicesIndicatorRect.center.dx,
          closeTo(servicesRect.center.dx, 0.5),
        );
        expect(
          servicesIndicatorRect.width,
          lessThanOrEqualTo(servicesRect.width + 0.5),
        );
        expect(
          servicesIndicatorRect.left,
          greaterThanOrEqualTo(servicesRect.left - 0.5),
        );
        expect(
          servicesIndicatorRect.right,
          lessThanOrEqualTo(servicesRect.right + 0.5),
        );

        await _pumpNavBar(tester, selectedIndex: 3);

        expect(tester.takeException(), isNull);

        final selectedSettingsRect = _itemRect(tester, 'settings');
        final settingsIndicatorRect = _indicatorRect(tester);
        final updatedNavSurfaceRect = _navSurfaceRect(tester);

        expect(
          selectedSettingsRect.width,
          greaterThan(_itemRect(tester, 'search').width),
        );
        expect(updatedNavSurfaceRect.width, closeTo(navSurfaceRect.width, 0.5));
        expect(
          updatedNavSurfaceRect.center.dx,
          closeTo(navSurfaceRect.center.dx, 0.5),
        );
        expect(
          settingsIndicatorRect.center.dx,
          closeTo(selectedSettingsRect.center.dx, 0.5),
        );
        expect(
          settingsIndicatorRect.width,
          lessThanOrEqualTo(selectedSettingsRect.width + 0.5),
        );
        expect(
          settingsIndicatorRect.left,
          greaterThanOrEqualTo(selectedSettingsRect.left - 0.5),
        );
        expect(
          settingsIndicatorRect.right,
          lessThanOrEqualTo(selectedSettingsRect.right + 0.5),
        );
      },
    );

    testWidgets('stays anchored near the bottom of the viewport', (
      tester,
    ) async {
      _setTestViewport(tester, const Size(390, 844));

      await _pumpNavBar(tester, selectedIndex: 0);

      final navSurfaceRect = _navSurfaceRect(tester);
      final distanceFromBottom = 844.0 - navSurfaceRect.bottom;

      expect(distanceFromBottom, greaterThanOrEqualTo(0));
      expect(
        distanceFromBottom,
        lessThanOrEqualTo(
          FloatingNavBarMetrics.bottomPadding +
              MediaQueryData.fromView(tester.view).padding.bottom +
              12,
        ),
      );
      expect(navSurfaceRect.center.dy, greaterThan(700));
    });

    testWidgets('applies elastic drag and springs back to rest', (
      tester,
    ) async {
      await _pumpNavBar(tester, selectedIndex: 0);

      final gesture = await tester.startGesture(
        tester.getCenter(
          find.byKey(const ValueKey('floating-nav-drag-transform')),
        ),
      );
      await gesture.moveBy(const Offset(40, 20));
      await tester.pump();
      await gesture.moveBy(const Offset(40, 20));
      await tester.pump();

      final dragged = _dragTransform(tester).transform.getTranslation();
      expect(dragged.x, greaterThan(0));
      expect(dragged.x, lessThan(40));
      expect(dragged.x, lessThanOrEqualTo(15));
      expect(dragged.y, greaterThan(0));
      expect(dragged.y, lessThan(20));
      expect(dragged.y, lessThanOrEqualTo(15));

      await gesture.up();
      await tester.pumpAndSettle();

      final settled = _dragTransform(tester).transform.getTranslation();
      expect(settled.x, closeTo(0, 0.01));
      expect(settled.y, closeTo(0, 0.01));
    });

    // Regression guard for the QA finding: the pill width was measured with a
    // TextPainter that got no textScaler, so at accessibility reading sizes the
    // label overflowed the bar on every screen of the app.
    group('text scaling', () {
      for (final scale in const [1.0, 1.3, 2.0, 3.0]) {
        testWidgets('lays out without overflow at ${scale}x', (tester) async {
          _setTestViewport(tester, const Size(390, 844));
          await _pumpNavBar(tester, selectedIndex: 1, textScale: scale);

          expect(tester.takeException(), isNull);

          // The selected label must fit inside the glass surface.
          final surface = _navSurfaceRect(tester);
          final label = tester.getRect(find.text('Activity'));
          expect(label.left, greaterThanOrEqualTo(surface.left - 0.01));
          expect(label.right, lessThanOrEqualTo(surface.right + 0.01));
          expect(label.top, greaterThanOrEqualTo(surface.top - 0.01));
          expect(label.bottom, lessThanOrEqualTo(surface.bottom + 0.01));

          // …and the bar must stay inside the viewport.
          expect(surface.left, greaterThanOrEqualTo(-0.01));
          expect(surface.right, lessThanOrEqualTo(390.01));
        });
      }

      testWidgets('the label grows but the bar stays a bar', (tester) async {
        _setTestViewport(tester, const Size(390, 844));

        await _pumpNavBar(tester, selectedIndex: 0, textScale: 1.0);
        final baseHeight = _navSurfaceRect(tester).height;
        final baseLabel = tester.getRect(find.text('Services')).height;

        await _pumpNavBar(tester, selectedIndex: 0, textScale: 3.0);
        final cappedHeight = _navSurfaceRect(tester).height;
        final cappedLabel = tester.getRect(find.text('Services')).height;

        // The reading preference is honoured up to maxTextScaleFactor…
        expect(cappedLabel, greaterThan(baseLabel));
        expect(
          cappedLabel / baseLabel,
          lessThanOrEqualTo(FloatingNavBarMetrics.maxTextScaleFactor + 0.05),
        );
        // …and the clamped label still fits the existing bar height, so the
        // chrome does not turn into a panel.
        expect(cappedHeight, closeTo(baseHeight, 0.01));
        expect(cappedHeight, lessThan(844 / 4));
      });

      testWidgets('scroll padding covers the bar at every scale', (
        tester,
      ) async {
        _setTestViewport(tester, const Size(390, 844));

        for (final scale in const [1.0, 1.3, 3.0]) {
          late double padding;
          late double barHeight;
          await tester.pumpWidget(
            MaterialApp(
              home: MediaQuery(
                data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                child: Builder(
                  builder: (context) {
                    padding = FloatingNavBarMetrics.getScrollViewBottomPadding(
                      context,
                    );
                    barHeight = FloatingNavBarMetrics.barHeightFor(context);
                    return const SizedBox.shrink();
                  },
                ),
              ),
            ),
          );

          // Content must always clear the bar plus its margins, otherwise the
          // last list row hides underneath it.
          expect(
            padding,
            greaterThanOrEqualTo(
              barHeight +
                  FloatingNavBarMetrics.topPadding +
                  FloatingNavBarMetrics.bottomPadding,
            ),
            reason: 'scale $scale',
          );
        }
      });
    });

    group('badge', () {
      Future<void> pumpBadged(
        WidgetTester tester, {
        required int selectedIndex,
        required int count,
        double textScale = 1.0,
      }) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(textScale)),
              child: child!,
            ),
            home: Scaffold(
              bottomNavigationBar: FloatingBottomNavBar(
                selectedIndex: selectedIndex,
                onDestinationSelected: (_) {},
                destinations: [
                  const FloatingNavDestination(
                    icon: Icons.view_list_outlined,
                    selectedIcon: Icons.view_list_rounded,
                    label: 'Dashboard',
                  ),
                  FloatingNavDestination(
                    icon: Icons.bolt_outlined,
                    selectedIcon: Icons.bolt_rounded,
                    label: 'Activity',
                    badgeCount: count,
                  ),
                  const FloatingNavDestination(
                    icon: Icons.search_outlined,
                    selectedIcon: Icons.search_rounded,
                    label: 'Search',
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      Finder badge() => find.byKey(const ValueKey('floating-nav-badge'));

      // A fixed 15pt box squeezed the numeral's line box to 12pt while the
      // glyph asked for 22pt at 2x: the count was drawn clipped to a sliver.
      testWidgets('the count is never squeezed below its own line height', (
        tester,
      ) async {
        for (final scale in [1.0, 1.3, 2.0, 3.0]) {
          for (final count in [3, 12]) {
            await pumpBadged(
              tester,
              selectedIndex: 2,
              count: count,
              textScale: scale,
            );
            final paragraph = tester.renderObject<RenderParagraph>(
              find.descendant(of: badge(), matching: find.byType(RichText)),
            );
            final wanted = paragraph.getMaxIntrinsicHeight(double.infinity);
            expect(
              paragraph.size.height,
              greaterThanOrEqualTo(wanted - 0.01),
              reason: 'count $count at ${scale}x',
            );
            // And it grows only as far as the bar's own clamp.
            final labelSmall = AppTheme.lightTheme().textTheme.labelSmall!;
            expect(
              wanted,
              lessThanOrEqualTo(
                labelSmall.fontSize! *
                        FloatingNavBarMetrics.maxTextScaleFactor +
                    0.01,
              ),
              reason: 'count $count at ${scale}x',
            );
          }
        }
      });

      testWidgets('the selected label keeps clear of the badge', (
        tester,
      ) async {
        for (final scale in [1.0, 1.3, 2.0]) {
          await pumpBadged(
            tester,
            selectedIndex: 1,
            count: 3,
            textScale: scale,
          );
          final badgeRect = tester.getRect(badge());
          final labelRect = tester.getRect(find.text('Activity'));
          expect(
            labelRect.left - badgeRect.right,
            greaterThanOrEqualTo(4),
            reason: 'at ${scale}x the badge ring touched the label',
          );
        }
      });

      testWidgets('the badge is the ink disc with the on-ink numeral', (
        tester,
      ) async {
        // Never a status tone and never a section's colour: permanent chrome
        // that turned green or amber would read as stack health.
        await pumpBadged(tester, selectedIndex: 0, count: 3);
        final scheme = AppTheme.lightTheme().colorScheme;
        final disc = tester.widget<Container>(badge());
        expect((disc.decoration! as BoxDecoration).color, scheme.primary);
        final numeral = tester.widget<Text>(
          find.descendant(of: badge(), matching: find.text('3')),
        );
        expect(numeral.style!.color, scheme.onPrimary);
      });

      testWidgets('past nine the badge reads 9+', (tester) async {
        await pumpBadged(tester, selectedIndex: 0, count: 12);
        expect(
          find.descendant(of: badge(), matching: find.text('9+')),
          findsOneWidget,
        );
      });
    });
  });
}

Future<void> _pumpNavBar(
  WidgetTester tester, {
  required int selectedIndex,
  bool settle = true,
  double textScale = 1.0,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.darkTheme(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        bottomNavigationBar: FloatingBottomNavBar(
          selectedIndex: selectedIndex,
          onDestinationSelected: (_) {},
          destinations: const [
            FloatingNavDestination(
              icon: Icons.view_list_outlined,
              selectedIcon: Icons.view_list_rounded,
              label: 'Services',
            ),
            FloatingNavDestination(
              icon: Icons.bolt_outlined,
              selectedIcon: Icons.bolt_rounded,
              label: 'Activity',
            ),
            FloatingNavDestination(
              icon: Icons.search_outlined,
              selectedIcon: Icons.search_rounded,
              label: 'Search',
            ),
            FloatingNavDestination(
              icon: Icons.settings_outlined,
              selectedIcon: Icons.settings_rounded,
              label: 'Settings',
            ),
          ],
        ),
      ),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  }
}

/// The key sits on the `Semantics` itself, so `getSemantics` resolves that node
/// rather than walking up past it to an ancestor.
Finder _navItem(String label) =>
    find.byKey(ValueKey('floating-nav-item-${label.toLowerCase()}'));

void _setTestViewport(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Transform _dragTransform(WidgetTester tester) {
  return tester.widget<Transform>(
    find.byKey(const ValueKey('floating-nav-drag-transform')),
  );
}

Rect _indicatorRect(WidgetTester tester) {
  return tester.getRect(find.byKey(const ValueKey('floating-nav-indicator')));
}

Rect _navSurfaceRect(WidgetTester tester) {
  return tester.getRect(find.byKey(const ValueKey('floating-nav-surface')));
}

Rect _itemRect(WidgetTester tester, String label) {
  return tester.getRect(find.byKey(ValueKey('floating-nav-item-$label')));
}
