/// The Settings readouts test a connection again only when something it is
/// tested with changes.
///
/// Both watched the whole settings model, so a theme toggle re-tested every
/// connection over the network, and signed in again wherever a service signs
/// in with a password: the class of defect that walked qBittorrent into its
/// ban, open for every other service that counts failed sign-ins.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/settings/data/service_verification.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';

import '../../../test_helpers/profiles/profiles.dart';

/// Everything that reached the network: HTTP, upgrades and TrueNAS calls.
int _traffic(ProfileHarness harness) =>
    harness.network.requests.length + harness.network.rpcCalls.length;

int _trafficTo(ProfileHarness harness, String id) =>
    harness.network.requestsTo(id).length;

/// Reads every readout the Settings screens draw, and keeps them alive.
Future<void> _readAll(ProviderContainer container) async {
  final settings = container.read(currentSettingsProvider);
  final services = {for (final i in settings.configuredInstances) i.service};
  for (final service in services) {
    container.listen(serviceDiagnosisProvider(service), (_, _) {});
    await container.read(serviceDiagnosisProvider(service).future);
  }
  for (final instance in settings.configuredInstances) {
    container.listen(instanceDiagnosisProvider(instance.id), (_, _) {});
    await container.read(instanceDiagnosisProvider(instance.id).future);
  }
}

Future<void> _write(
  ProviderContainer container,
  SettingsModel Function(SettingsModel) change,
) => container
    .read(settingsProvider.notifier)
    .updateSettings(change(container.read(currentSettingsProvider)));

void main() {
  test('a theme toggle tests no connection again', () async {
    final harness = await ProfileHarness.start(Profiles.p1);
    final container = harness.container();
    await _readAll(container);
    final before = _traffic(harness);
    expect(before, greaterThan(0));

    await _write(container, (s) => s.copyWith(themeMode: AppThemeMode.light));
    await _readAll(container);

    expect(_traffic(harness), before);
  });

  test('editing a connection tests its service again, and no other', () async {
    final harness = await ProfileHarness.start(Profiles.p1);
    final container = harness.container();
    await _readAll(container);
    // The service's row folds both Radarr, so both are its to ask again.
    int radarrs() =>
        _trafficTo(harness, WorldIds.radarr) +
        _trafficTo(harness, WorldIds.radarr4k);
    final radarr = radarrs();
    final everything = _traffic(harness);

    await _write(container, (s) {
      final edited = s
          .instanceById(WorldIds.radarr)!
          .copyWith(credential: worldKey(WorldIds.radarr));
      // The same key, re-saved: nothing it is tested with changed.
      return s.copyWithInstance(edited);
    });
    await _readAll(container);
    expect(_traffic(harness), everything);

    await _write(container, (s) {
      final edited = s
          .instanceById(WorldIds.radarr)!
          .copyWith(url: '${s.instanceById(WorldIds.radarr)!.url}/');
      return s.copyWithInstance(edited);
    });
    await _readAll(container);

    final radarrNow = radarrs();
    expect(radarrNow, greaterThan(radarr));
    expect(
      _traffic(harness) - everything,
      radarrNow - radarr,
      reason: 'no other service was asked again',
    );
  });

  test('a service gaining a connection tests the new one', () async {
    final harness = await ProfileHarness.start(Profiles.p1);
    final container = harness.container();
    await _readAll(container);
    final before = container.read(
      serviceDiagnosisProvider(ServiceKey.nzbget).future,
    );
    expect((await before).isConfigured, isFalse);

    await _write(
      container,
      (s) => s.copyWithInstance(WorldConnections.nzbget.instance),
    );

    final after = await container.read(
      serviceDiagnosisProvider(ServiceKey.nzbget).future,
    );
    expect(after.isConfigured, isTrue);
  });
}
