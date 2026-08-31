import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cupola/features/activity/domain/service_type.dart';
import 'package:cupola/features/activity/presentation/activity_provider.dart';
import 'package:cupola/features/movies/data/radarr_service.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';

import '../../../test_helpers/fake_secure_settings_store.dart';

const _fourK = ServiceInstance(
  id: 'radarr',
  service: ServiceKey.radarr,
  label: '4K',
  url: 'https://four-k.lan:7878',
  credential: 'key-4k',
);
const _hd = ServiceInstance(
  id: 'radarr-hd11111',
  service: ServiceKey.radarr,
  label: 'HD',
  url: 'https://hd.lan:7879',
  credential: 'key-hd',
);

Future<ProviderContainer> _container() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      secureSettingsStoreProvider.overrideWithValue(FakeSecureSettingsStore()),
      initialSettingsProvider.overrideWithValue(
        const SettingsModel(instances: [_fourK, _hd]),
      ),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

String _baseUrlOf(ProviderContainer container) =>
    (container.read(resolvedArrServiceProvider(ServiceType.movies))
            as RadarrService)
        .client
        .dio
        .options
        .baseUrl;

void main() {
  // /activity is a control room, not a readout: the same service this provider
  // hands out is what an auto-search and a queue removal are sent through. It
  // held the first one it ever resolved, and `watchApiClient` closes the Dio of
  // the client it replaces — so after a lens move a write went to a shut
  // transport, or to the server the user had just navigated away from.
  test('the Activity service follows the lens', () async {
    final container = await _container();

    expect(_baseUrlOf(container), 'https://four-k.lan:7878');

    await container
        .read(activeInstancesProvider.notifier)
        .select(ServiceKey.radarr, 'radarr-hd11111');

    expect(
      _baseUrlOf(container),
      'https://hd.lan:7879',
      reason: 'held by `read`, this still names the 4K box',
    );
  });

  test('and its transport is a live one, not the closed predecessor', () async {
    final container = await _container();

    final before = container.read(
      resolvedArrServiceProvider(ServiceType.movies),
    );
    await container
        .read(activeInstancesProvider.notifier)
        .select(ServiceKey.radarr, 'radarr-hd11111');
    final after = container.read(
      resolvedArrServiceProvider(ServiceType.movies),
    );

    // The distinction that makes this a crash rather than a stale read: the
    // client behind `before` was disposed when its transport changed, so
    // handing it out again is handing out a closed `Dio`.
    expect(identical(before, after), isFalse);
  });

  test('an unrelated settings write does not churn the service', () async {
    // The counterweight. A provider that rebuilt on every settings write would
    // tear down a live connection each time the theme changed.
    final container = await _container();

    final before = container.read(
      resolvedArrServiceProvider(ServiceType.movies),
    );
    await container
        .read(settingsProvider.notifier)
        .updateSettings(
          const SettingsModel(instances: [_fourK, _hd], region: 'IT'),
        );

    expect(
      identical(
        before,
        container.read(resolvedArrServiceProvider(ServiceType.movies)),
      ),
      isTrue,
    );
  });
}
