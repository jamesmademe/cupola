import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/series/domain/models/sonarr_series.dart';
import 'package:cupola/features/series/presentation/series_detail_view_model.dart';

void main() {
  group('SeriesDetailViewModel', () {
    SonarrSeries makeSeries({
      String? seriesType,
      String? certification,
      String? firstAired,
      String? lastAired,
      String? originalLanguage,
      String? network,
      List<String> genres = const [],
      int year = 2023,
      int runtime = 45,
      Map<String, dynamic>? statistics,
    }) {
      return SonarrSeries(
        id: 1,
        title: 'Test Series',
        sortTitle: 'test series',
        status: 'continuing',
        overview: 'A great series.',
        monitored: true,
        year: year,
        images: const [],
        tvdbId: 200,
        runtime: runtime,
        network: network,
        genres: genres,
        seasons: const [],
        statistics: statistics,
        seriesType: seriesType,
        certification: certification,
        firstAired: firstAired,
        lastAired: lastAired,
        originalLanguage: originalLanguage == null
            ? null
            : {'id': 1, 'name': originalLanguage},
      );
    }

    group('fromSeries', () {
      test('maps basic fields', () {
        final vm = SeriesDetailViewModel.fromSeries(
          makeSeries(network: 'HBO'),
          baseUrl: 'http://localhost:8989',
          apiKey: 'test-key',
        );

        expect(vm.title, 'Test Series');
        expect(vm.network, 'HBO');
      });

      test('maps enrichment fields', () {
        final vm = SeriesDetailViewModel.fromSeries(
          makeSeries(
            seriesType: 'standard',
            certification: 'TV-MA',
            firstAired: '2023-01-15T00:00:00Z',
            lastAired: '2023-12-20T00:00:00Z',
            originalLanguage: 'English',
          ),
          baseUrl: 'http://localhost:8989',
          apiKey: 'test-key',
        );

        expect(vm.seriesType, 'standard');
        expect(vm.certification, 'TV-MA');
        expect(vm.firstAired, '2023-01-15T00:00:00Z');
        expect(vm.lastAired, '2023-12-20T00:00:00Z');
        expect(vm.originalLanguage, 'English');
      });
    });

    group('episodeSummary', () {
      test('returns season and episode counts', () {
        final vm = SeriesDetailViewModel.fromSeries(
          makeSeries(
            statistics: {
              'seasonCount': 3,
              'episodeCount': 30,
              'episodeFileCount': 28,
            },
          ),
          baseUrl: 'http://localhost:8989',
          apiKey: 'test-key',
        );

        expect(vm.episodeSummary, contains('3 Seasons'));
        expect(vm.episodeSummary, contains('30 Episodes'));
      });

      test('returns null when no stats', () {
        final vm = SeriesDetailViewModel.fromSeries(
          makeSeries(),
          baseUrl: 'http://localhost:8989',
          apiKey: 'test-key',
        );

        expect(vm.episodeSummary, isNull);
      });
    });

    group('diskCounts', () {
      SeriesDetailViewModel withStats(Map<String, dynamic> statistics) =>
          SeriesDetailViewModel.fromSeries(
            makeSeries(statistics: statistics),
            baseUrl: 'http://localhost:8989',
            apiKey: 'test-key',
          );

      test('carries both figures when Sonarr sent both', () {
        final counts = withStats({
          'episodeCount': 24,
          'episodeFileCount': 18,
        }).diskCounts;
        expect(counts?.onDisk, 18);
        expect(counts?.expected, 24);
      });

      test('is unknown, never zero, when a figure is missing', () {
        // `?? 0` turned a file count Sonarr left out into "0 of 24 episodes on
        // disk" — the worst gap a series can have, from no data at all.
        expect(withStats({'episodeCount': 24}).diskCounts, isNull);
        expect(withStats({'episodeFileCount': 18}).diskCounts, isNull);
      });

      test('states no gap while nothing is expected yet', () {
        expect(
          withStats({'episodeCount': 0, 'episodeFileCount': 0}).diskCounts,
          isNull,
        );
      });
    });

    group('buildInfoGroups', () {
      testWidgets('the Episodes cell reads an em dash for a missing figure', (
        tester,
      ) async {
        final vm = SeriesDetailViewModel.fromSeries(
          makeSeries(statistics: {'episodeCount': 24}),
          baseUrl: 'http://localhost:8989',
          apiKey: 'test-key',
        );
        final episodes = vm
            .buildInfoGroups('HD-1080p')
            .firstWhere((group) => group.title == 'Episodes');

        await tester.pumpWidget(
          MaterialApp(home: Scaffold(body: episodes.child)),
        );

        expect(find.text('— / 24'), findsOneWidget);
        expect(find.textContaining('0'), findsNothing);
        // Spoken as what the dash means, never as "dash".
        expect(
          tester.getSemantics(find.text('— / 24')),
          matchesSemantics(label: 'unknown of 24'),
        );
      });

      test('the Episodes cell keeps both figures when Sonarr sent both', () {
        final vm = SeriesDetailViewModel.fromSeries(
          makeSeries(statistics: {'episodeCount': 24, 'episodeFileCount': 18}),
          baseUrl: 'http://localhost:8989',
          apiKey: 'test-key',
        );
        final episodes = vm
            .buildInfoGroups('HD-1080p')
            .firstWhere((group) => group.title == 'Episodes');

        expect((episodes.child as Text).data, '18 / 24');
      });

      test('returns empty when no data', () {
        final vm = SeriesDetailViewModel.fromSeries(
          makeSeries(),
          baseUrl: 'http://localhost:8989',
          apiKey: 'test-key',
        );

        expect(vm.buildInfoGroups(null), isEmpty);
      });

      test('includes series type capitalized', () {
        final vm = SeriesDetailViewModel.fromSeries(
          makeSeries(seriesType: 'anime'),
          baseUrl: 'http://localhost:8989',
          apiKey: 'test-key',
        );

        final typeGroup = vm
            .buildInfoGroups(null)
            .firstWhere((group) => group.title == 'Series type');

        expect(typeGroup.child, isA<Text>());
        expect((typeGroup.child as Text).data, 'Anime');
      });

      test('includes air dates as MediaFactsList', () {
        final vm = SeriesDetailViewModel.fromSeries(
          makeSeries(
            firstAired: '2023-01-15T00:00:00Z',
            lastAired: '2023-12-20T00:00:00Z',
          ),
          baseUrl: 'http://localhost:8989',
          apiKey: 'test-key',
        );

        final airDatesGroup = vm
            .buildInfoGroups(null)
            .firstWhere((group) => group.title == 'Air dates');

        expect(airDatesGroup.child, isA<MediaFactsList>());
      });

      test('preserves group order', () {
        final vm = SeriesDetailViewModel.fromSeries(
          makeSeries(
            seriesType: 'standard',
            certification: 'TV-14',
            originalLanguage: 'English',
            firstAired: '2023-01-15T00:00:00Z',
            genres: const ['Drama'],
            network: 'Netflix',
          ),
          baseUrl: 'http://localhost:8989',
          apiKey: 'test-key',
        );

        expect(vm.buildInfoGroups(null).map((group) => group.title).toList(), [
          'Series type',
          'Certification',
          'Original language',
          'Air dates',
          'Genre',
          'Network',
        ]);
      });

      test('the Series Type cell takes the caller\'s control when given', () {
        // Decision 50 turns that cell into a write. The view model holds no
        // service and no `ref`, so the screen passes the control in — but the
        // view model stays the one place that decides where the cell sits, so
        // the control cannot drift out of the Details card.
        const control = SizedBox(key: Key('series-type-control'));
        final vm = SeriesDetailViewModel.fromSeries(
          makeSeries(seriesType: 'anime'),
          baseUrl: 'http://localhost:8989',
          apiKey: 'test-key',
        );

        final withControl = vm
            .buildInfoGroups(null, seriesTypeControl: control)
            .firstWhere((group) => group.title == 'Series type');
        expect(withControl.child, same(control));

        // And without one it is still a fact — which is what a series this
        // Sonarr does not hold has to stay.
        final withoutControl = vm
            .buildInfoGroups(null)
            .firstWhere((group) => group.title == 'Series type');
        expect(withoutControl.child, isA<Text>());
      });
    });
  });
}
