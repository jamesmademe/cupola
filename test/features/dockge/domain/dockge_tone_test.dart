import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/status/media_status.dart';
import 'package:cupola/features/dockge/domain/models/dockge_agent.dart';
import 'package:cupola/features/dockge/domain/models/dockge_stack.dart';

void main() {
  group('DockgeStackStatus: decision 15', () {
    test('a stack that was never started is neutral, not amber', () {
      // "Inactive" is a compose file with no containers up. Nothing stopped,
      // nothing failed. Amber said a fault was waiting to be dealt with.
      expect(DockgeStackStatus.createdFile.tone, StatusTone.neutral);
      expect(DockgeStackStatus.createdStack.tone, StatusTone.neutral);
    });

    test('a stopped stack is neutral and reads Stopped, never amber', () {
      // Dockge says only "exited": no exit code, no date. A stack brought down
      // on purpose reads the same as one that crashed, so it is backlog, not a
      // fault. The word is Dockge's "exited", softened to what it means here.
      expect(DockgeStackStatus.exited.tone, StatusTone.neutral);
      expect(DockgeStackStatus.exited.label, 'Stopped');
    });

    test('running is the only green', () {
      final green = DockgeStackStatus.values
          .where((s) => s.tone == StatusTone.success)
          .toList();
      expect(green, [DockgeStackStatus.running]);
    });

    test('no state resolves to red', () {
      expect(
        DockgeStackStatus.values.map((s) => s.tone),
        isNot(contains(StatusTone.error)),
      );
    });

    test('an unknown code is unknown, not a guess at running', () {
      expect(DockgeStackStatus.fromCode(99), DockgeStackStatus.unknown);
      expect(DockgeStackStatus.fromCode(null), DockgeStackStatus.unknown);
      expect(DockgeStackStatus.unknown.tone, StatusTone.neutral);
    });

    test('isActive is the single definition of "this stack is up"', () {
      for (final status in DockgeStackStatus.values) {
        expect(status.isActive, status == DockgeStackStatus.running);
      }
    });
  });

  group('DockgeAgent: decision 41', () {
    test('an agent that is not answering is the one red in the feature', () {
      // The exception that proves the rule: this *is* a connection that did not
      // answer, which is exactly what red means.
      expect(
        const DockgeAgent(
          endpoint: 'nas:5001',
          name: 'nas',
          status: 'offline',
        ).tone,
        StatusTone.error,
      );
    });

    test('connecting is informational: it has not failed yet', () {
      expect(
        const DockgeAgent(
          endpoint: 'nas:5001',
          name: 'nas',
          status: 'connecting',
        ).tone,
        StatusTone.info,
      );
    });

    test('online is green and an unrecognised word is neutral', () {
      expect(DockgeAgent.local.tone, StatusTone.success);
      expect(
        const DockgeAgent(endpoint: 'x', name: 'x', status: 'weird').tone,
        StatusTone.neutral,
      );
    });

    test('the hub is the empty endpoint, and knows it', () {
      expect(DockgeAgent.local.isLocal, isTrue);
      expect(DockgeAgent.local.endpoint, isEmpty);
      expect(
        const DockgeAgent(endpoint: 'nas:5001', name: 'nas').isLocal,
        isFalse,
      );
    });

    test('an agent with no name is named by its endpoint', () {
      final agent = DockgeAgent.fromJson({'endpoint': 'nas:5001'});
      expect(agent.name, 'nas:5001');
    });

    test('the hub with no name at all still reads as local', () {
      expect(DockgeAgent.fromJson(const {}).name, 'local');
      expect(DockgeAgent.fromJson(const {}).isLocal, isTrue);
    });
  });
}
