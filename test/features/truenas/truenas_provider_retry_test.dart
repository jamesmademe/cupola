import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';
import 'package:cupola/features/truenas/data/truenas_ws_client.dart';
import 'package:cupola/features/truenas/domain/models/data_protection.dart';
import 'package:cupola/features/truenas/presentation/apps/truenas_apps_providers.dart';
import 'package:cupola/features/truenas/presentation/dashboard/truenas_dashboard_screen.dart';
import 'package:cupola/features/truenas/presentation/data_protection/truenas_data_protection_screen.dart';
import 'package:cupola/features/truenas/presentation/datasets/truenas_dataset_providers.dart';
import 'package:cupola/features/truenas/presentation/shares/truenas_shares_providers.dart';
import 'package:cupola/features/truenas/presentation/storage/truenas_storage_providers.dart';
import 'package:cupola/features/truenas/presentation/system/truenas_system_providers.dart';
import 'package:cupola/features/truenas/presentation/truenas_provider.dart';
import 'package:cupola/features/truenas/presentation/virt/truenas_virt_providers.dart';

/// A NAS that went dark: every call fails the way an unreachable host fails,
/// and every attempt is counted: a retry is an attempt.
class _DarkNas extends TrueNasWsClient {
  _DarkNas() : super(baseUrl: 'https://nas.local', apiKey: 'k');

  int calls = 0;

  @override
  Future<dynamic> call(String method, [List<dynamic> params = const []]) async {
    calls++;
    throw const TrueNasException(
      'connection refused',
      reason: ServiceFailureReason.unreachable,
    );
  }
}

typedef _Source = (String, ProviderListenable<AsyncValue<Object?>>);

/// Every read provider a TrueNAS screen watches. `_reportingProvider` is
/// private to its screen and carries the same policy.
final List<_Source> _sources = [
  ('version', truenasVersionProvider),
  ('dashboard', truenasDashboardProvider),
  ('dashboard interfaces', truenasDashboardInterfacesProvider),
  ('dataset tree', truenasDatasetTreeProvider),
  ('dataset', truenasDatasetProvider('tank/media')),
  ('snapshots', truenasSnapshotsProvider('tank/media')),
  ('pools', truenasPoolsProvider),
  ('pool', truenasPoolProvider('tank')),
  ('system info', truenasSystemInfoProvider),
  ('general config', truenasGeneralConfigProvider),
  ('advanced config', truenasAdvancedConfigProvider),
  ('mail config', truenasMailConfigProvider),
  ('update status', truenasUpdateStatusProvider),
  ('ntp servers', truenasNtpServersProvider),
  ('certificates', truenasCertificatesProvider),
  ('alert services', truenasAlertServicesProvider),
  ('network config', truenasNetworkConfigProvider),
  ('interfaces', truenasInterfacesProvider),
  ('users', truenasUsersProvider),
  ('groups', truenasGroupsProvider),
  ('virt global', truenasVirtGlobalProvider),
  ('virt instances', truenasVirtInstancesProvider('VM')),
  ('virt instance', truenasVirtInstanceProvider('vm1')),
  ('virt devices', truenasVirtDevicesProvider('vm1')),
  ('smb shares', truenasSmbSharesProvider),
  ('nfs shares', truenasNfsSharesProvider),
  ('iscsi targets', truenasIscsiTargetsProvider),
  ('services', truenasServicesProvider),
  for (final kind in TrueNasTaskKind.values)
    ('protection ${kind.name}', truenasProtectionTasksProvider(kind)),
  ('apps', truenasAppsProvider),
  ('app', truenasAppProvider('plex')),
];

/// The same read with Riverpod's default policy: the harness's own control.
final _defaultRetryPools = FutureProvider.autoDispose((ref) async {
  ref.watch(truenasClientProvider);
  return ref.watch(truenasStorageApiProvider).getPools();
});

/// The client provider's "not configured" throw, under the default policy.
final _defaultRetryClient = Provider<TrueNasWsClient>(
  (ref) => throw const TrueNasException('TrueNAS not configured'),
);

/// Shorter than Riverpod's first retry delay (200 ms): a provider that is
/// going to retry is still reporting *loading* at this point.
const _settle = Duration(milliseconds: 50);

ProviderContainer _containerOver(_DarkNas nas) {
  // No `retry:` on the container, deliberately: the policy under test is the
  // one each provider declares, and a container-wide override would hide it.
  final container = ProviderContainer(
    overrides: [truenasClientProvider.overrideWithValue(nas)],
  );
  addTearDown(container.dispose);
  return container;
}

ProviderContainer _containerWith(SettingsModel settings) {
  final container = ProviderContainer(
    overrides: [
      currentSettingsProvider.overrideWith((ref) => settings),
      initialActiveInstancesProvider.overrideWithValue(const {}),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  testWidgets('control: under the default policy a dark NAS is a spinner', (
    tester,
  ) async {
    // Proves the harness can see a retry at all, so the tests below are not
    // passing because nothing would ever have retried.
    final nas = _DarkNas();
    final container = _containerOver(nas);
    container.listen(_defaultRetryPools, (_, _) {});

    await tester.pump(_settle);
    expect(container.read(_defaultRetryPools).isLoading, isTrue);

    await tester.pump(const Duration(minutes: 1));
    expect(nas.calls, greaterThan(1));
  });

  testWidgets('every read settles on its first failure and is not retried', (
    tester,
  ) async {
    final nas = _DarkNas();
    final container = _containerOver(nas);
    for (final (_, provider) in _sources) {
      container.listen(provider, (_, _) {});
    }
    container.listen(truenasDashboardMetricsProvider, (_, _) {});

    await tester.pump(_settle);
    for (final (name, provider) in _sources) {
      final state = container.read(provider);
      expect(state.isLoading, isFalse, reason: '$name is still loading');
      expect(state.hasError, isTrue, reason: '$name did not reach its error');
    }
    // Best-effort by design: it degrades rather than failing the section, and
    // must settle just as promptly.
    final metrics = container.read(truenasDashboardMetricsProvider);
    expect(metrics.isLoading, isFalse);
    expect(metrics.hasValue, isTrue);
    // ...and it says that nothing arrived. The reporting API used to swallow
    // the failure into an empty answer, which the dashboard stamped as an
    // arrival, so its stale band could never appear.
    expect(metrics.requireValue.answered, isFalse);

    final attempts = nas.calls;
    await tester.pump(const Duration(minutes: 1));
    expect(nas.calls, attempts, reason: 'something retried on its own');
    for (final (name, provider) in _sources) {
      expect(container.read(provider).hasError, isTrue, reason: name);
    }
  });

  testWidgets('a manual Retry still asks again', (tester) async {
    final nas = _DarkNas();
    final container = _containerOver(nas);
    container.listen(truenasPoolsProvider, (_, _) {});
    await tester.pump(_settle);
    final attempts = nas.calls;

    // What the well's Retry and the pull-to-refresh both do.
    container.invalidate(truenasPoolsProvider);
    await tester.pump(_settle);

    expect(nas.calls, attempts + 1);
    final state = container.read(truenasPoolsProvider);
    expect(state.isLoading, isFalse);
    expect(state.hasError, isTrue);
  });

  testWidgets('control: a throwing sync provider is retried by default', (
    tester,
  ) async {
    // The counterpart for the test below: under the default policy the
    // listener does hear every rebuild's failure.
    final container = ProviderContainer();
    addTearDown(container.dispose);
    var failures = 0;
    container.listen(
      _defaultRetryClient,
      (_, _) {},
      onError: (_, _) => failures++,
      fireImmediately: true,
    );

    await tester.pump(const Duration(minutes: 1));
    expect(failures, greaterThan(1));
  });

  testWidgets('"not configured" fails once, not ten times', (tester) async {
    // The client provider throws this from its own build. Under the default
    // policy that is an `Exception` like any other, retried with backoff for a
    // condition no waiting changes.
    final container = _containerWith(const SettingsModel());
    var failures = 0;
    container.listen(
      truenasClientProvider,
      (_, _) {},
      onError: (_, _) => failures++,
      fireImmediately: true,
    );
    container.listen(truenasPoolsProvider, (_, _) {});

    await tester.pump(const Duration(minutes: 1));

    expect(failures, 1);
    final pools = container.read(truenasPoolsProvider);
    expect(pools.isLoading, isFalse);
    expect(pools.error.toString(), contains('not configured'));
  });

  testWidgets('an http:// address fails into the https refusal at once', (
    tester,
  ) async {
    final container = _containerWith(
      const SettingsModel(
        instances: [
          ServiceInstance(
            id: 'truenas',
            service: ServiceKey.truenas,
            url: 'http://nas.local',
            credential: 'k',
          ),
        ],
      ),
    );
    container.listen(truenasPoolsProvider, (_, _) {});

    await tester.pump(_settle);

    final pools = container.read(truenasPoolsProvider);
    expect(pools.isLoading, isFalse);
    expect(pools.error, isA<TrueNasInsecureTransportException>());
  });
}
