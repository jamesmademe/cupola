/// Where a queue record that is waiting to import is read, and where the
/// Manual import control is offered (catalogue M-12).
///
/// The live path is `arrQueueFault` -> `queueNeedsManualImport` ->
/// `DecisionKind.importBlocked`, and `decisionActionLabel` names its control.
/// A pending record without a warning is not a decision, so it offers no
/// control, whatever path its download carries.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/status/arr_queue_snapshot.dart';
import 'package:cupola/features/activity/domain/global_activity_status.dart';
import 'package:cupola/features/services/domain/dashboard_decision.dart';
import 'package:cupola/features/services/domain/in_flight.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

void main() {
  const pending = <String, dynamic>{
    'status': 'completed',
    'trackedDownloadState': 'importPending',
    'trackedDownloadStatus': 'ok',
  };

  test('a pending import reads "Waiting to import"', () {
    final entry = ArrQueueEntry.fromQueueItem(pending);

    expect(entry?.pipeline, MediaPipeline.importPending);
    expect(entry?.pipeline.label, 'Waiting to import');
  });

  test('a pending import is not a fault, so it offers no Manual import', () {
    final entry = ArrQueueEntry.fromQueueItem(pending);

    expect(
      queueNeedsManualImport(
        pipeline: entry?.pipeline,
        hasWarning: entry?.hasWarning ?? false,
      ),
      isFalse,
    );
    expect(arrQueueFault(pending), isNull);
  });

  test(
    'an output path on a pending record does not make it a manual import',
    () {
      // The catalogue said a row with `outputPath` offers Manual import. The
      // live path never reads `outputPath`: only the blocked-import decision
      // carries the control, and that decision is not made here.
      final withPath = {...pending, 'outputPath': '/downloads/Sintel.2010'};

      expect(arrQueueFault(withPath), isNull);
    },
  );

  test('a blocked import is the one state that offers Manual import', () {
    final blocked = {
      'status': 'completed',
      'trackedDownloadState': 'importBlocked',
      'trackedDownloadStatus': 'warning',
    };

    expect(arrQueueFault(blocked), InFlightFault.needsImport);
    expect(
      decisionActionLabel(
        DecisionKind.importBlocked,
        target: ServiceKey.radarr,
      ),
      'Manual import',
    );
  });

  test(
    'a blocked import on a service without the wizard opens that service',
    () {
      expect(
        decisionActionLabel(
          DecisionKind.importBlocked,
          target: ServiceKey.qbittorrent,
        ),
        'Open in qBittorrent',
      );
    },
  );
}
