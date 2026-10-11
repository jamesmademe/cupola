/// Every page the phone's bar floats over ends above it: scrolled to its
/// end, a page's last line sits clear of the bar's glass, and not a bar's
/// height above it.
///
/// The shell's `Scaffold(extendBody: true)` lays every page under the bar and
/// hands it the bar's height in `MediaQuery.padding.bottom`; a page reserves
/// it through `FloatingNavBarMetrics.getScrollViewBottomPadding`. A page that
/// passes its own padding instead ends under the glass (Needs you, 11/10),
/// and a page that adds the bar twice ends a bar's height short of it. Both
/// are a number in one build method, invisible in review, so this reads the
/// pages as the phone draws them.
library;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/router.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/core/widgets/floating_bottom_nav_bar.dart';
import 'package:cupola/features/media/domain/media_key.dart';
import 'package:cupola/features/services/domain/service_tab.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import '../../test_helpers/profiles/profiles.dart';

/// A 6.1" phone: the bar and the home indicator under it.
const _phone = Size(390, 844);
const _homeIndicator = 34.0;

/// The most a page's last line may stand above the glass: the row's own
/// padding and the page's breathing room, never another bar.
const _mostAbove = 80.0;

List<String> _locations(ConfigProfile profile) => [
  ServiceRoutes.home,
  ServiceRoutes.discover,
  ServiceRoutes.activity,
  ServiceRoutes.activityNeedsYou,
  ServiceRoutes.activityRequests,
  ServiceRoutes.activityHistory,
  ServiceRoutes.activityBlocklist,
  ServiceRoutes.stack,
  // A title's page, opened from the Home: a movie on the server, a series.
  ServiceRoutes.media(
    MediaKey.movie(WorldTitles.sintel.tmdbId),
    from: ServiceRoutes.home,
  ),
  ServiceRoutes.media(
    MediaKey.tv(WorldTitles.cosmosLaundromat.tmdbId),
    from: ServiceRoutes.home,
  ),
  for (final service in ServiceKey.values)
    if (profile.settings.isServiceConfigured(service))
      if (tabsFor(service) case final tabs?)
        for (final tab in tabs)
          '${ServiceRoutes.forService(service)}/${tab.segment}',
];

/// A page's last line: where it ends, what it says, the page it is on, and
/// whether its list is longer than its frame (only then does it end where
/// the list's padding says).
typedef _Last = ({double bottom, String text, String? page, bool overflows});

/// The vertical lists on screen that scroll.
List<ScrollableState> _lists() => [
  for (final element
      in find
          .byWidgetPredicate(
            (widget) =>
                widget is Scrollable &&
                axisDirectionToAxis(widget.axisDirection) == Axis.vertical,
          )
          .hitTestable()
          .evaluate())
    if ((element as StatefulElement).state case final ScrollableState state
        when state.position.maxScrollExtent > 0)
      state,
];

/// Where the page's last line ends once every list on it is scrolled to its
/// end, or null when nothing on it scrolls.
///
/// Every list, not the outer one alone: a `NestedScrollView` reaches the end
/// of its body only once its inner list is scrolled too. A line is read where
/// its list clips it, so a page whose list stops above the bar is not one
/// that ends under it.
Future<_Last?> _lastLine(WidgetTester tester, ProfileHarness harness) async {
  if (_lists().isEmpty) return null;
  // A list that builds lazily, or reads a next page at its end, grows as it
  // is scrolled: jump until every end stays put.
  for (var round = 0; round < 8; round++) {
    var moved = false;
    for (final list in _lists()) {
      final end = list.position.maxScrollExtent;
      if (list.position.pixels != end) {
        list.position.jumpTo(end);
        moved = true;
      }
    }
    await harness.settle(tester);
    if (!moved) break;
  }

  final lists = _lists();
  if (lists.isEmpty) return null;
  final page = lists.reduce((a, b) {
    final sa = a.context.size!, sb = b.context.size!;
    return sa.width * sa.height >= sb.width * sb.height ? a : b;
  });
  String? owner;
  page.context.visitAncestorElements((element) {
    final name = element.widget.runtimeType.toString();
    if (RegExp(r'(Screen|Page|Tab)$').hasMatch(name) &&
        !name.startsWith('_') &&
        !name.contains('Scroll')) {
      owner = name;
      return false;
    }
    return true;
  });

  _Last? last;
  void visit(RenderObject child) {
    // Words, pictures and the cards and pills that hold them: what a page
    // shows, not the boxes that lay it out.
    final shows =
        child is RenderParagraph ||
        child is RenderImage ||
        (child is RenderDecoratedBox &&
            child.hasSize &&
            child.size.height < _phone.height / 2);
    if (shows && child is RenderBox && child.hasSize && child.attached) {
      var rect = child.localToGlobal(Offset.zero) & child.size;
      // Clipped by every list it sits in, the carousels' too.
      RenderObject? clip = child;
      RenderViewportBase? list;
      while ((clip = RenderAbstractViewport.maybeOf(clip?.parent)) != null) {
        final box = clip! as RenderBox;
        rect = rect.intersect(box.localToGlobal(Offset.zero) & box.size);
        if (box is RenderViewportBase && box.axis == Axis.vertical) {
          list ??= box;
        }
      }
      if (rect.height > 0 &&
          rect.width > 0 &&
          rect.bottom > (last?.bottom ?? double.negativeInfinity)) {
        final offset = list?.offset;
        last = (
          bottom: rect.bottom,
          text: child is RenderParagraph
              ? child.text.toPlainText()
              : '${child.runtimeType}',
          page: owner,
          overflows: offset is ScrollPosition && offset.maxScrollExtent > 0,
        );
      }
    }
    child.visitChildren(visit);
  }

  (page.context.findRenderObject()!).visitChildren(visit);
  return last;
}

void main() {
  testWidgets('P1: every page ends above the bar, and right above it', (
    tester,
  ) async {
    tester.view.physicalSize = _phone;
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(
      top: 47,
      bottom: _homeIndicator,
    );
    addTearDown(tester.view.reset);

    final profile = Profiles.p1;
    final harness = await ProfileHarness.start(profile);
    harness.network.followFakeTime(tester.binding);
    // Closed by the test itself: the pages' own polls stop with it, before
    // the binding checks for timers.
    final container = ProviderContainer(overrides: harness.overrides);
    final router = container.read(routerProvider);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          theme: AppTheme.darkTheme(),
          routerConfig: router,
        ),
      ),
    );
    await harness.settle(tester);

    final under = <String>[];
    final short = <String>[];
    final read = <String>[];
    for (final location in _locations(profile)) {
      router.go(location);
      await harness.settle(tester);
      final bar = find.byType(FloatingBottomNavBar);
      if (bar.evaluate().isEmpty) continue;
      final glass = tester.getRect(bar).top + FloatingNavBarMetrics.topPadding;
      final last = await _lastLine(tester, harness);
      if (last == null) continue;
      read.add(location);
      final above = glass - last.bottom;
      final where = '$location (${last.page}, "${last.text}")';
      if (above < 0) under.add('$where: ${(-above).round()}pt under');
      if (last.overflows && above > _mostAbove) {
        short.add('$where: ${above.round()}pt above');
      }
    }

    // A sweep that measured nothing would pass both checks.
    expect(read.length, greaterThan(10), reason: read.join('\n'));
    expect(under, isEmpty, reason: 'The last line ends under the bar.');
    expect(short, isEmpty, reason: 'The page reserves the bar twice.');

    // Off the last service before the tree goes: Dockge's socket says
    // goodbye on a timer of its own.
    router.go(ServiceRoutes.home);
    await harness.settle(tester);
    await harness.unmount(tester);
    container.dispose();
    await tester.pump(const Duration(seconds: 1));
  });
}
