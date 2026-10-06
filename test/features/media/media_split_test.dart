/// A title opened on a tablet: beside the page it was opened from, at the
/// phone's location. The list stays on screen, live, and rings the
/// poster it opened; Back closes the pane, or returns to a title opened
/// inside it.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/router.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/core/utils/side_pane_route.dart';
import 'package:cupola/core/widgets/content_card.dart';
import 'package:cupola/features/media/domain/media_key.dart';
import 'package:cupola/features/media/presentation/media_page.dart';
import 'package:cupola/features/media/presentation/media_split.dart';
import 'package:cupola/features/media/presentation/open_media.dart';

import '../../test_helpers/profiles/profiles.dart';

const _tablet = Size(1180, 820);
const _upright = Size(834, 1194);

Future<(ProfileHarness, GoRouter, ProviderContainer)> _app(
  WidgetTester tester, {
  Size size = _tablet,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final harness = await ProfileHarness.start(Profiles.p1);
  harness.network.followFakeTime(tester.binding);
  final container = harness.container();
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
  await _answer(tester);
  return (harness, router, container);
}

Future<void> _answer(WidgetTester tester) async {
  for (var i = 0; i < 25; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _close(
  WidgetTester tester,
  ProfileHarness harness,
  ProviderContainer container,
) async {
  await tester.pumpWidget(const SizedBox.shrink());
  container.dispose();
  await harness.unmount(tester);
}

/// The titles on screen.
List<MediaKey> _shown(WidgetTester tester) => tester
    .widgetList<MediaPage>(find.byType(MediaPage).hitTestable())
    .map((page) => page.mediaKey)
    .toList();

/// The pane's back control, by what it says: Close or Back.
Finder _paneControl(String label) => find.bySemanticsLabel(label);

/// Taps the pane's back control. By its glyph: its words merge into the
/// first row of the page, which is wider than the plate.
Future<void> _tapPaneControl(WidgetTester tester, String label) async {
  expect(_paneControl(label), findsOneWidget);
  await tester.tap(
    find.descendant(
      of: find.byType(MediaPage),
      matching: find.byIcon(
        label == 'Close' ? Icons.close_rounded : Icons.chevron_left_rounded,
      ),
    ),
  );
  await _answer(tester);
}

final _bunny = MediaKey.movie(WorldTitles.bigBuckBunny.tmdbId);
final _charge = MediaKey.movie(WorldTitles.charge.tmdbId);
final _metropolis = MediaKey.movie(WorldTitles.metropolis.tmdbId);

void main() {
  group('MediaSplit.targetOf', () {
    test('reads a title under a mount, with its query', () {
      final target = MediaSplit.targetOf(
        Uri.parse(
          '/dashboard/radarr/library/media/movie/10378'
          '?i=radarr&heroTag=movie_2_0&posterUrl=https%3A%2F%2Fa%2Fp.jpg',
        ),
      )!;
      expect(target.key, MediaKey.movie(10378));
      expect(target.focus, 'radarr');
      expect(target.heroTag, 'movie_2_0');
      expect(target.posterUrl, 'https://a/p.jpg');
      expect(
        MediaSplit.targetOf(Uri.parse('/search/media/tv/1399'))?.key,
        MediaKey.tv(1399),
      );
      expect(
        MediaSplit.targetOf(Uri.parse('/activity/media/tv/tvdb/121361'))?.key,
        MediaKey.tvdb(121361),
      );
    });

    test('the root mount, other pages and malformed ids have no pane', () {
      for (final location in [
        '/media/movie/10378',
        '/dashboard/radarr/library',
        '/dashboard/radarr/library/movie/2',
        '/dashboard/radarr/library/media/movie/abc',
        '/dashboard/radarr/library/media/movie/10378/extra',
      ]) {
        expect(
          MediaSplit.targetOf(Uri.parse(location)),
          isNull,
          reason: location,
        );
      }
    });
  });

  group('MediaSplit.splits', () {
    Future<bool> splitsAt(WidgetTester tester, Size size) async {
      late bool splits;
      await tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData(size: size),
          child: Builder(
            builder: (context) {
              splits = MediaSplit.splits(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      return splits;
    }

    testWidgets('a touch build from 1024, never the desktop', (tester) async {
      expect(await splitsAt(tester, _tablet), isTrue);
      expect(await splitsAt(tester, const Size(1024, 768)), isTrue);
      expect(await splitsAt(tester, const Size(1000, 800)), isFalse);
      expect(await splitsAt(tester, _upright), isFalse);
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        expect(await splitsAt(tester, const Size(1440, 900)), isFalse);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });

  testWidgets('a title opens beside the library, at the phone\'s location; '
      'the list stays live, readable and rings its poster', (tester) async {
    final semantics = tester.ensureSemantics();
    final (harness, router, container) = await _app(tester);
    router.go(ServiceRoutes.radarrLibrary);
    await _answer(tester);

    await tester.tap(find.text('Big Buck Bunny').first);
    await _answer(tester);

    expect(
      router.state.uri.path,
      '${ServiceRoutes.radarrLibrary}/media/movie/${_bunny.tmdbId}',
    );
    expect(_shown(tester), [_bunny]);
    // The library is still on screen and in reach, band included.
    expect(find.text('Monitored').hitTestable(), findsOneWidget);
    expect(find.text('Radarr').hitTestable(), findsOneWidget);
    // And a screen reader still reads it: no barrier hides it.
    expect(find.bySemanticsLabel(RegExp('^Big Buck Bunny')), findsWidgets);
    expect(_paneControl('Close'), findsOneWidget);

    // The poster it opened wears the ring, and no other does.
    final tag = router.state.uri.queryParameters['heroTag'];
    CustomPaint ringOf(ContentCard card) => tester
        .widgetList<CustomPaint>(
          find.descendant(
            of: find.byWidget(card),
            matching: find.byType(CustomPaint),
          ),
        )
        .first;
    final cards = tester.widgetList<ContentCard>(find.byType(ContentCard));
    expect(
      [
        for (final card in cards)
          if (ringOf(card).foregroundPainter != null) card.paneTag,
      ],
      [tag],
    );

    // Beside the pane the library is not the current route, and is still
    // the page on screen: its polls go on.
    final list = tester.element(find.text('Monitored'));
    expect(ModalRoute.isCurrentOf(list), isFalse);
    expect(SidePaneScope.hostsOf(list), isTrue);

    // Close gives the library its width back.
    await _tapPaneControl(tester, 'Close');
    expect(router.state.uri.path, ServiceRoutes.radarrLibrary);
    expect(_shown(tester), isEmpty);
    expect(SidePaneSlots.instance.debugCount, 0);

    semantics.dispose();
    await _close(tester, harness, container);
  });

  testWidgets('a title chosen in the list takes the pane\'s place; one opened '
      'in the pane is pushed on it, and Back returns', (tester) async {
    final semantics = tester.ensureSemantics();
    final (harness, router, container) = await _app(tester);
    router.go(ServiceRoutes.seerrDiscover);
    await _answer(tester);

    await tester.tap(find.text('Charge (2022)'));
    await _answer(tester);
    expect(_shown(tester), [_charge]);

    await tester.tap(find.text('Metropolis (1927)'));
    await _answer(tester);
    expect(_shown(tester), [_metropolis]);
    expect(_paneControl('Close'), findsOneWidget);

    // From inside the pane: the pane's own history.
    tester.element(find.byType(MediaPage)).openMedia(_bunny);
    await _answer(tester);
    expect(_shown(tester), [_bunny]);
    expect(_paneControl('Back'), findsOneWidget);

    await _tapPaneControl(tester, 'Back');
    expect(_shown(tester), [_metropolis]);

    // Metropolis replaced Charge: Close leaves the list, not Charge.
    await _tapPaneControl(tester, 'Close');
    expect(_shown(tester), isEmpty);
    expect(router.state.uri.path, ServiceRoutes.seerrDiscover);

    semantics.dispose();
    await _close(tester, harness, container);
  });

  testWidgets('upright, a title takes the page as on a phone, and turning '
      'the tablet keeps it', (tester) async {
    final (harness, router, container) = await _app(tester, size: _upright);
    router.go(ServiceRoutes.radarrLibrary);
    await _answer(tester);

    await tester.tap(find.text('Big Buck Bunny').first);
    await _answer(tester);
    expect(_shown(tester), [_bunny]);
    expect(find.text('Monitored').hitTestable(), findsNothing);

    // On its side: beside the library.
    tester.view.physicalSize = _tablet;
    await _answer(tester);
    expect(_shown(tester), [_bunny]);
    expect(find.text('Monitored').hitTestable(), findsOneWidget);

    // Upright again: the full page, and Back is the library.
    tester.view.physicalSize = _upright;
    await _answer(tester);
    expect(_shown(tester), [_bunny]);
    expect(find.text('Monitored').hitTestable(), findsNothing);
    router.pop();
    await _answer(tester);
    expect(router.state.uri.path, ServiceRoutes.radarrLibrary);
    expect(_shown(tester), isEmpty);

    await _close(tester, harness, container);
  });
}
