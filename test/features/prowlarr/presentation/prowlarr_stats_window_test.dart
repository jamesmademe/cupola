import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/prowlarr/data/prowlarr_service.dart';
import 'package:cupola/features/prowlarr/presentation/prowlarr_provider.dart';

import '../../../test_helpers/fake_api_client.dart';

void main() {
  group('prowlarrIndexerStatsProvider', () {
    test('asks Prowlarr for a bounded window, not for all time', () async {
      // The rule: the readout says "the last day" and the figure has to mean
      // it. This provider used to call getIndexerStats() bare, so Queries,
      // Grabs and Fails were lifetime totals that only ever climbed. A Fails
      // count that can never return to zero is not a fault signal, it is a
      // permanent amber KPI.
      final client = FakeApiClient()..getResponseData = <String, dynamic>{};
      final container = ProviderContainer(
        overrides: [
          prowlarrServiceProvider.overrideWithValue(ProwlarrService(client)),
        ],
      );
      addTearDown(container.dispose);

      await container.read(prowlarrIndexerStatsProvider.future);

      final params = client.lastGetQueryParameters!;
      final start = DateTime.parse(params['startDate'] as String);
      final end = DateTime.parse(params['endDate'] as String);

      // The width is the contract; the exact instants are a clock read.
      expect(end.difference(start), prowlarrStatsWindow);
      expect(prowlarrStatsWindow, const Duration(hours: 24));
    });

    test('both bounds come from one clock read', () async {
      // Two KPIs resolved a few milliseconds apart must describe the same day.
      // Reading `DateTime.now()` twice, once per bound, is how Grabs comes
      // to exceed Queries on a busy indexer.
      final client = FakeApiClient()..getResponseData = <String, dynamic>{};
      final container = ProviderContainer(
        overrides: [
          prowlarrServiceProvider.overrideWithValue(ProwlarrService(client)),
        ],
      );
      addTearDown(container.dispose);

      await container.read(prowlarrIndexerStatsProvider.future);

      final params = client.lastGetQueryParameters!;
      final end = DateTime.parse(params['endDate'] as String);
      final start = DateTime.parse(params['startDate'] as String);
      expect(end.subtract(prowlarrStatsWindow), start);
    });
  });
}
