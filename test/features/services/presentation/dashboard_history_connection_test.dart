/// A history record carries the connection it came off.
///
/// A failed import on Home becomes a manual import, and the wizard files into
/// one server's library under that server's id for the film. Each Radarr
/// numbers its films from one, so "film 1" on the 4K is a different film on
/// the HD: a Fix that resolved its connection through the lens at tap time
/// would import into whichever library the lens had moved to since.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/services/domain/arr_import.dart';
import 'package:cupola/features/services/domain/dashboard_decision.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import '../../../test_helpers/profiles/profiles.dart';
import '../../../test_helpers/profiles/service_fakes.dart';

/// One failed import of Elephants Dream, film 1 on the 4K Radarr.
Map<String, Object?> _failedImport(DateTime now) => {
  'id': 41,
  'movieId': 1,
  'eventType': 'importFailed',
  'sourceTitle': 'Elephants.Dream.2006.2160p.UHD.BluRay',
  'date': now.subtract(const Duration(minutes: 20)).toUtc().toIso8601String(),
  'movie': {'id': 1, 'title': 'Elephants Dream', 'year': 2006},
  'data': {'message': 'Not a valid video file'},
};

void main() {
  test('P1, lens on the 4K: a failed import keeps the 4K connection', () async {
    final harness = await ProfileHarness.start(
      Profiles.p1.withLens(ServiceKey.radarr, WorldIds.radarr4k),
    );
    harness.network.on(
      WorldIds.radarr4k,
      'GET',
      '/api/v3/history',
      (r) => NetworkReply.json(
        pagedEnvelope(r, [_failedImport(harness.network.now)]),
      ),
    );
    final container = harness.container(retry: (_, _) => null);

    final history = await container.read(servicesArrHistoryProvider.future);
    final entry = history.entries.singleWhere(
      (entry) => entry.outcome == ArrImportOutcome.failed,
    );
    expect(entry.instanceId, WorldIds.radarr4k);

    final decisions = await container.read(
      dashboardDecisionSourceProvider(DecisionSource.history).future,
    );
    final fix = decisions.decisions.singleWhere(
      (decision) => decision.kind == DecisionKind.failedImport,
    );
    expect(fix.actionId, 1);
    expect(fix.instanceId, WorldIds.radarr4k);
  });
}
