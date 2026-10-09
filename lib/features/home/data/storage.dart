/// What Storage reads: the pools of every TrueNAS and the array of every
/// Unraid, together.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/providers/provider_retry.dart';
import 'package:cupola/features/discover/presentation/library_calendar_provider.dart'
    show calendarClockProvider;
import 'package:cupola/features/home/domain/storage.dart';
import 'package:cupola/features/services/domain/source_coverage.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/truenas/data/truenas_service.dart';
import 'package:cupola/features/truenas/presentation/truenas_provider.dart';
import 'package:cupola/features/unraid/presentation/unraid_provider.dart';

/// How often Storage is read again while the Home is seen.
const homeStorageInterval = Duration(seconds: 60);

/// The pools, in connection order, and which connections answered.
typedef HomeStorage = ({List<StoragePool> pools, SourceCoverage coverage});

/// Every TrueNAS asked for its pools and every Unraid for its array, at once.
///
/// A pool TrueNAS does not call healthy is read once more with its topology,
/// the only answer that names the disk in trouble; a healthy one never is.
final homeStorageProvider = FutureProvider.autoDispose<HomeStorage>((
  ref,
) async {
  final settings = ref.watch(currentSettingsProvider);
  final now = ref.watch(calendarClockProvider)();
  final reads = <Future<(List<StoragePool>, SourceCoverage)>>[];

  SourceCoverage answered(ServiceKey service, String id) =>
      SourceCoverage.answeredBy(
        service,
        instanceId: id,
        name: settings.connectionName(id),
      );
  SourceCoverage failed(ServiceKey service, String id, Object error) =>
      SourceCoverage.failure(
        service,
        error,
        instanceId: id,
        name: settings.connectionName(id),
      );

  for (final instance in settings.configuredInstancesOf(ServiceKey.truenas)) {
    final id = instance.id;
    // Kept alive for the read: a connection beside the lens has a socket
    // of its own.
    final service = TrueNasService(ref.watch(truenasClientForProvider(id)));
    reads.add(
      _truenasPools(service, instanceId: id, now: now).then(
        (pools) => (pools, answered(ServiceKey.truenas, id)),
        onError: (Object error) =>
            (const <StoragePool>[], failed(ServiceKey.truenas, id, error)),
      ),
    );
  }
  for (final instance in settings.configuredInstancesOf(ServiceKey.unraid)) {
    final id = instance.id;
    reads.add(
      ref
          .watch(unraidClientForProvider(id))
          .getArray()
          .then(
            (array) => (
              [storagePoolOfUnraid(array, instanceId: id)],
              answered(ServiceKey.unraid, id),
            ),
            onError: (Object error) =>
                (const <StoragePool>[], failed(ServiceKey.unraid, id, error)),
          ),
    );
  }

  final answers = await Future.wait(reads);
  return (
    pools: [for (final (pools, _) in answers) ...pools],
    coverage: SourceCoverage.merge([for (final (_, c) in answers) c]),
  );
}, retry: noProviderRetry);

Future<List<StoragePool>> _truenasPools(
  TrueNasService service, {
  required String instanceId,
  required DateTime now,
}) async {
  final pools = await service.getPools();
  final read = await Future.wait([
    for (final pool in pools)
      if (pool.healthy && pool.status.toUpperCase() == 'ONLINE')
        Future.value(pool)
      else
        // The topology is a second thought: without it the pool still says
        // its state, only not which disk.
        service
            .getPool(pool.name)
            .then((whole) => whole ?? pool, onError: (Object _) => pool),
  ]);
  return [
    for (final pool in read)
      storagePoolOfTrueNas(pool, instanceId: instanceId, now: now),
  ];
}
