import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/media_detail_view.dart';
import 'package:cupola/features/discover/presentation/collection_detail_screen.dart';
import 'package:cupola/features/discover/presentation/discover_catalog.dart';
import 'package:cupola/features/search/presentation/search_screen.dart';
import 'package:cupola/features/discover/presentation/discover_see_all_screen.dart';
import 'package:cupola/features/discover/presentation/person_detail_screen.dart';

import '../../../test_helpers/profiles/profiles.dart';

/// Every page fed by Seerr asks whether there is a Seerr before it asks Seerr.
///
/// The other order is a provider that throws for a condition no retry can
/// change: the film page's lookup failed and was asked again ten times over
/// forty seconds, under a placeholder that looked settled, and the Discover
/// tab drew a search bar over rails that each stood aside for a message
/// nobody drew.
void main() {
  // P4 is the stack with no Seerr in it: Radarr, Sonarr, Lidarr, Prowlarr and
  // two download clients. A title's own page reads from those and draws
  // Seerr as one row to set up: the Media page's tests hold it.
  group('P4, no Seerr', () {
    final pages = <String, Widget>{
      'a person': const PersonDetailScreen(personId: 17),
      'a collection': const CollectionDetailScreen(collectionId: 3),
      'See all': const DiscoverSeeAllScreen(type: 'movies', title: 'Movies'),
    };

    for (final MapEntry(key: name, value: page) in pages.entries) {
      testWidgets('$name says Seerr is not set up and asks nothing', (
        tester,
      ) async {
        final harness = await ProfileHarness.start(Profiles.p4);
        final failures = _FailureLog();
        await tester.pumpWidget(
          ProviderScope(
            overrides: harness.overrides,
            observers: [failures],
            child: MaterialApp(theme: AppTheme.darkTheme(), home: page),
          ),
        );

        // The first frame already says it: the answer is not something to
        // wait for.
        expect(find.text('Seerr is not set up'), findsOneWidget);
        expect(_setUpButton('Seerr'), findsOneWidget);
        expect(find.byType(MediaDetailLoadingView), findsNothing);

        // And nothing was asked. A provider that reached for the missing
        // Seerr would fail here, and the film page's did, ten times over
        // forty seconds of backoff, under a placeholder that looked settled.
        await tester.pump(const Duration(minutes: 1));
        expect(failures.providers, isEmpty);
        expect(find.text('Retry'), findsNothing);
        expect(tester.takeException(), isNull);

        await harness.unmount(tester);
      });
    }
  });

  // The Discover tab is not a Seerr page: without Seerr it still searches
  // the services there are, and only the catalogue is missing.
  testWidgets('P4: the Discover tab without Seerr searches what there is and '
      'asks Seerr nothing', (tester) async {
    final harness = await ProfileHarness.start(Profiles.p4);
    final failures = _FailureLog();
    await tester.pumpWidget(
      ProviderScope(
        overrides: harness.overrides,
        observers: [failures],
        child: MaterialApp(
          theme: AppTheme.darkTheme(),
          home: const SearchScreen(),
        ),
      ),
    );

    expect(find.text('Seerr is not set up'), findsNothing);
    expect(find.text('Discover'), findsOneWidget);
    await tester.pump(const Duration(minutes: 1));
    expect(failures.providers, isEmpty);
    expect(harness.network.requestsTo(WorldIds.seerr), isEmpty);
    expect(tester.takeException(), isNull);

    await harness.unmount(tester);
  });

  // P5 knows its Radarr only through Seerr, so Cupola has no Radarr of its
  // own: `/activity/movies` has nothing to read.
  testWidgets('P3: with Seerr set up the Discover tab draws its catalogue', (
    tester,
  ) async {
    final harness = await pumpWithProfile(
      tester,
      Profiles.p3,
      child: const SearchScreen(),
    );

    expect(find.text('Seerr is not set up'), findsNothing);
    expect(find.byType(DiscoverCatalog), findsOneWidget);
    expect(harness.network.requestsTo(WorldIds.seerr), isNotEmpty);

    await harness.unmount(tester);
  });
}

/// The placeholder's one way out: a filled button reading `Set up <service>`.
Finder _setUpButton(String service) => find.ancestor(
  of: find.text('Set up $service'),
  matching: find.byWidgetPredicate((widget) => widget is FilledButton),
);

/// Every provider that failed while the page was up.
final class _FailureLog extends ProviderObserver {
  final providers = <String>[];

  @override
  void providerDidFail(
    ProviderObserverContext context,
    Object error,
    StackTrace stackTrace,
  ) {
    providers.add('${context.provider.name ?? context.provider}: $error');
  }
}
