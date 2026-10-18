/// A title opened on a tablet: beside the page it was opened from, at the
/// phone's location. The list stays on screen, live, and rings the
/// poster it opened; Back closes the pane, or returns to a title opened
/// inside it. A person and a collection opened from a list go beside it the
/// same way; a phone and a desktop window keep the whole page.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/widgets/pressable_scale.dart';
import 'package:cupola/features/discover/domain/catalog_query.dart';
import 'package:cupola/features/discover/presentation/catalog_page.dart';
import 'package:cupola/features/discover/presentation/collection_page.dart';
import 'package:cupola/features/discover/presentation/discover_atrium.dart';
import 'package:cupola/features/discover/presentation/person_page.dart';
import 'package:cupola/core/router.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/features/discover/domain/discover_index.dart';
import 'package:cupola/core/utils/side_pane_route.dart';
import 'package:cupola/core/widgets/content_card.dart';
import 'package:cupola/features/media/domain/media_key.dart';
import 'package:cupola/features/media/presentation/media_page.dart';
import 'package:cupola/features/media/presentation/media_split.dart';
import 'package:cupola/features/media/presentation/open_media.dart';

import '../../test_helpers/profiles/fakes/media_fakes.dart';
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
Finder _paneControl(String label) => find.descendant(
  // The pane's: the list beside it keeps a back plate of its own.
  of: find.byType(MediaPane),
  matching: find.bySemanticsLabel(label),
);

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

/// The person or the collection on screen, by type.
Finder _page<T extends Widget>() => find.byType(T).hitTestable();

/// Taps the back control of the person's or the collection's page.
Future<void> _tapShelfControl(WidgetTester tester, String label) async {
  expect(_paneControl(label), findsOneWidget);
  await tester.tap(
    find
        .byIcon(
          label == 'Close' ? Icons.close_rounded : Icons.chevron_left_rounded,
        )
        .hitTestable()
        .last,
  );
  await _answer(tester);
}

/// Opens the atrium's People index and taps the person in it.
Future<void> _openPersonFromPeople(
  WidgetTester tester,
  GoRouter router,
  ProviderContainer container,
) async {
  router.go(ServiceRoutes.discover);
  await _answer(tester);
  router.push(ServiceRoutes.discoverIndex(DiscoverIndex.people));
  await _answer(tester);
  await tester.tap(find.text(SeerrFake.personName));
  await _answer(tester);
}

final _person = '${ServiceRoutes.discover}/media/person/${SeerrFake.personId}';

final _bunny = MediaKey.movie(WorldTitles.bigBuckBunny.tmdbId);
final _charge = MediaKey.movie(WorldTitles.charge.tmdbId);
final _metropolis = MediaKey.movie(WorldTitles.metropolis.tmdbId);

void main() {
  group('MediaSplit.targetOf', () {
    test('reads a title under a mount, with its query', () {
      final target = MediaSplit.targetOf(
        Uri.parse(
          '/stack/radarr/library/media/movie/10378'
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

    test('reads the season a series opens on, and tells one season of it '
        'from another', () {
      final second = MediaSplit.targetOf(
        Uri.parse('/stack/plex/libraries/media/tv/1399?i=plex&season=2'),
      )!;
      expect(second.season, 2);
      expect(
        MediaSplit.targetOf(Uri.parse('/search/media/tv/1399'))?.season,
        isNull,
      );
      // The same series on another season is another page: the pane draws
      // it fresh, on its own season.
      final page = MediaSplit.pageOf;
      expect(
        page(
          Uri.parse('/stack/plex/libraries/media/tv/1399?season=2'),
        )!.identity,
        isNot(
          page(
            Uri.parse('/stack/plex/libraries/media/tv/1399?season=3'),
          )!.identity,
        ),
      );
      expect(
        page(
          Uri.parse('/stack/plex/libraries/media/tv/1399?season=2'),
        )!.identity,
        page(
          Uri.parse('/stack/plex/libraries/media/tv/1399?season=2'),
        )!.identity,
      );
      // It is still the same title, to the list that rings it.
      expect(
        page(
          Uri.parse('/stack/plex/libraries/media/tv/1399?season=2'),
        )!.selected,
        MediaKey.tv(1399),
      );
    });

    test('reads a person and a collection under a mount, with their query', () {
      final person = MediaSplit.pageOf(
        Uri.parse(
          '/discover/media/person/90001?posterUrl=https%3A%2F%2Fa%2Fp.jpg',
        ),
      );
      expect(person, isA<MediaPanePerson>());
      expect((person! as MediaPanePerson).id, 90001);
      expect((person as MediaPanePerson).posterUrl, 'https://a/p.jpg');
      final collection = MediaSplit.pageOf(
        Uri.parse('/stack/seerr/requests/media/collection/90101'),
      );
      expect((collection! as MediaPaneCollection).id, 90101);
      // A title is still a title, in the shell's own terms.
      final title = MediaSplit.pageOf(Uri.parse('/search/media/tv/1399'));
      expect(title?.selected, MediaKey.tv(1399));
      // The same page is the same page; another one is not.
      expect(
        MediaSplit.pageOf(Uri.parse('/discover/media/person/5'))?.identity,
        MediaSplit.pageOf(Uri.parse('/activity/media/person/5'))?.identity,
      );
      expect(
        MediaSplit.pageOf(Uri.parse('/discover/media/person/5'))?.identity,
        isNot(
          MediaSplit.pageOf(
            Uri.parse('/discover/media/collection/5'),
          )?.identity,
        ),
      );
    });

    test('a person or a collection at the root, malformed or with more '
        'after it has no pane', () {
      for (final location in [
        '/media/person/90001',
        '/media/collection/90101',
        '/discover/media/person/abc',
        '/discover/media/person/90001/extra',
        '/discover/media/people/90001',
      ]) {
        expect(
          MediaSplit.pageOf(Uri.parse(location)),
          isNull,
          reason: location,
        );
      }
    });

    test('the root mount, other pages and malformed ids have no pane', () {
      for (final location in [
        '/media/movie/10378',
        '/stack/radarr/library',
        '/stack/radarr/library/movie/2',
        '/stack/radarr/library/media/movie/abc',
        '/stack/radarr/library/media/movie/10378/extra',
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
    // A catalogue page: every movie of the catalogue in a grid.
    router.go(
      ServiceRoutes.discoverCatalog(const CatalogQuery.all(CatalogKind.movie)),
    );
    await _answer(tester);

    final charge = find.text('Charge');
    await tester.ensureVisible(charge);
    await _answer(tester);
    await tester.tap(charge);
    await _answer(tester);
    expect(_shown(tester), [_charge]);

    // Beside the pane the grid is narrower: further down it.
    final metropolis = find
        .descendant(
          of: find.byType(CatalogPage),
          matching: find.text('Metropolis'),
        )
        .first;
    await tester.ensureVisible(metropolis);
    await _answer(tester);
    await tester.tap(metropolis);
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
    expect(router.state.uri.path, '/discover/all/movie');

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
  testWidgets('a person chosen in a list opens beside it, at the phone\'s '
      'location; the list stays, and Close gives it its width back', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final (harness, router, container) = await _app(tester);

    await _openPersonFromPeople(tester, router, container);

    expect(router.state.uri.path, _person);
    expect(_page<PersonPage>(), findsOneWidget);
    // The index is still on screen and in reach, beside the pane.
    expect(
      find.text('Who is behind this week’s trending titles').hitTestable(),
      findsOneWidget,
    );
    expect(
      tester.getRect(find.byType(PersonPage)).left,
      greaterThan(tester.getRect(find.byType(DiscoverIndexPage)).right - 1),
    );
    // The row the pane shows says so, to the eye and to a screen reader.
    final row = find
        .ancestor(
          of: find.descendant(
            of: find.byType(DiscoverIndexPage),
            matching: find.text(SeerrFake.personName),
          ),
          matching: find.byType(PressableScale),
        )
        .first;
    expect(tester.getSemantics(row), containsSemantics(isSelected: true));

    await _tapShelfControl(tester, 'Close');
    expect(
      router.state.uri.path,
      ServiceRoutes.discoverIndex(DiscoverIndex.people),
    );
    expect(find.byType(PersonPage), findsNothing);
    expect(SidePaneSlots.instance.debugCount, 0);
    expect(tester.getSemantics(row), containsSemantics(isSelected: false));

    semantics.dispose();
    await _close(tester, harness, container);
  });

  testWidgets('a person opened from a title in the pane stays in it, and '
      'Back returns to the title', (tester) async {
    final semantics = tester.ensureSemantics();
    final (harness, router, container) = await _app(tester);
    router.go(
      ServiceRoutes.discoverCatalog(const CatalogQuery.all(CatalogKind.movie)),
    );
    await _answer(tester);
    final charge = find.text('Charge');
    await tester.ensureVisible(charge);
    await _answer(tester);
    await tester.tap(charge);
    await _answer(tester);
    expect(_shown(tester), [_charge]);

    tester.element(find.byType(MediaPage)).openPerson(SeerrFake.personId);
    await _answer(tester);
    expect(router.state.uri.path, _person);
    expect(_page<PersonPage>(), findsOneWidget);
    expect(_shown(tester), isEmpty);
    // The catalogue is still the list beside it.
    expect(find.byType(CatalogPage).hitTestable(), findsOneWidget);

    await _tapShelfControl(tester, 'Back');
    expect(_shown(tester), [_charge]);
    expect(find.byType(PersonPage), findsNothing);

    await _tapPaneControl(tester, 'Close');
    expect(router.state.uri.path, '/discover/all/movie');
    expect(_shown(tester), isEmpty);

    semantics.dispose();
    await _close(tester, harness, container);
  });

  testWidgets('a person chosen in the list takes the place of the title the '
      'pane shows', (tester) async {
    final semantics = tester.ensureSemantics();
    final (harness, router, container) = await _app(tester);
    router.go(ServiceRoutes.discover);
    await _answer(tester);
    tester.element(find.byType(DiscoverAtrium)).openMedia(_bunny);
    await _answer(tester);
    expect(_shown(tester), [_bunny]);

    tester.element(find.byType(DiscoverAtrium)).openPerson(SeerrFake.personId);
    await _answer(tester);
    expect(_page<PersonPage>(), findsOneWidget);
    expect(_shown(tester), isEmpty);

    // Close leaves the list, not the title it replaced.
    await _tapShelfControl(tester, 'Close');
    expect(router.state.uri.path, ServiceRoutes.discover);
    expect(_shown(tester), isEmpty);

    semantics.dispose();
    await _close(tester, harness, container);
  });

  testWidgets('the collection the atrium invites to complete opens beside '
      'it', (tester) async {
    final semantics = tester.ensureSemantics();
    final (harness, router, container) = await _app(tester);
    router.go(ServiceRoutes.discover);
    await _answer(tester);

    final invitation = find.text('Complete the collection');
    await tester.ensureVisible(invitation);
    await _answer(tester);
    await tester.tap(invitation);
    await _answer(tester);

    expect(
      router.state.uri.path,
      '${ServiceRoutes.discover}/media/collection/${SeerrFake.collectionId}',
    );
    expect(_page<CollectionPage>(), findsOneWidget);
    expect(find.byType(DiscoverAtrium).hitTestable(), findsOneWidget);

    await _tapShelfControl(tester, 'Close');
    expect(router.state.uri.path, ServiceRoutes.discover);
    expect(find.byType(CollectionPage), findsNothing);

    semantics.dispose();
    await _close(tester, harness, container);
  });

  testWidgets('on a phone the person takes the whole page', (tester) async {
    final (harness, router, container) = await _app(
      tester,
      size: const Size(390, 844),
    );

    await _openPersonFromPeople(tester, router, container);

    expect(router.state.uri.path, _person);
    expect(_page<PersonPage>(), findsOneWidget);
    expect(find.byType(DiscoverIndexPage).hitTestable(), findsNothing);
    expect(SidePaneSlots.instance.debugCount, 0);

    router.pop();
    await _answer(tester);
    expect(
      router.state.uri.path,
      ServiceRoutes.discoverIndex(DiscoverIndex.people),
    );
    expect(find.byType(PersonPage), findsNothing);

    await _close(tester, harness, container);
  });

  testWidgets('in a desktop window the person takes the whole page, as a '
      'title does', (tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (_) async => null);
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      final (harness, router, container) = await _app(
        tester,
        size: const Size(1440, 900),
      );

      await _openPersonFromPeople(tester, router, container);

      expect(router.state.uri.path, _person);
      expect(_page<PersonPage>(), findsOneWidget);
      expect(find.byType(DiscoverAtrium).hitTestable(), findsNothing);
      expect(SidePaneSlots.instance.debugCount, 0);

      await _close(tester, harness, container);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
