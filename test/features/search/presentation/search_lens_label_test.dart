import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/search/domain/global_search_result.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';

const _fourK = ServiceInstance(
  id: 'radarr',
  service: ServiceKey.radarr,
  label: '4K',
  url: 'https://four-k.lan:7878',
  credential: 'k',
);
const _hd = ServiceInstance(
  id: 'radarr-hd11111',
  service: ServiceKey.radarr,
  label: 'HD',
  url: 'https://hd.lan:7879',
  credential: 'k',
);
const _sonarr = ServiceInstance(
  id: 'sonarr',
  service: ServiceKey.sonarr,
  url: 'https://sonarr.lan:8989',
  credential: 'k',
);

void main() {
  group('the section says which connection answered', () {
    test('nothing to say while a service has one connection', () {
      const group = GlobalSearchServiceResults(
        service: ServiceKey.sonarr,
        results: [],
      );
      // The default, and the one that matters: a stack with one Sonarr must
      // not grow a chip naming the only Sonarr there is.
      expect(group.instanceLabel, isEmpty);
    });

    test('carries the label when there is one to carry', () {
      const group = GlobalSearchServiceResults(
        service: ServiceKey.radarr,
        results: [],
        instanceLabel: '4K',
      );
      expect(group.instanceLabel, '4K');
    });

    test('an offline section is named too', () {
      // "Radarr did not answer" is a worse sentence than "Radarr · 4K did not
      // answer" when the other connection did.
      const group = GlobalSearchServiceResults(
        service: ServiceKey.radarr,
        results: [],
        error: 'boom',
        instanceLabel: 'Anime',
      );
      expect(group.hasError, isTrue);
      expect(group.instanceLabel, 'Anime');
    });
  });

  group('search follows the lens', () {
    ProviderContainer container({Map<ServiceKey, String> lenses = const {}}) {
      final c = ProviderContainer(
        overrides: [
          currentSettingsProvider.overrideWith(
            (ref) => const SettingsModel(instances: [_fourK, _hd, _sonarr]),
          ),
          initialActiveInstancesProvider.overrideWithValue(lenses),
        ],
      );
      addTearDown(c.dispose);
      return c;
    }

    test('a service with one connection reports no label to show', () {
      expect(
        container().read(hasMultipleInstancesProvider(ServiceKey.sonarr)),
        isFalse,
      );
    });

    test('the label follows the lens, not the first connection', () {
      // The bug this guards: the search legs read lens-aware providers while
      // the key that decides whether to refetch described the first connection.
      // Moving the lens showed the previous server's answers and never
      // refetched, because nothing the provider watched had changed.
      final c = container(lenses: {ServiceKey.radarr: 'radarr-hd11111'});

      expect(c.read(hasMultipleInstancesProvider(ServiceKey.radarr)), isTrue);
      expect(c.read(activeInstanceProvider(ServiceKey.radarr))?.label, 'HD');
      expect(
        c.read(activeInstanceProvider(ServiceKey.radarr))?.url,
        'https://hd.lan:7879',
      );
    });
  });
}
