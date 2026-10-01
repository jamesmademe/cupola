/// A pull on a library grid asks the lens's queue again.
///
/// The grids badge every title over the queue snapshot of the connection the
/// lens is on, and the pull invalidated only the lens wrapper, which resolves
/// the lens and re-watches its family member: the member kept the answer it
/// already had, so the badges were redrawn over the queue from before the
/// pull. Lidarr's grid had the same fault and already drops the family.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/movies/presentation/movies_screen.dart';
import 'package:cupola/features/series/presentation/series_screen.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import '../../../test_helpers/profiles/profiles.dart';

int _queueReads(ProfileHarness harness, String id, String path) =>
    harness.network.requestsTo(id).where((r) => r.uri.path == path).length;

Future<void> _pull(WidgetTester tester, ProfileHarness harness) async {
  await tester
      .widget<RefreshIndicator>(find.byType(RefreshIndicator).first)
      .onRefresh();
  await harness.settle(tester);
}

void main() {
  testWidgets('P1, lens on the 4K: a pull on Movies re-reads the 4K queue, '
      'and only it', (tester) async {
    final harness = await pumpWithProfile(
      tester,
      Profiles.p1.withLens(ServiceKey.radarr, WorldIds.radarr4k),
      child: const MoviesScreen(),
    );
    const queue = '/api/v3/queue';
    final before4k = _queueReads(harness, WorldIds.radarr4k, queue);
    final beforeHd = _queueReads(harness, WorldIds.radarr, queue);
    expect(before4k, greaterThan(0));

    await _pull(tester, harness);

    expect(
      _queueReads(harness, WorldIds.radarr4k, queue),
      greaterThan(before4k),
    );
    expect(_queueReads(harness, WorldIds.radarr, queue), beforeHd);

    await harness.unmount(tester);
  });

  testWidgets('P6, lens on the anime Sonarr: a pull on Series re-reads the '
      'anime queue, and only it', (tester) async {
    final harness = await pumpWithProfile(
      tester,
      Profiles.p6.withLens(ServiceKey.sonarr, WorldIds.sonarrAnime),
      child: const SeriesScreen(),
    );
    const queue = '/api/v3/queue';
    final beforeAnime = _queueReads(harness, WorldIds.sonarrAnime, queue);
    final beforeMain = _queueReads(harness, WorldIds.sonarr, queue);
    expect(beforeAnime, greaterThan(0));

    await _pull(tester, harness);

    expect(
      _queueReads(harness, WorldIds.sonarrAnime, queue),
      greaterThan(beforeAnime),
    );
    expect(_queueReads(harness, WorldIds.sonarr, queue), beforeMain);

    await harness.unmount(tester);
  });
}
