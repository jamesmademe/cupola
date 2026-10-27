import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/activity/domain/service_type.dart';
import 'package:cupola/features/activity/presentation/activity_provider.dart';
import 'package:cupola/features/discover/data/seerr_service.dart';
import 'package:cupola/features/discover/domain/models/seerr_request.dart';
import 'package:cupola/features/discover/presentation/discover_provider.dart';
import 'package:cupola/features/movies/data/radarr_service.dart';
import 'package:cupola/features/music/data/lidarr_service.dart';
import 'package:cupola/features/series/data/sonarr_service.dart';

import '../../../test_helpers/fake_services.dart';
import '../../../test_helpers/settings_scope.dart';

void main() {
  late List<Override> settingsOverrides;

  setUp(() async {
    // The feed distinguishes "not configured" from "did not answer", so it reads
    // settings, which throw unless overridden.
    settingsOverrides = await settingsScopeOverrides(
      configured: activityServiceKeys,
    );
  });

  ProviderContainer createContainer({
    SeerrService? seerrService,
    RadarrService? radarrService,
    SonarrService? sonarrService,
    LidarrService? lidarrService,
    List<SeerrRequest>? requests,
  }) {
    final container = ProviderContainer(
      overrides: [
        ...settingsOverrides,
        if (seerrService != null)
          seerrServiceProvider.overrideWith((ref) => seerrService),
        if (requests != null) ...[
          requestsProvider.overrideWith((ref) async => requests),
          // Now reads the requests in motion, which Seerr filters itself.
          activeRequestsForProvider.overrideWith((ref, id) async => requests),
        ],
        if (radarrService != null)
          radarrServiceProvider.overrideWith((ref) => radarrService),
        if (sonarrService != null)
          sonarrServiceProvider.overrideWith((ref) => sonarrService),
        if (lidarrService != null)
          lidarrServiceProvider.overrideWith((ref) => lidarrService),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('ServiceType.displayTitle returns the expected label per type', () {
    const expected = {
      ServiceType.movies: 'Movies',
      ServiceType.series: 'Series',
      ServiceType.music: 'Music',
      ServiceType.discover: 'Requests',
    };
    for (final entry in expected.entries) {
      expect(entry.key.displayTitle, entry.value, reason: '${entry.key}');
    }
  });

  test('ServiceType.supportsArrActivity is true only for *arr services', () {
    expect(ServiceType.movies.supportsArrActivity, isTrue);
    expect(ServiceType.series.supportsArrActivity, isTrue);
    expect(ServiceType.music.supportsArrActivity, isTrue);
    expect(ServiceType.discover.supportsArrActivity, isFalse);
  });

  group('resolveArrService', () {
    test('returns the Radarr/Sonarr/Lidarr service for its matching type', () {
      final radarr = FakeRadarrService();
      final sonarr = FakeSonarrService();
      final lidarr = FakeLidarrService();
      final container = createContainer(
        radarrService: radarr,
        sonarrService: sonarr,
        lidarrService: lidarr,
      );

      expect(
        identical(
          container.read(resolvedArrServiceProvider(ServiceType.movies)),
          radarr,
        ),
        isTrue,
      );
      expect(
        identical(
          container.read(resolvedArrServiceProvider(ServiceType.series)),
          sonarr,
        ),
        isTrue,
      );
      expect(
        identical(
          container.read(resolvedArrServiceProvider(ServiceType.music)),
          lidarr,
        ),
        isTrue,
      );
    });

    test('throws for discover', () {
      final container = createContainer();

      expect(
        () => container.read(resolvedArrServiceProvider(ServiceType.discover)),
        throwsA(
          predicate<Object>(
            (error) => error.toString().contains(
              'only supports movies, series, and music',
            ),
            'provider error for unsupported discover service type',
          ),
        ),
      );
    });
  });

  group('global activity providers', () {
    // APP-05: the merge that folds a connection's two Wanted halves together
    // dropped their totals, so every connection on Wanted › All came out
    // "unanswered" and its tile could only count loaded rows.

    // A list from anywhere but `getRequests` carries no count from Seerr, and
    // its length is the rows, not the history.

    // The whole point of moving onto the page primitives. `history` serves a
    // window; the envelope says how big the set is. Read off the window, the
    // figure answered "how many did we fetch": 50, forever, for a server with
    // 340 records, and it looked exactly like an answer to the question the
    // user asked.

    // Null is not zero. A server that did not send `totalRecords` (an older
    // build, a proxy that rewrote the body) has told us nothing about the size
    // of the set, and falling back to the row count here would reinstate the
    // defect one layer up while looking like a sensible default.
  });
}
