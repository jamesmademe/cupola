import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/activity/presentation/activity_provider.dart';
import 'package:cupola/features/activity/presentation/global_activity_screen.dart';
import 'package:cupola/features/discover/data/seerr_service.dart';
import 'package:cupola/features/discover/presentation/discover_provider.dart';
import 'package:cupola/features/movies/data/radarr_service.dart';
import 'package:cupola/features/music/data/lidarr_service.dart';
import 'package:cupola/features/series/data/sonarr_service.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import '../../../test_helpers/fake_services.dart';
import '../../../test_helpers/settings_scope.dart';

/// The second Sonarr. The first one keeps the primary id, so its storage keys
/// — and every override that names `sonarrServiceProvider` — are unchanged.
const _secondSonarr = ServiceInstance(
  id: 'sonarr-2222222',
  service: ServiceKey.sonarr,
  label: '2',
  url: 'https://second.lan:8989',
  credential: 'key-2',
);

Future<List<Override>> _twoSonarrs() => settingsScopeOverrides(
  configured: activityServiceKeys,
  customize: (settings) => settings.copyWithInstance(_secondSonarr),
);

ProviderContainer _container({
  required List<Override> settings,
  SonarrService? lens,
  SonarrService? second,
  SeerrService? seerr,
}) {
  final container = ProviderContainer(
    overrides: [
      ...settings,
      requestsProvider.overrideWith((ref) async => const []),
      if (seerr != null) seerrServiceProvider.overrideWith((ref) => seerr),
      radarrServiceProvider.overrideWith((ref) => FakeRadarrService()),
      lidarrServiceProvider.overrideWith((ref) => FakeLidarrService()),
      if (lens != null) sonarrServiceProvider.overrideWith((ref) => lens),
      if (second != null)
        sonarrServiceForProvider(_secondSonarr.id).overrideWithValue(second),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  // The device pass that started this: two Sonarrs, eight downloads, all of
  // them on the second connection. With the lens on it the pill said 8; moved
  // to the first it said 0 and "Nothing from Sonarr right now" — while the
  // eight were still downloading.
  test(
    'the queue is the sum of a service\'s connections, not the lens\'s',
    () async {
      final container = _container(
        settings: await _twoSonarrs(),
        lens: _QueueSonarrService(const [
          {
            'id': 1,
            'title': 'A.Release',
            'status': 'downloading',
            'series': {'title': 'From the first'},
          },
        ]),
        second: _QueueSonarrService(const [
          {
            'id': 1,
            'title': 'B.Release',
            'status': 'downloading',
            'series': {'title': 'From the second'},
          },
          {
            'id': 2,
            'title': 'C.Release',
            'status': 'downloading',
            'series': {'title': 'Also the second'},
          },
        ]),
      );

      final feed = await container.read(globalQueueItemsProvider.future);

      expect(
        feed.items.map((item) => item.title),
        containsAll(<String>[
          'From the first',
          'From the second',
          'Also the second',
        ]),
      );
      expect(
        feed.items.where((i) => i.service == ServiceKey.sonarr),
        hasLength(3),
      );
      // Both queue ids are 1 — per-server numbering, which is exactly why a row
      // has to carry its connection rather than its service alone.
      expect(
        feed.items
            .where((i) => i.service == ServiceKey.sonarr)
            .map((i) => i.instanceId)
            .toSet(),
        {'sonarr', _secondSonarr.id},
      );
    },
  );

  test('a row names its connection only when there is more than one', () async {
    final container = _container(
      settings: await _twoSonarrs(),
      lens: _QueueSonarrService(const [
        {
          'id': 1,
          'title': 'A.Release',
          'status': 'downloading',
          'series': {'title': 'From the first'},
        },
      ]),
      second: _QueueSonarrService(const []),
    );

    final feed = await container.read(globalQueueItemsProvider.future);
    final sonarrRow = feed.items.firstWhere(
      (item) => item.service == ServiceKey.sonarr,
    );

    // The first Sonarr has no label of its own, so it falls back to its id —
    // the same rule the search sections and the lens sheet follow.
    expect(sonarrRow.instanceLabel, 'sonarr');
  });

  test('a lone connection grows no label', () async {
    final container = _container(
      settings: await settingsScopeOverrides(configured: activityServiceKeys),
      lens: _QueueSonarrService(const [
        {
          'id': 1,
          'title': 'A.Release',
          'status': 'downloading',
          'series': {'title': 'Only one'},
        },
      ]),
    );

    final feed = await container.read(globalQueueItemsProvider.future);
    final row = feed.items.firstWhere((i) => i.service == ServiceKey.sonarr);

    expect(row.instanceLabel, isEmpty);
    expect(row.instanceId, 'sonarr');
  });

  // The property the old per-service result existed to protect, now owed per
  // connection: a dead Sonarr and an idle Sonarr must not look alike, and one
  // dead connection must not blank its sibling.
  test('one unreachable connection is carried, not swallowed', () async {
    final container = _container(
      settings: await _twoSonarrs(),
      lens: _ThrowingQueueSonarrService(),
      second: _QueueSonarrService(const [
        {
          'id': 7,
          'title': 'B.Release',
          'status': 'downloading',
          'series': {'title': 'Still here'},
        },
      ]),
    );

    final feed = await container.read(globalQueueItemsProvider.future);

    // The survivor is intact.
    expect(
      feed.items.where((i) => i.service == ServiceKey.sonarr).single.title,
      'Still here',
    );
    expect(feed.isPartial, isTrue);
    expect(feed.allConfiguredFailed, isFalse);

    // And the failure names the connection, not just the service — "Sonarr did
    // not answer" is the wrong sentence when the other Sonarr did.
    final failed = feed.failures.single;
    expect(failed.service, ServiceKey.sonarr);
    expect(failed.instanceId, 'sonarr');
    expect(failed.title, 'Sonarr · sonarr');

    // The sibling is reported separately and is *reached*, which is the whole
    // distinction: empty is not the same fact as unreachable.
    final reached = feed
        .resultsFor(ServiceKey.sonarr)
        .firstWhere((r) => r.instanceId == _secondSonarr.id);
    expect(reached.reached, isTrue);
  });

  test('an empty connection stays distinguishable from a dead one', () async {
    final container = _container(
      settings: await _twoSonarrs(),
      lens: _QueueSonarrService(const []),
      second: _QueueSonarrService(const []),
    );

    final feed = await container.read(globalQueueItemsProvider.future);

    expect(feed.failures, isEmpty);
    expect(feed.isPartial, isFalse);
    expect(
      feed.resultsFor(ServiceKey.sonarr).map((r) => r.reached),
      everyElement(isTrue),
    );
  });

  test(
    'every connection of a service failing is not the same as all of them',
    () async {
      final container = _container(
        settings: await _twoSonarrs(),
        lens: _ThrowingQueueSonarrService(),
        second: _ThrowingQueueSonarrService(),
      );

      final feed = await container.read(globalQueueItemsProvider.future);

      // Radarr and Lidarr answered, so the screen must not claim total failure.
      expect(feed.allConfiguredFailed, isFalse);
      expect(feed.resultsFor(ServiceKey.sonarr).every((r) => r.failed), isTrue);
      expect(feed.failures, hasLength(2));
    },
  );

  test('a paged bucket pages every connection', () async {
    final container = _container(
      settings: await _twoSonarrs(),
      lens: _HistorySonarrService(const [
        {'sourceTitle': 'First.Server', 'eventType': 'grabbed'},
      ]),
      second: _HistorySonarrService(const [
        {'sourceTitle': 'Second.Server', 'eventType': 'grabbed'},
      ]),
    );

    final notifier = container.read(globalHistoryFeedProvider.notifier);
    await notifier.loading;
    final feed = container.read(globalHistoryFeedProvider).feed!;

    expect(
      feed.items
          .where((i) => i.service == ServiceKey.sonarr)
          .map((i) => i.title),
      containsAll(<String>['First.Server', 'Second.Server']),
    );
  });

  testWidgets('the filter pill counts every connection of its service', (
    tester,
  ) async {
    final container = _container(
      settings: await _twoSonarrs(),
      seerr: FakeSeerrService(),
      lens: _QueueSonarrService(const [
        {
          'id': 1,
          'title': 'A.Release',
          'status': 'downloading',
          'series': {'title': 'From the first'},
        },
      ]),
      second: _QueueSonarrService(const [
        {
          'id': 1,
          'title': 'B.Release',
          'status': 'downloading',
          'series': {'title': 'From the second'},
        },
      ]),
    );

    await _pumpScreen(tester, container);

    // Twice: the filter pill and the group header both say it, and that they
    // AGREE is the assertion. Folding the results by service alone left the
    // pill reporting whichever connection happened to be merged last, so the
    // header said 2 and the pill under it said 1.
    expect(find.bySemanticsLabel('Sonarr, 2 items'), findsNWidgets(2));
    expect(find.text('From the first'), findsOneWidget);
    expect(find.text('From the second'), findsOneWidget);

    await _closeScreen(tester, container);
  });

  testWidgets('one dead connection does not turn its service into a dash', (
    tester,
  ) async {
    final container = _container(
      settings: await _twoSonarrs(),
      seerr: FakeSeerrService(),
      // The live one first and the dead one second, deliberately: folding by
      // service kept whichever came last, so a service with something to show
      // reported the dash of its dead sibling.
      lens: _QueueSonarrService(const [
        {
          'id': 1,
          'title': 'B.Release',
          'status': 'downloading',
          'series': {'title': 'Still here'},
        },
      ]),
      second: _ThrowingQueueSonarrService(),
    );

    await _pumpScreen(tester, container);

    // One real item was reached, so the pill prints it. The dash is reserved
    // for "no idea", which is only true when nothing of this service answered.
    expect(find.bySemanticsLabel('Sonarr, 1 item'), findsNWidgets(2));
    // And the incompleteness is named by connection: "Sonarr did not respond"
    // is the wrong sentence while the other Sonarr is answering.
    expect(
      find.textContaining('Sonarr · ${_secondSonarr.label}'),
      findsWidgets,
    );

    await _closeScreen(tester, container);
  });

  testWidgets('a service whose every connection failed still says so', (
    tester,
  ) async {
    final container = _container(
      settings: await _twoSonarrs(),
      seerr: FakeSeerrService(),
      lens: _ThrowingQueueSonarrService(),
      second: _ThrowingQueueSonarrService(),
    );

    await _pumpScreen(tester, container);

    expect(find.bySemanticsLabel('Sonarr, did not answer'), findsOneWidget);

    await _closeScreen(tester, container);
  });

  test(
    'an unconfigured service is still reported once, not per connection',
    () async {
      final container = _container(
        settings: await settingsScopeOverrides(
          configured: const [ServiceKey.sonarr],
        ),
        lens: _QueueSonarrService(const []),
      );

      final feed = await container.read(globalQueueItemsProvider.future);

      expect(
        feed.unconfigured.map((r) => r.service),
        containsAll(const [ServiceKey.radarr, ServiceKey.lidarr]),
      );
      expect(
        feed.unconfigured.where((r) => r.service == ServiceKey.radarr),
        hasLength(1),
      );
    },
  );
}

Future<void> _pumpScreen(
  WidgetTester tester,
  ProviderContainer container,
) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: GlobalActivityScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

/// Takes the screen down inside the test body.
///
/// The Now bucket holds a 15s poll while it is on screen, and the pending-timer
/// check runs before any tear-down — so both the tree and the container have to
/// go here.
Future<void> _closeScreen(
  WidgetTester tester,
  ProviderContainer container,
) async {
  await tester.pumpWidget(const SizedBox());
  container.dispose();
}

class _QueueSonarrService extends FakeSonarrService {
  _QueueSonarrService(this.queue);

  final List<dynamic> queue;

  @override
  Future<List<dynamic>> getQueue({
    Map<String, dynamic>? queryParameters,
  }) async => queue;
}

class _HistorySonarrService extends FakeSonarrService {
  _HistorySonarrService(this.history);

  final List<dynamic> history;

  @override
  Future<List<dynamic>> getHistory({
    int page = 1,
    int pageSize = 20,
    Map<String, dynamic>? queryParameters,
  }) async => page == 1 ? history : const [];
}

class _ThrowingQueueSonarrService extends FakeSonarrService {
  @override
  Future<List<dynamic>> getQueue({
    Map<String, dynamic>? queryParameters,
  }) async {
    throw const SocketException('Connection refused');
  }
}
