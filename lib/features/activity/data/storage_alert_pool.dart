/// The pool behind a TrueNAS alert about a disk: what a scrub would repair,
/// and how far one that runs has got.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/lifecycle/gated_poll.dart';
import 'package:cupola/core/providers/provider_retry.dart';
import 'package:cupola/features/truenas/data/storage_api.dart';
import 'package:cupola/features/truenas/domain/models/pool.dart';
import 'package:cupola/features/truenas/presentation/truenas_provider.dart';

/// Which disk of which TrueNAS connection.
typedef StorageAlertDisk = ({String instanceId, String disk});

/// The pool holding [StorageAlertDisk.disk], with its topology, read on the
/// TrueNAS that raised the alert; null when no pool holds a disk by that
/// name (a spare, a disk since replaced).
final storageAlertPoolProvider = FutureProvider.autoDispose
    .family<TrueNasPool?, StorageAlertDisk>((ref, key) async {
      final api = TrueNasStorageApi(
        ref.watch(truenasClientForProvider(key.instanceId)),
      );
      for (final pool in await api.getPools()) {
        final whole = pool.hasTopology ? pool : await api.getPool(pool.name);
        if (whole?.memberNamed(key.disk) != null) return whole;
      }
      return null;
    }, retry: noProviderRetry);

/// How often a running scan is read again.
const storageScanInterval = Duration(minutes: 1);

/// The poll of a running scan, for the card to watch while the scan runs and
/// the page is on screen (`watchWhileLive`).
final storageScanPollProvider = Provider.autoDispose
    .family<void, StorageAlertDisk>((ref, key) {
      ref.gatedPoll(
        id: 'activity.scan.${key.instanceId}.${key.disk}',
        interval: storageScanInterval,
        onTick: () => ref.invalidate(storageAlertPoolProvider(key)),
      );
    });
