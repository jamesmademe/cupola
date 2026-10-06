/// Which connection a search lane asked, on the profiles' fake network.
///
/// Radarr and Sonarr run a lane per connection. Seerr, Jellyfin and Plex run
/// one, on the lens. That lane used to carry no name at all, so with two
/// Jellyfin its answer read as the household's; the name reaches the row
/// (`On Jellyfin · Cabin`) and a silent source's line.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/search/domain/global_search_result.dart';
import 'package:cupola/features/search/presentation/global_search_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import '../../../test_helpers/profiles/profiles.dart';

List<SearchLeg> _legs(ProfileHarness harness) {
  final container = harness.container();
  final sub = container.listen(globalSearchLegsProvider, (_, _) {});
  addTearDown(sub.close);
  return sub.read();
}

Iterable<String> _names(List<SearchLeg> legs, ServiceKey service) =>
    legs.where((leg) => leg.instance.service == service).map((leg) => leg.name);

void main() {
  final twoJellyfin = Profiles.p1.withConnection(
    WorldConnections.jellyfinCabin,
  );

  test('P1 + the cabin Jellyfin: the lens-only lane names the Jellyfin it '
      'asked', () async {
    final harness = await ProfileHarness.start(twoJellyfin);
    final legs = _legs(harness);

    // One lane, on the lens: the home Jellyfin, which nobody named.
    expect(_names(legs, ServiceKey.jellyfin), ['Jellyfin 1']);
    // A lone Seerr grows no name.
    expect(_names(legs, ServiceKey.seerr), ['']);
    // Bazarr's titles are Radarr's and Sonarr's, and music is not in the
    // catalogue: neither is asked.
    expect(_names(legs, ServiceKey.bazarr), isEmpty);
    expect(_names(legs, ServiceKey.lidarr), isEmpty);
    // The arrs keep a lane per connection, named by the same rule.
    expect(_names(legs, ServiceKey.radarr), ['Radarr 1', '4K']);
  });

  test('the lane follows the lens to the connection it asks', () async {
    final harness = await ProfileHarness.start(
      twoJellyfin.withLens(ServiceKey.jellyfin, WorldIds.jellyfinCabin),
    );
    final legs = _legs(harness);

    final jellyfin = legs.where(
      (leg) => leg.instance.service == ServiceKey.jellyfin,
    );
    expect(jellyfin.single.instance.id, WorldIds.jellyfinCabin);
    expect(jellyfin.single.name, 'Cabin');
    expect(
      GlobalSearchServiceResults(leg: jellyfin.single).laneTitle,
      'Jellyfin · Cabin',
    );
  });

  test('P1: one Jellyfin is called nothing', () async {
    final harness = await ProfileHarness.start(Profiles.p1);
    expect(_names(_legs(harness), ServiceKey.jellyfin), ['']);
  });

  test(
    'P1: on a household where everything answers, every lane answers',
    () async {
      final harness = await ProfileHarness.start(Profiles.p1);
      final container = harness.container();
      final sub = container.listen(globalSearchLanesProvider, (_, _) {});
      addTearDown(sub.close);
      container.read(globalSearchQueryProvider.notifier).state = 'sintel';

      for (final leg in container.read(globalSearchLegsProvider)) {
        final lane = await container.read(globalSearchLegProvider(leg).future);
        expect(
          lane.state,
          SearchLaneState.answered,
          reason: '${lane.laneTitle}: ${lane.faultSentence}',
        );
      }
      expect(harness.network.unanswered, isEmpty);
    },
  );
}
