/// The tab tapped again, on a phone: deep in the tab, its root; at the root
/// and scrolled down, the top; at the top, the page read again. No page
/// listens for it: the shell scrolls the route's primary list.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/providers/navigation_refresh_provider.dart';
import 'package:cupola/core/router.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/core/widgets/floating_bottom_nav_bar.dart';
import 'package:cupola/features/discover/domain/discover_index.dart';

import '../../../test_helpers/profiles/profiles.dart';

void main() {
  Future<(ProfileHarness, ProviderContainer)> start(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(top: 47, bottom: 34);
    addTearDown(tester.view.reset);
    final harness = await ProfileHarness.start(Profiles.p1);
    harness.network.followFakeTime(tester.binding);
    final container = ProviderContainer(overrides: harness.overrides);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          theme: AppTheme.darkTheme(),
          routerConfig: container.read(routerProvider),
        ),
      ),
    );
    await harness.settle(tester);
    container.read(routerProvider).go(ServiceRoutes.home);
    await harness.settle(tester);
    return (harness, container);
  }

  Future<void> close(
    WidgetTester tester,
    ProfileHarness harness,
    ProviderContainer container,
  ) async {
    await harness.unmount(tester);
    container.dispose();
    await tester.pump(const Duration(seconds: 1));
  }

  Finder tab(String label) => find.descendant(
    of: find.byType(FloatingBottomNavBar),
    matching: find.text(label),
  );

  /// The page's own list: the tallest vertical one of the tab on screen
  /// (the tabs behind it are muted).
  ScrollPosition pageList(WidgetTester tester) {
    final lists = [
      for (final element in find.byType(Scrollable).evaluate())
        if ((element as StatefulElement).state case final ScrollableState state
            when state.position.axis == Axis.vertical && TickerMode.of(element))
          state,
    ];
    lists.sort(
      (a, b) => b.context.size!.height.compareTo(a.context.size!.height),
    );
    return lists.first.position;
  }

  testWidgets('scrolled down, the Home goes back to its top; at the top, it '
      'reads again', (tester) async {
    final (harness, container) = await start(tester);
    final refreshes = container.read(
      navigationRefreshProvider(NavigationSection.home).notifier,
    );

    pageList(tester).jumpTo(600);
    await tester.pump();
    await tester.tap(tab('Home'));
    await harness.settle(tester);
    expect(pageList(tester).pixels, 0);
    expect(refreshes.state, 0);

    await tester.tap(tab('Home'));
    await harness.settle(tester);
    expect(refreshes.state, 1);

    await close(tester, harness, container);
  });

  testWidgets('an index of Discover goes back to the lobby, then its top', (
    tester,
  ) async {
    final (harness, container) = await start(tester);
    final router = container.read(routerProvider);
    router.go(ServiceRoutes.discover);
    await harness.settle(tester);
    router.push(ServiceRoutes.discoverIndex(DiscoverIndex.genres));
    await harness.settle(tester);

    await tester.tap(tab('Discover'));
    await harness.settle(tester);
    expect(router.state.uri.path, ServiceRoutes.discover);

    pageList(tester).jumpTo(400);
    await tester.pump();
    await tester.tap(tab('Discover'));
    await harness.settle(tester);
    expect(pageList(tester).pixels, 0);

    await close(tester, harness, container);
  });
}
