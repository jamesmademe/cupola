import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/models/media_preview.dart';
import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/features/discover/presentation/catalog_providers.dart';
import 'package:cupola/features/home/data/last_known/media_preview_codec.dart';
import 'package:cupola/features/home/data/last_known/requester_shelves_last_known.dart';
import 'package:cupola/features/home/domain/home_module.dart';
import 'package:cupola/features/home/presentation/home_screen.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';
import 'package:cupola/features/home/data/home_last_known.dart';

import '../../../test_helpers/requester_cold_start.dart';

MediaPreview _title(
  String title, {
  int id = 1,
  String mediaType = 'movie',
  String? releaseDate,
  Map<String, dynamic>? mediaInfo,
  double? voteAverage,
}) => MediaPreview(
  id: id,
  title: title,
  mediaType: mediaType,
  releaseDate: releaseDate,
  mediaInfo: mediaInfo,
  voteAverage: voteAverage,
  voteCount: voteAverage == null ? null : 900,
);

const _failure = ClassifiedFailure(ServiceFailureReason.unreachable);

/// The requester's two shelves at a cold start: the posters they last drew,
/// said for what they are, and never replaced by a failure or a skeleton once
/// they have posters.
void main() {
  late RequesterColdStart app;
  setUp(() => app = RequesterColdStart());

  final shelves = Column(
    children: [
      homeModuleView(HomeModule.trending),
      homeModuleView(HomeModule.comingSoon),
    ],
  );

  Future<void> run(
    WidgetTester tester, {
    Future<List<MediaPreview>> Function()? trending,
    Future<List<MediaPreview>> Function()? comingSoon,
    DateTime? now,
    int userId = 7,
    SettingsModel Function(SettingsModel)? customize,
  }) => app.run(
    tester,
    child: shelves,
    trending: trending,
    comingSoon: comingSoon,
    now: now,
    userId: userId,
    customize: customize,
  );

  // A new list at every read, as a new answer is: a slot does not write a
  // value it has just written, and one list handed to every run would not.
  List<MediaPreview> trending() => [
    _title('Dune', id: 1, voteAverage: 7.9),
    _title('Severance', id: 2, mediaType: 'tv'),
  ];
  List<MediaPreview> comingSoon() => [
    _title('Tron', id: 3, releaseDate: '2026-10-14'),
    _title('Hamnet', id: 4, releaseDate: '2026-10-20'),
    _title('Untitled', id: 5),
  ];

  Future<void> firstRun(WidgetTester tester) async {
    await run(
      tester,
      trending: () async => trending(),
      comingSoon: () async => comingSoon(),
    );
    await tester.pumpAndSettle();
    expect(find.text('Dune'), findsOne);
    expect(find.text('Tron'), findsOne);
    expect(find.textContaining('As of'), findsNothing);
  }

  group('a cold start', () {
    testWidgets('draws both shelves at once, says so, then the live ones', (
      tester,
    ) async {
      await firstRun(tester);

      final trendingAnswer = Completer<List<MediaPreview>>();
      final comingAnswer = Completer<List<MediaPreview>>();
      await run(
        tester,
        trending: () => trendingAnswer.future,
        comingSoon: () => comingAnswer.future,
        now: requesterNow.add(const Duration(hours: 1)),
      );
      await tester.pumpAndSettle();
      // Posters, not skeletons: the titles, the score and the day under them.
      expect(find.text('Trending this week'), findsOne);
      expect(find.text('Dune'), findsOne);
      expect(find.text('Severance'), findsOne);
      expect(find.text('TMDB\u00A07.9'), findsOne);
      expect(find.text('Coming soon'), findsOne);
      expect(find.text('Tron'), findsOne);
      expect(find.text('Wed 14 Oct'), findsOne);
      expect(find.text('As of 20:53\u00A0· checking now'), findsOne);

      trendingAnswer.complete([_title('Wicked', id: 9)]);
      await tester.pumpAndSettle();
      expect(find.text('Dune'), findsNothing);
      expect(find.text('Wicked'), findsOne);
      // Coming soon is still the drawing: the line stays for it.
      expect(find.text('As of 20:53\u00A0· checking now'), findsOne);

      comingAnswer.complete([
        _title('Moana', id: 10, releaseDate: '2026-11-01'),
      ]);
      await tester.pumpAndSettle();
      expect(find.text('Tron'), findsNothing);
      expect(find.text('Moana'), findsOne);
      expect(find.textContaining('As of'), findsNothing);
    });

    testWidgets('a live read that fails keeps both over the failure, with no '
        'line of their own, and stops checking', (tester) async {
      await firstRun(tester);

      await run(
        tester,
        trending: () async => throw _failure,
        comingSoon: () async => throw _failure,
      );
      await tester.pumpAndSettle();
      expect(find.text('Dune'), findsOne);
      expect(find.text('Tron'), findsOne);
      expect(find.textContaining('row is missing'), findsNothing);
      expect(find.text('As of 20:53'), findsOne);
    });

    testWidgets('another server or another person draws nothing of it', (
      tester,
    ) async {
      await firstRun(tester);
      await run(tester);
      expect(find.text('Dune'), findsOne, reason: 'the control draws it');

      await run(
        tester,
        customize: (settings) => settings.copyWithInstance(
          settings
              .instancesOf(ServiceKey.seerr)
              .first
              .copyWith(url: 'https://other.example.com'),
        ),
      );
      expect(find.text('Dune'), findsNothing);
      expect(find.text('Tron'), findsNothing);
      expect(find.textContaining('As of'), findsNothing);
    });

    testWidgets('another person draws nothing of it', (tester) async {
      await firstRun(tester);
      await run(tester);
      expect(find.text('Dune'), findsOne, reason: 'the control draws it');

      await run(tester, userId: 8);
      expect(find.text('Dune'), findsNothing);
      expect(find.text('Tron'), findsNothing);
      expect(find.textContaining('As of'), findsNothing);
    });

    testWidgets('Coming soon is cut again: a title whose day has passed is '
        'not coming, one with no day stays', (tester) async {
      await firstRun(tester);

      // Wed 14 Oct is today: still coming.
      await run(tester, now: DateTime(2026, 10, 14, 9));
      expect(find.text('Tron'), findsOne);

      await run(tester, now: DateTime(2026, 10, 15, 9));
      expect(find.text('Tron'), findsNothing);
      expect(find.text('Hamnet'), findsOne);
      expect(find.text('Untitled'), findsOne);
      // The shelf above it is not cut: its drawing is whole.
      expect(find.text('Dune'), findsOne);
    });

    testWidgets('a drawing with nothing left is the skeleton, and over a '
        'failure nothing', (tester) async {
      await run(
        tester,
        trending: () async => trending(),
        comingSoon: () async => [
          _title('Tron', id: 3, releaseDate: '2026-10-14'),
        ],
      );
      await tester.pumpAndSettle();

      await run(tester, now: DateTime(2026, 10, 20, 9));
      expect(find.text('Coming soon'), findsOne);
      expect(find.text('Tron'), findsNothing);
      // Trending is still the drawing; Coming soon is not, and the line says
      // only what is drawn.
      expect(find.text('Dune'), findsOne);
      expect(find.text('As of Mon 12 Oct\u00A0· checking now'), findsOne);

      await run(
        tester,
        now: DateTime(2026, 10, 20, 9),
        comingSoon: () async => throw _failure,
      );
      await tester.pumpAndSettle();
      expect(find.text('Coming soon'), findsNothing);
      expect(find.textContaining('row is missing'), findsNothing);
    });

    testWidgets('an empty answer is not a shelf: the drawing before it '
        'stays', (tester) async {
      await firstRun(tester);
      await run(
        tester,
        trending: () async => const [],
        comingSoon: () async => const [],
      );
      await tester.pumpAndSettle();
      expect(find.text('Dune'), findsNothing);

      await run(tester);
      expect(find.text('Dune'), findsOne);
      expect(find.text('Tron'), findsOne);
    });
  });

  group('a live shelf', () {
    testWidgets('keeps its posters while it is asked again, and when that '
        'fails', (tester) async {
      // What Seerr does each time it is asked: answers, then never does, then
      // fails.
      final answers = <Future<List<MediaPreview>> Function()>[
        () async => trending(),
        () => Completer<List<MediaPreview>>().future,
        () async => throw _failure,
      ];
      var reads = 0;
      await run(
        tester,
        trending: () => answers[reads++](),
        comingSoon: () async => comingSoon(),
      );
      await tester.pumpAndSettle();
      expect(find.text('Dune'), findsOne);

      final container = ProviderScope.containerOf(
        tester.element(find.text('Dune')),
      );
      container.invalidate(atriumTrendingProvider);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(reads, 2, reason: 'asked again, and no answer yet');
      // Asked again: the posters stay, no skeleton under the heading.
      expect(find.text('Dune'), findsOne);

      // The read that failed is the Home's one line to say; the shelf stays.
      container.invalidate(atriumTrendingProvider);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(reads, 3, reason: 'asked a third time, and it failed');
      expect(find.text('Dune'), findsOne);
      expect(find.textContaining('row is missing'), findsNothing);
    });

    testWidgets('is absent when its read failed and nothing was known '
        'before', (tester) async {
      await run(
        tester,
        trending: () async => throw _failure,
        comingSoon: () async => throw _failure,
      );
      await tester.pumpAndSettle();
      expect(find.text('Trending this week'), findsNothing);
      expect(find.text('Coming soon'), findsNothing);
      expect(find.textContaining('row is missing'), findsNothing);
    });
  });

  group('the codec', () {
    test('keeps what a poster draws, whole', () {
      final item = _title(
        'Severance',
        id: 95396,
        mediaType: 'tv',
        releaseDate: '2022-02-18',
        voteAverage: 8.4,
        mediaInfo: {'status': 5, 'status4k': 1},
      );
      final json = mediaPreviewToJson(item);
      final back = mediaPreviewFromJson(json)!;
      expect(mediaPreviewToJson(back), json);
      expect(back.id, 95396);
      expect(back.title, 'Severance');
      expect(back.mediaType, 'tv');
      expect(back.releaseDate, '2022-02-18');
      expect(back.voteAverage, 8.4);
      expect(back.voteCount, 900);
      expect(back.mediaInfo, {'status': 5, 'status4k': 1});
    });

    test('refuses a title it cannot read whole', () {
      expect(mediaPreviewFromJson(null), isNull);
      expect(mediaPreviewFromJson({'id': 1, 'title': 'x'}), isNull);
      expect(
        mediaPreviewFromJson({'id': '1', 'title': 'x', 'mediaType': 'movie'}),
        isNull,
      );
      expect(
        trendingLastKnown.decode({
          'items': [
            mediaPreviewToJson(_title('Dune')),
            {'id': 'broken'},
          ],
        }, (_) => throw StateError('no pictures')),
        isNull,
      );
      expect(
        trendingLastKnown.decode('nonsense', (_) => throw StateError('none')),
        isNull,
      );
    });

    test('keeps no one else, and no download', () {
      final item = _title(
        'Dune',
        mediaInfo: {
          'status': 3,
          'status4k': 1,
          'requests': [
            {
              'requestedBy': {
                'email': 'luca@example.com',
                'displayName': 'Luca',
                'avatar': 'https://seerr.example.com/avatar?token=hunter2',
              },
            },
          ],
          'downloadStatus': [
            {'size': 100, 'sizeLeft': 38, 'title': 'Dune.2021.2160p'},
          ],
        },
      );
      final data = jsonEncode(trendingLastKnown.encode([item], _keep));
      for (final private in [
        'luca@example.com',
        'Luca',
        'hunter2',
        'requests',
        'requestedBy',
        'downloadStatus',
        'sizeLeft',
        'Dune.2021',
      ]) {
        expect(data, isNot(contains(private)), reason: private);
      }
      // What the poster says of it is kept.
      expect(data, contains('"status":3'));
    });

    test('keeps the first posters only, and nothing for an empty shelf', () {
      final many = [for (var i = 0; i < 30; i++) _title('T$i', id: i)];
      final data = trendingLastKnown.encode(many, _keep)! as Map;
      expect((data['items'] as List).length, 20);
      expect(trendingLastKnown.encode(const [], _keep), isNull);
    });
  });
}

/// Keeps the pictures as the Home does, against no connection: a picture
/// with headers has nothing to be kept by, and only public ones are.
final _keep = storedImageKeeper(const SettingsModel());
