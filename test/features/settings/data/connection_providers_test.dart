import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderException;
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/movies/data/radarr_service.dart';
import 'package:cupola/features/sabnzbd/presentation/sabnzbd_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/service_not_configured.dart';

import '../../../test_helpers/settings_scope.dart';

/// The pair every service client has: the lens's client and a named
/// connection's. Tested through two services built two ways (an `ApiClient`
/// service and a transport client).
void main() {
  Future<ProviderContainer> container() async {
    final container = ProviderContainer(
      overrides: await settingsScopeOverrides(
        configured: [ServiceKey.radarr, ServiceKey.sabnzbd],
      ),
    );
    addTearDown(container.dispose);
    return container;
  }

  test('the empty id is the lens, one client and not two', () async {
    final c = await container();
    expect(
      identical(
        c.read(radarrServiceForProvider('')),
        c.read(radarrServiceProvider),
      ),
      isTrue,
    );
    expect(
      identical(
        c.read(sabnzbdClientForProvider('')),
        c.read(sabnzbdClientProvider),
      ),
      isTrue,
    );
  });

  test('an id that names nothing is not configured, never the lens', () async {
    final c = await container();
    expect(
      () => c.read(radarrServiceForProvider('nobody')),
      throwsA(
        isA<ProviderException>().having(
          (e) => e.exception,
          'cause',
          isA<ServiceNotConfigured>(),
        ),
      ),
    );
    expect(
      () => c.read(sabnzbdClientForProvider('nobody')),
      throwsA(
        isA<ProviderException>().having(
          (e) => e.exception,
          'cause',
          isA<ServiceNotConfigured>(),
        ),
      ),
    );
  });

  test('a service that is not configured throws by type', () async {
    final c = ProviderContainer(
      overrides: await settingsScopeOverrides(configured: const []),
    );
    addTearDown(c.dispose);
    expect(
      () => c.read(sabnzbdClientProvider),
      throwsA(
        isA<ProviderException>().having(
          (e) => e.exception,
          'cause',
          isA<ServiceNotConfigured>(),
        ),
      ),
    );
  });
}
