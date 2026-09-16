import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/npm/domain/models/npm_models.dart';
import 'package:cupola/features/npm/presentation/npm_access.dart';

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

ProviderContainer _container(Future<NpmAccount?> Function() probe) {
  final container = ProviderContainer(
    overrides: [npmAccountProvider.overrideWith((ref) => probe())],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  group('npmWriteAccessProvider — decision 34', () {
    test('an admin may write and gets no band', () async {
      final container = _container(() async => _account(admin: true));
      await container.read(npmAccountProvider.future);

      final access = container.read(npmWriteAccessProvider);

      expect(access.state, NpmWriteAccessState.granted);
      expect(access.canManage(NpmResource.proxyHosts), isTrue);
      expect(access.showBand, isFalse);
    });

    test('a view-only account is dimmed and told why', () async {
      final container = _container(
        () async =>
            _account(admin: false, permissions: const {'proxy_hosts': 'view'}),
      );
      await container.read(npmAccountProvider.future);

      final access = container.read(npmWriteAccessProvider);

      expect(access.state, NpmWriteAccessState.viewOnly);
      expect(access.canManage(NpmResource.proxyHosts), isFalse);
      expect(access.showBand, isTrue);
      expect(access.hint, 'requires an admin account');
    });

    test(
      'a probe that failed falls back to read-only, never to optimism',
      () async {
        // Cross-cutting C states this as a rule: a control offered on a guess is
        // a control that 403s in the user's hand.
        final container = _container(() async => null);
        await container.read(npmAccountProvider.future);

        final access = container.read(npmWriteAccessProvider);

        expect(access.state, NpmWriteAccessState.unknown);
        expect(access.canManage(NpmResource.certificates), isFalse);
        expect(access.showBand, isTrue);
        // …and it says it could not ask, rather than claiming NPM refused.
        expect(access.bandMessage, contains('could not read'));
      },
    );

    test('nothing is claimed while the probe is still out', () async {
      final container = _container(
        () => Future.delayed(
          const Duration(milliseconds: 50),
          () => _account(admin: true),
        ),
      );

      final access = container.read(npmWriteAccessProvider);

      expect(access.state, NpmWriteAccessState.checking);
      expect(access.canManage(NpmResource.proxyHosts), isFalse);
      // No band yet: a banner that appears and then disappears is worse than a
      // beat of silence.
      expect(access.showBand, isFalse);
    });

    test('a 403 on a write outranks whatever the probe said', () async {
      final container = _container(() async => _account(admin: true));
      await container.read(npmAccountProvider.future);
      expect(
        container
            .read(npmWriteAccessProvider)
            .canManage(NpmResource.proxyHosts),
        isTrue,
      );

      container.read(npmWriteRefusedProvider.notifier).markRefused();

      final access = container.read(npmWriteAccessProvider);
      expect(access.state, NpmWriteAccessState.viewOnly);
      expect(access.canManage(NpmResource.proxyHosts), isFalse);
    });
  });
}
