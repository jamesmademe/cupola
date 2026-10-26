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

import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/features/discover/data/seerr_accounts.dart';
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
  test('a service row and the form of each of its connections ask a server '
      'once between them', () async {
    // What the forms alone cost: one test per connection.
    final alone = await ProfileHarness.start(Profiles.p1);
    final aloneContainer = alone.container();
    for (final instance
        in aloneContainer.read(currentSettingsProvider).configuredInstances) {
      aloneContainer.listen(instanceDiagnosisProvider(instance.id), (_, _) {});
      await aloneContainer.read(instanceDiagnosisProvider(instance.id).future);
    }
    final formsOnly = _traffic(alone);
    expect(formsOnly, greaterThan(0));

    // The service rows beside them cost nothing more.
    final both = await ProfileHarness.start(Profiles.p1);
    await _readAll(both.container());

    expect(_traffic(both), formsOnly);
  });

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

  test('a Seerr account is tested again when its session moves, and only '
      'its service', () async {
    const friend = WorldIds.seerrFriend;
    final harness = await ProfileHarness.start(Profiles.p9);
    final container = harness.container();
    final accounts = container.read(seerrAccountsProvider);
    container.listen(instanceDiagnosisProvider(friend), (_, _) {});
    await _readAll(container);
    final session = harness.network.seerrSessionOf(friend);
    // Every service but Seerr, whose row folds both its connections.
    int otherServices() =>
        _traffic(harness) -
        _trafficTo(harness, WorldIds.seerr) -
        _trafficTo(harness, friend);
    final elsewhere = otherServices();
    Future<ServiceDiagnosis> friendNow() =>
        container.read(instanceDiagnosisProvider(friend).future);
    expect((await friendNow()).isConnected, isTrue);

    // New permissions are what /auth/me said, not what it is asked with.
    final asked = _trafficTo(harness, friend);
    await accounts.recordWhoAmI(friend, {'permissions': 32 | 128});
    await _readAll(container);
    expect(_trafficTo(harness, friend), asked);

    // The session ends: it reads signed out, asking nothing.
    await accounts.sessionEnded(friend);
    expect((await friendNow()).reason, ServiceFailureReason.sessionEnded);
    expect(
      (await container.read(
        serviceDiagnosisProvider(ServiceKey.seerr).future,
      )).reason,
      ServiceFailureReason.sessionEnded,
    );

    // Signed in again: tested again, and answering.
    final signedOut = container
        .read(currentSettingsProvider)
        .instanceById(friend)!;
    final beforeSignIn = _trafficTo(harness, friend);
    await accounts.signedIn(
      signedOut,
      signedOut.account!.copyWith(session: session),
    );
    expect((await friendNow()).isConnected, isTrue);
    expect(_trafficTo(harness, friend), greaterThan(beforeSignIn));

    // Signed out from the form: signed out again.
    await accounts.signOut(friend);
    expect((await friendNow()).reason, ServiceFailureReason.sessionEnded);

    await _readAll(container);
    expect(otherServices(), elsewhere, reason: 'no other service was asked');
  });
}
