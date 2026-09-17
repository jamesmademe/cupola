/// The stack headline's counting rule and its clock.
///
/// These assertions moved here from `stack_readout_test.dart` when the two
/// models became one: the rules did not change, the file that owns them did.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/shell/domain/stack_health.dart';

import '../../../test_helpers/settings_scope.dart';

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

    test('one connection can never be degraded', () {
      // Degraded means *disagreement*, and one opinion cannot disagree with
      // itself. A single connection only ever answers or does not.
      expect(
        foldServiceState(total: 1, offline: 0, checking: 0),
        StackServiceState.answering,
      );
      expect(
        foldServiceState(total: 1, offline: 1, checking: 0),
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

  group('stackHealthFrom', () {
    test('the sum closes: degraded is counted inside answering', () {
      final health = stackHealthFrom(
        states: const [
          StackServiceState.answering,
          StackServiceState.degraded,
          StackServiceState.unreachable,
        ],
        registrySize: 5,
      );

      expect(health.configured, 3);
      expect(health.answering + health.unreachable, health.configured);
      expect(health.degraded, 1);
      expect(health.notSetUp, 2);
      expect(health.headline, '2 of 3 answering');
    });

    test('the qualifiers are in reading order and omitted at zero', () {
      final health = stackHealthFrom(
        states: const [
          StackServiceState.answering,
          StackServiceState.degraded,
          StackServiceState.unreachable,
          StackServiceState.checking,
        ],
        registrySize: 5,
      );

      expect(health.qualifiers, [
        '1 degraded',
        '1 unreachable',
        '1 checking',
        '1 not set up',
      ]);
    });

    test('a clear stack says only the headline — no permanent green', () {
      final health = stackHealthFrom(
        states: const [StackServiceState.answering],
        registrySize: 1,
      );

      expect(health.allClear, isTrue);
      expect(health.sentence, '1 of 1 answering');
    });

    test('a degraded service is not all clear', () {
      final health = stackHealthFrom(
        states: const [StackServiceState.degraded],
        registrySize: 1,
      );

      expect(health.allClear, isFalse);
    });

    test('a probe in flight is never a fault', () {
      // The one assertion that keeps the cold open honest: while answers are
      // still coming in the stack is *not* wrong, so nothing on this sentence
      // may read as a fault — `allClear` stays true and the only thing said is
      // that somebody is being asked.
      final health = stackHealthFrom(
        states: const [StackServiceState.answering, StackServiceState.checking],
        registrySize: 2,
      );

      expect(health.allClear, isTrue);
      expect(health.degraded, 0);
      expect(health.unreachable, 0);
      expect(health.qualifiers, ['1 checking']);
    });
  });

  /// The count and the names are one fold, and the band is the reason.
  ///
  /// The Dashboard header counts [StackHealth.unreachable]; the alert band, the
  /// inspector card and the drained sections name
  /// [unreachableServicesProvider]. Those used to be two derivations — the count
  /// folded every connection, the names asked the *lens* — so one surface could
  /// call a service answering while the line below it said it did not answer.
  group('the names behind the count', () {
    ProviderContainer containerWith(
      Map<ServiceKey, FoldedServiceHealth> folds,
    ) {
      final container = ProviderContainer(
        overrides: [
          currentSettingsProvider.overrideWith(
            (ref) => settingsWithServices(folds.keys.toList()),
          ),
          foldedServiceHealthProvider.overrideWith(
            (ref, service) =>
                folds[service] ?? (total: 0, offline: 0, checking: 0),
          ),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('an unreachable service is both counted and named', () {
      final container = containerWith({
        ServiceKey.radarr: (total: 1, offline: 0, checking: 0),
        ServiceKey.lidarr: (total: 2, offline: 2, checking: 0),
      });

      final health = container.read(stackHealthProvider);
      final named = container.read(unreachableServicesProvider);

      expect(health.unreachable, 1);
      expect(named, [ServiceKey.lidarr]);
      expect(named.length, health.unreachable);
    });

    test('a degraded service is counted as answering and never named', () {
      // Two Radarr, one dark. The header says `degraded`; the band has nothing
      // to say, because "Radarr did not answer" is false about a Radarr that
      // did.
      final container = containerWith({
        ServiceKey.radarr: (total: 2, offline: 1, checking: 0),
      });

      final health = container.read(stackHealthProvider);

      expect(health.degraded, 1);
      expect(health.answering, 1);
      expect(health.unreachable, 0);
      expect(container.read(unreachableServicesProvider), isEmpty);
    });

    test('a probe still out names nobody', () {
      final container = containerWith({
        ServiceKey.radarr: (total: 1, offline: 0, checking: 1),
      });

      expect(container.read(stackHealthProvider).checking, 1);
      expect(container.read(unreachableServicesProvider), isEmpty);
    });
  });

  group('the age', () {
    final at = DateTime.utc(2024, 6, 1, 12);

    test('is bucketed, and never counts seconds', () {
      final health = stackHealthFrom(
        states: const [StackServiceState.answering],
        registrySize: 1,
        checkedAt: at,
      );

      expect(
        health.ageLabel(at.add(const Duration(seconds: 45))),
        'refreshed just now',
      );
      expect(
        health.ageLabel(at.add(const Duration(minutes: 1))),
        'refreshed 1 minute ago',
      );
      expect(
        health.ageLabel(at.add(const Duration(minutes: 6))),
        'refreshed 6 minutes ago',
      );
      expect(
        health.ageLabel(at.add(const Duration(hours: 2))),
        'refreshed 2 hours ago',
      );
    });

    test('a reading that has not happened has no age', () {
      final health = stackHealthFrom(
        states: const [StackServiceState.checking],
        registrySize: 1,
      );

      expect(health.ageLabel(at), isNull);
      expect(health.sentenceAt(at), isNot(contains('refreshed')));
    });
  });
}
