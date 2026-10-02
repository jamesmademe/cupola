/// Each arr's library is downloaded once a session, whichever surface asks
/// first.
///
/// The library is the heaviest answer the app asks for (`/movie`, `/series`,
/// `/artist`, `/author`), and Home's cards, the KPI rail, the wall and the
/// Overview each made their own copy of the same request: up to three a
/// session for the lens, at every cold open. And Home's fold read every other
/// connection's library straight off the service, in an `autoDispose`
/// provider, so it downloaded it again each time Home was rebuilt.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/movies/presentation/movies_provider.dart';
import 'package:cupola/features/movies/presentation/radarr_overview_provider.dart';
import 'package:cupola/features/services/presentation/service_kpi_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import '../../../test_helpers/profiles/profiles.dart';

int _libraryReads(ProfileHarness harness, String id) => harness.network
    .requestsTo(id)
    .where((r) => r.method == 'GET' && r.path == '/api/v3/movie')
    .length;

void main() {
  test('P1: Home, then the Movies wall, then the Overview read the lens '
      'Radarr\'s library once', () async {
    final harness = await ProfileHarness.start(Profiles.p1);
    final container = harness.container(retry: (_, _) => null);
    final card = container.listen(
      serviceKpiProvider(ServiceKey.radarr),
      (_, _) {},
    );
    addTearDown(card.close);

    await container.read(serviceKpiProvider(ServiceKey.radarr).future);
    await container.read(moviesProvider.future);
    await container.read(radarrOverviewMoviesProvider.future);
    await container.read(radarrRecentlyAddedProvider.future);

    // It used to be three: the rail's copy, the wall's and the Overview's.
    expect(_libraryReads(harness, WorldIds.radarr), 1);
  });

  test('P1: Home\'s fold reads the 4K Radarr\'s library once, however often '
      'Home is rebuilt', () async {
    final harness = await ProfileHarness.start(Profiles.p1);
    final container = harness.container(retry: (_, _) => null);

    for (var visit = 0; visit < 3; visit++) {
      final fold = container.listen(
        foldedServiceKpisProvider(ServiceKey.radarr),
        (_, _) {},
      );
      await container.read(foldedServiceKpisProvider(ServiceKey.radarr).future);
      // Leaving Home disposes the fold and every per-connection read under it.
      fold.close();
      await Future<void>.delayed(Duration.zero);
    }

    // It used to be one a visit.
    expect(_libraryReads(harness, WorldIds.radarr4k), 1);
  });
}
