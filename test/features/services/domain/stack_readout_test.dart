/// The header's counting rule and its clock.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/services/domain/stack_readout.dart';

void main() {
  group('foldServiceState', () {
    test('every connection answering is answering', () {
      expect(
        foldServiceState(total: 2, offline: 0, checking: 0),
        StackServiceState.answering,
      );
    });

    test('connections that disagree are degraded, not unreachable', () {
      expect(
        foldServiceState(total: 2, offline: 1, checking: 0),
        StackServiceState.degraded,
      );
    });

    test('every connection dark is unreachable', () {
      expect(
        foldServiceState(total: 2, offline: 2, checking: 0),
        StackServiceState.unreachable,
      );
    });

    test('a probe still out is checking, and is not a fault', () {
      expect(
        foldServiceState(total: 1, offline: 0, checking: 1),
        StackServiceState.checking,
      );
      // Half answered: the service answers, so it is not "checking" as a whole —
      // but nothing has failed either.
      expect(
        foldServiceState(total: 2, offline: 0, checking: 1),
        StackServiceState.answering,
      );
    });
  });

  group('stackReadoutFrom', () {
    test('the sum closes: degraded is counted inside answering', () {
      final readout = stackReadoutFrom(
        states: const [
          StackServiceState.answering,
          StackServiceState.degraded,
          StackServiceState.unreachable,
        ],
        registrySize: 5,
      );

      expect(readout.configured, 3);
      expect(readout.answering + readout.unreachable, readout.configured);
      expect(readout.degraded, 1);
      expect(readout.notSetUp, 2);
      expect(readout.headline, '2 of 3 answering');
    });

    test('the qualifiers are in reading order and omitted at zero', () {
      final readout = stackReadoutFrom(
        states: const [
          StackServiceState.answering,
          StackServiceState.degraded,
          StackServiceState.unreachable,
          StackServiceState.checking,
        ],
        registrySize: 5,
      );

      expect(readout.qualifiers, [
        '1 degraded',
        '1 unreachable',
        '1 checking',
        '1 not set up',
      ]);
    });

    test('a clear stack says only the headline — no permanent green', () {
      final readout = stackReadoutFrom(
        states: const [StackServiceState.answering],
        registrySize: 1,
      );

      expect(readout.allClear, isTrue);
      expect(readout.sentence, '1 of 1 answering');
    });

    test('a degraded service is not all clear', () {
      final readout = stackReadoutFrom(
        states: const [StackServiceState.degraded],
        registrySize: 1,
      );

      expect(readout.allClear, isFalse);
    });
  });

  group('the age', () {
    final at = DateTime.utc(2024, 6, 1, 12);

    test('is bucketed, and never counts seconds', () {
      final readout = stackReadoutFrom(
        states: const [StackServiceState.answering],
        registrySize: 1,
        checkedAt: at,
      );

      expect(
        readout.ageLabel(at.add(const Duration(seconds: 45))),
        'refreshed just now',
      );
      expect(
        readout.ageLabel(at.add(const Duration(minutes: 1))),
        'refreshed 1 minute ago',
      );
      expect(
        readout.ageLabel(at.add(const Duration(minutes: 6))),
        'refreshed 6 minutes ago',
      );
      expect(
        readout.ageLabel(at.add(const Duration(hours: 2))),
        'refreshed 2 hours ago',
      );
    });

    test('a reading that has not happened has no age', () {
      final readout = stackReadoutFrom(
        states: const [StackServiceState.checking],
        registrySize: 1,
      );

      expect(readout.ageLabel(at), isNull);
      expect(readout.sentenceAt(at), isNot(contains('refreshed')));
    });
  });
}
