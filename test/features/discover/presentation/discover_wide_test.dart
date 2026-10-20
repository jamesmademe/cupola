/// The Discover tab on a tablet and in a desktop window: drawn at 390 for the
/// phone, it lays itself out for the width it is given rather than
/// stretching the phone across it. These tests measure; they do not
/// photograph.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/app_breakpoints.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/models/media_preview.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/features/discover/domain/catalog_query.dart';
import 'package:cupola/features/discover/domain/collection_shelf.dart';
import 'package:cupola/features/discover/domain/library_calendar.dart';
import 'package:cupola/features/discover/domain/models/collection_detail.dart';
import 'package:cupola/features/discover/domain/models/seerr_genre.dart';
import 'package:cupola/features/discover/presentation/catalog_page.dart';
import 'package:cupola/features/discover/presentation/catalog_providers.dart';
import 'package:cupola/features/discover/domain/discover_index.dart';
import 'package:cupola/features/discover/presentation/discover_atrium.dart';
import 'package:cupola/features/discover/presentation/discover_details_provider.dart';
import 'package:cupola/features/discover/presentation/discover_page.dart';
import 'package:cupola/features/discover/presentation/discover_provider.dart';
import 'package:cupola/features/discover/presentation/widgets/calendar_band.dart';
import 'package:cupola/features/discover/presentation/widgets/calendar_week_strip.dart';
import 'package:cupola/features/discover/presentation/widgets/catalog_poster.dart';
import 'package:cupola/features/discover/presentation/widgets/collection_tally.dart';
import 'package:cupola/features/discover/presentation/widgets/discover_door.dart';
import 'package:cupola/features/discover/presentation/widgets/search_row.dart';
import 'package:cupola/features/media/presentation/shelf_page.dart';
import 'package:cupola/features/search/presentation/global_search_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import '../../../test_helpers/profiles/profiles.dart';
import '../../../test_helpers/settings_scope.dart';

/// The atrium's width on a tablet on its side: 1180 less the rail.
const _tablet = Size(1100, 2400);
const _phone = Size(390, 2400);
const _desktop = Size(1440, 900);

const _doors = [
  'Trending, This week',
  'Genres, 1',
  'Networks, Series',
  'Studios, Movies',
  'People, Directors, cast',
  'Decades, 1920s to now',
];

const _trending = [
  MediaPreview(id: 20, title: 'Trending One', mediaType: 'movie'),
  MediaPreview(id: 21, title: 'Trending Two', mediaType: 'tv'),
];

void main() {
  group('the atrium\'s doors', () {
    testWidgets('all six on one row at a tablet\'s width', (tester) async {
      await _atrium(tester, _tablet);

      final rects = _doorRects(tester);
      expect(rects.map((rect) => rect.top).toSet(), hasLength(1));
      for (var i = 1; i < rects.length; i++) {
        expect(rects[i].left, greaterThan(rects[i - 1].right));
      }
      // Each still at least a door of the narrowest phone.
      expect(rects.first.width, greaterThanOrEqualTo(104));
    });

    testWidgets('three to a row on a phone, as drawn', (tester) async {
      await _atrium(tester, _phone);

      final tops = [for (final rect in _doorRects(tester)) rect.top];
      expect(tops.sublist(0, 3).toSet(), hasLength(1));
      expect(tops.sublist(3).toSet(), hasLength(1));
      expect(tops[3], greaterThan(tops[0]));
    });

    testWidgets('at a large reading size: three to a row when wide, two on '
        'a phone', (tester) async {
      // Past the size at which a door drops its corner (1.3).
      tester.platformDispatcher.textScaleFactorTestValue = 1.5;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await _atrium(tester, _tablet);
      var tops = [for (final rect in _doorRects(tester)) rect.top];
      expect(tops.toSet(), hasLength(2));
      expect(tops.sublist(0, 3).toSet(), hasLength(1));

      await tester.pumpWidget(const SizedBox.shrink());
      await _atrium(tester, _phone);
      tops = [for (final rect in _doorRects(tester)) rect.top];
      expect(tops.toSet(), hasLength(3));
    });
  });

  group('an open index', () {
    testWidgets('its tiles add a column wherever one fits at 160', (
      tester,
    ) async {
      Future<int> firstRow(Size size) async {
        await _atrium(tester, size, index: DiscoverIndex.moods);
        return _firstRow(tester);
      }

      expect(await firstRow(_tablet), 6);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(await firstRow(_phone), 2);
    });

    testWidgets('the people read at a page of one column\'s measure, under '
        'the line that says who they are', (tester) async {
      await _atrium(tester, _tablet, index: DiscoverIndex.people);

      final row = tester.getRect(find.byType(SearchRow));
      expect(row.width, lessThanOrEqualTo(AppBreakpoints.readingWell));
      expect(row.left, AppSpacing.lg);
    });
  });

  group('the calendar\'s band', () {
    testWidgets('a tablet upright beside a title\'s list: the week beside the '
        'words, at its measure', (tester) async {
      await _band(tester, 860);

      final words = tester.getRect(find.text('Calendar'));
      final week = tester.getRect(find.byType(CalendarWeekStrip));
      expect(week.width, CalendarBand.weekMeasure);
      expect(week.left, greaterThan(words.right));
      expect(week.top, lessThan(words.bottom));
    });

    testWidgets('a tablet on its side: the days with their posters in place '
        'of the dots, beside the words', (tester) async {
      await _band(tester, 1100);

      expect(find.byType(CalendarWeekStrip), findsNothing);
      final words = tester.getRect(find.text('Calendar'));
      final today = tester.getRect(find.textContaining('Today\u00A0·'));
      expect(today.left, greaterThan(words.right));
    });

    testWidgets('a phone\'s: the week under the words, the band\'s width', (
      tester,
    ) async {
      await _band(tester, 390);

      final words = tester.getRect(find.text('Calendar'));
      final week = tester.getRect(find.byType(CalendarWeekStrip));
      expect(week.top, greaterThan(words.bottom));
      // The band's margins, its padding and its hairline edges.
      expect(week.width, 390 - 4 * AppSpacing.lg - 2);
    });

    testWidgets('between the two: under the words, and no wider than the '
        'widest phone draws it', (tester) async {
      await _band(tester, 700);

      final words = tester.getRect(find.text('Calendar'));
      final week = tester.getRect(find.byType(CalendarWeekStrip));
      expect(week.top, greaterThan(words.bottom));
      expect(week.width, CalendarBand.weekMeasure);
      expect(week.left, words.left);
    });
  });

  group('the invitation to complete a collection', () {
    testWidgets('a tablet\'s: the strip beside the words, the legend under '
        'them', (tester) async {
      await _tally(tester, 1068);

      final title = tester.getRect(find.text(CollectionTally.invitationTitle));
      final legend = tester.getRect(find.text('5 on your server'));
      final covers = [
        for (final element in find.byType(ShelfArtwork).evaluate())
          tester.getRect(find.byWidget(element.widget)),
      ];
      expect(covers, hasLength(8));
      expect(covers.first.left, greaterThan(title.right));
      expect(covers.first.top, lessThan(legend.top));
      expect(
        covers.last.right - covers.first.left,
        lessThanOrEqualTo(CollectionTally.stripMeasure),
      );
    });

    testWidgets('a phone\'s: the words, the strip, the legend, one under '
        'another', (tester) async {
      await _tally(tester, 358);

      final title = tester.getRect(find.text(CollectionTally.invitationTitle));
      final legend = tester.getRect(find.text('5 on your server'));
      final cover = tester.getRect(find.byType(ShelfArtwork).first);
      expect(cover.top, greaterThan(title.bottom));
      expect(legend.top, greaterThan(cover.bottom));
    });
  });

  group('in a desktop window', () {
    setUp(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (_) async => null);
    });
    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    testWidgets('at 1440 the tab is in its well, and a search\'s rows at a '
        'page of one column\'s measure inside it', (tester) async {
      await _onMac(() async {
        final harness = await pumpWithProfile(
          tester,
          Profiles.p1,
          child: const DiscoverPage(),
          surfaceSize: _desktop,
        );

        final atrium = tester.getRect(find.byType(DiscoverAtrium));
        expect(atrium.width, AppBreakpoints.contentWell);
        expect(atrium.center.dx, closeTo(_desktop.width / 2, 0.5));

        final container = ProviderScope.containerOf(
          tester.element(find.byType(DiscoverPage)),
        );
        container.read(globalSearchQueryProvider.notifier).state = 'in';
        container.read(globalSearchFieldVersionProvider.notifier).state++;
        await harness.settle(tester);

        final rows = find.byType(SearchRow);
        expect(rows, findsWidgets);
        for (final element in rows.evaluate()) {
          final rect = tester.getRect(find.byWidget(element.widget));
          expect(rect.width, lessThanOrEqualTo(AppBreakpoints.readingWell));
          expect(rect.left, atrium.left + AppSpacing.lg);
        }
        // The field and its Cancel end where the answers do.
        final right = tester.getRect(rows.first).right;
        expect(
          tester.getRect(find.byType(SearchBar)).left,
          atrium.left + AppSpacing.lg,
        );
        expect(
          tester.getRect(find.text('Cancel')).right,
          lessThanOrEqualTo(right + 0.5),
        );
        expect(tester.getRect(find.byType(SearchBar)).right, lessThan(right));

        await harness.unmount(tester);
      });
    });

    testWidgets('at 1440 a catalogue page holds seven columns in its well', (
      tester,
    ) async {
      await _onMac(() async {
        final harness = await pumpWithProfile(
          tester,
          Profiles.p1,
          child: const CatalogPage(query: CatalogQuery.trending()),
          surfaceSize: _desktop,
        );

        final posters = _postersOf(tester);
        final left = posters.map((rect) => rect.left).reduce(_min);
        final right = posters.map((rect) => rect.right).reduce(_max);
        expect(
          right - left,
          closeTo(AppBreakpoints.contentWell - 2 * AppSpacing.lg, 0.5),
        );
        expect((left + right) / 2, closeTo(_desktop.width / 2, 0.5));
        expect(posters.map((rect) => rect.left).toSet(), hasLength(7));

        await harness.unmount(tester);
      });
    });
  });

  testWidgets('on a tablet a catalogue page takes the width, and its switch '
      'stays a phone\'s row from its words', (tester) async {
    final harness = await pumpWithProfile(
      tester,
      Profiles.p1,
      child: const CatalogPage(query: CatalogQuery.trending()),
      surfaceSize: const Size(1180, 820),
    );

    final posters = _postersOf(tester);
    expect(posters.map((rect) => rect.left).toSet(), hasLength(8));
    final toggle = tester.getRect(find.byType(Switch));
    expect(toggle.right, lessThanOrEqualTo(AppBreakpoints.splitList));

    await harness.unmount(tester);
  });
}

double _min(double a, double b) => a < b ? a : b;
double _max(double a, double b) => a > b ? a : b;

/// The doors of the lobby, by their spoken names, where they are.
List<Rect> _doorRects(WidgetTester tester) => [
  for (final door in _doors) tester.getRect(find.bySemanticsLabel(door)),
];

/// How many tiles share the first row of the grid on screen.
int _firstRow(WidgetTester tester) {
  final rects = [
    for (final element in find.byType(DiscoverDoor).evaluate())
      tester.getRect(find.byWidget(element.widget)),
  ];
  final top = rects.map((rect) => rect.top).reduce(_min);
  return rects.where((rect) => (rect.top - top).abs() < 0.5).length;
}

/// The posters of the grid on screen.
List<Rect> _postersOf(WidgetTester tester) => [
  for (final element in find.byType(CatalogPoster).evaluate())
    tester.getRect(find.byWidget(element.widget)),
];

Future<void> _onMac(Future<void> Function() body) async {
  debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
  try {
    await body();
  } finally {
    debugDefaultTargetPlatformOverride = null;
  }
}

/// The atrium at [size], or the page of [index] when one is named.
Future<ProviderContainer> _atrium(
  WidgetTester tester,
  Size size, {
  DiscoverIndex? index,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final container = ProviderContainer(
    overrides: [
      seerrNumberingProvider.overrideWith((ref) async => null),
      currentSettingsProvider.overrideWith(
        (ref) => settingsWithServices([ServiceKey.seerr]),
      ),
      atriumTrendingProvider.overrideWith((ref) async => _trending),
      bestMissingProvider.overrideWith((ref) async => const []),
      comingSoonProvider.overrideWith((ref) async => const []),
      catalogGenresProvider.overrideWith(
        (ref, kind) async => const [SeerrGenre(id: 16, name: 'Animation')],
      ),
      trendingPeopleProvider.overrideWith(
        (ref) async => const [
          (
            id: 1,
            name: 'Ian Hubert',
            role: 'Director',
            title: 'Tears of Steel',
            profilePath: null,
          ),
        ],
      ),
      requestsProvider.overrideWith((ref) async => const []),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.darkTheme(),
        home: index == null
            ? const Scaffold(body: DiscoverAtrium())
            : DiscoverIndexPage(index: index),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

Future<void> _band(WidgetTester tester, double width) async {
  final now = DateTime(2026, 9, 29, 20, 53);
  await _framed(
    tester,
    width,
    CalendarBand(
      events: [
        CalendarEvent(
          identity: 'sf',
          kind: CalendarKind.movie,
          day: DateTime(2026, 9, 29),
          title: 'Sprite Fright',
          state: const CalendarState.notYet(),
        ),
      ],
      window: CalendarWindow.from(now),
      now: now,
      onTap: () {},
    ),
  );
}

Future<void> _tally(WidgetTester tester, double width) async {
  await _framed(
    tester,
    width,
    CollectionTally.invitation(
      shelf: CollectionShelf.of(
        CollectionDetail(
          id: 1,
          name: 'Blender Open Movies',
          parts: [
            for (final (id, status) in const [
              (1, 5),
              (2, 3),
              (3, 5),
              (4, 5),
              (5, 5),
              (6, 5),
              (7, 3),
              (8, 2),
            ])
              MediaPreview(
                id: id,
                title: 'Part $id',
                mediaType: 'movie',
                releaseDate: '20${10 + id}-04-10',
                mediaInfo: {'status': status},
              ),
          ],
        ),
      ),
      name: 'Blender Open Movies',
      onTap: () {},
    ),
  );
}

/// [child] laid out [width] wide at the top left of a tall window.
Future<void> _framed(WidgetTester tester, double width, Widget child) async {
  tester.view.physicalSize = Size(width + 200, 1200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        theme: AppTheme.darkTheme(),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(width: width, child: child),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
