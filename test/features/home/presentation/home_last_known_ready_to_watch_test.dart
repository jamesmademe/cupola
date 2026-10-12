import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/title_light.dart';
import 'package:cupola/features/discover/domain/models/seerr_request.dart';
import 'package:cupola/features/home/data/featured.dart';
import 'package:cupola/features/home/data/last_known/my_requests_last_known.dart';
import 'package:cupola/features/home/data/last_known/seerr_request_codec.dart';
import 'package:cupola/features/home/presentation/widgets/featured_pager.dart';
import 'package:cupola/features/home/presentation/widgets/ready_to_watch_module.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';

import '../../../test_helpers/requester_cold_start.dart';

const _watchLink =
    'https://jellyfin.example.com/web/index.html#!/details?id=ab';

/// The requester's Ready to watch at a cold start: what it last drew, said for
/// what it is, until her Seerr answers.
void main() {
  group('a cold start', () {
    late RequesterColdStart app;
    setUp(() => app = RequesterColdStart());

    Future<void> run(
      WidgetTester tester, {
      Future<List<SeerrRequest>> Function()? requests,
      DateTime? now,
      int userId = 7,
      SettingsModel Function(SettingsModel)? customize,
    }) => app.run(
      tester,
      child: const HomeReadyToWatchModule(),
      requests: requests,
      now: now,
      userId: userId,
      customize: customize,
    );

    Future<void> firstRun(WidgetTester tester) async {
      await run(
        tester,
        requests: () async => [
          requesterRequest(watchUrl: _watchLink, voteAverage: 7.1),
        ],
      );
      await tester.pumpAndSettle();
      expect(find.text('Sintel'), findsOne);
      expect(find.textContaining('As of'), findsNothing);
    }

    testWidgets('draws the last drawing at once, says so, then the live '
        'one', (tester) async {
      await firstRun(tester);

      final answer = Completer<List<SeerrRequest>>();
      await run(
        tester,
        requests: () => answer.future,
        now: requesterNow.add(const Duration(hours: 1)),
      );
      // No skeleton: the title she last saw, how she asked for it, the way to
      // watch it and Details, and the one line.
      expect(find.text('Sintel'), findsOne);
      expect(find.text('Ready to watch · since Saturday'), findsOne);
      expect(find.textContaining('You asked for it on Wednesday'), findsOne);
      expect(find.textContaining('TMDB 7.1'), findsOne);
      expect(find.text('Watch'), findsOne);
      expect(find.text('Details'), findsOne);
      expect(find.text('As of 20:53 · checking now'), findsOne);

      answer.complete([
        requesterRequest(
          id: 2,
          title: 'Spring',
          tmdbId: 7,
          arrived: const Duration(hours: 3),
        ),
      ]);
      await tester.pumpAndSettle();
      expect(find.text('Sintel'), findsNothing);
      expect(find.text('Spring'), findsOne);
      expect(find.textContaining('As of'), findsNothing);
    });

    testWidgets('a live read that fails keeps the drawing over the failure '
        'and stops checking', (tester) async {
      await firstRun(tester);

      await run(
        tester,
        requests: () async =>
            throw const ClassifiedFailure(ServiceFailureReason.unreachable),
      );
      await tester.pumpAndSettle();
      // The module draws no failure of its own (the Home says it once); the
      // line says the drawing is old, and no longer checks.
      expect(find.text('Sintel'), findsOne);
      expect(find.text('Details'), findsOne);
      expect(find.text('As of 20:53'), findsOne);
    });

    /// The same start, as the drawing's own: it is drawn.
    Future<void> control(WidgetTester tester, {DateTime? now}) async {
      await run(tester, now: now);
      expect(find.text('Sintel'), findsOne, reason: 'the control draws it');
      expect(find.textContaining('· checking now'), findsOne);
    }

    testWidgets('another server draws nothing of it', (tester) async {
      await firstRun(tester);
      await control(tester);

      await run(
        tester,
        customize: (settings) => settings.copyWithInstance(
          settings
              .instancesOf(ServiceKey.seerr)
              .first
              .copyWith(url: 'https://other.example.com'),
        ),
      );
      expect(find.text('Sintel'), findsNothing);
      expect(find.textContaining('As of'), findsNothing);
    });

    testWidgets('another person draws nothing of it', (tester) async {
      await firstRun(tester);
      await control(tester);

      await run(tester, userId: 8);
      expect(find.text('Sintel'), findsNothing);
      expect(find.textContaining('As of'), findsNothing);
    });

    testWidgets('an arrival the week left behind is not drawn as ready, '
        'and the module is the skeleton, not absent', (tester) async {
      await firstRun(tester);
      // Arrived two days before the drawing: six days old it is still inside
      // the week, eight it is not.
      await control(tester, now: requesterNow.add(const Duration(days: 4)));

      await run(tester, now: requesterNow.add(const Duration(days: 6)));
      expect(find.text('Sintel'), findsNothing);
      expect(find.textContaining('As of'), findsNothing);
      expect(find.byType(FeaturedSkeleton), findsOne);
    });

    testWidgets('a week left behind, over a failure, says nothing at all', (
      tester,
    ) async {
      await firstRun(tester);

      await run(
        tester,
        now: requesterNow.add(const Duration(days: 6)),
        requests: () async =>
            throw const ClassifiedFailure(ServiceFailureReason.unreachable),
      );
      await tester.pumpAndSettle();
      expect(find.byType(FeaturedSkeleton), findsNothing);
      expect(find.text('Sintel'), findsNothing);
      expect(find.textContaining('As of'), findsNothing);
    });

    testWidgets('a link that carried a key is no Watch in the drawing, and '
        'Details stays', (tester) async {
      await run(
        tester,
        requests: () async => [
          requesterRequest(
            watchUrl: 'https://jellyfin.example.com/web/?api_key=hunter2',
          ),
        ],
      );
      await tester.pumpAndSettle();
      expect(find.text('Watch'), findsOne);

      await run(tester);
      expect(find.text('Sintel'), findsOne);
      expect(find.text('Watch'), findsNothing);
      expect(find.text('Details'), findsOne);
    });
  });

  group('the room', () {
    // Her art is empty here: the light is whatever the pictures would give.
    const light = TitleLight(
      light: Color(0xFF8844AA),
      actionFill: Color(0xFFCCBBDD),
      actionInk: Color(0xFF110022),
      dayPrimary: Color(0xFF552288),
    );
    final lit = featuredLightProvider.overrideWith((ref, url) => light);
    const probe = Column(children: [HomeReadyToWatchModule(), _RoomProbe()]);

    testWidgets('is lit by the title the drawing leads with until the live '
        'answer comes', (tester) async {
      final app = RequesterColdStart();
      await app.run(
        tester,
        child: probe,
        requests: () async => [requesterRequest()],
        overrides: [lit],
      );
      await tester.pumpAndSettle();
      expect(find.text('room ${light.light.toARGB32()}'), findsOne);

      // The next start: nothing live yet, and the room is already the
      // drawing's title's, so it does not change colour when the answer comes.
      await app.run(tester, child: probe, overrides: [lit]);
      expect(find.text('room ${light.light.toARGB32()}'), findsOne);
    });

    testWidgets("is the neutral lamp when the drawing is another person's", (
      tester,
    ) async {
      final app = RequesterColdStart();
      await app.run(
        tester,
        child: probe,
        requests: () async => [requesterRequest()],
        overrides: [lit],
      );
      await tester.pumpAndSettle();

      await app.run(tester, child: probe, userId: 8, overrides: [lit]);
      expect(find.text('room none'), findsOne);
    });
  });

  group('the codec', () {
    test('keeps every field the modules draw, whole', () {
      final request = requesterRequest(
        id: 9,
        title: 'Tears of Steel',
        tmdbId: 133701,
        status: RequestStatus.approved,
        availability: SeerrMediaAvailability.partiallyAvailable,
        asked: const Duration(days: 9),
        answered: const Duration(days: 8),
        arrived: const Duration(days: 1),
        watchUrl: _watchLink,
        voteAverage: 7.3,
        is4k: true,
        type: 'tv',
      );
      final json = seerrRequestToJson(request);
      final back = seerrRequestFromJson(json)!;
      expect(seerrRequestToJson(back), json);
      expect(back.id, 9);
      expect(back.type, 'tv');
      expect(back.is4k, isTrue);
      expect(back.status, RequestStatus.approved);
      expect(back.mediaAvailability, SeerrMediaAvailability.partiallyAvailable);
      expect(back.media!.title, 'Tears of Steel');
      expect(back.media!.tmdbId, 133701);
      expect(back.media!.voteAverage, 7.3);
      expect(back.watchUrl, _watchLink);
      expect(
        DateTime.parse(
          back.createdAt,
        ).isAtSameMomentAs(DateTime.parse(request.createdAt)),
        isTrue,
      );
      expect(
        back.media!.addedAt!.isAtSameMomentAs(request.media!.addedAt!),
        isTrue,
      );
    });

    test('refuses a record it cannot read whole', () {
      expect(seerrRequestFromJson(null), isNull);
      expect(seerrRequestFromJson({'id': 'x'}), isNull);
      expect(
        seerrRequestFromJson({'id': 1, 'status': 'nope', 'type': 'movie'}),
        isNull,
      );
      // A media it cannot read is not a request without one.
      expect(
        seerrRequestFromJson({
          'id': 1,
          'status': 'approved',
          'type': 'movie',
          'media': {'status': 'sideways'},
        }),
        isNull,
      );
      expect(
        myRequestsLastKnown.decode({
          'requests': [
            seerrRequestToJson(requesterRequest()),
            {'id': 'broken'},
          ],
        }, (_) => throw StateError('no pictures')),
        isNull,
        reason: 'a drawing missing a request would state a wrong count',
      );
      expect(
        myRequestsLastKnown.decode(
          'nonsense',
          (_) => throw StateError('no pictures'),
        ),
        isNull,
      );
    });

    test('keeps no credential, nobody else and nothing that runs', () {
      final request = requesterRequest(
        watchUrl: 'https://jellyfin.example.com/web/?api_key=hunter2',
        requestedBy: const RequestedBy(
          id: 4,
          displayName: 'Anna Rossi',
          avatar: 'https://seerr.example.com/avatar?token=hunter3',
        ),
        status: RequestStatus.approved,
        availability: SeerrMediaAvailability.processing,
        arrived: null,
        downloads: [movingDownload(requesterNow)],
      );
      final data = jsonEncode(myRequestsLastKnown.encode([request]));
      for (final secret in [
        'hunter2',
        'hunter3',
        'api_key',
        'Anna Rossi',
        'avatar',
        'requestedBy',
        'sizeLeft',
        'estimatedCompletionTime',
        'downloads',
      ]) {
        expect(data, isNot(contains(secret)), reason: secret);
      }

      // A link kept on the Home of Jellyfin and Plex puts its query after the
      // `#`: a key there is a key too.
      final fragment = requesterRequest(
        watchUrl: 'https://plex.example.com/web/#!/server/ab/details?token=zz9',
      );
      expect(jsonEncode(seerrRequestToJson(fragment)), isNot(contains('zz9')));
    });

    test('keeps the on-its-way, the newest arrivals and the newest answers '
        'and no more', () {
      List<SeerrRequest> arrivals(int count) => [
        for (var i = 0; i < count; i++)
          requesterRequest(
            id: 100 + i,
            title: 'Arrived $i',
            arrived: Duration(hours: 2 + i),
          ),
      ];
      final requests = [
        requesterRequest(
          id: 1,
          title: 'Waiting',
          status: RequestStatus.pendingApproval,
          availability: SeerrMediaAvailability.unknown,
          arrived: null,
        ),
        ...arrivals(6),
        for (var i = 0; i < 5; i++)
          requesterRequest(
            id: 200 + i,
            title: 'No $i',
            status: RequestStatus.declined,
            availability: SeerrMediaAvailability.unknown,
            arrived: null,
            answered: Duration(days: 1 + i),
          ),
        // Long on the server and without a day: never on the Home.
        requesterRequest(id: 300, title: 'Old', arrived: null),
      ];
      final data = myRequestsLastKnown.encode(requests)! as Map;
      final titles = [
        for (final json in data['requests'] as List)
          ((json as Map)['media'] as Map)['title'],
      ];
      expect(titles, [
        'Waiting',
        'Arrived 0',
        'Arrived 1',
        'Arrived 2',
        'No 0',
        'No 1',
        'No 2',
      ]);
    });

    test(
      'is not kept when the on-the-way list was longer than it can state',
      () {
        final many = [
          for (var i = 0; i < 101; i++)
            requesterRequest(
              id: i,
              status: RequestStatus.pendingApproval,
              availability: SeerrMediaAvailability.unknown,
              arrived: null,
            ),
        ];
        expect(myRequestsLastKnown.encode(many), isNull);
      },
    );
  });
}

/// The light the Home's room is given, said as text.
class _RoomProbe extends ConsumerWidget {
  const _RoomProbe();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final light = ref.watch(featuredRoomLightProvider);
    return Text('room ${light == null ? 'none' : light.toARGB32()}');
  }
}
