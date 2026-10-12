import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/activity/presentation/activity_provider.dart';
import 'package:cupola/features/discover/data/seerr_service.dart';
import 'package:cupola/features/discover/domain/models/seerr_request.dart';
import 'package:cupola/features/movies/data/radarr_service.dart';
import 'package:cupola/features/music/data/lidarr_service.dart';
import 'package:cupola/features/series/data/sonarr_service.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import '../../../test_helpers/fake_services.dart';
import '../../../test_helpers/settings_scope.dart';

/// The second Seerr. The first one keeps the primary id, so every override that
/// names `seerrServiceProvider` (which is how the whole suite supplies a fake
/// Seerr) still addresses it.
const _secondSeerr = ServiceInstance(
  id: 'seerr-2222222',
  service: ServiceKey.seerr,
  label: 'Anime',
  url: 'https://second.lan:5055',
  credential: 'key-2',
);

Future<List<Override>> _twoSeerrs() => settingsScopeOverrides(
  configured: activityServiceKeys,
  customize: (settings) => settings.copyWithInstance(_secondSeerr),
);

SeerrRequest _request(int id, String title) => SeerrRequest(
  id: id,
  status: RequestStatus.pendingApproval,
  type: 'movie',
  createdAt: '2026-08-01T10:00:00.000Z',
  media: RequestMedia(id: id, tmdbId: id, mediaType: 'movie', title: title),
);

ProviderContainer _container({
  required List<Override> settings,
  SeerrService? lens,
  SeerrService? second,
}) {
  final container = ProviderContainer(
    overrides: [
      ...settings,
      radarrServiceProvider.overrideWith((ref) => FakeRadarrService()),
      sonarrServiceProvider.overrideWith((ref) => FakeSonarrService()),
      lidarrServiceProvider.overrideWith((ref) => FakeLidarrService()),
      if (lens != null) seerrServiceProvider.overrideWith((ref) => lens),
      if (second != null)
        seerrServiceForProvider(_secondSeerr.id).overrideWithValue(second),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  // The gap this closes: /activity aggregated the three \*arr over every
  // connection and left Seerr resolving through the lens, so with two Seerrs
  // configured the second one's requests were simply not on the screen.
  test(
    'the feed carries the requests of every Seerr, not just the lens\'s',
    () async {
      final container = _container(
        settings: await _twoSeerrs(),
        lens: _RequestsSeerrService([_request(1, 'From the first')]),
        second: _RequestsSeerrService([
          _request(1, 'From the second'),
          _request(2, 'Also the second'),
        ]),
      );

      final feed = await container.read(globalNowItemsProvider.future);
      final requests = feed.items.where((i) => i.service == ServiceKey.seerr);

      expect(
        requests.map((i) => i.title),
        containsAll(<String>[
          'From the first',
          'From the second',
          'Also the second',
        ]),
      );
      expect(requests, hasLength(3));
      // Both servers have a request id 1: Seerr numbers its requests per
      // instance, which is exactly why a row has to carry its connection.
      expect(requests.map((i) => i.instanceId).toSet(), {
        'seerr',
        _secondSeerr.id,
      });
    },
  );

  test(
    'a request row names its connection only when there is more than one',
    () async {
      final container = _container(
        settings: await _twoSeerrs(),
        lens: _RequestsSeerrService([_request(1, 'From the first')]),
        second: _RequestsSeerrService([_request(1, 'From the second')]),
      );

      final feed = await container.read(globalNowItemsProvider.future);
      final byTitle = {
        for (final item in feed.items) item.title: item.instanceLabel,
      };

      // The first Seerr has no label of its own, so it is called by its place
      // among the Seerrs (the app's one rule, which the \*arr rows and the
      // lens sheet follow too). Never its id.
      expect(byTitle['From the first'], 'Seerr 1');
      expect(byTitle['From the second'], 'Anime');
    },
  );

  test('a lone Seerr grows no label', () async {
    final container = _container(
      settings: await settingsScopeOverrides(configured: activityServiceKeys),
      lens: _RequestsSeerrService([_request(1, 'Only one')]),
    );

    final feed = await container.read(globalNowItemsProvider.future);
    final row = feed.items.firstWhere((i) => i.service == ServiceKey.seerr);

    expect(row.instanceLabel, isEmpty);
    expect(row.instanceId, 'seerr');
  });

  test('one unreachable Seerr is carried, not swallowed', () async {
    final container = _container(
      settings: await _twoSeerrs(),
      lens: _ThrowingSeerrService(),
      second: _RequestsSeerrService([_request(1, 'Still here')]),
    );

    final feed = await container.read(globalNowItemsProvider.future);

    // The survivor is intact.
    expect(
      feed.items.where((i) => i.service == ServiceKey.seerr).single.title,
      'Still here',
    );
    expect(feed.isPartial, isTrue);

    // And the failure names the connection, not just the service.
    final failed = feed.failures.single;
    expect(failed.service, ServiceKey.seerr);
    expect(failed.instanceId, 'seerr');
    expect(failed.title, 'Seerr 1');

    final reached = feed
        .resultsFor(ServiceKey.seerr)
        .firstWhere((r) => r.instanceId == _secondSeerr.id);
    expect(reached.reached, isTrue);
  });

  test('an empty Seerr stays distinguishable from a dead one', () async {
    final container = _container(
      settings: await _twoSeerrs(),
      lens: _RequestsSeerrService(const []),
      second: _RequestsSeerrService(const []),
    );

    final feed = await container.read(globalNowItemsProvider.future);

    expect(feed.failures, isEmpty);
    expect(feed.isPartial, isFalse);
    expect(
      feed.resultsFor(ServiceKey.seerr).map((r) => r.reached),
      everyElement(isTrue),
    );
  });

  // The distinction above only exists if the service stops turning an outage
  // into an empty list. It used to `catch (e) { return []; }` around the whole
  // load, so a Seerr that never answered and a Seerr with no requests produced
  // byte-identical output, and no caller could tell.
  test('a Seerr that does not answer reports it', () async {
    final container = _container(
      settings: await settingsScopeOverrides(configured: activityServiceKeys),
      lens: _ThrowingSeerrService(),
    );

    final feed = await container.read(globalNowItemsProvider.future);

    expect(feed.resultsFor(ServiceKey.seerr).single.failed, isTrue);
  });
}

class _RequestsSeerrService extends FakeSeerrService {
  _RequestsSeerrService(this.requests);

  final List<SeerrRequest> requests;

  @override
  Future<List<SeerrRequest>> getRequests() async => requests;
}

class _ThrowingSeerrService extends FakeSeerrService {
  @override
  Future<List<SeerrRequest>> getRequests() async {
    throw Exception('offline');
  }
}
