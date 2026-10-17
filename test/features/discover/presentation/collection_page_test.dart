import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/models/media_preview.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/discover/domain/models/collection_detail.dart';
import 'package:cupola/features/discover/presentation/collection_page.dart';
import 'package:cupola/features/discover/presentation/discover_details_provider.dart';
import 'package:cupola/features/media/presentation/media_decision_card.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import '../../../test_helpers/profiles/fakes/media_fakes.dart';
import '../../../test_helpers/profiles/profiles.dart';
import '../../../test_helpers/settings_scope.dart';

const _collectionId = 42;

CollectionDetail _collection({List<MediaPreview> parts = const []}) =>
    CollectionDetail(
      id: _collectionId,
      name: 'The Trilogy',
      overview: 'Three films.',
      parts: parts,
    );

Future<void> _pump(
  WidgetTester tester,
  FutureOr<CollectionDetail> Function(Ref ref, int id) builder,
) async {
  await tester.pumpWidget(
    ProviderScope(
      // Riverpod 3 re-runs a failed provider on its own backoff schedule, which
      // would make the load count non-deterministic. Switched off so the test
      // measures only what the retry button does.
      retry: (retryCount, error) => null,
      overrides: [
        currentSettingsProvider.overrideWith(
          (ref) => settingsWithServices([ServiceKey.seerr]),
        ),
        collectionDetailProvider.overrideWith(builder),
        seerrNumberingProvider.overrideWith((ref) async => null),
      ],
      child: const MaterialApp(
        home: CollectionPage(collectionId: _collectionId),
      ),
    ),
  );
}

Future<ProfileHarness> _blender(WidgetTester tester, ConfigProfile profile) =>
    pumpWithProfile(
      tester,
      profile,
      child: const CollectionPage(collectionId: SeerrFake.collectionId),
      surfaceSize: const Size(430, 2400),
    );

void main() {
  group('CollectionPage', () {
    testWidgets('a failed lookup names Seerr and is not a dead end', (
      tester,
    ) async {
      var loads = 0;
      await _pump(tester, (ref, id) {
        loads++;
        return Future<CollectionDetail>.error(Exception('Connection refused'));
      });
      await tester.pumpAndSettle();

      expect(find.byType(AppErrorState), findsOneWidget);
      expect(
        find.text('The request to Seerr did not complete'),
        findsOneWidget,
      );
      // The exception's own words never reach the screen, and a failure
      // nobody can attribute adds no sentence that repeats the headline.
      expect(find.textContaining('Connection refused'), findsNothing);
      expect(find.text('The request did not complete.'), findsNothing);
      expect(loads, 1);

      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      // The retry re-runs the very lookup that failed, in place.
      expect(loads, 2);
    });

    testWidgets('an empty collection is not dressed as a failure', (
      tester,
    ) async {
      await _pump(
        tester,
        (ref, id) async => const CollectionDetail(id: 0, name: ''),
      );
      await tester.pumpAndSettle();

      // Empty-state voice, and copy that says which nothing this is: it must
      // not read like the network error above.
      expect(find.byType(AppEmptyState), findsOneWidget);
      expect(find.byType(AppErrorState), findsNothing);
      expect(find.text('No collection here'), findsOneWidget);
      expect(find.text('The request to Seerr did not complete'), findsNothing);
      expect(find.text('Retry'), findsNothing);
    });

    testWidgets('a loaded collection lists its movies, oldest first', (
      tester,
    ) async {
      await _pump(
        tester,
        (ref, id) async => _collection(
          parts: const [
            MediaPreview(
              id: 8,
              mediaType: 'movie',
              title: 'Part Two',
              releaseDate: '2004-05-01',
            ),
            MediaPreview(
              id: 7,
              mediaType: 'movie',
              title: 'Part One',
              releaseDate: '2001-05-01',
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(AppErrorState), findsNothing);
      expect(find.byType(AppEmptyState), findsNothing);
      expect(find.text('The Trilogy'), findsOneWidget);
      expect(
        find.text('Collection\u00A0· 2 movies\u00A0· 2001–2004'),
        findsOneWidget,
      );
      expect(find.text('0 of 2 on your server'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Part One')).dy,
        lessThan(tester.getTopLeft(find.text('Part Two')).dy),
      );
      // A pull reads the page again.
      expect(find.byType(RefreshIndicator), findsOneWidget);
    });

    testWidgets('a collection with no titles filed under it says so', (
      tester,
    ) async {
      await _pump(tester, (ref, id) async => _collection());
      await tester.pumpAndSettle();

      // A valid collection with zero parts used to render a full hero over an
      // empty rail that collapsed to nothing.
      expect(find.text('In release order'), findsOneWidget);
      expect(
        find.text('TMDB lists no movies in this collection yet.'),
        findsOneWidget,
      );
    });
  });

  group('on the profiles', () {
    testWidgets('P1: how much is on the server, and the request to approve', (
      tester,
    ) async {
      final harness = await _blender(tester, Profiles.p1);

      expect(find.text(SeerrFake.collectionName), findsOneWidget);
      expect(find.text('5 of 8 on your server'), findsOneWidget);
      expect(find.text('2 on the way'), findsOneWidget);
      expect(find.text('1 waiting for approval'), findsOneWidget);
      // The request for Charge, answered here as on its own page.
      expect(find.byType(MediaDecisionCard), findsOneWidget);
      expect(find.text('Approve'), findsOneWidget);
      // In release order.
      expect(
        tester.getTopLeft(find.text('Elephants Dream')).dy,
        lessThan(tester.getTopLeft(find.text('Charge').last).dy),
      );

      await harness.unmount(tester);
    });

    testWidgets('P2: the collection without anyone else\'s requests, and no '
        'service named', (tester) async {
      final harness = await _blender(tester, Profiles.p2);

      expect(find.text('5 of 8 on your server'), findsOneWidget);
      expect(find.byType(MediaDecisionCard), findsNothing);
      expect(find.textContaining('Seerr'), findsNothing);
      expect(find.textContaining('Radarr'), findsNothing);

      await harness.unmount(tester);
    });
  });
}
