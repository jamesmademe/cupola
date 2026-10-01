/// Activity's figures, driven through the app's own clients on the profiles'
/// fake network: a count says what answered, and names what did not.
///
/// Each of these was a number that looked like an answer to the question the
/// user asked and answered a smaller one: the connections that happened to
/// answer, the rows that happened to be loaded, the first page of a list.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/status/media_status.dart';
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

      final readout = nowReadout(feed);
      expect(readout.text, '1 in the queue · Sonarr Anime not counted');
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
        nowReadout(feed).text,
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

      final readout = nowReadout(feed);
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

      expect(nowReadout(feed).text, '1 in the queue');
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
        find.textContaining(RegExp(r'^\d+ in the queue · Lidarr not counted')),
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
}
