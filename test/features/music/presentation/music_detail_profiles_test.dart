import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/music/presentation/music_detail_screen.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';

import '../../../test_helpers/profiles/profiles.dart';

void main() {
  group('a queue refresh that fails', () {
    testWidgets('keeps the album it held, and says how old it is', (
      tester,
    ) async {
      var failing = false;
      final harness = await ProfileHarness.start(Profiles.p1);
      harness.network.on(
        WorldIds.lidarr,
        'GET',
        '/api/v1/queue',
        (_) => failing
            ? NetworkReply.json({'message': 'boom'}, status: 500)
            : NetworkReply.json({
                'page': 1,
                'pageSize': 200,
                'totalRecords': 1,
                'records': const [
                  {
                    'id': 1,
                    'artistId': 1,
                    'albumId': 4,
                    'title': 'Sintel (Anniversary Edition)',
                    'status': 'downloading',
                    'trackedDownloadState': 'downloading',
                    'size': 300000000,
                    'sizeleft': 120000000,
                  },
                ],
              }),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: harness.overrides,
          child: MaterialApp(
            theme: AppTheme.darkTheme(),
            home: const MusicDetailScreen(artistId: 1, heroTag: 'artist-1'),
          ),
        ),
      );
      await harness.settle(tester);
      expect(_badge(tester).label, 'Downloading');
      expect(find.byType(InlineErrorRetry), findsNothing);

      failing = true;
      ProviderScope.containerOf(
        tester.element(find.byType(MusicDetailScreen)),
      ).invalidate(lidarrQueueSnapshotsForProvider);
      await harness.settle(tester);

      // It used to drop to "Partial", the download gone from the page.
      expect(_badge(tester).label, 'Downloading');
      expect(
        find.text(
          "Lidarr's queue answered with an error, so the downloads shown are "
          'as they were a moment ago.',
        ),
        findsOneWidget,
      );

      await harness.unmount(tester);
    });
  });

  group('the quality profile row', () {
    testWidgets('comes back once a later read answers', (tester) async {
      // Tall enough that the Details card is built without scrolling.
      await tester.binding.setSurfaceSize(const Size(800, 3000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var profilesAnswer = false;
      final harness = await ProfileHarness.start(Profiles.p1);
      harness.network.on(
        WorldIds.lidarr,
        'GET',
        '/api/v1/qualityprofile',
        (_) => profilesAnswer
            ? null
            : NetworkReply.json({'message': 'boom'}, status: 500),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: harness.overrides,
          child: MaterialApp(
            theme: AppTheme.darkTheme(),
            home: const MusicDetailScreen(artistId: 1, heroTag: 'artist-1'),
          ),
        ),
      );
      await harness.settle(tester);

      // Omitted while the profiles are unknown, and asked for once.
      expect(find.text('Details'), findsOneWidget);
      expect(find.text('Quality profile'), findsNothing);
      expect(
        harness.network
            .requestsTo(WorldIds.lidarr)
            .where((r) => r.uri.path == '/api/v1/qualityprofile'),
        hasLength(1),
      );

      profilesAnswer = true;
      await tester
          .widget<RefreshIndicator>(find.byType(RefreshIndicator))
          .onRefresh();
      await harness.settle(tester);
      // The profiles are asked for after the frame that drew the fresh artist,
      // and that frame leaves nothing scheduled for `settle` to wait on.
      await tester.pump(const Duration(milliseconds: 100));
      await harness.settle(tester);

      expect(find.text('Quality profile'), findsOneWidget);
      expect(find.text('HD-1080p'), findsOneWidget);

      await harness.unmount(tester);
    });
  });

  testWidgets('an artist opened on the second Lidarr reads that Lidarr\'s '
      'queue, not the lens\'s', (tester) async {
    // The ids in a queue are its server's: read off the lens, the page badged
    // the vinyl Lidarr's artist 1 with the other server's artist 1.
    final harness = await ProfileHarness.start(
      Profiles.p1.withConnection(WorldConnections.lidarrVinyl),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: harness.overrides,
        child: MaterialApp(
          theme: AppTheme.darkTheme(),
          home: const MusicDetailScreen(
            artistId: 1,
            heroTag: 'artist-1',
            instanceId: WorldIds.lidarrVinyl,
          ),
        ),
      ),
    );
    await harness.settle(tester);

    bool asksQueue(NetworkRequest r) => r.uri.path == '/api/v1/queue';
    expect(
      harness.network.requestsTo(WorldIds.lidarrVinyl).where(asksQueue),
      isNotEmpty,
    );
    expect(
      harness.network.requestsTo(WorldIds.lidarr).where(asksQueue),
      isEmpty,
    );

    await harness.unmount(tester);
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
