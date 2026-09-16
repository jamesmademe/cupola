import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/capability/capability_scope.dart';

void main() {
  group('the fallback rule', () {
    test('a failed probe is read-only, never optimistic', () {
      // The rule the whole enum exists to enforce. A probe that errors or times
      // out has told us nothing, and the only safe reading of nothing is the
      // restrictive one: a false read-only costs a banner and a trip to
      // Settings, a false read-write costs a container that never stopped.
      expect(CapabilityScope.readOnly.canWrite, isFalse);
      expect(CapabilityScope.readOnly.isRestricted, isTrue);
    });

    test('unprobed is not the same as refused', () {
      // `unknown` is a timing state, not a verdict. Dimming every write for the
      // sub-second window before the probe answers, then un-dimming them a
      // frame later, makes a healthy connection look broken on every cold open.
      expect(CapabilityScope.unknown.canWrite, isTrue);
      expect(CapabilityScope.unknown.isRestricted, isFalse);
    });
  });

  group('the cache is keyed by connection, not by service', () {
    test('two connections to the same service answer independently', () {
      // A TrueNAS with a full key at home and a friend's box behind a read-only
      // token are both "TrueNAS". Keying on the service would let one govern
      // the other, which dims controls that work and enables ones that cannot.
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(capabilityScopeProvider.notifier);
      notifier.record('truenas-home', CapabilityScope.readWrite);
      notifier.record('truenas-friend', CapabilityScope.readOnly);

      expect(
        container.read(capabilityScopeForProvider('truenas-home')),
        CapabilityScope.readWrite,
      );
      expect(
        container.read(capabilityScopeForProvider('truenas-friend')),
        CapabilityScope.readOnly,
      );
    });

    test('an unprobed connection reads as unknown, not as absent', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(
        container.read(capabilityScopeForProvider('never-probed')),
        CapabilityScope.unknown,
      );
    });
  });

  group('the second signal', () {
    test('a 403 on any write marks the connection read-only', () {
      // The signal that needs no endpoint: the service itself answering the
      // question the probe asked. It is what gets a service with no probe — or
      // one whose probe was wrong — to the right banner after one refusal,
      // instead of letting the user press a dead control all afternoon.
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(capabilityScopeProvider.notifier);
      notifier.record('npm-1', CapabilityScope.readWrite);
      notifier.markReadOnly('npm-1');

      expect(
        container.read(capabilityScopeForProvider('npm-1')).canWrite,
        isFalse,
      );
    });

    test('recording the same answer twice does not churn the state', () {
      // Every write control on the page watches this. A probe re-running on a
      // connection that has not changed must not rebuild them.
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(capabilityScopeProvider.notifier);
      notifier.record('jellyfin-1', CapabilityScope.readOnly);
      final first = container.read(capabilityScopeProvider);
      notifier.record('jellyfin-1', CapabilityScope.readOnly);

      expect(identical(container.read(capabilityScopeProvider), first), isTrue);
    });

    test(
      'forgetting a connection sends the next connect back to the probe',
      () {
        // The whole point of "Update the key" is that the old verdict is now
        // wrong. A remembered read-only would survive the fix and keep the
        // controls dimmed after the user had already corrected it.
        final container = ProviderContainer();
        addTearDown(container.dispose);

        final notifier = container.read(capabilityScopeProvider.notifier);
        notifier.record('unraid-1', CapabilityScope.readOnly);
        notifier.forget('unraid-1');

        expect(
          container.read(capabilityScopeForProvider('unraid-1')),
          CapabilityScope.unknown,
        );
      },
    );
  });
}
