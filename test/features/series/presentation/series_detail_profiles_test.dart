import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
}

/// Pumps [child] under [profile] with [routes] answering ahead of the world
/// from the first request on, which `pumpWithProfile` cannot do: its first
/// frame has already asked by the time it hands the harness back.
Future<ProfileHarness> _pump(
  WidgetTester tester,
  ConfigProfile profile,
  Widget child, {
  void Function(ProfileNetwork network)? routes,
}) async {
  final harness = await ProfileHarness.start(profile);
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
