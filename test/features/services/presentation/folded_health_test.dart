import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/services/domain/service_summary.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
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
const _anime = ServiceInstance(
  id: 'radarr-anime11',
  service: ServiceKey.radarr,
  label: 'Anime',
  url: 'https://vps.altrove.net:7878',
  credential: 'k',
);

ServiceSummary _summary({required bool online}) => ServiceSummary(
  service: ServiceKey.radarr,
  status: online ? ServiceSummaryStatus.online : ServiceSummaryStatus.offline,
  host: 'somewhere',
  version: online ? '5.0' : null,
);

/// Overrides each connection's probe so the test decides who is up, without a
/// socket anywhere.
ProviderContainer _container(Map<String, bool> upById) {
  final container = ProviderContainer(
    overrides: [
      currentSettingsProvider.overrideWith(
        (ref) => const SettingsModel(instances: [_fourK, _hd, _anime]),
      ),
      for (final entry in upById.entries)
        instanceSummaryProvider((
          service: ServiceKey.radarr,
          instanceId: entry.key,
        )).overrideWith((ref) async => _summary(online: entry.value)),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  test('ids come back in the user order, as a stable value', () {
    final container = _container(const {});
    final first = container.read(serviceInstanceIdsProvider(ServiceKey.radarr));
    final again = container.read(serviceInstanceIdsProvider(ServiceKey.radarr));

    expect(first, ['radarr', 'radarr-hd11111', 'radarr-anime11']);
    // Same value, not merely equal contents — a fresh List each read would
    // rebuild every consumer on every unrelated settings write.
    expect(identical(first, again), isTrue);
  });

  test('a service with no connections folds to nothing', () async {
    final container = ProviderContainer(
      overrides: [
        currentSettingsProvider.overrideWith((ref) => const SettingsModel()),
      ],
    );
    addTearDown(container.dispose);

    expect(container.read(foldedServiceHealthProvider(ServiceKey.radarr)), (
      total: 0,
      offline: 0,
      faulted: 0,
      checking: 0,
    ));
  });

  test('all up folds to nothing offline', () async {
    final container = _container(const {
      'radarr': true,
      'radarr-hd11111': true,
      'radarr-anime11': true,
    });
    for (final id in container.read(
      serviceInstanceIdsProvider(ServiceKey.radarr),
    )) {
      await container.read(
        instanceSummaryProvider((
          service: ServiceKey.radarr,
          instanceId: id,
        )).future,
      );
    }

    final folded = container.read(
      foldedServiceHealthProvider(ServiceKey.radarr),
    );
    expect(folded.total, 3);
    expect(folded.offline, 0);
  });

  test('one down is counted, and the other two are not hidden', () async {
    // The state the matrix cell exists to report: "Offline" would be false —
    // two are answering — and "Online" would hide the one that is not.
    final container = _container(const {
      'radarr': true,
      'radarr-hd11111': true,
      'radarr-anime11': false,
    });
    for (final id in container.read(
      serviceInstanceIdsProvider(ServiceKey.radarr),
    )) {
      await container.read(
        instanceSummaryProvider((
          service: ServiceKey.radarr,
          instanceId: id,
        )).future,
      );
    }

    final folded = container.read(
      foldedServiceHealthProvider(ServiceKey.radarr),
    );
    expect(folded.total, 3);
    expect(folded.offline, 1);
    expect(folded.checking, 0);
  });

  test('a probe still in flight counts as checking, not as offline', () {
    // Read before awaiting: an unanswered probe must not be reported as a
    // failure, or every cold start would flash a false alarm.
    final container = _container(const {
      'radarr': true,
      'radarr-hd11111': true,
      'radarr-anime11': true,
    });

    final folded = container.read(
      foldedServiceHealthProvider(ServiceKey.radarr),
    );
    expect(folded.checking, 3);
    expect(folded.offline, 0);
  });

  test('the per-service probe follows the lens, not the first', () async {
    final container = ProviderContainer(
      overrides: [
        currentSettingsProvider.overrideWith(
          (ref) => const SettingsModel(instances: [_fourK, _hd]),
        ),
        initialActiveInstancesProvider.overrideWithValue({
          ServiceKey.radarr: 'radarr-hd11111',
        }),
        instanceSummaryProvider((
          service: ServiceKey.radarr,
          instanceId: 'radarr',
        )).overrideWith((ref) async => _summary(online: true)),
        instanceSummaryProvider((
          service: ServiceKey.radarr,
          instanceId: 'radarr-hd11111',
        )).overrideWith((ref) async => _summary(online: false)),
      ],
    );
    addTearDown(container.dispose);

    final summary = await container.read(
      serviceSummaryProvider(ServiceKey.radarr).future,
    );
    // Asking "is Radarr up" from a screen reading HD has to answer for HD.
    expect(summary.isOnline, isFalse);
  });
}
