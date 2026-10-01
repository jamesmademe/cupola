import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/bazarr/domain/models/bazarr_models.dart';
import 'package:cupola/features/bazarr/presentation/bazarr_movie_detail_screen.dart';
import 'package:cupola/features/bazarr/presentation/bazarr_series_detail_screen.dart';

import '../../../test_helpers/profiles/profiles.dart';

/// The wanted row a page is opened from: it names the languages and the
/// title, never the record's own figures.
const _wantedMovie = BazarrWantedItem(
  title: 'Tears of Steel',
  radarrId: 5,
  missingLanguages: [
    BazarrSubtitleLanguage(code2: 'de', code3: 'deu', name: 'German'),
  ],
);

const _wantedEpisode = BazarrWantedItem(
  seriesTitle: 'Cosmos Laundromat',
  episodeNumber: '2x01',
  episodeTitle: 'Episode 1',
  sonarrSeriesId: 1,
  sonarrEpisodeId: 1011,
  missingLanguages: [
    BazarrSubtitleLanguage(code2: 'it', code3: 'ita', name: 'Italian'),
  ],
);

int _reads(ProfileHarness harness, String path) => harness.network
    .requestsTo(WorldIds.bazarr)
    .where((r) => r.uri.path == path)
    .length;

void main() {
  group('a Bazarr movie page opened from the wanted list', () {
    testWidgets('says the lookup did not answer, over what it was handed', (
      tester,
    ) async {
      // P7: Bazarr does not answer.
      final harness = await _pump(
        tester,
        Profiles.p7,
        const BazarrMovieDetailScreen(radarrId: 5, initialWanted: _wantedMovie),
      );

      // The fallback stays: the title and the languages the row named.
      expect(find.text('Tears of Steel'), findsWidgets);
      // And the dash is no longer the only trace of what happened.
      expect(
        find.text(
          'Bazarr did not answer, so the movie record is missing from this '
          'page.',
        ),
        findsOneWidget,
      );
      _expectGlyphTone(tester, StatusTone.error);

      final asked = _reads(harness, '/api/movies');
      await tester.tap(
        find.descendant(
          of: find.byType(InlineErrorRetry),
          matching: find.text('Retry'),
        ),
      );
      await harness.settle(tester);
      expect(_reads(harness, '/api/movies'), greaterThan(asked));

      await harness.unmount(tester);
    });

    testWidgets('a lookup Bazarr answered with a fault is amber', (
      tester,
    ) async {
      var failing = true;
      final harness = await _pump(
        tester,
        Profiles.p1,
        const BazarrMovieDetailScreen(radarrId: 5, initialWanted: _wantedMovie),
        routes: (network) => network.on(
          WorldIds.bazarr,
          'GET',
          '/api/movies',
          (_) => failing
              ? NetworkReply.json({'message': 'boom'}, status: 500)
              : null,
        ),
      );

      expect(
        find.text(
          'Bazarr answered with an error, so the movie record is missing '
          'from this page.',
        ),
        findsOneWidget,
      );
      _expectGlyphTone(tester, StatusTone.warning);

      failing = false;
      await tester.tap(
        find.descendant(
          of: find.byType(InlineErrorRetry),
          matching: find.text('Retry'),
        ),
      );
      await harness.settle(tester);

      // Answered: the line goes, whatever the answer was.
      expect(find.byType(InlineErrorRetry), findsNothing);

      await harness.unmount(tester);
    });
  });

  group('a Bazarr series page opened from the wanted list', () {
    testWidgets('says the lookup did not answer, over what it was handed', (
      tester,
    ) async {
      final harness = await _pump(
        tester,
        Profiles.p7,
        const BazarrSeriesDetailScreen(
          sonarrSeriesId: 1,
          initialWanted: _wantedEpisode,
        ),
      );

      expect(find.text('Cosmos Laundromat'), findsWidgets);
      expect(
        find.text(
          'Bazarr did not answer, so the series record is missing from this '
          'page.',
        ),
        findsOneWidget,
      );

      final asked = _reads(harness, '/api/series');
      await tester.tap(
        find.descendant(
          of: find.byType(InlineErrorRetry),
          matching: find.text('Retry'),
        ),
      );
      await harness.settle(tester);
      expect(_reads(harness, '/api/series'), greaterThan(asked));

      await harness.unmount(tester);
    });
  });

  group('a Bazarr page opened cold on a Bazarr that does not answer', () {
    testWidgets('a movie says so at once, after one walk of the list', (
      tester,
    ) async {
      final harness = await _pump(
        tester,
        Profiles.p7,
        const BazarrMovieDetailScreen(radarrId: 5),
      );

      // It used to sit on its skeleton through a minute of backoff first.
      expect(find.text('Bazarr did not answer'), findsOneWidget);
      expect(_reads(harness, '/api/movies'), 1);

      await harness.unmount(tester);
    });

    testWidgets('a series says so at once, after one walk of the list', (
      tester,
    ) async {
      final harness = await _pump(
        tester,
        Profiles.p7,
        const BazarrSeriesDetailScreen(sonarrSeriesId: 1),
      );

      expect(find.text('Bazarr did not answer'), findsOneWidget);
      expect(_reads(harness, '/api/series'), 1);

      await harness.unmount(tester);
    });
  });
}

/// The line's one glyph carries the tone, walked for the ground it is on.
void _expectGlyphTone(WidgetTester tester, StatusTone tone) {
  final context = tester.element(find.byType(InlineErrorRetry));
  final scheme = Theme.of(context).colorScheme;
  final glyph = tester.widget<Icon>(
    find.descendant(
      of: find.byType(InlineErrorRetry),
      matching: find.byType(Icon),
    ),
  );
  expect(glyph.color, statusToneColor(scheme, tone, surface: scheme.surface));
}

/// Pumps [child] under [profile] with [routes] answering ahead of the world
/// from the first request on.
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
