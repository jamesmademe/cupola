import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/last_known/last_known_store.dart';
import 'package:cupola/core/last_known/stored_image.dart';
import 'package:cupola/core/status/arr_queue_snapshot.dart';
import 'package:cupola/core/status/lexicon.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/features/discover/domain/library_calendar.dart';
import 'package:cupola/features/discover/presentation/library_calendar_provider.dart'
    show calendarClockProvider;
import 'package:cupola/features/home/data/featured.dart';
import 'package:cupola/features/home/data/last_known/featured_last_known.dart';
import 'package:cupola/features/home/data/resume.dart';
import 'package:cupola/features/home/domain/featured.dart';
import 'package:cupola/features/home/presentation/widgets/continue_watching_module.dart';
import 'package:cupola/features/home/presentation/widgets/featured_module.dart';
import 'package:cupola/features/home/presentation/widgets/home_as_of_line.dart';
import 'package:cupola/features/services/domain/arr_import.dart';
import 'package:cupola/features/services/domain/source_coverage.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/stream/domain/models/stream_item.dart';

import '../../../test_helpers/settings_scope.dart';

final _now = DateTime(2026, 10, 12, 20, 53);

StreamItem _item(String id, String title, {String? backdrop}) => StreamItem(
  id: id,
  title: title,
  subtitle: null,
  kind: StreamItemKind.movie,
  posterPath: null,
  backdropPath: backdrop,
  year: 2021,
  runtimeMs: 1500000,
  isPlayed: false,
  resumeOffsetMs: 1200000,
  unplayedChildCount: null,
);

ResumeRow _row(String id, String title) => (
  service: ServiceKey.jellyfin,
  instanceId: 'jellyfin',
  connectionName: null,
  item: _item(id, title, backdrop: '/Items/$id/Images/Backdrop/0'),
);

final _spring = ArrHistoryEntry(
  service: ServiceKey.radarr,
  id: 1,
  mediaId: 1,
  title: 'Spring',
  unitId: null,
  detail: null,
  posterUrl: '',
  outcome: ArrImportOutcome.imported,
  at: _now.subtract(const Duration(hours: 2)),
  reason: null,
  instanceId: 'radarr',
  tmdbId: 7,
  backdropUrl: 'https://art.test/spring.jpg',
);

final _spriteFright = CalendarEvent(
  identity: 'sprite-fright',
  kind: CalendarKind.movie,
  day: DateTime(_now.year, _now.month, _now.day),
  title: 'Sprite Fright',
  release: Lexicon.onDigital,
  backdrop: (url: 'https://art.test/sprite.jpg', headers: null),
  state: CalendarState.inFlight(
    mediaStatusFromQueue(
      availability: MediaAvailability.missing,
      monitored: true,
      queueEntry: const ArrQueueEntry(
        pipeline: MediaPipeline.downloading,
        progress: 0.62,
      ),
    ),
  ),
);

List<FeaturedSlide> _evening() => [
  FeaturedArrival(
    _spring,
    art: (url: _spring.backdropUrl, headers: null),
    play: (
      service: ServiceKey.jellyfin,
      instanceId: 'jellyfin',
      item: _item('jf-spring', 'Spring'),
    ),
  ),
  FeaturedToday(_spriteFright, art: _spriteFright.backdrop!),
];

/// Featured at a cold start: the slides the person last saw, with their Play,
/// until the live slides come (T1).
void main() {
  late LastKnownStore store;
  setUp(() => store = LastKnownStore.memory());

  Future<void> run(
    WidgetTester tester,
    Future<List<FeaturedSlide>> Function() slides, {
    DateTime? now,
    List<ResumeRow> resume = const [],
  }) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final clock = now ?? _now;
    await tester.pumpWidget(
      ProviderScope(
        key: UniqueKey(),
        overrides: [
          ...await settingsScopeOverrides(
            configured: const [ServiceKey.jellyfin, ServiceKey.radarr],
          ),
          lastKnownStoreProvider.overrideWithValue(store),
          calendarClockProvider.overrideWithValue(() => clock),
          arrivalsClockProvider.overrideWithValue(() => clock),
          featuredProvider.overrideWith((ref) => slides()),
          featuredAdvancesProvider.overrideWithValue(false),
          homeResumeProvider.overrideWith(
            (ref) async => (
              rows: resume,
              coverage: SourceCoverage.answeredBy(ServiceKey.jellyfin),
              viewerMissing: const <String>[],
            ),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.darkTheme(),
          home: Scaffold(
            body: ListView(
              // The line under a header, as on the Home: a list drops a
              // first child of no height before it can grow.
              children: const [
                SizedBox(height: 1),
                HomeAsOfLine(),
                HomeFeaturedModule(),
                HomeContinueWatchingModule(),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  Future<void> firstRun(
    WidgetTester tester, {
    List<FeaturedSlide>? slides,
  }) async {
    await run(tester, () async => slides ?? _evening());
    await tester.pumpAndSettle();
    expect(find.text('Spring'), findsWidgets);
  }

  testWidgets('draws the last slides at once, with their Play, then the live '
      'ones', (tester) async {
    await firstRun(tester);

    final answer = Completer<List<FeaturedSlide>>();
    await run(tester, () => answer.future);
    expect(find.text('Spring'), findsWidgets);
    expect(find.text('Play'), findsWidgets);
    expect(find.text('As of 20:53 · checking now'), findsOne);

    answer.complete(const []);
    await tester.pumpAndSettle();
    expect(find.text('Spring'), findsNothing);
    expect(find.textContaining('As of'), findsNothing);
  });

  testWidgets('a download of today says no figure from a drawing', (
    tester,
  ) async {
    await firstRun(tester);
    await run(tester, () => Completer<List<FeaturedSlide>>().future);

    expect(find.textContaining('62%'), findsNothing);
  });

  testWidgets('a drawing of another day keeps what is still true', (
    tester,
  ) async {
    await firstRun(tester);
    await run(
      tester,
      () => Completer<List<FeaturedSlide>>().future,
      now: _now.add(const Duration(days: 1)),
    );

    // Today's slide was yesterday's; the arrival is a day older.
    expect(find.text('Sprite Fright'), findsNothing);
    expect(find.text('Spring'), findsWidgets);
    expect(find.text('As of yesterday 20:53 · checking now'), findsOne);
  });

  testWidgets('Continue watching steps aside for the title a drawing leads '
      'with', (tester) async {
    final row = _row('e1', 'Charge');
    await firstRun(
      tester,
      slides: [
        FeaturedResume(
          row,
          art: (url: 'https://jellyfin.test/backdrop.jpg', headers: null),
        ),
        ..._evening(),
      ],
    );
    await run(
      tester,
      () => Completer<List<FeaturedSlide>>().future,
      resume: [row],
    );
    await tester.pump();

    expect(find.text('Continue watching'), findsNothing);
  });

  test('a slide keeps no credential, and comes back whole', () {
    final slides = [
      FeaturedResume(
        _row('e1', 'Charge'),
        art: (
          url: 'https://jellyfin.test/Items/e1/Images/Backdrop/0',
          headers: const {'Authorization': 'MediaBrowser Token="secret-token"'},
        ),
      ),
      ..._evening(),
    ];
    final data = featuredLastKnown.encode(slides);
    final json = jsonEncode(data);
    expect(json, isNot(contains('secret-token')));
    expect(json, isNot(contains('Authorization')));

    final back = featuredLastKnown.decode(
      jsonDecode(json),
      (image) => switch (image) {
        StoredUrl(:final url) => (url: url, headers: null),
        StoredStreamImage(:final path) => (
          url: 'https://jellyfin.test$path',
          headers: const {'Authorization': 'from the connection today'},
        ),
        StoredArrImage(:final url) => (url: url, headers: null),
      },
    )!;
    expect(
      [for (final slide in back) slide.title],
      ['Charge', 'Spring', 'Sprite Fright'],
    );
    expect((back[1] as FeaturedArrival).play?.item.id, 'jf-spring');
    expect(back[0].art.headers, {'Authorization': 'from the connection today'});
  });
}
