/// The probe notes since when a connection has not answered.
///
/// Driven through the app's real clients on the profiles' fake network, as
/// the probe's classification is: a refused dial starts a silence, any answer
/// ends it (a refused key included), and the first time is the one that
/// stays across every probe that fails after it.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/status/read_clock.dart';
import 'package:cupola/core/status/silence_clock.dart';
import 'package:cupola/features/services/domain/service_summary.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';

import '../../../test_helpers/profiles/profiles.dart';

/// The settings a test edits mid-run.
final _editedSettings = NotifierProvider<_EditedSettings, SettingsModel>(
  () => _EditedSettings(const SettingsModel()),
);

class _EditedSettings extends Notifier<SettingsModel> {
  _EditedSettings(this._initial);

  final SettingsModel _initial;

  @override
  SettingsModel build() => _initial;

  void set(SettingsModel settings) => state = settings;
}

void main() {
  late DateTime now;
  late ProfileHarness harness;
  late ProviderContainer container;

  Future<void> start(ConfigProfile profile) async {
    now = DateTime(2026, 10, 12, 20, 41);
    harness = await ProfileHarness.start(
      profile,
      overrides: [
        readClockProvider.overrideWithValue(ReadClock(now: () => now)),
      ],
    );
    container = harness.container(retry: (_, _) => null);
  }

  InstanceRef sabnzbd() =>
      (service: ServiceKey.sabnzbd, instanceId: WorldIds.sabnzbd);

  /// Asks the probe again, as a Retry or a pull does.
  Future<ServiceSummary> probe(InstanceRef key) {
    container.invalidate(instanceSummaryProvider(key));
    return container.read(instanceSummaryProvider(key).future);
  }

  DateTime? silentSince(ServiceKey service, String id) =>
      container.read(silenceClockProvider).since(silenceKey(service, id));

  group('a probe that does not answer', () {
    test('starts the silence at the moment it did not', () async {
      await start(
        Profiles.p1.withBehaviour(
          WorldIds.sabnzbd,
          ConnectionBehaviour.didNotAnswer,
        ),
      );

      final summary = await probe(sabnzbd());

      expect(summary.didNotAnswer, isTrue);
      expect(
        silentSince(ServiceKey.sabnzbd, WorldIds.sabnzbd),
        DateTime(2026, 10, 12, 20, 41),
      );
    });

    test(
      'keeps the first time across every probe that fails after it',
      () async {
        await start(
          Profiles.p1.withBehaviour(
            WorldIds.sabnzbd,
            ConnectionBehaviour.didNotAnswer,
          ),
        );
        await probe(sabnzbd());

        now = DateTime(2026, 10, 12, 20, 47);
        expect((await probe(sabnzbd())).didNotAnswer, isTrue);
        now = DateTime(2026, 10, 12, 20, 59);
        expect((await probe(sabnzbd())).didNotAnswer, isTrue);

        expect(
          silentSince(ServiceKey.sabnzbd, WorldIds.sabnzbd),
          DateTime(2026, 10, 12, 20, 41),
        );
      },
    );

    test('is a silence however it did not answer', () async {
      await start(
        Profiles.p1.withBehaviour(
          WorldIds.sabnzbd,
          ConnectionBehaviour.timesOut,
        ),
      );

      await probe(sabnzbd());

      expect(
        silentSince(ServiceKey.sabnzbd, WorldIds.sabnzbd),
        DateTime(2026, 10, 12, 20, 41),
      );
    });
  });

  group('a connection that answers again', () {
    test('has no silence any more', () async {
      await start(
        Profiles.p1.withBehaviour(
          WorldIds.sabnzbd,
          ConnectionBehaviour.didNotAnswer,
        ),
      );
      await probe(sabnzbd());
      expect(silentSince(ServiceKey.sabnzbd, WorldIds.sabnzbd), isNotNull);

      harness.network.behave(WorldIds.sabnzbd, ConnectionBehaviour.answers);
      now = DateTime(2026, 10, 12, 20, 50);
      final summary = await probe(sabnzbd());

      expect(summary.isOnline, isTrue);
      expect(silentSince(ServiceKey.sabnzbd, WorldIds.sabnzbd), isNull);
    });

    test('starts a new silence from its own first time', () async {
      await start(
        Profiles.p1.withBehaviour(
          WorldIds.sabnzbd,
          ConnectionBehaviour.didNotAnswer,
        ),
      );
      await probe(sabnzbd());
      harness.network.behave(WorldIds.sabnzbd, ConnectionBehaviour.answers);
      await probe(sabnzbd());

      harness.network.behave(
        WorldIds.sabnzbd,
        ConnectionBehaviour.didNotAnswer,
      );
      now = DateTime(2026, 10, 12, 22, 5);
      await probe(sabnzbd());

      expect(
        silentSince(ServiceKey.sabnzbd, WorldIds.sabnzbd),
        DateTime(2026, 10, 12, 22, 5),
      );
    });

    // An answer that says something is wrong is still an answer: the box is
    // up, and amber must not carry a clock that says it has been dark.
    test('that refuses the key is an answer, and ends the silence', () async {
      await start(
        Profiles.p1.withBehaviour(
          WorldIds.sabnzbd,
          ConnectionBehaviour.didNotAnswer,
        ),
      );
      await probe(sabnzbd());
      expect(silentSince(ServiceKey.sabnzbd, WorldIds.sabnzbd), isNotNull);

      harness.network.behave(WorldIds.sabnzbd, ConnectionBehaviour.refusesKey);
      final summary = await probe(sabnzbd());

      expect(summary.isFault, isTrue);
      expect(silentSince(ServiceKey.sabnzbd, WorldIds.sabnzbd), isNull);
    });
  });

  group('a probe that is refused', () {
    test('starts no silence', () async {
      await start(
        Profiles.p1.withBehaviour(
          WorldIds.sabnzbd,
          ConnectionBehaviour.refusesKey,
        ),
      );

      final summary = await probe(sabnzbd());

      expect(summary.isFault, isTrue);
      expect(silentSince(ServiceKey.sabnzbd, WorldIds.sabnzbd), isNull);
    });
  });

  group('two connections of one service', () {
    test('are two silences', () async {
      await start(
        Profiles.p1.withBehaviour(
          WorldIds.radarr4k,
          ConnectionBehaviour.didNotAnswer,
        ),
      );

      await probe((service: ServiceKey.radarr, instanceId: WorldIds.radarr));
      await probe((service: ServiceKey.radarr, instanceId: WorldIds.radarr4k));

      expect(silentSince(ServiceKey.radarr, WorldIds.radarr4k), isNotNull);
      expect(silentSince(ServiceKey.radarr, WorldIds.radarr), isNull);
    });

    test('keep their own time, and each answer ends only its own', () async {
      await start(
        Profiles.p1
            .withBehaviour(WorldIds.radarr, ConnectionBehaviour.didNotAnswer)
            .withBehaviour(WorldIds.radarr4k, ConnectionBehaviour.didNotAnswer),
      );
      final radarr = (service: ServiceKey.radarr, instanceId: WorldIds.radarr);
      final radarr4k = (
        service: ServiceKey.radarr,
        instanceId: WorldIds.radarr4k,
      );
      await probe(radarr);
      now = DateTime(2026, 10, 12, 20, 55);
      await probe(radarr4k);

      expect(
        silentSince(ServiceKey.radarr, WorldIds.radarr),
        DateTime(2026, 10, 12, 20, 41),
      );
      expect(
        silentSince(ServiceKey.radarr, WorldIds.radarr4k),
        DateTime(2026, 10, 12, 20, 55),
      );

      harness.network.behave(WorldIds.radarr, ConnectionBehaviour.answers);
      await probe(radarr);

      expect(silentSince(ServiceKey.radarr, WorldIds.radarr), isNull);
      expect(
        silentSince(ServiceKey.radarr, WorldIds.radarr4k),
        DateTime(2026, 10, 12, 20, 55),
      );
    });
  });

  group('a connection that is not set up', () {
    test('carries no silence from before it was emptied', () async {
      now = DateTime(2026, 10, 12, 20, 41);
      final profile = Profiles.p1.withBehaviour(
        WorldIds.sabnzbd,
        ConnectionBehaviour.didNotAnswer,
      );
      harness = await ProfileHarness.start(
        profile,
        overrides: [
          readClockProvider.overrideWithValue(ReadClock(now: () => now)),
          currentSettingsProvider.overrideWith(
            (ref) => ref.watch(_editedSettings),
          ),
          _editedSettings.overrideWith(() => _EditedSettings(profile.settings)),
        ],
      );
      container = harness.container(retry: (_, _) => null);
      await probe(sabnzbd());
      expect(silentSince(ServiceKey.sabnzbd, WorldIds.sabnzbd), isNotNull);

      // The same connection, with its address and key taken out.
      final emptied = profile.settings
          .instanceById(WorldIds.sabnzbd)!
          .copyWith(url: '', credential: '');
      container
          .read(_editedSettings.notifier)
          .set(
            SettingsModel(
              instances: [
                for (final instance in profile.settings.instances)
                  if (instance.id == WorldIds.sabnzbd) emptied else instance,
              ],
            ),
          );
      final summary = await container.read(
        instanceSummaryProvider(sabnzbd()).future,
      );

      // Not asked, so neither silent nor dark: not set up.
      expect(summary.isNotSetUp, isTrue);
      expect(summary.didNotAnswer, isFalse);
      expect(silentSince(ServiceKey.sabnzbd, WorldIds.sabnzbd), isNull);
    });
  });

  test(
    'a silence is never written to disk: a new run starts with none',
    () async {
      await start(
        Profiles.p1.withBehaviour(
          WorldIds.sabnzbd,
          ConnectionBehaviour.didNotAnswer,
        ),
      );
      await probe(sabnzbd());
      expect(silentSince(ServiceKey.sabnzbd, WorldIds.sabnzbd), isNotNull);

      // Another app run: a container of its own over the same settings.
      final nextRun = harness.container(retry: (_, _) => null);

      expect(
        nextRun
            .read(silenceClockProvider)
            .since(silenceKey(ServiceKey.sabnzbd, WorldIds.sabnzbd)),
        isNull,
      );
    },
  );
}
