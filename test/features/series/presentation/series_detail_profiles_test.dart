import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

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
}
