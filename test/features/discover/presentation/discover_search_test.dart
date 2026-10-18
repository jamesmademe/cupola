import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// ignore: implementation_imports
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cupola/features/search/presentation/recent_searches_provider.dart';
import 'package:cupola/core/models/media_preview.dart';
import 'package:cupola/core/providers/navigation_refresh_provider.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/core/widgets/media_poster_card.dart';
import 'package:cupola/core/widgets/search_bar_header.dart';
import 'package:cupola/core/widgets/shimmer_placeholder.dart';
import 'package:cupola/features/discover/data/seerr_service.dart';
import 'package:cupola/features/discover/domain/seerr_search.dart';
import 'package:cupola/features/discover/presentation/discover_details_provider.dart';
import 'package:cupola/features/discover/presentation/discover_page.dart';
import 'package:cupola/features/movies/data/radarr_service.dart';
import 'package:cupola/features/movies/domain/models/radarr_movie.dart';
import 'package:cupola/features/music/presentation/music_search_provider.dart';
import 'package:cupola/features/search/presentation/global_search_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';

import '../../../test_helpers/fake_services.dart';
import '../../../test_helpers/model_builders.dart';
import '../../../test_helpers/settings_scope.dart';

/// The Discover tab's search: the answer by kind, one row per title whoever
/// found it, the plus where the operator may add, a source that is silent
/// stated once, and the field's own states (recent searches, Cancel).
void main() {
  group('the answer, by kind', () {
    testWidgets('what the server holds leads, then the catalogue, then '
        'people', (tester) async {
      await _pump(tester);

      for (final heading in ['On your server', 'Movies', 'Series', 'People']) {
        expect(find.text(heading), findsOneWidget, reason: heading);
      }
      // Seerr and Radarr both found Dune: one row, in what the server holds,
      // in Seerr's word.
      expect(find.text('Dune'), findsOneWidget);
      expect(find.text('Available'), findsOneWidget);
      expect(
        find.text('Movie\u00A0· 2021\u00A0· TMDB\u00A07.8'),
        findsOneWidget,
      );
      expect(find.text('Arrival'), findsOneWidget);
      expect(find.text('Dune: Prophecy'), findsOneWidget);
      expect(find.text('Denis Villeneuve'), findsOneWidget);
      expect(find.text('Known for Dune, Arrival'), findsOneWidget);
      // No service is drawn as a section.
      expect(find.text('Radarr'), findsNothing);
      expect(find.text('Seerr'), findsNothing);
    });

    testWidgets('a title Radarr could add carries the plus; one it holds, '
        'or whose arr is not set up, does not', (tester) async {
      await _pump(tester);

      expect(find.bySemanticsLabel('Add Arrival to Radarr'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('^Add Dune')), findsNothing);
      // No Sonarr in this stack: the series opens its page, which asks.
      expect(
        find.bySemanticsLabel(RegExp('^Add Dune: Prophecy')),
        findsNothing,
      );
    });

    testWidgets('the plus opens the add sheet the title\'s page opens', (
      tester,
    ) async {
      await _pump(tester);

      await tester.tap(find.bySemanticsLabel('Add Arrival to Radarr'));
      await _frames(tester);

      expect(find.text('Add to Radarr'), findsOneWidget);
      expect(find.text('Arrival\u00A0· 2016'), findsOneWidget);
    });

    testWidgets('a word that names someone leads with them', (tester) async {
      await _pump(
        tester,
        seerr: _Seerr(
          titles: [_duneSeerr],
          people: const [SeerrSearchPerson(id: 1, name: 'Dune Lady')],
          leadsWithPeople: true,
        ),
      );

      double top(String text) => tester.getTopLeft(find.text(text)).dy;
      expect(top('People'), lessThan(top('Movies')));
      // What the server holds still leads.
      expect(top('On your server'), lessThan(top('People')));
    });

    testWidgets('an average of a handful of votes is not drawn', (
      tester,
    ) async {
      await _pump(
        tester,
        seerr: _Seerr(
          titles: const [
            MediaPreview(
              id: 1,
              title: 'Dune Story',
              mediaType: 'movie',
              releaseDate: '2020-01-01',
              voteAverage: 10,
              voteCount: 1,
            ),
          ],
        ),
      );

      expect(find.text('Movie\u00A0· 2020'), findsOneWidget);
      expect(find.textContaining('TMDB'), findsNothing);
    });

    testWidgets('a source with no one by that name says so', (tester) async {
      await _pump(tester, seerr: _Seerr(titles: [_duneSeerr]));

      expect(find.text('People'), findsOneWidget);
      expect(find.text('No one called “dune”'), findsOneWidget);
    });

    testWidgets('nothing anywhere, once every source has answered', (
      tester,
    ) async {
      await _pump(tester, seerr: _Seerr(), radarr: _Radarr(), query: 'qwxz');

      expect(find.text('Nothing called “qwxz”'), findsOneWidget);
    });
  });

  group('sources that are slow or silent', () {
    testWidgets('a source still out does not hold the ones that answered', (
      tester,
    ) async {
      final radarr = _Radarr(results: [_duneRadarr], parks: true);
      await _pump(tester, radarr: radarr, settle: false);

      expect(find.text('Dune'), findsOneWidget);
      expect(find.byType(ShimmerPlaceholder), findsWidgets);
      // Radarr has not said whether it holds Arrival: no plus yet.
      expect(find.bySemanticsLabel('Add Arrival to Radarr'), findsNothing);

      await _release(tester, radarr.release);
    });

    testWidgets('"nothing called" waits for every source', (tester) async {
      final radarr = _Radarr(parks: true);
      await _pump(
        tester,
        seerr: _Seerr(),
        radarr: radarr,
        query: 'qwxz',
        settle: false,
      );

      expect(find.textContaining('Nothing called'), findsNothing);

      await _release(tester, radarr.release);
      await _frames(tester);
      expect(find.text('Nothing called “qwxz”'), findsOneWidget);
    });

    testWidgets('a source past its deadline says what is missing, once, with '
        'a Retry that asks it alone again', (tester) async {
      final seerr = _Seerr(titles: [_duneSeerr]);
      final radarr = _Radarr(results: [_duneRadarr], parks: true);
      await _pump(tester, seerr: seerr, radarr: radarr, settle: false);
      await tester.pump(const Duration(seconds: 11));
      await tester.pump();

      expect(
        find.text('No Radarr results: the search timed out.'),
        findsOneWidget,
      );
      // Seerr's answer still stands, and Dune is not called Radarr's.
      expect(find.text('Dune'), findsOneWidget);
      expect(find.bySemanticsLabel('Retry Radarr'), findsOneWidget);

      final seerrCalls = seerr.calls;
      final radarrCalls = radarr.calls;
      await tester.tap(find.bySemanticsLabel('Retry Radarr'));
      await tester.pump();
      expect(radarr.calls, radarrCalls + 1);
      expect(seerr.calls, seerrCalls);

      await _release(tester, radarr.release);
    });

    testWidgets('a Seerr that did not answer leaves Radarr\'s answer', (
      tester,
    ) async {
      await _pump(tester, seerr: _Seerr(fails: true));

      expect(find.textContaining('No Seerr results'), findsOneWidget);
      expect(find.text('Dune'), findsOneWidget);
      expect(find.text('In Radarr'), findsOneWidget);
      // People come from Seerr alone: not asked, so not said.
      expect(find.text('People'), findsNothing);
    });
  });

  group('the field', () {
    testWidgets('the refresh command runs the query again instead of '
        'erasing it', (tester) async {
      final radarr = _Radarr(results: [_duneRadarr]);
      await _pump(tester, radarr: radarr);
      final calls = radarr.calls;

      _containerOf(tester).read(globalSearchRerunProvider.notifier).state++;
      await _frames(tester);

      expect(radarr.calls, calls + 1);
      expect(_containerOf(tester).read(globalSearchQueryProvider), 'dune');
    });

    testWidgets('a query is a recent search once it stays put, not every '
        'prefix on the way', (tester) async {
      await _pump(
        tester,
        radarr: _Radarr(results: [_duneRadarr]),
        query: 'dun',
      );
      final container = _containerOf(tester);

      await tester.pump(const Duration(milliseconds: 500));
      container.read(globalSearchQueryProvider.notifier).state = 'dune';
      await _frames(tester);
      await tester.pump(const Duration(seconds: 3));

      expect(container.read(recentSearchesProvider), ['dune']);
    });

    testWidgets('the tab again clears the field', (tester) async {
      await _pump(tester);

      _containerOf(tester)
          .read(navigationRefreshProvider(NavigationSection.discover).notifier)
          .state++;
      await _frames(tester);

      expect(_containerOf(tester).read(globalSearchQueryProvider), isEmpty);
      expect(find.text('Discover'), findsOneWidget);
    });

    testWidgets('the magnifier is the secondary ink', (tester) async {
      await _pump(tester);

      final context = tester.element(find.byType(DiscoverPage));
      final glyph = tester.widget<Icon>(
        find.descendant(
          of: find.byType(SearchBarHeader),
          matching: find.byIcon(Icons.search_rounded),
        ),
      );
      expect(glyph.color, Theme.of(context).colorScheme.onSurfaceVariant);
    });

    testWidgets('focused and empty: the recent searches, which run, and '
        'go one by one', (tester) async {
      SharedPreferences.setMockInitialValues({
        'recent_searches': ['metropolis', 'caligari'],
      });
      final prefs = await SharedPreferences.getInstance();
      await _pump(tester, query: '', prefs: prefs);
      expect(find.text('Discover'), findsOneWidget);

      await tester.tap(find.byType(SearchBar));
      await _frames(tester);

      expect(find.text('Recent searches'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      // The field took the title's place.
      expect(find.text('Discover'), findsNothing);

      await tester.tap(find.byTooltip('Remove caligari from recent searches'));
      await _frames(tester);
      expect(find.text('caligari'), findsNothing);

      await tester.tap(find.text('metropolis'));
      await _frames(tester);
      expect(
        _containerOf(tester).read(globalSearchQueryProvider),
        'metropolis',
      );
    });

    testWidgets('at rest the field sits under the title, and taking the '
        'title\'s place it keeps its focus', (tester) async {
      await _pump(tester, query: '');
      expect(
        tester.getTopLeft(find.byType(SearchBar)).dy,
        greaterThan(tester.getBottomLeft(find.text('Discover')).dy),
      );

      await tester.tap(find.byType(SearchBar));
      await _frames(tester);
      expect(find.text('Discover'), findsNothing);

      // The same field, still focused: what is typed now is the query.
      tester.testTextInput.enterText('nosferatu');
      await tester.pump(const Duration(seconds: 1));
      await _frames(tester);
      expect(_containerOf(tester).read(globalSearchQueryProvider), 'nosferatu');
    });

    testWidgets('with a mouse, a recent search runs: the click does not '
        'take the field away first', (tester) async {
      SharedPreferences.setMockInitialValues({
        'recent_searches': ['metropolis', 'caligari'],
      });
      final prefs = await SharedPreferences.getInstance();
      await _pump(tester, query: '', prefs: prefs);

      await tester.tap(find.byType(SearchBar), kind: PointerDeviceKind.mouse);
      await _frames(tester);
      expect(find.text('Recent searches'), findsOneWidget);

      await tester.tap(
        find.byTooltip('Remove caligari from recent searches'),
        kind: PointerDeviceKind.mouse,
      );
      await _frames(tester);
      expect(find.text('caligari'), findsNothing);
      expect(find.text('Recent searches'), findsOneWidget);

      await tester.tap(find.text('metropolis'), kind: PointerDeviceKind.mouse);
      await _frames(tester);
      expect(
        _containerOf(tester).read(globalSearchQueryProvider),
        'metropolis',
      );
    });

    testWidgets('Cancel clears the query and puts the field away', (
      tester,
    ) async {
      await _pump(tester);
      expect(find.text('Cancel'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await _frames(tester);

      expect(_containerOf(tester).read(globalSearchQueryProvider), isEmpty);
      expect(find.text('Cancel'), findsNothing);
      expect(find.text('Discover'), findsOneWidget);
    });
  });

  group('where a row goes', () {
    testWidgets('a title opens its page on the copy that holds it', (
      tester,
    ) async {
      final router = _router();
      await _pumpRouter(tester, router);

      await tester.tap(find.text('Dune'));
      await _frames(tester);

      expect(find.text('Title'), findsOneWidget);
      final location = router.state.uri;
      expect(location.path, '${ServiceRoutes.discover}/media/movie/438631');
      expect(location.queryParameters['i'], 'radarr');
    });

    testWidgets('a title with artwork flies its poster; one without does '
        'not fly an empty box', (tester) async {
      await _pump(tester, settle: false);

      final hero = tester.widget<Hero>(
        find.byWidgetPredicate(
          (widget) =>
              widget is Hero && widget.tag == 'search_radarr_movie_10_0',
        ),
      );
      expect(
        hero.transitionOnUserGestures,
        MediaPosterCard.flightOnUserGestures,
      );
      // Arrival has no artwork anywhere: its initials, no flight.
      expect(
        find.ancestor(of: find.text('AR'), matching: find.byType(Hero)),
        findsNothing,
      );
    });

    testWidgets('music is Lidarr\'s own search, for the same word', (
      tester,
    ) async {
      final router = _router(withLidarr: true);
      await _pumpRouter(tester, router, withLidarr: true);

      await tester.ensureVisible(find.text('Search Lidarr for “dune”'));
      await tester.tap(find.text('Search Lidarr for “dune”'));
      await _frames(tester);

      expect(router.state.uri.path, ServiceRoutes.lidarrLibrary);
      expect(_containerOf(tester).read(musicSearchQueryProvider), 'dune');
    });
  });

  group('without Seerr', () {
    testWidgets('the catalogue\'s place says where it comes from, and the '
        'field still searches Radarr', (tester) async {
      await _pump(tester, query: '', withSeerr: false);

      expect(find.text('The catalog comes from Seerr'), findsOneWidget);
      expect(find.text('Set up Seerr'), findsOneWidget);
      expect(find.textContaining('searches Radarr'), findsOneWidget);
      // People come from Seerr: the field does not promise them.
      expect(find.text('Movies and series'), findsOneWidget);
    });

    testWidgets('typing still searches what is set up', (tester) async {
      await _pump(tester, withSeerr: false);

      expect(find.text('Dune'), findsOneWidget);
      expect(find.text('In Radarr'), findsOneWidget);
      expect(find.text('People'), findsNothing);
    });
  });
}

const _duneSeerr = MediaPreview(
  id: 438631,
  title: 'Dune',
  mediaType: 'movie',
  releaseDate: '2021-09-15',
  voteAverage: 7.8,
  posterPath: '/dune.jpg',
  mediaInfo: {'status': 5},
);

final _duneRadarr = buildMovie(
  id: 10,
  title: 'Dune',
  tmdbId: 438631,
  year: 2021,
);

final _arrivalRadarr = buildMovie(
  id: 0,
  title: 'Arrival',
  tmdbId: 329865,
  year: 2016,
  hasFile: false,
);

class _Seerr extends FakeSeerrService {
  _Seerr({
    this.titles = const [],
    this.people = const [],
    this.fails = false,
    this.leadsWithPeople = false,
  });

  final List<MediaPreview> titles;
  final List<SeerrSearchPerson> people;
  final bool fails;
  final bool leadsWithPeople;
  var calls = 0;

  @override
  Future<SeerrSearchAnswer> search(
    String query, {
    CancelToken? cancelToken,
  }) async {
    calls++;
    if (fails) {
      throw DioException(
        requestOptions: RequestOptions(path: '/api/v1/search'),
        type: DioExceptionType.connectionError,
      );
    }
    return SeerrSearchAnswer(
      titles: titles,
      people: people,
      leadsWithPeople: leadsWithPeople,
    );
  }
}

class _Radarr extends FakeRadarrService {
  _Radarr({this.results = const [], this.parks = false});

  final List<RadarrMovie> results;
  final bool parks;
  final List<Completer<List<RadarrMovie>>> _parked = [];
  var calls = 0;

  @override
  Future<List<RadarrMovie>> lookupMovies(
    String term, {
    CancelToken? cancelToken,
    bool reportFailure = false,
  }) {
    calls++;
    if (!parks) return Future.value(results);
    final completer = Completer<List<RadarrMovie>>();
    _parked.add(completer);
    return completer.future;
  }

  void release() {
    for (final completer in _parked) {
      if (!completer.isCompleted) completer.complete(results);
    }
  }
}

_Seerr _defaultSeerr() => _Seerr(
  titles: const [
    _duneSeerr,
    MediaPreview(
      id: 90228,
      title: 'Dune: Prophecy',
      mediaType: 'tv',
      releaseDate: '2024-11-17',
    ),
    MediaPreview(
      id: 329865,
      title: 'Arrival',
      mediaType: 'movie',
      releaseDate: '2016-11-10',
    ),
  ],
  people: const [
    SeerrSearchPerson(
      id: 137427,
      name: 'Denis Villeneuve',
      knownFor: ['Dune', 'Arrival', 'Sicario'],
    ),
  ],
);

List<Override> _overrides({
  FakeSeerrService? seerr,
  RadarrService? radarr,
  String query = 'dune',
  bool withSeerr = true,
  bool withLidarr = false,
  SharedPreferences? prefs,
}) => [
  currentSettingsProvider.overrideWith(
    (ref) => settingsWith(
      radarrUrl: 'http://radarr.local:7878',
      radarrApiKey: 'key',
      seerrUrl: withSeerr ? 'http://seerr.local:5055' : '',
      seerrApiKey: withSeerr ? 'key' : '',
      lidarrUrl: withLidarr ? 'http://lidarr.local:8686' : '',
      lidarrApiKey: withLidarr ? 'key' : '',
    ),
  ),
  if (prefs != null) sharedPreferencesProvider.overrideWithValue(prefs),
  globalSearchQueryProvider.overrideWith((ref) => query),
  seerrServiceProvider.overrideWith((ref) => seerr ?? _defaultSeerr()),
  seerrNumberingProvider.overrideWith((ref) async => null),
  radarrServiceProvider.overrideWith(
    (ref) => radarr ?? _Radarr(results: [_duneRadarr, _arrivalRadarr]),
  ),
];

Future<void> _pump(
  WidgetTester tester, {
  FakeSeerrService? seerr,
  RadarrService? radarr,
  String query = 'dune',
  bool withSeerr = true,
  bool settle = true,
  SharedPreferences? prefs,
}) async {
  tester.view.physicalSize = const Size(1170, 2532 * 2);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: _overrides(
        seerr: seerr,
        radarr: radarr,
        query: query,
        withSeerr: withSeerr,
        prefs: prefs,
      ),
      child: const MaterialApp(home: DiscoverPage()),
    ),
  );
  await _frames(tester);
  if (settle && query.isEmpty) await tester.pumpAndSettle();
}

GoRouter _router({bool withLidarr = false}) {
  final router = GoRouter(
    initialLocation: ServiceRoutes.discover,
    routes: [
      GoRoute(
        path: ServiceRoutes.discover,
        builder: (context, state) => const DiscoverPage(),
        routes: [
          GoRoute(
            path: 'media/movie/:id',
            builder: (context, state) => const Scaffold(body: Text('Title')),
          ),
        ],
      ),
      GoRoute(
        path: ServiceRoutes.lidarrLibrary,
        builder: (context, state) => const Scaffold(body: Text('Lidarr')),
      ),
    ],
  );
  addTearDown(router.dispose);
  return router;
}

Future<void> _pumpRouter(
  WidgetTester tester,
  GoRouter router, {
  bool withLidarr = false,
}) async {
  tester.view.physicalSize = const Size(1170, 2532 * 2);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: _overrides(withLidarr: withLidarr),
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await _frames(tester);
}

ProviderContainer _containerOf(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(DiscoverPage)));

/// Discrete frames rather than `pumpAndSettle`: a source still out draws a
/// shimmer that repeats, and a poster's load is never settled in a test.
Future<void> _frames(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Lets a parked source finish before the tree comes down: it holds its own
/// deadline timer, which a test may not leave pending.
Future<void> _release(WidgetTester tester, void Function() release) async {
  release();
  await tester.pump();
}
