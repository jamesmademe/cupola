import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/settings/domain/service_key.dart';

void main() {
  group('hasScopedCredential', () {
    test('is true for exactly Unraid, TrueNAS and Nginx Proxy Manager', () {
      expect(ServiceKey.values.where((s) => s.hasScopedCredential).toSet(), {
        ServiceKey.unraid,
        ServiceKey.truenas,
        ServiceKey.nginxProxyManager,
      });
    });

    test('is false for Jellyfin', () {
      // A non-admin Jellyfin token is only ever shown sessions it may control,
      // so a gate would dim session controls that work.
      expect(ServiceKey.jellyfin.hasScopedCredential, isFalse);
    });
  });

  group('the capability copy', () {
    test('an NPM login is an account, changed; everything else a key', () {
      expect(ServiceKey.nginxProxyManager.capabilityFixLabel, 'Change account');
      expect(ServiceKey.nginxProxyManager.capabilityCredentialNoun, 'account');
      for (final service in [ServiceKey.unraid, ServiceKey.truenas]) {
        expect(service.capabilityFixLabel, 'Update the key');
        expect(service.capabilityCredentialNoun, 'key');
      }
    });
  });
}
