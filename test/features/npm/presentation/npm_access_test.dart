import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/capability/capability_scope.dart';
import 'package:cupola/features/npm/domain/models/npm_models.dart';
import 'package:cupola/features/npm/presentation/npm_access.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import '../../../test_helpers/settings_scope.dart';

NpmAccount _account({
  required bool admin,
  Map<String, String> permissions = const {},
}) {
  return NpmAccount(
    id: 1,
    name: 'Test',
    isAdmin: admin,
    permissions: permissions,
  );
}

/// The connection the NPM pages read through: the first one takes the
/// service's route param as its id.
const _npm = 'npm';

Future<ProviderContainer> _container(
  Future<NpmAccount?> Function() probe,
) async {
  final container = ProviderContainer(
    retry: (_, _) => null,
    overrides: [
      ...await settingsScopeOverrides(
        configured: const [ServiceKey.nginxProxyManager],
      ),
      npmAccountProvider.overrideWith((ref) => probe()),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

Future<CapabilityGrant> _settled(ProviderContainer container) async {
  // Keep the probe alive while it answers.
  final sub = container.listen(capabilityGrantForProvider(_npm), (_, _) {});
  addTearDown(sub.close);
  await container.read(npmAccountProvider.future);
  await pumpEventQueue();
  return container.read(capabilityGrantForProvider(_npm));
}

/// Decision 34's behaviour, on the shared capability layer.
void main() {
  group('the NPM gate — decision 34', () {
    test('an admin may write and gets no band', () async {
      final container = await _container(() async => _account(admin: true));
      final grant = await _settled(container);

      expect(grant.scopeFor(NpmResource.proxyHosts.key).canWrite, isTrue);
      expect(grant.restrictsAny(null), isFalse);
    });

    test('a view-only account is dimmed, per resource', () async {
      final container = await _container(
        () async =>
            _account(admin: false, permissions: const {'proxy_hosts': 'view'}),
      );
      final grant = await _settled(container);

      expect(grant, const CapabilityGrant.readOnly());
      expect(grant.scopeFor(NpmResource.proxyHosts.key).canWrite, isFalse);
      expect(grant.restrictsAny(null), isTrue);
    });

    test('a scoped account writes only what it manages', () async {
      final container = await _container(
        () async => _account(
          admin: false,
          permissions: const {'proxy_hosts': 'manage', 'certificates': 'view'},
        ),
      );
      final grant = await _settled(container);

      expect(grant.scopeFor(NpmResource.proxyHosts.key).canWrite, isTrue);
      expect(grant.scopeFor(NpmResource.certificates.key).canWrite, isFalse);
      // Not wholly restricted, so no band on a page with no writes…
      expect(grant.restrictsAny(null), isFalse);
      // …but one on the Certificates tab.
      expect(grant.restrictsAny({NpmResource.certificates.key}), isTrue);
    });

    test(
      'a probe that failed falls back to read-only, never to optimism',
      () async {
        // Cross-cutting C states this as a rule: a control offered on a guess
        // is a control that 403s in the user's hand. And it is recorded as
        // "could not ask", so the band does not claim NPM refused.
        final container = await _container(() async => null);
        final grant = await _settled(container);

        expect(grant, const CapabilityGrant.unanswered());
        expect(grant.scopeFor(NpmResource.certificates.key).canWrite, isFalse);
      },
    );

    test('while the probe is still out the controls stay live', () async {
      // The shared rule: `unknown` is a timing state, not a verdict. NPM used
      // to hold every write here; a 403 now teaches it on the first refusal
      // instead, which is cheaper than every cold open looking broken.
      final pending = Completer<NpmAccount?>();
      final container = await _container(() => pending.future);

      final grant = container.read(capabilityGrantForProvider(_npm));

      expect(grant, const CapabilityGrant.unknown());
      expect(grant.scopeFor(NpmResource.proxyHosts.key).canWrite, isTrue);
      expect(grant.restrictsAny(null), isFalse);
      pending.complete(null);
    });

    test('a 403 on a write outranks whatever the probe said', () async {
      final container = await _container(() async => _account(admin: true));
      expect(
        (await _settled(
          container,
        )).scopeFor(NpmResource.proxyHosts.key).canWrite,
        isTrue,
      );

      container.read(capabilityScopeProvider.notifier).markReadOnly(_npm);

      final grant = container.read(capabilityGrantForProvider(_npm));
      expect(grant, const CapabilityGrant.refused());
      expect(grant.scopeFor(NpmResource.proxyHosts.key).canWrite, isFalse);
    });
  });
}
