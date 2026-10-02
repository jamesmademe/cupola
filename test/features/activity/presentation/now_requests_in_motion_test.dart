/// Activity's Now lists the Seerr requests still in motion, and asks Seerr for
/// them by its own filters.
///
/// It used to page every request the server ever held, with no filter, hydrate
/// each one, and then list requests delivered long ago under Downloading.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/activity/presentation/activity_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import '../../../test_helpers/profiles/profiles.dart';

void main() {
  test('P1: Now asks Seerr for the requests in motion, never for the whole '
      'history', () async {
    final harness = await ProfileHarness.start(Profiles.p1);
    final container = harness.container(retry: (_, _) => null);

    final feed = await container.read(globalNowItemsProvider.future);

    final reads = harness.network
        .requestsTo(WorldIds.seerr)
        .where((r) => r.path == '/api/v1/request')
        .toList();
    expect(reads.map((r) => r.query['filter']).toSet(), {
      'pending',
      'processing',
      'failed',
    });

    final titles = {
      for (final result in feed.results)
        if (result.service == ServiceKey.seerr)
          for (final item in result.items) item.title,
    };
    // Two waiting for approval, two approved and on their way. Coffee Run,
    // Sintel and the 4K Tears of Steel are on the server already.
    expect(titles, {
      WorldTitles.charge.title,
      WorldTitles.metropolis.title,
      WorldTitles.spriteFright.title,
      WorldTitles.cosmosLaundromat.title,
    });
  });
}
