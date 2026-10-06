import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/models/media_preview.dart';
import 'package:cupola/core/widgets/content_card.dart';
import 'package:cupola/core/widgets/shimmer_placeholder.dart';
import 'package:cupola/features/discover/domain/models/seerr_genre.dart';
import 'package:cupola/features/discover/domain/models/seerr_request.dart';
import 'package:cupola/features/discover/presentation/discover_provider.dart';
import 'package:cupola/features/discover/presentation/discover_catalog.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import '../../../test_helpers/settings_scope.dart';

const _movies = [
  MediaPreview(id: 1, title: 'Movie One', mediaType: 'movie'),
  MediaPreview(id: 2, title: 'Movie Two', mediaType: 'movie'),
];

const _tvShows = [MediaPreview(id: 10, title: 'Show One', mediaType: 'tv')];

const _trending = [
  MediaPreview(id: 20, title: 'Trending One', mediaType: 'movie'),
];

void main() {
  group('DiscoverCatalog', () {
    testWidgets('renders curated section headers when data loads', (
      tester,
    ) async {
      await _pumpDiscover(tester);
      await tester.pumpAndSettle();

      expect(find.text('Trending'), findsOneWidget);
      expect(find.text('Popular movies'), findsOneWidget);
      expect(find.text('Popular series'), findsOneWidget);
      expect(find.byType(ContentCard), findsWidgets);
    });

    testWidgets('shows skeleton when a section is loading', (tester) async {
      await _pumpDiscover(
        tester,
        trendingBuilder: (ref) => Completer<List<MediaPreview>>().future,
      );
      await tester.pump();

      expect(find.byType(ShimmerPlaceholder), findsWidgets);
    });

    testWidgets('hides a section that returns an empty list', (tester) async {
      await _pumpDiscover(
        tester,
        moviesBuilder: (ref) async => const <MediaPreview>[],
      );
      await tester.pumpAndSettle();

      // Empty rows collapse rather than showing a placeholder message.
      expect(find.text('Popular movies'), findsNothing);
      expect(find.text('Trending'), findsOneWidget);
    });

    testWidgets('leads with the decisions and puts the rails under them', (
      tester,
    ) async {
      // Seerr's home is the one that is not its catalogue: approving is what
      // the phone opens it for, so a waiting request sits above Trending and
      // above the region readout that labels the rails.
      await _pumpDiscover(
        tester,
        requests: [
          SeerrRequest(
            id: 1,
            status: RequestStatus.pendingApproval,
            media: const RequestMedia(title: 'Dune', tmdbId: 1),
            createdAt: '2026-09-15T00:00:00Z',
            type: 'movie',
          ),
        ],
      );
      await tester.pumpAndSettle();

      final decisions = tester.getTopLeft(find.text('Needs a decision')).dy;
      expect(
        decisions,
        lessThan(tester.getTopLeft(find.text('Region · IT')).dy),
      );
      expect(decisions, lessThan(tester.getTopLeft(find.text('Trending')).dy));
    });

    testWidgets('a rail whose source failed says so, under its header', (
      tester,
    ) async {
      // Every rail used to vanish when Seerr did not answer, because every
      // read answered a failure with `[]`.
      await _pumpDiscover(
        tester,
        trendingBuilder: (ref) => Future<List<MediaPreview>>.error(
          const SocketException('Connection refused'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Trending'), findsOneWidget);
      expect(
        find.text('Seerr did not answer, so this row is missing.'),
        findsOneWidget,
      );
    });
  });
}

Future<void> _pumpDiscover(
  WidgetTester tester, {
  Future<List<MediaPreview>> Function(Ref ref)? trendingBuilder,
  Future<List<MediaPreview>> Function(Ref ref)? moviesBuilder,
  Future<List<MediaPreview>> Function(Ref ref)? tvBuilder,
  List<SeerrRequest> requests = const [],
}) async {
  // Tall viewport so all catalog rows build (the vertical ListView is lazy).
  tester.view.physicalSize = const Size(1200, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        // The region chip reads the app setting, which reaches
        // `sharedPreferencesProvider` — wired in main.dart and throwing
        // anywhere else. One value is all this screen needs from it.
        regionProvider.overrideWithValue('IT'),
        // The catalogue is drawn only once there is a Seerr to ask.
        currentSettingsProvider.overrideWith(
          (ref) => settingsWithServices([ServiceKey.seerr]),
        ),
        discoverTrendingProvider.overrideWith(
          trendingBuilder ?? (ref) async => _trending,
        ),
        discoverMoviesProvider.overrideWith(
          moviesBuilder ?? (ref) async => _movies,
        ),
        discoverTVProvider.overrideWith(tvBuilder ?? (ref) async => _tvShows),
        // Keep the rest of the catalog deterministic (empty → hidden rows).
        discoverUpcomingMoviesProvider.overrideWith(
          (ref) async => const <MediaPreview>[],
        ),
        discoverUpcomingTvProvider.overrideWith(
          (ref) async => const <MediaPreview>[],
        ),
        discoverTopRatedMoviesProvider.overrideWith(
          (ref) async => const <MediaPreview>[],
        ),
        movieGenresProvider.overrideWith((ref) async => const <SeerrGenre>[]),
        requestsProvider.overrideWith((ref) async => requests),
      ],
      child: const MaterialApp(home: Scaffold(body: DiscoverCatalog())),
    ),
  );
}
