/// The feed's own figures: a count says what answered, and names what did
/// not.
///
/// Each of these was a number that looked like an answer to the question the
/// user asked and answered a smaller one: the connections that happened to
/// answer, the first page of a list. The page's own figures (the readout, the
/// sections' counts) are held where the page is tested
/// (`activity_page_test.dart`, `domain/activity_readout_test.dart`).
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/status/media_status.dart';
import 'package:cupola/features/activity/domain/service_type.dart';
import 'package:cupola/features/activity/presentation/activity_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

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

void main() {
  group('the service counts', () {
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
  });
}
