import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/services/domain/source_coverage.dart';
import 'package:cupola/features/activity/presentation/activity_provider.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/shell/presentation/desktop/inspector_pane.dart';

ServicesInFlight _inFlight({int moving = 0}) => (
  preview: const [],
  activeCount: moving,
  movingCount: moving,
  queued: const [],
  faults: const [],
  held: 0,
  rateBytesPerSecond: null,
  clients: 1,
  coverage: SourceCoverage.none,
);

void main() {
  test('the arrs empty and a client moving: it says so, not "Nothing '
      'downloading"', () {
    final note = inspectorEmptyQueueNote(
      const ActivityFeed.empty(),
      _inFlight(moving: 2),
    );

    expect(note, isNot(contains('Nothing downloading')));
    expect(note, startsWith('2 moving'));
    expect(note, endsWith('Open Activity to see them.'));
  });

  test('nothing anywhere: nothing downloading', () {
    expect(
      inspectorEmptyQueueNote(const ActivityFeed.empty(), _inFlight()),
      'Nothing downloading right now.',
    );
  });
}
