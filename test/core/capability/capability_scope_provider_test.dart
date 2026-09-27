import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/capability/capability_scope.dart';
import 'package:cupola/core/capability/connection_capability.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';

import '../../test_helpers/settings_scope.dart';

/// The merged read, the ledger's pruning and the "asked once per credential"
/// promise, against real settings.
void main() {
  // The first instance of a service takes its route param as its id.
  const unraidId = 'unraid';
  const truenasId = 'truenas';

  Future<ProviderContainer> containerWith({
    List<Object> overrides = const [],
    Map<ServiceKey, CapabilityProbe>? probes,
  }) async {
    final container = ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        ...await settingsScopeOverrides(
          configured: const [ServiceKey.unraid, ServiceKey.truenas],
        ),
        if (probes != null) capabilityProbesProvider.overrideWithValue(probes),
        ...overrides.cast(),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  Future<void> updateSettings(
    ProviderContainer container,
    SettingsModel Function(SettingsModel) change,
  ) => container
      .read(settingsProvider.notifier)
      .updateSettings(change(container.read(settingsProvider)));

  group('the merged read', () {
    test('a learned refusal outranks the probe', () async {
      final container = await containerWith(
        probes: {
          ServiceKey.unraid: (ref, id) async =>
              const CapabilityGrant.readWrite(),
        },
      );
      await container.read(connectionCapabilityProvider(unraidId).future);
      expect(
        container.read(capabilityGrantForProvider(unraidId)),
        const CapabilityGrant.readWrite(),
      );

      container.read(capabilityScopeProvider.notifier).markReadOnly(unraidId);
      expect(
        container.read(capabilityGrantForProvider(unraidId)),
        const CapabilityGrant.refused(),
      );
      expect(
        container.read(capabilityScopeForProvider(unraidId)),
        CapabilityScope.readOnly,
      );
    });

    test('a probe still out reads as unknown, and stays live', () async {
      final pending = Completer<CapabilityGrant>();
      final container = await containerWith(
        overrides: [
          connectionCapabilityProvider.overrideWith(
            (ref, id) => pending.future,
          ),
        ],
      );
      expect(
        container.read(capabilityGrantForProvider(unraidId)),
        const CapabilityGrant.unknown(),
      );
      expect(
        container.read(capabilityScopeForProvider(unraidId)).canWrite,
        isTrue,
      );
      pending.complete(const CapabilityGrant.readOnly());
    });

    test(
      'a probe that errors reads as unanswered, never as permission',
      () async {
        final container = await containerWith(
          overrides: [
            connectionCapabilityProvider.overrideWith(
              (ref, id) async => throw StateError('no answer'),
            ),
          ],
        );
        await expectLater(
          container.read(connectionCapabilityProvider(unraidId).future),
          throwsStateError,
        );
        expect(
          container.read(capabilityGrantForProvider(unraidId)),
          const CapabilityGrant.unanswered(),
        );
      },
    );

    test(
      'a probe that throws is folded to unanswered by the provider',
      () async {
        final container = await containerWith(
          probes: {
            ServiceKey.unraid: (ref, id) async => throw Exception('boom'),
          },
        );
        expect(
          await container.read(connectionCapabilityProvider(unraidId).future),
          const CapabilityGrant.unanswered(),
        );
      },
    );

    test('a service with no scoped credential is never asked', () async {
      var asked = 0;
      final container = await containerWith(
        probes: {
          ServiceKey.radarr: (ref, id) async {
            asked++;
            return const CapabilityGrant.readOnly();
          },
        },
      );
      await updateSettings(
        container,
        (s) => s.copyWithService(
          ServiceKey.radarr,
          url: 'https://radarr.test',
          apiKey: 'k',
        ),
      );
      expect(
        await container.read(connectionCapabilityProvider('radarr').future),
        const CapabilityGrant.unknown(),
      );
      expect(asked, 0);
    });

    test('an id that names no connection is unknown', () async {
      final container = await containerWith();
      expect(
        await container.read(connectionCapabilityProvider('nope').future),
        const CapabilityGrant.unknown(),
      );
    });
  });

  group('the ledger', () {
    test('markReadOnly records a refusal, not an answer', () async {
      final container = await containerWith();
      container.read(capabilityScopeProvider.notifier).markReadOnly(unraidId);
      expect(
        container.read(capabilityScopeProvider)[unraidId]!.basis,
        CapabilityBasis.refused,
      );
    });

    test(
      'a credential change forgets that connection and only that one',
      () async {
        final container = await containerWith();
        final ledger = container.read(capabilityScopeProvider.notifier);
        ledger.markReadOnly(unraidId);
        ledger.markReadOnly(truenasId);

        await updateSettings(
          container,
          (s) => s.copyWithService(ServiceKey.unraid, apiKey: 'a-new-key'),
        );

        expect(
          container.read(capabilityScopeProvider).containsKey(unraidId),
          isFalse,
        );
        expect(
          container.read(capabilityScopeProvider)[truenasId],
          const CapabilityGrant.refused(),
        );
      },
    );

    test('an unrelated settings write forgets nothing', () async {
      final container = await containerWith();
      container.read(capabilityScopeProvider.notifier).markReadOnly(unraidId);

      await updateSettings(
        container,
        (s) => s.copyWith(themeMode: AppThemeMode.dark),
      );

      expect(
        container.read(capabilityScopeProvider)[unraidId],
        const CapabilityGrant.refused(),
      );
    });
  });

  group('asked once per credential', () {
    test(
      're-asks after a credential change, not after anything else',
      () async {
        var calls = 0;
        final container = await containerWith(
          probes: {
            ServiceKey.unraid: (ref, id) async {
              calls++;
              return const CapabilityGrant.readOnly();
            },
          },
        );
        final sub = container.listen(
          connectionCapabilityProvider(unraidId),
          (_, _) {},
        );
        addTearDown(sub.close);

        await container.read(connectionCapabilityProvider(unraidId).future);
        expect(calls, 1);

        // Unrelated: the theme, and another service's key.
        await updateSettings(
          container,
          (s) => s.copyWith(themeMode: AppThemeMode.dark),
        );
        await updateSettings(
          container,
          (s) => s.copyWithService(ServiceKey.truenas, apiKey: 'other'),
        );
        await container.read(connectionCapabilityProvider(unraidId).future);
        expect(calls, 1);

        // This connection's own key.
        await updateSettings(
          container,
          (s) => s.copyWithService(ServiceKey.unraid, apiKey: 'a-new-key'),
        );
        await container.read(connectionCapabilityProvider(unraidId).future);
        expect(calls, 2);
      },
    );
  });
}
