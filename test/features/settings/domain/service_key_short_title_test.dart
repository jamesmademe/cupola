import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/settings/domain/service_key.dart';

void main() {
  test('a short name only where the full one cannot fit a Stack tile', () {
    expect(ServiceKey.nginxProxyManager.shortTitle, 'Proxy Manager');
    for (final service in ServiceKey.values) {
      expect(
        service.shortTitle.length,
        lessThanOrEqualTo(14),
        reason: '${service.title} overflows a half-width tile',
      );
      if (service != ServiceKey.nginxProxyManager) {
        expect(service.shortTitle, service.title);
      }
    }
  });
}
