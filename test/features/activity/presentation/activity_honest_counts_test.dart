/// Activity's figures, driven through the app's own clients on the profiles'
/// fake network: a count says what answered, and names what did not.
///
/// Each of these was a number that looked like an answer to the question the
/// user asked and answered a smaller one: the connections that happened to
/// answer, the rows that happened to be loaded, the first page of a list.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/status/media_status.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/features/activity/domain/service_type.dart';
import 'package:cupola/features/activity/presentation/activity_provider.dart';
import 'package:cupola/features/activity/presentation/global_activity_screen.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import '../../../test_helpers/profiles/profiles.dart';

GlobalActivityItem _queued(ServiceKey service, String title) =>
    GlobalActivityItem(
      kind: GlobalActivityKind.queue,
      service: service,
      serviceType: ServiceType.movies,
      title: title,
      subtitle: '',
      status: const MediaStatusInfo(
        labelOverride: 'Downloading',
        toneOverride: StatusTone.info,
      ),
    );

ActivityServiceResult _answered(
  ServiceKey service,
  List<GlobalActivityItem> items, {
  String instanceId = '',
  String label = '',
}) => ActivityServiceResult(
  service: service,
  instanceId: instanceId,
  label: label,
  items: items,
  total: items.length,
  configured: true,
);

ActivityServiceResult _silent(
  ServiceKey service, {
  String instanceId = '',
  String label = '',
}) => ActivityServiceResult(
  service: service,
  instanceId: instanceId,
  label: label,
  items: const [],
  configured: true,
  error: const SocketException('Connection refused'),
);

/// Every \*arr connection of the full household, failing.
ConfigProfile _everyArrDown(ConfigProfile profile) => profile
    .withBehaviour(WorldIds.radarr, ConnectionBehaviour.didNotAnswer)
    .withBehaviour(WorldIds.radarr4k, ConnectionBehaviour.didNotAnswer)
    // A refusal among the silences: "nothing answered" is about whether a
    // figure exists, and a refused key gives no figure either.
    .withBehaviour(WorldIds.sonarr, ConnectionBehaviour.refusesKey)
    .withBehaviour(WorldIds.lidarr, ConnectionBehaviour.didNotAnswer);

void main() {
  group('the page bar readout', () {
    test('counts what answered and names what did not', () {
      final radarr = [_queued(ServiceKey.radarr, 'Dune')];
      final feed = ActivityFeed(
        items: radarr,
        results: [
          _answered(ServiceKey.radarr, radarr),
          _silent(ServiceKey.sonarr, instanceId: 'anime', label: 'Anime'),
        ],
      );

      final readout = nowReadout(feed)!;
      expect(readout.text, '1 in the queue · Sonarr Anime not counted');
      expect(readout.spoken, readout.text);
    });

    test('what to act on comes first, the reservation last', () {
      // The qualifier used to follow the count, and a phone's ellipsis took
      // the manual-import clause, the one asking for something, to keep it.
      const blocked = MediaStatusInfo(pipeline: MediaPipeline.importBlocked);
      final radarr = [
        for (var i = 0; i < 18; i++)
          GlobalActivityItem(
            kind: GlobalActivityKind.queue,
            service: ServiceKey.radarr,
            serviceType: ServiceType.movies,
            title: 'Blocked $i',
            subtitle: '',
            status: blocked,
          ),
        for (var i = 0; i < 6; i++) _queued(ServiceKey.radarr, 'Moving $i'),
      ];
      final feed = ActivityFeed(
        items: radarr,
        results: [
          _answered(ServiceKey.radarr, radarr),
          _silent(ServiceKey.lidarr),
        ],
      );

      final readout = nowReadout(feed)!;
      expect(
        readout.text,
        '24 in the queue · 18 need a manual import · Lidarr not counted',
      );
      expect(readout.spoken, readout.text);
    });

    // "Nothing in the queue" was the sentence for a queue that answered empty
    // and for a queue that could not be asked. Only the first one is true.
    test('an empty answer beside a failure is not "nothing"', () {
      final feed = ActivityFeed(
        items: const [],
        results: [
          _answered(ServiceKey.radarr, const []),
          _silent(ServiceKey.lidarr),
        ],
      );

      expect(
        nowReadout(feed)!.text,
        'Nothing in the queue · Lidarr not counted',
      );
    });

    test('with no *arr answering there is no figure at all', () {
      final feed = ActivityFeed(
        items: const [],
        results: [
          _silent(ServiceKey.radarr),
          _silent(ServiceKey.sonarr),
          // Seerr answering says nothing about the queue.
          _answered(ServiceKey.seerr, const []),
        ],
      );

      final readout = nowReadout(feed)!;
      expect(readout.text, '— in the queue');
      expect(readout.spoken, 'queue count unavailable');
    });

    test('a Seerr that did not answer leaves the queue figure whole', () {
      final radarr = [_queued(ServiceKey.radarr, 'Dune')];
      final feed = ActivityFeed(
        items: radarr,
        results: [
          _answered(ServiceKey.radarr, radarr),
          _silent(ServiceKey.seerr),
        ],
      );

      expect(nowReadout(feed)!.text, '1 in the queue');
    });

    test('with no *arr set up there is no queue to speak of', () {
      final feed = ActivityFeed(
        items: const [],
        results: [
          const ActivityServiceResult.unconfigured(ServiceKey.radarr),
          const ActivityServiceResult.unconfigured(ServiceKey.sonarr),
          const ActivityServiceResult.unconfigured(ServiceKey.lidarr),
          _answered(ServiceKey.seerr, const []),
        ],
      );

      expect(nowReadout(feed), isNull);
    });

    testWidgets('P2: Seerr alone, and the bar claims nothing about a queue', (
      tester,
    ) async {
      final harness = await pumpWithProfile(
        tester,
        Profiles.p2,
        child: const GlobalActivityScreen(),
      );

      expect(find.text('Activity'), findsOneWidget);
      expect(find.textContaining('in the queue'), findsNothing);

      await harness.unmount(tester);
    });

    testWidgets('P7: Lidarr is away, and the bar says it is not counted', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final harness = await pumpWithProfile(
        tester,
        Profiles.p7,
        child: const GlobalActivityScreen(),
      );

      expect(find.textContaining('Nothing in the queue'), findsNothing);
      expect(
        find.textContaining(
          RegExp(r'^\d+ in the queue( · [^·]+)* · Lidarr not counted$'),
        ),
        findsOneWidget,
      );

      handle.dispose();
      await harness.unmount(tester);
    });

    testWidgets('P1 with every *arr down: an em dash, never "nothing"', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final harness = await pumpWithProfile(
        tester,
        _everyArrDown(Profiles.p1),
        child: const GlobalActivityScreen(),
      );

      expect(find.text('— in the queue'), findsOneWidget);
      expect(find.textContaining('Nothing in the queue'), findsNothing);
      expect(
        find.bySemanticsLabel('Activity, queue count unavailable'),
        findsOneWidget,
      );

      handle.dispose();
      await harness.unmount(tester);
    });
  });

  group('the service tiles', () {
    test('a failed connection makes the count a floor and is named', () {
      final count = activityCount([
        _answered(ServiceKey.sonarr, [_queued(ServiceKey.sonarr, 'A')]),
        _silent(ServiceKey.sonarr, instanceId: 'anime', label: 'Anime'),
        _answered(ServiceKey.radarr, const []),
      ], service: ServiceKey.sonarr);

      expect(count.total, 1);
      expect(count.isFloor, isTrue);
      expect(notCountedClause(count.notCounted), 'Sonarr Anime not counted');
    });

    test('every connection answering is a total, not a floor', () {
      final count = activityCount([
        _answered(ServiceKey.sonarr, [_queued(ServiceKey.sonarr, 'A')]),
        _answered(ServiceKey.radarr, [_queued(ServiceKey.radarr, 'B')]),
      ]);

      expect(count.total, 2);
      expect(count.isFloor, isFalse);
    });

    testWidgets(
      'P6: Sonarr Anime does not answer, so Sonarr reads as a floor',
      (tester) async {
        final handle = tester.ensureSemantics();
        final harness = await pumpWithProfile(
          tester,
          Profiles.p6.withBehaviour(
            WorldIds.sonarrAnime,
            ConnectionBehaviour.didNotAnswer,
          ),
          child: const GlobalActivityScreen(),
        );

        // The other Sonarr answered, so the tile keeps its number — marked as
        // the floor it is, with the missing connection named to the ear.
        expect(
          find.bySemanticsLabel(
            RegExp(r'^Sonarr, \d+ items?, Sonarr Anime not counted$'),
          ),
          findsOneWidget,
        );
        expect(
          find.bySemanticsLabel(RegExp(r'^All, .*Sonarr Anime not counted$')),
          findsOneWidget,
        );
        expect(
          find.bySemanticsLabel(RegExp(r'^Sonarr, \d+ items?$')),
          findsNothing,
        );
        // And the eye gets the mark, on the Sonarr tile and on All.
        expect(find.textContaining(RegExp(r'^\d+\+$')), findsNWidgets(2));

        handle.dispose();
        await harness.unmount(tester);
      },
    );
  });

  group('a queue walk cut short', () {
    testWidgets('P3: a full page and no count reads 200+, never 200', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final harness = await pumpWithProfile(
        tester,
        Profiles.p3,
        child: const GlobalActivityScreen(),
        settle: false,
      );
      // A server behind a proxy that drops `totalRecords`: one full page of
      // the queue, and nothing to say whether a second one follows.
      harness.network.on(
        WorldIds.radarr,
        'GET',
        '/api/v3/queue',
        (_) => NetworkReply.json({
          'page': 1,
          'pageSize': 200,
          'records': [
            for (var i = 0; i < 200; i++)
              {
                'id': i + 1,
                'title': 'Release.$i',
                'status': 'downloading',
                'size': 1000,
                'sizeleft': 500,
              },
          ],
        }),
      );
      await harness.settle(tester);

      // The Radarr tile and Radarr's group header, both marked.
      expect(find.text('200+'), findsNWidgets(2));
      expect(find.text('200'), findsNothing);
      expect(
        find.bySemanticsLabel('Radarr, at least 200 items'),
        findsNWidgets(2),
      );
      expect(
        find.textContaining(RegExp(r'^\d+\+ in the queue')),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(RegExp(r'^Activity, at least \d+ in the queue')),
        findsOneWidget,
      );

      handle.dispose();
      await harness.unmount(tester);
    });
  });

  group('the group header', () {
    testWidgets('P3: the header states the server\'s total, not the page', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final harness = await pumpWithProfile(
        tester,
        Profiles.p3,
        child: const GlobalActivityScreen(),
        settle: false,
      );
      _historyPage(harness, WorldIds.radarr, total: 2369);
      await harness.settle(tester);
      await tester.tap(find.text('History'));
      await harness.settle(tester);

      // Fifty rows under it; the tile and the header both say how many there
      // are. The header used to say 50, and 100 after Show more.
      expect(find.bySemanticsLabel('Radarr, 2369 items'), findsNWidgets(2));
      expect(find.text('2369'), findsNWidgets(2));
      expect(find.text('50'), findsNothing);

      handle.dispose();
      await harness.unmount(tester);
    });

    testWidgets('P3: with no total given, the header says what is shown', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final harness = await pumpWithProfile(
        tester,
        Profiles.p3,
        child: const GlobalActivityScreen(),
        settle: false,
      );
      _historyPage(harness, WorldIds.radarr, total: null);
      await harness.settle(tester);
      await tester.tap(find.text('History'));
      await harness.settle(tester);

      expect(find.text('50 shown'), findsOneWidget);
      expect(find.bySemanticsLabel('Radarr, 50 shown'), findsOneWidget);
      expect(
        find.bySemanticsLabel('Radarr, count unavailable'),
        findsOneWidget,
      );

      handle.dispose();
      await harness.unmount(tester);
    });

    testWidgets('P7: Radarr 4K does not answer, and Radarr\'s header says so', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final harness = await pumpWithProfile(
        tester,
        Profiles.p7.withBehaviour(
          WorldIds.radarr4k,
          ConnectionBehaviour.didNotAnswer,
        ),
        child: const GlobalActivityScreen(),
      );
      await tester.tap(find.text('History'));
      await harness.settle(tester);

      expect(
        find.textContaining(RegExp(r'^\d+ · Radarr 4K not counted$')),
        findsOneWidget,
      );
      // The header and the tile, saying the same sentence.
      expect(
        find.bySemanticsLabel(
          RegExp(r'^Radarr, \d+ items?, Radarr 4K not counted$'),
        ),
        findsNWidgets(2),
      );

      handle.dispose();
      await harness.unmount(tester);
    });
  });

  group('Seerr', () {
    testWidgets('P2: a lost page keeps Seerr\'s count and says what came', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final harness = await ProfileHarness.start(Profiles.p2);
      // 120 requests in pages of 50; the second page fails.
      harness.network.on(WorldIds.seerr, 'GET', '/api/v1/request', (request) {
        final skip = int.tryParse(request.query['skip'] ?? '') ?? 0;
        if (skip == 50) {
          return NetworkReply.json({'message': 'boom'}, status: 500);
        }
        final rows = skip == 0 ? 50 : 20;
        return NetworkReply.json({
          'pageInfo': {'pages': 3, 'pageSize': 50, 'results': 120},
          'results': [
            for (var i = 0; i < rows; i++)
              {
                'id': skip + i + 1,
                'status': 2,
                'createdAt': '2026-09-01T10:00:00.000Z',
                'type': 'movie',
                'media': {
                  'id': skip + i + 1,
                  'status': 3,
                  'mediaType': 'movie',
                  'title': 'Request ${skip + i + 1}',
                },
              },
          ],
        });
      });
      await tester.pumpWidget(
        ProviderScope(
          overrides: harness.overrides,
          child: MaterialApp(
            theme: AppTheme.darkTheme(),
            home: const GlobalActivityScreen(),
          ),
        ),
      );
      await harness.settle(tester);

      // The total is Seerr's; the rows under it are not all of them, and
      // there is no Show more to fetch the rest, so the header says so.
      expect(find.text('120 · 70 shown'), findsOneWidget);
      expect(
        find.bySemanticsLabel('Seerr, 120 items, 70 shown'),
        findsOneWidget,
      );

      handle.dispose();
      await harness.unmount(tester);
    });
  });

  group('Finished today', () {
    // 15:00 local, so "today" and "yesterday" are hours from either edge.
    final now = DateTime(2026, 10, 1, 15);
    const radarr = (GlobalActivityKind.history, ServiceType.movies, 'radarr');
    const sonarr = (GlobalActivityKind.history, ServiceType.series, 'sonarr');

    GlobalActivityItem landed(String id, DateTime at, {ServiceType? type}) =>
        GlobalActivityItem(
          kind: GlobalActivityKind.history,
          service: type == ServiceType.series
              ? ServiceKey.sonarr
              : ServiceKey.radarr,
          serviceType: type ?? ServiceType.movies,
          instanceId: id,
          title: 'Landed',
          subtitle: '',
          status: const MediaStatusInfo.unknown(),
          sortDate: at,
        );

    PagedCursor cursor({bool hasMore = true, Object? error}) => PagedCursor(
      fetched: 50,
      lastPageFull: hasMore,
      total: hasMore ? 300 : 50,
      configured: true,
      error: error,
    );

    test('a first page full of today is a floor, not the day', () {
      final today = finishedTodayOf(
        PagedArrFeedState(
          feed: ActivityFeed(
            items: [
              for (var i = 0; i < 50; i++)
                landed('radarr', now.subtract(Duration(minutes: i))),
            ],
            results: const [],
          ),
          cursors: {radarr: cursor()},
        ),
        now: now,
      );

      expect(today.rows, hasLength(finishedTodayLimit));
      expect(today.count, 50);
      expect(today.complete, isFalse);
    });

    test('a page that reaches yesterday holds the whole day', () {
      final today = finishedTodayOf(
        PagedArrFeedState(
          feed: ActivityFeed(
            items: [
              for (var i = 0; i < 9; i++)
                landed('radarr', now.subtract(Duration(minutes: i))),
              landed('radarr', now.subtract(const Duration(days: 1))),
              // Sonarr has nothing more to give, so it needs no such proof.
              landed('sonarr', now, type: ServiceType.series),
            ],
            results: const [],
          ),
          cursors: {radarr: cursor(), sonarr: cursor(hasMore: false)},
        ),
        now: now,
      );

      expect(today.count, 10);
      expect(today.complete, isTrue);
    });

    test('a connection that failed leaves the day a floor', () {
      final today = finishedTodayOf(
        PagedArrFeedState(
          feed: ActivityFeed(items: [landed('radarr', now)], results: const []),
          cursors: {
            radarr: cursor(hasMore: false),
            sonarr: cursor(error: const SocketException('Connection refused')),
          },
        ),
        now: now,
      );

      expect(today.count, 1);
      expect(today.complete, isFalse);
    });

    testWidgets(
      'P3 on the desktop: the band counts the day, not its six rows',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1280, 3000));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final harness = await ProfileHarness.start(Profiles.p3);
        // Fifty records of Radarr's 300, every one of them from today: the
        // page cannot prove the day ends inside it. Stamped at the group's
        // fixed 15:00 and read against it, never the wall clock: records
        // stamped "now" and a band reading "now" a moment later fall on two
        // days when the run straddles midnight.
        final at = now.toUtc().toIso8601String();
        harness.network.on(WorldIds.radarr, 'GET', '/api/v3/history', (r) {
          final page = int.tryParse(r.query['page'] ?? '') ?? 1;
          return NetworkReply.json({
            'page': page,
            'pageSize': 50,
            'totalRecords': 300,
            'records': page == 1
                ? [
                    for (var i = 0; i < 50; i++)
                      {
                        'id': i + 1,
                        'eventType': 'grabbed',
                        'sourceTitle': 'Release.$i',
                        'date': at,
                      },
                  ]
                : const [],
          });
        });
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              ...harness.overrides,
              // The provider's own reading, with the clock pinned.
              finishedTodayProvider.overrideWith(
                (ref) => finishedTodayOf(
                  ref.watch(globalHistoryFeedProvider),
                  now: now,
                ),
              ),
            ],
            child: MaterialApp(
              theme: AppTheme.darkTheme(),
              home: const GlobalActivityScreen(),
            ),
          ),
        );
        await harness.settle(tester);

        // At least Radarr's fifty; six rows drawn under it.
        expect(
          find.textContaining(RegExp(r'^Finished today · \d+\+ items$')),
          findsOneWidget,
        );
        expect(find.text('Finished today · 6 items'), findsNothing);

        await harness.unmount(tester);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    );
  });
}

/// Answers [connection]'s history with fifty records out of [total], or with
/// no `totalRecords` at all when [total] is null.
void _historyPage(ProfileHarness harness, String connection, {int? total}) {
  harness.network.on(connection, 'GET', '/api/v3/history', (request) {
    final page = int.tryParse(request.query['page'] ?? '') ?? 1;
    return NetworkReply.json({
      'page': page,
      'pageSize': 50,
      'totalRecords': ?total,
      'records': page == 1
          ? [
              for (var i = 0; i < 50; i++)
                {
                  'id': i + 1,
                  'eventType': 'grabbed',
                  'sourceTitle': 'Release.$i',
                  'date': harness.network.now
                      .subtract(Duration(days: 2, minutes: i))
                      .toUtc()
                      .toIso8601String(),
                },
            ]
          : const [],
    });
  });
}
