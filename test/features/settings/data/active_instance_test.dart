import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/data/settings_service.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';

import '../../../test_helpers/fake_secure_settings_store.dart';

/// Exposes [watchTransport] so a test can read what a client would be built
/// from, without standing up a client.
final _transportProvider = Provider.family<ServiceTransport, ServiceKey>(
  (ref, service) => watchTransport(ref, service),
);

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
const _sonarr = ServiceInstance(
  id: 'sonarr',
  service: ServiceKey.sonarr,
  url: 'https://sonarr.lan:8989',
  credential: 'key-sonarr',
);

ProviderContainer _container({Map<ServiceKey, String> lenses = const {}}) {
  final container = ProviderContainer(
    overrides: [
      currentSettingsProvider.overrideWith(
        (ref) => const SettingsModel(instances: [_fourK, _hd, _sonarr]),
      ),
      initialActiveInstancesProvider.overrideWithValue(lenses),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  group('with no lens set', () {
    test('a service resolves to its first instance', () {
      final transport = _container().read(
        _transportProvider(ServiceKey.radarr),
      );

      expect(transport.url, 'https://four-k.lan:7878');
      expect(transport.apiKey, 'key-4k');
      expect(transport.instanceId, 'radarr');
      expect(transport.configured, isTrue);
    });

    test('a service with no instance at all is not configured', () {
      final transport = _container().read(_transportProvider(ServiceKey.plex));

      expect(transport.configured, isFalse);
      expect(transport.url, '');
      expect(transport.instanceId, '');
    });
  });

  group('with a lens set', () {
    test('the transport is the other server, not the first', () {
      final transport = _container(
        lenses: {ServiceKey.radarr: 'radarr-hd11111'},
      ).read(_transportProvider(ServiceKey.radarr));

      expect(transport.url, 'https://hd.lan:7879');
      expect(transport.apiKey, 'key-hd');
      expect(transport.instanceId, 'radarr-hd11111');
    });

    test('moving one service does not move another', () {
      final container = _container(
        lenses: {ServiceKey.radarr: 'radarr-hd11111'},
      );

      expect(
        container.read(_transportProvider(ServiceKey.sonarr)).url,
        'https://sonarr.lan:8989',
      );
    });

    test('an id that names nothing falls back to the first', () {
      // The shape after an instance is removed while it was the chosen lens.
      final transport = _container(
        lenses: {ServiceKey.radarr: 'radarr-deleted'},
      ).read(_transportProvider(ServiceKey.radarr));

      expect(transport.instanceId, 'radarr');
      expect(transport.url, 'https://four-k.lan:7878');
    });

    test('an id belonging to another service falls back too', () {
      final transport = _container(
        lenses: {ServiceKey.radarr: 'sonarr'},
      ).read(_transportProvider(ServiceKey.radarr));

      expect(transport.instanceId, 'radarr');
    });
  });

  group('moving the lens', () {
    // These write, so they need real storage behind them. A lens change that
    // cannot be persisted throws rather than being swallowed: the same
    // contract every other settings write has.
    late SharedPreferences prefs;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
    });

    ProviderContainer writable({Map<ServiceKey, String> lenses = const {}}) {
      final container = ProviderContainer(
        overrides: [
          currentSettingsProvider.overrideWith(
            (ref) => const SettingsModel(instances: [_fourK, _hd, _sonarr]),
          ),
          initialActiveInstancesProvider.overrideWithValue(lenses),
          sharedPreferencesProvider.overrideWithValue(prefs),
          secureSettingsStoreProvider.overrideWithValue(
            FakeSecureSettingsStore(),
          ),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('changes what the transport resolves to', () async {
      final container = writable();
      expect(
        container.read(_transportProvider(ServiceKey.radarr)).instanceId,
        'radarr',
      );

      await container
          .read(activeInstancesProvider.notifier)
          .select(ServiceKey.radarr, 'radarr-hd11111');

      expect(
        container.read(_transportProvider(ServiceKey.radarr)).instanceId,
        'radarr-hd11111',
      );
    });

    test('clearing puts it back on the first', () async {
      final container = writable(lenses: {ServiceKey.radarr: 'radarr-hd11111'});
      await container
          .read(activeInstancesProvider.notifier)
          .clear(ServiceKey.radarr);

      expect(
        container.read(_transportProvider(ServiceKey.radarr)).instanceId,
        'radarr',
      );
    });

    test('the choice is on disk for the next launch', () async {
      await writable()
          .read(activeInstancesProvider.notifier)
          .select(ServiceKey.radarr, 'radarr-hd11111');

      expect(
        SettingsService(prefs, FakeSecureSettingsStore()).loadActiveInstances(),
        {ServiceKey.radarr: 'radarr-hd11111'},
      );
    });
  });

  group('the lens survives a launch', () {
    late SharedPreferences prefs;
    late SettingsService service;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      service = SettingsService(prefs, FakeSecureSettingsStore());
    });

    test('round-trips through storage', () async {
      await service.saveActiveInstances({
        ServiceKey.radarr: 'radarr-hd11111',
        ServiceKey.sonarr: 'sonarr',
      });

      expect(
        SettingsService(prefs, FakeSecureSettingsStore()).loadActiveInstances(),
        {ServiceKey.radarr: 'radarr-hd11111', ServiceKey.sonarr: 'sonarr'},
      );
    });

    test('an empty map removes the key rather than storing "{}"', () async {
      await service.saveActiveInstances({ServiceKey.radarr: 'x'});
      await service.saveActiveInstances({});

      expect(prefs.getString('active_instances'), isNull);
      expect(service.loadActiveInstances(), isEmpty);
    });

    test('a service this build no longer has is dropped on load', () async {
      await prefs.setString(
        'active_instances',
        '{"radarr":"radarr-hd11111","somethingRemoved":"x"}',
      );

      expect(service.loadActiveInstances(), {
        ServiceKey.radarr: 'radarr-hd11111',
      });
    });

    test('garbage costs the lenses and nothing else', () async {
      await prefs.setString('active_instances', 'not json');
      expect(service.loadActiveInstances(), isEmpty);
    });

    test('a stale id is kept on disk, not pruned at load time', () async {
      // Resolution happens at read time against the instance list, which this
      // class cannot see. Pruning here would throw away the user's choice
      // whenever storage was read before the connections were.
      await service.saveActiveInstances({ServiceKey.radarr: 'radarr-gone'});
      expect(service.loadActiveInstances(), {ServiceKey.radarr: 'radarr-gone'});
    });
  });

  test('reading a lens needs no storage bootstrap', () {
    // Deliberate: initialActiveInstancesProvider defaults to empty instead of
    // throwing, so asking "which server does this talk to" never drags
    // SharedPreferences in behind it.
    final container = ProviderContainer(
      overrides: [
        currentSettingsProvider.overrideWith(
          (ref) => const SettingsModel(instances: [_fourK]),
        ),
      ],
    );
    addTearDown(container.dispose);

    expect(
      container.read(_transportProvider(ServiceKey.radarr)).url,
      'https://four-k.lan:7878',
    );
  });
}
