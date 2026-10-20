import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/services/domain/in_flight.dart';
import 'package:cupola/features/services/domain/source_coverage.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/shell/presentation/desktop/in_flight_glance.dart';

/// The sidebar's "In flight": the Home's Downloads folded to two lines.
void main() {
  ServiceQueueItem item(
    String title, {
    double? progress,
    InFlightFault? fault,
    bool queued = false,
  }) => ServiceQueueItem(
    service: ServiceKey.radarr,
    title: title,
    progress: progress,
    clientLabel: 'qBittorrent',
    fault: fault,
    queued: queued,
  );

  ServicesInFlight inFlight({
    List<ServiceQueueItem> moving = const [],
    List<ServiceQueueItem> faults = const [],
    List<ServiceQueueItem> queued = const [],
    int? rate,
  }) => (
    preview: moving,
    activeCount: moving.length,
    movingCount: moving.length,
    queued: queued,
    faults: faults,
    held: 0,
    rateBytesPerSecond: rate,
    clients: rate == null ? 0 : 1,
    coverage: SourceCoverage.none,
  );

  test('nothing moving and nothing stuck: nothing in flight, and the queued '
      'said quietly', () {
    final glance = inFlightGlanceOf(
      inFlight(queued: [item('Sintel', queued: true)]),
    );
    expect(glance.title, 'Nothing in flight');
    expect(glance.note, '1 queued');
    expect(glance.bars, isEmpty);
    expect(glance.spoken, 'Nothing in flight, 1 queued. Open Activity');
  });

  test('the moving ones then the stuck ones, one bar each, with the rate', () {
    final glance = inFlightGlanceOf(
      inFlight(
        moving: [
          item('Cosmos', progress: 0.88),
          item('Sprite Fright', progress: 0.62),
        ],
        faults: [
          item('Big Buck Bunny', progress: 0.47, fault: InFlightFault.stalled),
          // A download that needs importing is a decision, not a transfer.
          item('Pack', progress: 1, fault: InFlightFault.needsImport),
        ],
        rate: 40 * 1024 * 1024,
      ),
    );

    expect(glance.title, '2 moving');
    expect(glance.rate, isNotNull);
    expect(glance.bars, [
      (progress: 0.88, stuck: false),
      (progress: 0.62, stuck: false),
      (progress: 0.47, stuck: true),
    ]);
    expect(glance.stuck, 1);
    expect(glance.more, 0);
    expect(glance.spoken, startsWith('2 moving, at '));
    expect(glance.spoken, endsWith(', 1 stuck. Open Activity'));
  });

  test('past the bars the width holds, the rest is a count', () {
    final glance = inFlightGlanceOf(
      inFlight(
        moving: [for (var i = 0; i < 8; i++) item('t$i', progress: 0.1 * i)],
      ),
    );
    expect(glance.bars, hasLength(InFlightGlance.maxBars));
    expect(glance.more, 8 - InFlightGlance.maxBars);
  });

  test('only stuck: nothing moving, and no rate to say', () {
    final glance = inFlightGlanceOf(
      inFlight(
        faults: [item('Big Buck Bunny', fault: InFlightFault.stalled)],
        rate: 0,
      ),
    );
    expect(glance.title, 'Nothing moving');
    expect(glance.rate, isNull);
    expect(glance.stuck, 1);
  });
}
