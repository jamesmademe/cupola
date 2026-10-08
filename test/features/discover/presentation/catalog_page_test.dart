import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/models/media_preview.dart';
import 'package:cupola/features/discover/data/seerr_service.dart';
import 'package:cupola/features/discover/domain/catalog_query.dart';
import 'package:cupola/features/discover/domain/models/seerr_genre.dart';
import 'package:cupola/features/discover/presentation/catalog_page.dart';
import 'package:cupola/features/discover/presentation/discover_details_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import '../../../test_helpers/fake_services.dart';
import '../../../test_helpers/settings_scope.dart';

void main() {
  testWidgets('a genre both halves share: its name, where the titles come '
      'from, every control, the posters and how many there are', (
    tester,
  ) async {
    final seerr = _CatalogSeerr(totalResults: 2380);
    await _pumpPage(
      tester,
      seerr,
      const CatalogQuery.genre(CatalogKind.movie, 16, 'Animation'),
    );

    expect(find.text('Animation'), findsOneWidget);
    expect(find.text('From the Seerr catalog'), findsOneWidget);
    for (final control in [
      'Movies',
      'Series',
      'Popular',
      'Decade',
      'Rating 7+ · 100+ votes',
      'Under 100\u00A0min',
      'Hide what I have',
    ]) {
      expect(find.text(control), findsOneWidget, reason: control);
    }
    expect(find.text('Spring'), findsOneWidget);
    expect(find.text('Scores from TMDB · 2,380 titles'), findsOneWidget);
    expect(seerr.asked.single.kind, CatalogKind.movie);
  });

  testWidgets('a capped figure is a floor', (tester) async {
    await _pumpPage(
      tester,
      _CatalogSeerr(totalResults: 20001),
      const CatalogQuery.all(CatalogKind.movie),
    );

    expect(find.text('Scores from TMDB · 20,000+ titles'), findsOneWidget);
  });

  testWidgets('a network is series alone: no halves, no running time', (
    tester,
  ) async {
    await _pumpPage(
      tester,
      _CatalogSeerr(),
      const CatalogQuery.network(213, 'Netflix'),
    );

    expect(find.text('Netflix'), findsOneWidget);
    expect(find.text('Series'), findsNothing);
    expect(find.text('Under 100\u00A0min'), findsNothing);
    expect(find.text('Popular'), findsOneWidget);
  });

  testWidgets('trending has its two windows and nothing to filter', (
    tester,
  ) async {
    final seerr = _CatalogSeerr(totalResults: 10000);
    await _pumpPage(tester, seerr, const CatalogQuery.trending());

    expect(find.text('Today'), findsOneWidget);
    expect(find.text('This week'), findsOneWidget);
    expect(find.text('Popular'), findsNothing);
    expect(find.text('Decade'), findsNothing);
    // TMDB's cap is not a count of what trends.
    expect(find.text('Scores from TMDB'), findsOneWidget);

    await tester.tap(find.text('Today'));
    await tester.pumpAndSettle();
    expect(seerr.asked.last.window, TrendingWindow.day);
  });

  testWidgets('the other half asks again', (tester) async {
    final seerr = _CatalogSeerr();
    await _pumpPage(
      tester,
      seerr,
      const CatalogQuery.genre(CatalogKind.movie, 16, 'Animation'),
    );

    await tester.tap(find.text('Series'));
    await tester.pumpAndSettle();

    expect(seerr.asked.last.kind, CatalogKind.tv);
  });

  testWidgets('Hide what I have takes off what the server holds, and is '
      'remembered', (tester) async {
    final scope = await settingsScope(configured: [ServiceKey.seerr]);
    await _pumpPage(
      tester,
      _CatalogSeerr(),
      const CatalogQuery.all(CatalogKind.movie),
      prefs: scope,
    );
    expect(find.text('Elephants Dream'), findsOneWidget);

    await tester.tap(find.text('Hide what I have'));
    await tester.pumpAndSettle();

    expect(find.text('Elephants Dream'), findsNothing);
    expect(find.text('Spring'), findsOneWidget);
    expect(scope.prefs.getBool('catalog_hide_owned'), isTrue);
  });

  testWidgets('a genre reached by its id alone takes its name from Seerr', (
    tester,
  ) async {
    await _pumpPage(
      tester,
      _CatalogSeerr(),
      catalogQueryFor(CatalogBase.genre, {'kind': 'movie', 'id': '16'}, {})!,
    );

    expect(find.text('Animation'), findsOneWidget);
  });

  group('a route\'s question, from its path alone', () {
    test('names come from the curated lists, then from the link', () {
      expect(
        catalogQueryFor(CatalogBase.network, {'id': '213'}, {})!.title,
        'Netflix',
      );
      expect(
        catalogQueryFor(
          CatalogBase.keyword,
          {'kind': 'movie', 'id': '999'},
          {'title': 'Lighthouses'},
        )!.title,
        'Lighthouses',
      );
      expect(
        catalogQueryFor(CatalogBase.language, {
          'kind': 'tv',
          'code': 'ko',
        }, {})!.title,
        'Korean',
      );
    });

    test('parameters it cannot read are no page', () {
      expect(catalogQueryFor(CatalogBase.all, {'kind': 'book'}, {}), isNull);
      expect(
        catalogQueryFor(CatalogBase.genre, {'kind': 'movie', 'id': 'x'}, {}),
        isNull,
      );
      expect(
        catalogQueryFor(CatalogBase.decade, {
          'kind': 'movie',
          'start': '1995',
        }, {}),
        isNull,
      );
    });

    test('trending reads its window', () {
      expect(
        catalogQueryFor(CatalogBase.trending, {}, {'window': 'day'})!.window,
        TrendingWindow.day,
      );
      expect(
        catalogQueryFor(CatalogBase.trending, {}, {})!.window,
        TrendingWindow.week,
      );
    });
  });
}

/// Seerr answering every catalogue page with the same three titles, one of
/// them on the server, and recording what it was asked.
class _CatalogSeerr extends FakeSeerrService {
  _CatalogSeerr({this.totalResults = 3});

  final int totalResults;
  final asked = <CatalogQuery>[];

  @override
  Future<CatalogPageResult> getCatalogPage(
    CatalogQuery query, {
    int page = 1,
    DateTime? today,
  }) async {
    asked.add(query);
    return CatalogPageResult(
      items: const [
        MediaPreview(id: 1, title: 'Spring', mediaType: 'movie'),
        MediaPreview(
          id: 2,
          title: 'Elephants Dream',
          mediaType: 'movie',
          mediaInfo: {'status': 5},
        ),
        MediaPreview(id: 3, title: 'Charge', mediaType: 'movie'),
      ],
      page: page,
      totalPages: 1,
      totalResults: totalResults,
    );
  }

  @override
  Future<List<SeerrGenre>> getMovieGenres() async => const [
    SeerrGenre(id: 16, name: 'Animation'),
  ];
}

Future<void> _pumpPage(
  WidgetTester tester,
  FakeSeerrService seerr,
  CatalogQuery query, {
  SettingsScope? prefs,
}) async {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        if (prefs != null)
          sharedPreferencesProvider.overrideWith((ref) => prefs.prefs),
        currentSettingsProvider.overrideWith(
          (ref) => settingsWithServices([ServiceKey.seerr]),
        ),
        seerrServiceProvider.overrideWithValue(seerr),
        seerrNumberingProvider.overrideWith((ref) async => null),
      ],
      child: MaterialApp(home: CatalogPage(query: query)),
    ),
  );
  await tester.pumpAndSettle();
}
