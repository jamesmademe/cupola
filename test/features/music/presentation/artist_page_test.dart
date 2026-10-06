/// An artist's page on the profiles' Lidarr: Jan Morgenstern, three albums
/// on disk and one announced, as the board draws them.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/music/domain/models/lidarr_artist.dart';
import 'package:cupola/features/music/presentation/artist_page.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';

import '../../../test_helpers/profiles/profiles.dart';

const _tall = Size(800, 3200);

Future<ProfileHarness> _open(
  WidgetTester tester, {
  ConfigProfile? profile,
  ArtistPage page = const ArtistPage(artistId: 1),
  void Function(ProfileHarness harness)? arrange,
  Size size = _tall,
  bool settle = true,
}) async {
  final harness = await ProfileHarness.start(profile ?? Profiles.p1);
  harness.network.followFakeTime(tester.binding);
  arrange?.call(harness);
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: harness.overrides,
      child: MaterialApp(home: page),
    ),
  );
  if (settle) await harness.settle(tester);
  return harness;
}

/// The profiles' albums, with Elephants Dream's files gone when [wanted],
/// and Sintel's anniversary out and unmonitored when [unmonitored].
List<Map<String, Object?>> _albums({
  bool wanted = false,
  bool unmonitored = false,
}) => [
  for (final (id, title, year, files) in [
    (1, 'Elephants Dream', 2006, wanted ? 0 : 5),
    (2, 'Big Buck Bunny', 2008, 5),
    (3, 'Sintel', 2010, 5),
  ])
    {
      'id': id,
      'artistId': 1,
      'title': title,
      'monitored': true,
      'releaseDate': '$year-01-01T00:00:00Z',
      'images': const <Object?>[],
      'statistics': {'trackFileCount': files, 'totalTrackCount': 5},
    },
  if (unmonitored)
    {
      'id': 5,
      'artistId': 1,
      'title': 'Caminandes',
      'monitored': false,
      'releaseDate': '2013-01-01T00:00:00Z',
      'images': const <Object?>[],
      'statistics': {'trackFileCount': 0, 'totalTrackCount': 3},
    },
];

void _answerAlbums(ProfileHarness harness, List<Map<String, Object?>> albums) =>
    harness.network.on(
      WorldIds.lidarr,
      'GET',
      '/api/v1/album',
      (_) => NetworkReply.json(albums),
    );

Map<String, Object?> _queue(List<Map<String, Object?>> records) => {
  'page': 1,
  'pageSize': 200,
  'totalRecords': records.length,
  'records': records,
};

const _downloadingElephants = {
  'id': 1,
  'artistId': 1,
  'albumId': 1,
  'title': 'Elephants Dream',
  'status': 'downloading',
  'trackedDownloadState': 'downloading',
  'size': 300000000,
  'sizeleft': 120000000,
};

/// Lidarr keeps what it is sent: a later read of the artist answers with
/// the record the last write put.
void _persistArtistWrites(ProfileHarness harness) {
  Object? written;
  harness.network
    ..on(WorldIds.lidarr, 'PUT', '/api/v1/artist/1', (r) {
      written = r.json;
      return NetworkReply.json(written);
    })
    ..on(
      WorldIds.lidarr,
      'GET',
      '/api/v1/artist/1',
      (_) => written == null ? null : NetworkReply.json(written),
    );
}

Future<void> _scrollTo(WidgetTester tester, Finder finder) => tester
    .scrollUntilVisible(finder, 200, scrollable: find.byType(Scrollable).first);

void main() {
  group('the artist and the albums', () {
    testWidgets('as the board draws them: who, what is on disk, what is '
        'coming, and the settings', (tester) async {
      final harness = await _open(tester);

      expect(find.text('Jan Morgenstern'), findsOneWidget);
      expect(
        find.text('3\u00A0albums on disk · 1\u00A0announced'),
        findsOneWidget,
      );
      expect(find.text('JM'), findsOneWidget);
      expect(find.text('Coming'), findsOneWidget);
      expect(
        find.textContaining(
          RegExp(r'^Out \w{3} \d{1,2} \w{3}.* · not out yet$'),
        ),
        findsOneWidget,
      );
      expect(find.text("Lidarr looks for it once it's out"), findsOneWidget);
      expect(find.text('On disk'), findsOneWidget);
      expect(find.text('3 albums'), findsOneWidget);
      expect(find.text('2010 · 5 tracks · 21\u00A0min'), findsOneWidget);
      expect(find.text('Complete'), findsNWidgets(3));
      // Newest first.
      final sintel = tester.getTopLeft(find.text('Sintel')).dy;
      final bunny = tester.getTopLeft(find.text('Big Buck Bunny')).dy;
      final dream = tester.getTopLeft(find.text('Elephants Dream')).dy;
      expect(sintel < bunny && bunny < dream, isTrue);
      // Nothing is wanted and nothing is left alone: no such section.
      expect(find.text('Wanted'), findsNothing);
      expect(find.text('Unmonitored'), findsNothing);

      expect(find.text('Details'), findsOneWidget);
      expect(find.text('Lidarr keeps these albums up to date'), findsOneWidget);
      expect(find.text('Monitor new albums'), findsOneWidget);
      expect(find.text('HD-1080p'), findsOneWidget);
      expect(find.text('Folder'), findsOneWidget);
      expect(find.text('Open in Lidarr'), findsOneWidget);
      final switches = tester.widgetList<Switch>(find.byType(Switch));
      expect([for (final s in switches) s.value], [true, true]);

      await harness.unmount(tester);
    });

    testWidgets('an album opens on its tracks, in order, and says how many '
        'are on disk; a complete one asks for no search', (tester) async {
      final semantics = tester.ensureSemantics();
      final harness = await _open(tester);

      expect(
        find.bySemanticsLabel('Sintel, 2010, 5 tracks, 21 minutes, Complete'),
        findsOneWidget,
      );
      expect(find.text('Opening'), findsNothing);

      await tester.tap(find.text('Sintel'));
      await harness.settle(tester);

      final titles = ['Opening', 'Scales', 'The Dragon', 'Snow', 'Finale'];
      final tops = [
        for (final title in titles) tester.getTopLeft(find.text(title)).dy,
      ];
      expect(tops, [...tops]..sort());
      expect(find.text('2:48'), findsOneWidget);
      expect(find.text('5 of 5 tracks on disk'), findsOneWidget);
      expect(
        find.bySemanticsLabel('Track 3, The Dragon, 5:36, on disk'),
        findsOneWidget,
      );
      expect(find.text('Search for this album'), findsNothing);
      expect(find.text('Search releases'), findsOneWidget);

      semantics.dispose();
      await harness.unmount(tester);
    });
  });

  group('what Lidarr is looking for', () {
    testWidgets('an album out with nothing on disk is wanted, and its row '
        'searches for it on the page\'s Lidarr', (tester) async {
      final harness = await _open(
        tester,
        arrange: (harness) => _answerAlbums(harness, _albums(wanted: true)),
      );

      expect(
        find.text('2\u00A0albums on disk · 1\u00A0wanted'),
        findsOneWidget,
      );
      expect(find.text('Wanted'), findsNWidgets(2));
      expect(find.text('1 album'), findsOneWidget);

      await tester.tap(find.text('Elephants Dream'));
      await harness.settle(tester);
      await tester.tap(find.text('Search for this album'));
      await harness.settle(tester);

      final command = harness.network
          .requestsTo(WorldIds.lidarr)
          .where((r) => r.method == 'POST' && r.path == '/api/v1/command')
          .single;
      expect(jsonDecode(command.body), {
        'name': 'AlbumSearch',
        'albumIds': [1],
      });
      expect(find.text('Lidarr is searching for Elephants Dream'), findsOne);

      await harness.unmount(tester);
    });

    testWidgets('over a queue that did not answer, an empty album is not '
        'Wanted: it may be downloading', (tester) async {
      final harness = await _open(
        tester,
        arrange: (harness) {
          _answerAlbums(harness, _albums(wanted: true));
          harness.network.on(
            WorldIds.lidarr,
            'GET',
            '/api/v1/queue',
            (_) => NetworkReply.json({'message': 'boom'}, status: 500),
          );
        },
      );

      expect(find.text('Unknown'), findsOneWidget);
      // The section's heading still says it is wanted; its row does not.
      expect(find.text('Wanted'), findsOneWidget);

      await harness.unmount(tester);
    });

    testWidgets('an album in the queue says what the queue says', (
      tester,
    ) async {
      final harness = await _open(
        tester,
        arrange: (harness) {
          _answerAlbums(harness, _albums(wanted: true));
          harness.network.on(
            WorldIds.lidarr,
            'GET',
            '/api/v1/queue',
            (_) => NetworkReply.json(_queue([_downloadingElephants])),
          );
        },
      );

      expect(find.text('Downloading 60%'), findsOneWidget);

      await harness.unmount(tester);
    });

    testWidgets('a queue refresh that fails keeps the download it held, and '
        'says how old it is', (tester) async {
      var failing = false;
      final harness = await _open(
        tester,
        arrange: (harness) {
          _answerAlbums(harness, _albums(wanted: true));
          harness.network.on(
            WorldIds.lidarr,
            'GET',
            '/api/v1/queue',
            (_) => failing
                ? NetworkReply.json({'message': 'boom'}, status: 500)
                : NetworkReply.json(_queue([_downloadingElephants])),
          );
        },
      );
      expect(find.text('Downloading 60%'), findsOneWidget);
      expect(find.byType(InlineErrorRetry), findsNothing);

      failing = true;
      ProviderScope.containerOf(
        tester.element(find.byType(ArtistPage)),
      ).invalidate(lidarrQueueSnapshotsForProvider);
      await harness.settle(tester);

      // The download stays; its figure, which is no longer current, goes.
      expect(find.text('Downloading'), findsOneWidget);
      expect(
        find.text(
          "Lidarr's queue answered with an error, so the downloads shown are "
          'as they were a moment ago.',
        ),
        findsOneWidget,
      );

      await harness.unmount(tester);
    });

    testWidgets('the albums Lidarr leaves alone wait behind Show them', (
      tester,
    ) async {
      final harness = await _open(
        tester,
        arrange: (harness) =>
            _answerAlbums(harness, _albums(unmonitored: true)),
      );

      expect(find.text('Unmonitored'), findsOneWidget);
      expect(find.text('Caminandes'), findsNothing);

      await _scrollTo(tester, find.text('Show them'));
      await tester.tap(find.text('Show them'));
      await harness.settle(tester);

      expect(find.text('Caminandes'), findsOneWidget);

      await harness.unmount(tester);
    });
  });

  group('the settings write to the page\'s Lidarr', () {
    testWidgets('Monitored off', (tester) async {
      final harness = await _open(tester, arrange: _persistArtistWrites);

      await tester.tap(find.text('Monitored'));
      await harness.settle(tester);

      final put = harness.network
          .requestsTo(WorldIds.lidarr)
          .where((r) => r.method == 'PUT')
          .single;
      expect((put.json as Map)['monitored'], isFalse);
      expect(
        find.text('Lidarr has stopped monitoring this artist'),
        findsOneWidget,
      );
      expect(tester.widgetList<Switch>(find.byType(Switch)).first.value, false);

      await harness.unmount(tester);
    });

    testWidgets('Monitor new albums off', (tester) async {
      final harness = await _open(tester, arrange: _persistArtistWrites);

      await tester.tap(find.text('Monitor new albums'));
      await harness.settle(tester);

      final put = harness.network
          .requestsTo(WorldIds.lidarr)
          .where((r) => r.method == 'PUT')
          .single;
      expect((put.json as Map)['monitorNewItems'], 'none');
      expect(
        find.text('Lidarr no longer adds new albums by Jan Morgenstern'),
        findsOneWidget,
      );

      await harness.unmount(tester);
    });

    testWidgets('the quality profile row comes back once a later read '
        'answers', (tester) async {
      var profilesAnswer = false;
      final harness = await _open(
        tester,
        arrange: (harness) => harness.network.on(
          WorldIds.lidarr,
          'GET',
          '/api/v1/qualityprofile',
          (_) => profilesAnswer
              ? null
              : NetworkReply.json({'message': 'boom'}, status: 500),
        ),
      );

      expect(find.text('Details'), findsOneWidget);
      expect(find.text('Quality profile'), findsNothing);

      profilesAnswer = true;
      await tester
          .widget<RefreshIndicator>(find.byType(RefreshIndicator))
          .onRefresh();
      await harness.settle(tester);
      await tester.pump(const Duration(milliseconds: 100));
      await harness.settle(tester);

      expect(find.text('Quality profile'), findsOneWidget);
      expect(find.text('HD-1080p'), findsOneWidget);

      await harness.unmount(tester);
    });
  });

  testWidgets('removing asks what it takes, then removes from the page\'s '
      'Lidarr', (tester) async {
    final semantics = tester.ensureSemantics();
    final harness = await _open(
      tester,
      arrange: (harness) => harness.network.on(
        WorldIds.lidarr,
        'DELETE',
        '/api/v1/artist/1',
        (_) => NetworkReply.json(const <String, Object?>{}),
      ),
    );

    await tester.tap(find.bySemanticsLabel('More actions for Jan Morgenstern'));
    await harness.settle(tester);
    await tester.tap(find.text('Remove from Lidarr'));
    await harness.settle(tester);

    expect(find.text('Remove Jan Morgenstern from Lidarr?'), findsOneWidget);
    expect(find.text('Lidarr stops looking for their albums.'), findsOneWidget);
    expect(find.textContaining(RegExp(r'^Also delete .+ of files$')), findsOne);

    await tester.tap(find.text('Remove from Lidarr').last);
    await harness.settle(tester);

    final delete = harness.network
        .requestsTo(WorldIds.lidarr)
        .where((r) => r.method == 'DELETE')
        .single;
    expect(delete.query['deleteFiles'], 'false');
    expect(find.text('Removed from Lidarr'), findsOneWidget);

    semantics.dispose();
    await harness.unmount(tester);
  });

  group('reading', () {
    testWidgets('the library\'s record stands in while the page reads its '
        'own', (tester) async {
      final harness = await _open(
        tester,
        page: ArtistPage(
          artistId: 1,
          initialArtist: LidarrArtist.fromJson({
            'id': 1,
            'artistName': 'Jan Morgenstern',
          }),
        ),
        settle: false,
      );
      await tester.pump();

      expect(find.text('Jan Morgenstern'), findsOneWidget);
      expect(find.byType(ShimmerList), findsOneWidget);

      await harness.settle(tester);
      expect(
        find.text('3\u00A0albums on disk · 1\u00A0announced'),
        findsOneWidget,
      );

      await harness.unmount(tester);
    });

    testWidgets('an artist that could not be read says why, and Retry reads '
        'it again', (tester) async {
      var failing = true;
      final harness = await _open(
        tester,
        arrange: (harness) => harness.network.on(
          WorldIds.lidarr,
          'GET',
          '/api/v1/artist/1',
          (_) => failing
              ? NetworkReply.json({'message': 'boom'}, status: 500)
              : null,
        ),
      );

      expect(find.byType(AppErrorState), findsOneWidget);
      expect(find.text('Jan Morgenstern'), findsNothing);

      failing = false;
      await tester.tap(find.text('Retry'));
      await harness.settle(tester);

      expect(find.text('Jan Morgenstern'), findsOneWidget);
      expect(find.byType(AppErrorState), findsNothing);

      await harness.unmount(tester);
    });

    testWidgets('albums that could not be read name Lidarr, and Retry reads '
        'them again', (tester) async {
      var failing = true;
      final harness = await _open(
        tester,
        arrange: (harness) => harness.network.on(
          WorldIds.lidarr,
          'GET',
          '/api/v1/album',
          (_) => failing
              ? NetworkReply.json({'message': 'boom'}, status: 500)
              : null,
        ),
      );

      expect(find.text('Jan Morgenstern'), findsOneWidget);
      expect(find.text('Albums'), findsOneWidget);
      expect(find.byType(AppErrorState), findsOneWidget);

      failing = false;
      await tester.tap(find.text('Retry'));
      await harness.settle(tester);

      expect(find.text('On disk'), findsOneWidget);

      await harness.unmount(tester);
    });

    testWidgets('a Lidarr not set up is the way to set it up', (tester) async {
      final harness = await _open(tester, profile: Profiles.p2);

      expect(find.byType(NotConfiguredPlaceholder), findsOneWidget);

      await harness.unmount(tester);
    });

    testWidgets('an artist opened on the second Lidarr reads that Lidarr, and '
        'names it', (tester) async {
      final harness = await _open(
        tester,
        profile: Profiles.p1.withConnection(WorldConnections.lidarrVinyl),
        page: const ArtistPage(artistId: 1, instanceId: WorldIds.lidarrVinyl),
      );

      bool asks(NetworkRequest r) =>
          r.path == '/api/v1/queue' || r.path == '/api/v1/artist/1';
      expect(
        harness.network.requestsTo(WorldIds.lidarrVinyl).where(asks),
        hasLength(2),
      );
      expect(harness.network.requestsTo(WorldIds.lidarr).where(asks), isEmpty);
      expect(find.textContaining(RegExp(r'^Open in .*Vinyl$')), findsOneWidget);

      await harness.unmount(tester);
    });

    testWidgets('at twice the reading size the name goes under the disc', (
      tester,
    ) async {
      final harness = await ProfileHarness.start(Profiles.p1);
      harness.network.followFakeTime(tester.binding);
      await tester.binding.setSurfaceSize(const Size(390, 3200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        ProviderScope(
          overrides: harness.overrides,
          child: const MediaQuery(
            data: MediaQueryData(
              size: Size(390, 3200),
              textScaler: TextScaler.linear(2),
            ),
            child: MaterialApp(home: ArtistPage(artistId: 1)),
          ),
        ),
      );
      await harness.settle(tester);

      expect(tester.takeException(), isNull);
      final disc = tester.getCenter(find.text('JM'));
      final name = tester.getCenter(find.text('Jan Morgenstern'));
      expect(name.dy, greaterThan(disc.dy));

      await harness.unmount(tester);
    });
  });
}
