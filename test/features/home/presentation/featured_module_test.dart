import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cupola/core/capability/audience.dart';
import 'package:cupola/core/status/arr_queue_snapshot.dart';
import 'package:cupola/core/status/lexicon.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/features/discover/domain/library_calendar.dart';
import 'package:cupola/features/home/data/featured.dart';
import 'package:cupola/features/home/data/resume.dart';
import 'package:cupola/features/home/domain/featured.dart';
import 'package:cupola/features/home/domain/home_layout.dart';
import 'package:cupola/features/home/domain/home_module.dart';
import 'package:cupola/features/home/presentation/widgets/continue_watching_module.dart';
import 'package:cupola/features/home/presentation/widgets/featured_module.dart';
import 'package:cupola/features/services/domain/arr_import.dart';
import 'package:cupola/features/services/domain/source_coverage.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/stream/domain/models/stream_item.dart';

import '../../../test_helpers/settings_scope.dart';

const _art = (url: 'https://art.test/wide.jpg', headers: null);

StreamItem _item(String id, String title) => StreamItem(
  id: id,
  title: title,
  subtitle: null,
  kind: StreamItemKind.movie,
  posterPath: null,
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
  item: _item(id, title),
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
  at: DateTime.now().subtract(const Duration(hours: 2)),
  reason: null,
  instanceId: 'radarr',
  tmdbId: 7,
  backdropUrl: 'https://art.test/spring.jpg',
);

final _spriteFright = CalendarEvent(
  identity: 'sprite-fright',
  kind: CalendarKind.movie,
  day: DateTime.now(),
  title: 'Sprite Fright',
  release: Lexicon.onDigital,
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

const _jellyfin = ServiceInstance(
  id: 'jellyfin',
  service: ServiceKey.jellyfin,
  url: 'http://jellyfin.local:8096',
  credential: 'key',
);

/// Featured on the Home: its slides as the pager draws them, and Continue
/// watching stepping aside for its first.
void main() {
  Future<void> pump(
    WidgetTester tester,
    Future<List<FeaturedSlide>> Function() slides, {
    HomeResume? resume,
    HomeLayout? layout,
  }) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final scope = await settingsScopeOverrides(
      configured: const [ServiceKey.jellyfin, ServiceKey.radarr],
    );
    if (layout != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        HomeLayout.keyFor(Audience.operator),
        layout.toJson(),
      );
    }
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...scope,
          featuredProvider.overrideWith((ref) => slides()),
          featuredAdvancesProvider.overrideWithValue(false),
          homeResumeProvider.overrideWith(
            (ref) async =>
                resume ??
                (
                  rows: const <ResumeRow>[],
                  coverage: SourceCoverage.answeredBy(ServiceKey.jellyfin),
                  viewerMissing: const <String>[],
                ),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.darkTheme(),
          home: Scaffold(
            body: ListView(
              children: const [
                HomeFeaturedModule(),
                HomeContinueWatchingModule(),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  testWidgets('each slide its two ways: Resume, Play where a server holds '
      'it, and the queue while it downloads', (tester) async {
    await pump(
      tester,
      () async => [
        FeaturedResume(_row('m1', 'Cosmos Laundromat'), art: _art),
        FeaturedArrival(
          _spring,
          art: _art,
          play: (
            service: _jellyfin.service,
            instanceId: _jellyfin.id,
            item: _item('jf-spring', 'Spring'),
          ),
        ),
        FeaturedToday(_spriteFright, art: _art),
      ],
    );
    for (final title in ['Cosmos Laundromat', 'Spring', 'Sprite Fright']) {
      expect(find.text(title), findsOne, reason: title);
    }
    expect(find.text('Resume'), findsOne);
    expect(find.text('Play'), findsOne);
    expect(find.text('Queue'), findsOne);
    // Beside Resume and Play, and leading the slide of today's release.
    expect(find.text('Details'), findsNWidgets(3));
    expect(find.text('Out on digital today · downloading 62%'), findsOne);
  });

  testWidgets('an arrival no server holds leads with Details alone, and one '
      'slide has no control', (tester) async {
    final semantics = tester.ensureSemantics();
    await pump(tester, () async => [FeaturedArrival(_spring, art: _art)]);
    expect(find.text('Details'), findsOne);
    expect(find.text('Play'), findsNothing);
    expect(find.bySemanticsLabel(RegExp('featured, 1 of')), findsNothing);
    semantics.dispose();
  });

  testWidgets('while it is read, the art box holds its place', (tester) async {
    final semantics = tester.ensureSemantics();
    final never = Completer<List<FeaturedSlide>>();
    await pump(tester, () => never.future);
    expect(find.bySemanticsLabel('Loading featured'), findsOne);
    semantics.dispose();
  });

  testWidgets('nothing to feature: no module', (tester) async {
    await pump(tester, () async => const []);
    expect(find.text('Details'), findsNothing);
    expect(find.text('Resume'), findsNothing);
  });

  group('Continue watching', () {
    final only = _row('m1', 'Cosmos Laundromat');

    HomeResume resumeOf(List<ResumeRow> rows) => (
      rows: rows,
      coverage: SourceCoverage.answeredBy(ServiceKey.jellyfin),
      viewerMissing: const <String>[],
    );

    testWidgets('steps aside when its only title is the first slide', (
      tester,
    ) async {
      await pump(
        tester,
        () async => [FeaturedResume(only, art: _art)],
        resume: resumeOf([only]),
      );
      expect(find.text('Continue watching'), findsNothing);
      expect(find.text('Resume'), findsOne);
    });

    testWidgets('stays with a second title', (tester) async {
      await pump(
        tester,
        () async => [FeaturedResume(only, art: _art)],
        resume: resumeOf([only, _row('m2', 'Sintel')]),
      );
      expect(find.text('Continue watching'), findsOne);
    });

    testWidgets('stays when Featured is off the Home', (tester) async {
      await pump(
        tester,
        () async => [FeaturedResume(only, art: _art)],
        resume: resumeOf([only]),
        layout: HomeLayout.defaultFor(
          Audience.operator,
        ).switched(HomeModule.featured, on: false),
      );
      expect(find.text('Continue watching'), findsOne);
    });
  });
}
