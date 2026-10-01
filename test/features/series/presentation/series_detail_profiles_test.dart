import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/series/domain/models/sonarr_series.dart';
import 'package:cupola/features/series/presentation/series_detail_provider.dart';
import 'package:cupola/features/series/presentation/series_detail_screen.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import '../../../test_helpers/profiles/profiles.dart';

/// The container the page under test reads from.
ProviderContainer _container(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(SeriesDetailScreen)));

void main() {
  group('a Sonarr that is not set up', () {
    testWidgets('says so on the first frame and asks Sonarr nothing', (
      tester,
    ) async {
      final harness = await pumpWithProfile(
        tester,
        Profiles.p3.without(ServiceKey.sonarr),
        child: const SeriesDetailScreen(seriesId: 1, heroTag: 'series-1'),
        settle: false,
      );
      await tester.pump();

      expect(find.byType(NotConfiguredPlaceholder), findsOneWidget);
      expect(find.byType(MediaDetailLoadingView), findsNothing);
      const item = (instanceId: '', id: 1);
      expect(_container(tester).exists(seriesDetailForProvider(item)), isFalse);
      expect(
        _container(tester).exists(seriesEpisodesForProvider(item)),
        isFalse,
      );

      await harness.unmount(tester);
    });

    testWidgets('a preloaded series does not stand in for a Sonarr', (
      tester,
    ) async {
      final harness = await pumpWithProfile(
        tester,
        Profiles.p3.without(ServiceKey.sonarr),
        child: SeriesDetailScreen(
          seriesId: 1,
          heroTag: 'series-1',
          initialSeries: SonarrSeries.fromJson(const {
            'id': 1,
            'title': 'Charge',
            'year': 2022,
            'path': '/tv/Charge',
          }),
        ),
        settle: false,
      );
      await tester.pump();

      expect(find.byType(NotConfiguredPlaceholder), findsOneWidget);
      expect(find.text('Charge'), findsNothing);

      await harness.unmount(tester);
    });
  });

  group('the episode list', () {
    testWidgets('a failed read offers a Retry that asks for the episodes', (
      tester,
    ) async {
      var episodesAnswer = false;
      // Sonarr answers the series and fails the episodes, the one read this
      // page exists for.
      final harness = await _pump(
        tester,
        Profiles.p7,
        const SeriesDetailScreen(seriesId: 1, heroTag: 'series-1'),
        routes: (network) => network.on(
          WorldIds.sonarr,
          'GET',
          '/api/v3/episode',
          (_) => episodesAnswer
              ? null
              : NetworkReply.json({'message': 'boom'}, status: 500),
        ),
      );

      final retry = find.descendant(
        of: find.byType(AppErrorState),
        matching: find.text('Retry'),
      );
      await tester.ensureVisible(retry);
      await harness.settle(tester);
      expect(find.text('Sonarr answered with an error'), findsOneWidget);

      episodesAnswer = true;
      final asked = _episodeReads(harness);
      await tester.tap(retry);
      await harness.settle(tester);

      expect(_episodeReads(harness), greaterThan(asked));
      expect(find.byType(AppErrorState), findsNothing);
      expect(find.byType(MediaChildTile), findsWidgets);

      await harness.unmount(tester);
    });
  });

  group('a refresh of the episodes that fails', () {
    testWidgets('keeps the episodes it had, under a line with Retry', (
      tester,
    ) async {
      var episodesFail = false;
      final harness = await _pump(
        tester,
        Profiles.p7,
        const SeriesDetailScreen(seriesId: 1, heroTag: 'series-1'),
        routes: (network) => network.on(
          WorldIds.sonarr,
          'GET',
          '/api/v3/episode',
          (_) => episodesFail
              ? NetworkReply.json({'message': 'boom'}, status: 500)
              : null,
        ),
      );
      expect(find.byType(MediaChildTile), findsWidgets);

      episodesFail = true;
      await tester
          .widget<RefreshIndicator>(find.byType(RefreshIndicator))
          .onRefresh();
      await harness.settle(tester);

      // The series answered, so no page band; the rows stay, and the line
      // above them says what they are.
      expect(find.byType(FaultBand), findsNothing);
      expect(find.byType(AppErrorState), findsNothing);
      expect(find.byType(MediaChildTile), findsWidgets);
      final line = find.text(
        'Sonarr answered with an error, so these are the episodes it listed '
        'last.',
      );
      expect(line, findsOneWidget);

      episodesFail = false;
      final retry = find.descendant(
        of: find.byType(InlineErrorRetry),
        matching: find.text('Retry'),
      );
      await tester.ensureVisible(retry);
      await harness.settle(tester);
      await tester.tap(retry);
      await harness.settle(tester);

      expect(line, findsNothing);
      expect(find.byType(MediaChildTile), findsWidgets);

      await harness.unmount(tester);
    });
  });

  group('a Sonarr that does not answer', () {
    final sonarrDown = Profiles.p7.withBehaviour(
      WorldIds.sonarr,
      ConnectionBehaviour.didNotAnswer,
    );

    testWidgets('a preloaded series stays, under a red band that says so', (
      tester,
    ) async {
      final harness = await _pump(
        tester,
        sonarrDown,
        SeriesDetailScreen(
          seriesId: 1,
          heroTag: 'series-1',
          initialSeries: SonarrSeries.fromJson(const {
            'id': 1,
            'title': 'Cosmos Laundromat',
            'year': 2015,
            'monitored': true,
            'qualityProfileId': 1,
            'path': '/mnt/tank/media/series/Cosmos Laundromat',
          }),
        ),
      );

      expect(find.text('Cosmos Laundromat'), findsWidgets);
      final band = tester.widget<FaultBand>(find.byType(FaultBand));
      expect(band.tone, StatusTone.error);
      expect(
        band.message,
        'Sonarr did not answer. Everything below is what it said last.',
      );

      final asked = harness.network.requestsTo(WorldIds.sonarr).length;
      await tester.tap(
        find.descendant(
          of: find.byType(FaultBand),
          matching: find.text('Retry'),
        ),
      );
      await harness.settle(tester);
      // The series and its episodes, both: one outage, one Retry.
      final paths = harness.network
          .requestsTo(WorldIds.sonarr)
          .skip(asked)
          .map((r) => r.uri.path)
          .toSet();
      expect(paths, containsAll(['/api/v3/series/1', '/api/v3/episode']));

      await harness.unmount(tester);
    });

    testWidgets('the episodes do not say it a second time', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 3000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final harness = await _pump(
        tester,
        sonarrDown,
        SeriesDetailScreen(
          seriesId: 1,
          heroTag: 'series-1',
          initialSeries: SonarrSeries.fromJson(const {
            'id': 1,
            'title': 'Cosmos Laundromat',
            'year': 2015,
            'monitored': true,
            'qualityProfileId': 1,
            'path': '/mnt/tank/media/series/Cosmos Laundromat',
            'seasons': [
              {
                'seasonNumber': 1,
                'monitored': true,
                'statistics': {
                  'episodeFileCount': 10,
                  'episodeCount': 10,
                  'totalEpisodeCount': 10,
                },
              },
            ],
          }),
        ),
      );

      // One statement of the silence, at the top of the page.
      expect(find.byType(FaultBand), findsOneWidget);
      expect(find.text('Sonarr did not answer'), findsNothing);
      expect(find.byType(AppErrorState), findsNothing);
      expect(find.byType(InlineErrorRetry), findsNothing);
      expect(
        find.text('The episodes appear here once Sonarr sends them.'),
        findsOneWidget,
      );

      await harness.unmount(tester);
    });

    testWidgets('a cold open says it did not answer, at once', (tester) async {
      final harness = await _pump(
        tester,
        sonarrDown,
        const SeriesDetailScreen(seriesId: 1, heroTag: 'series-1'),
      );

      expect(find.text('Sonarr did not answer'), findsOneWidget);
      expect(
        harness.network
            .requestsTo(WorldIds.sonarr)
            .where((r) => r.uri.path == '/api/v3/series/1'),
        hasLength(1),
      );

      await harness.unmount(tester);
    });
  });

  group('a queue the page could not read', () {
    testWidgets('is said over a series not all on disk', (tester) async {
      var failing = true;
      final harness = await _pump(
        tester,
        Profiles.p7,
        const SeriesDetailScreen(seriesId: 1, heroTag: 'series-1'),
        routes: (network) => network.on(
          WorldIds.sonarr,
          'GET',
          '/api/v3/queue',
          (_) => failing
              ? NetworkReply.json({'message': 'boom'}, status: 500)
              : null,
        ),
      );

      expect(
        find.text(
          "Sonarr's queue answered with an error, so this page cannot tell "
          'whether any of it is downloading.',
        ),
        findsOneWidget,
      );
      // What is on disk stands: a queue nobody could read only takes away
      // the claim that nothing is on its way.
      expect(_badge(tester).label, 'Partial');

      failing = false;
      await tester.tap(
        find.descendant(
          of: find.byType(InlineErrorRetry),
          matching: find.text('Retry'),
        ),
      );
      await harness.settle(tester);
      expect(find.byType(InlineErrorRetry), findsNothing);
      // The 18 grabs Sonarr will not place on its own outrank the two still
      // downloading.
      expect(_badge(tester).label, 'Import blocked');

      await harness.unmount(tester);
    });
  });

  group('a queue that answered', () {
    testWidgets('names the downloads it holds', (tester) async {
      final harness = await _pump(
        tester,
        Profiles.p1,
        const SeriesDetailScreen(seriesId: 1, heroTag: 'series-1'),
      );

      expect(_badge(tester).label, 'Import blocked');
      expect(find.byType(InlineErrorRetry), findsNothing);

      await harness.unmount(tester);
    });
  });
}

/// The status the hero's badge reads.
MediaStatusInfo _badge(WidgetTester tester) => tester
    .widget<StatusBadge>(
      find.descendant(
        of: find.byType(MediaDetailPosterRow),
        matching: find.byType(StatusBadge),
      ),
    )
    .info;

/// Pumps [child] under [profile] with [routes] answering ahead of the world
/// from the first request on, which `pumpWithProfile` cannot do: its first
/// frame has already asked by the time it hands the harness back.
Future<ProfileHarness> _pump(
  WidgetTester tester,
  ConfigProfile profile,
  Widget child, {
  void Function(ProfileNetwork network)? routes,
  List<Override> overrides = const [],
}) async {
  final harness = await ProfileHarness.start(profile, overrides: overrides);
  routes?.call(harness.network);
  await tester.pumpWidget(
    ProviderScope(
      overrides: harness.overrides,
      child: MaterialApp(theme: AppTheme.darkTheme(), home: child),
    ),
  );
  await harness.settle(tester);
  return harness;
}

int _episodeReads(ProfileHarness harness) => harness.network
    .requestsTo(WorldIds.sonarr)
    .where((r) => r.uri.path == '/api/v3/episode')
    .length;
