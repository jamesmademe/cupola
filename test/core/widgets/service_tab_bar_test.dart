import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/service_tab_bar.dart';
import 'package:cupola/features/services/domain/service_tab.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

void main() {
  Future<List<ServiceTab>> pump(
    WidgetTester tester, {
    ServiceKey service = ServiceKey.radarr,
    ServiceTab current = ServiceTab.overview,
    Size size = const Size(390, 844),
  }) async {
    final taps = <ServiceTab>[];
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme(),
        home: Scaffold(
          body: ServiceTabBar(
            service: service,
            current: current,
            onSelected: taps.add,
          ),
        ),
      ),
    );
    return taps;
  }

  group('ServiceTabBar', () {
    testWidgets('a page opened on a tab past the edge brings it into view', (
      tester,
    ) async {
      await pump(
        tester,
        service: ServiceKey.bazarr,
        current: ServiceTab.providers,
      );
      await tester.pumpAndSettle();

      final tab = tester.getRect(find.text('Providers'));
      expect(tab.right, lessThanOrEqualTo(390));
      expect(tab.left, greaterThanOrEqualTo(0));
    });

    testWidgets('draws the service\'s own bar, in order', (tester) async {
      await pump(tester, size: const Size(1440, 900));

      for (final tab in tabsFor(ServiceKey.radarr)!) {
        expect(find.text(tab.label), findsOneWidget, reason: tab.name);
      }
      // A tab belonging to a different service is not on this bar.
      expect(find.text(ServiceTab.rss.label), findsNothing);
    });

    testWidgets('TrueNAS draws nothing, not an empty strip', (tester) async {
      // Ten sections are too many for a bar, so TrueNAS keeps its console. An
      // empty bar would read as tabs that failed to load, which is a different
      // fact and a worse one.
      await pump(tester, service: ServiceKey.truenas);

      expect(find.byType(ListView), findsNothing);
      expect(tester.getSize(find.byType(ServiceTabBar)).height, 0);
    });

    testWidgets('the selected tab is selected to a screen reader', (
      tester,
    ) async {
      await pump(tester, current: ServiceTab.library);

      final handle = tester.ensureSemantics();
      expect(
        tester.getSemantics(find.text(ServiceTab.library.label)),
        matchesSemantics(
          label: 'Library',
          isSelected: true,
          isButton: true,
          hasSelectedState: true,
        ),
      );
      handle.dispose();
    });

    testWidgets('tapping another tab reports it; tapping the current one does '
        'nothing', (tester) async {
      final taps = await pump(tester, current: ServiceTab.overview);

      await tester.tap(find.text(ServiceTab.library.label));
      await tester.pump();
      expect(taps, [ServiceTab.library]);

      // Re-selecting is not navigation. Letting it through would push an
      // identical location and give the back gesture a step that goes nowhere.
      await tester.tap(find.text(ServiceTab.overview.label));
      await tester.pump();
      expect(taps, [ServiceTab.library]);
    });

    testWidgets('a narrow frame scrolls the bar rather than squeezing it', (
      tester,
    ) async {
      // Eight of the sixteen label sets are wider than the narrowest frame the
      // app draws. A bar that distributed its tabs would shrink the labels
      // instead, which is the one thing the width is not allowed to change.
      await pump(
        tester,
        service: ServiceKey.unraid,
        size: const Size(320, 700),
      );

      final scrollable = tester.widget<SingleChildScrollView>(
        find.byType(SingleChildScrollView),
      );
      expect(scrollable.scrollDirection, Axis.horizontal);

      // Every tab is built even when it is off-screen, so a screen reader can
      // reach the whole bar without scrolling it.
      for (final tab in tabsFor(ServiceKey.unraid)!) {
        expect(find.text(tab.label), findsOneWidget, reason: tab.name);
      }

      // And the row really is wider than the frame; otherwise this test would
      // pass on a bar that squeezed its labels to fit.
      expect(tester.getSize(find.byType(Row).first).width, greaterThan(320));
    });

    testWidgets('every tab clears the touch target floor', (tester) async {
      await pump(tester, size: const Size(1440, 900));

      for (final tab in tabsFor(ServiceKey.radarr)!) {
        final size = tester.getSize(
          find.ancestor(
            of: find.text(tab.label),
            matching: find.byType(InkWell),
          ),
        );
        expect(size.height, greaterThanOrEqualTo(44), reason: tab.name);
        expect(size.width, greaterThanOrEqualTo(44), reason: tab.name);
      }
    });
  });
}
