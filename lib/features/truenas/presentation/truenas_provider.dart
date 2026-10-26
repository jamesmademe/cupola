import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/network/network_change.dart';
import 'package:cupola/core/providers/provider_retry.dart';
import 'package:cupola/features/settings/data/connection_providers.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/truenas/data/apps_api.dart';
import 'package:cupola/features/truenas/data/credentials_api.dart';
import 'package:cupola/features/truenas/data/data_protection_api.dart';
import 'package:cupola/features/truenas/data/dataset_api.dart';
import 'package:cupola/features/truenas/data/network_api.dart';
import 'package:cupola/features/truenas/data/reporting_api.dart';
import 'package:cupola/features/truenas/data/sharing_api.dart';
import 'package:cupola/features/truenas/data/storage_api.dart';
import 'package:cupola/features/truenas/data/system_api.dart';
import 'package:cupola/features/truenas/data/truenas_service.dart';
import 'package:cupola/features/truenas/data/truenas_ws_client.dart';
import 'package:cupola/features/truenas/data/virt_api.dart';
import 'package:cupola/features/truenas/domain/truenas_version.dart';

/// Long-lived WebSocket client for TrueNAS, rebuilt when the connection it
/// describes changes. Closed automatically when disposed.
///
/// Follows the **lens**. It used to read the flat `truenasUrl`/`truenasApiKey`
/// projections, which are always the *first* connection, so a second NAS could
/// be configured, probed and counted and never once read. Every one of the eight
/// domain APIs below watches this single client, so they all follow with it:
/// the breadth of the surface was never the obstacle it looked like.
///
/// Moving the lens tears the socket down and opens another, which is exactly
/// what editing the address already did.
///
/// ## Retry: none, anywhere in this feature
///
/// Every TrueNAS provider (this one, [truenasClientForProvider] and each
/// `FutureProvider` under `presentation/`) carries `retry: noProviderRetry`.
/// Riverpod's default re-runs a failed build ten times over roughly forty
/// seconds, and for all of that time the provider reports *loading*, so a NAS
/// that went dark drew a skeleton that never resolved instead of the offline
/// well and its Retry. A section's own poll made it worse: each tick
/// invalidated the provider, which cancelled the pending retry and started the
/// count again, so the error state was never reached at all. Retrying is the
/// user's call here: every well offers Retry and pull-to-refresh, and both
/// invalidate the provider that failed. Nothing here derives from another
/// `FutureProvider`, so a Retry always re-runs the call that failed.
///
/// The client throws "not configured" from this build, and would be retried
/// for it like any other `Exception`: a condition no waiting changes.
final truenasClientProvider = _truenas.lens;

final truenasClientForProvider = _truenas.forConnection;

final _truenas = ConnectionProviders<TrueNasWsClient>.transport(
  ServiceKey.truenas,
  retry: noProviderRetry,
  create: (ref, transport) {
    // A network change may have left the open socket half-open: the next call
    // pings it rather than waiting out the call timeout. Listened to, never
    // watched, so the client is not rebuilt (and its socket closed) by it.
    // Every client of the pair, the named connection's included.
    final client = TrueNasWsClient(
      baseUrl: transport.url,
      apiKey: transport.apiKey,
      certFingerprint: transport.pin,
      accessHeaders: transport.access.headers(),
      onlyAtHome: transport.onlyAtHomeOf(ServiceKey.truenas),
    );
    ref.listen(networkChangesProvider, (_, _) => client.markSuspect());
    return client;
  },
  close: (client) => client.close(),
);

final truenasServiceProvider = Provider<TrueNasService>((ref) {
  return TrueNasService(ref.watch(truenasClientProvider));
});

/// Dashboard facade bound to one configured TrueNAS connection id.
final truenasServiceForProvider = Provider.family<TrueNasService, String>((
  ref,
  instanceId,
) {
  final activeId =
      ref.read(activeInstanceProvider(ServiceKey.truenas))?.id ?? '';
  if (instanceId.isEmpty || instanceId == activeId) {
    return ref.watch(truenasServiceProvider);
  }
  return TrueNasService(ref.watch(truenasClientForProvider(instanceId)));
});

// ── Domain-grouped API providers ───────────────────────────────────────────
final truenasSystemApiProvider = Provider<TrueNasSystemApi>(
  (ref) => TrueNasSystemApi(ref.watch(truenasClientProvider)),
);
final truenasStorageApiProvider = Provider<TrueNasStorageApi>(
  (ref) => TrueNasStorageApi(ref.watch(truenasClientProvider)),
);
final truenasDatasetApiProvider = Provider<TrueNasDatasetApi>(
  (ref) => TrueNasDatasetApi(ref.watch(truenasClientProvider)),
);
final truenasSharingApiProvider = Provider<TrueNasSharingApi>(
  (ref) => TrueNasSharingApi(ref.watch(truenasClientProvider)),
);
final truenasDataProtectionApiProvider = Provider<TrueNasDataProtectionApi>(
  (ref) => TrueNasDataProtectionApi(ref.watch(truenasClientProvider)),
);
final truenasVirtApiProvider = Provider<TrueNasVirtApi>(
  (ref) => TrueNasVirtApi(ref.watch(truenasClientProvider)),
);
final truenasAppsApiProvider = Provider<TrueNasAppsApi>(
  (ref) => TrueNasAppsApi(ref.watch(truenasClientProvider)),
);
final truenasReportingApiProvider = Provider<TrueNasReportingApi>(
  (ref) => TrueNasReportingApi(ref.watch(truenasClientProvider)),
);
final truenasNetworkApiProvider = Provider<TrueNasNetworkApi>(
  (ref) => TrueNasNetworkApi(ref.watch(truenasClientProvider)),
);
final truenasCredentialsApiProvider = Provider<TrueNasCredentialsApi>(
  (ref) => TrueNasCredentialsApi(ref.watch(truenasClientProvider)),
);

/// The connected server's parsed version, or null if unavailable/unparseable.
final truenasVersionProvider = FutureProvider.autoDispose<TrueNasVersion?>((
  ref,
) async {
  final raw = await ref.watch(truenasSystemApiProvider).getVersion();
  return TrueNasVersion.parse(raw);
}, retry: noProviderRetry);

/// The dashboard snapshot (system, pools, alerts, services).
final truenasDashboardProvider = FutureProvider.autoDispose((ref) async {
  // Keep the client alive for the life of this fetch.
  ref.watch(truenasClientProvider);
  return ref.watch(truenasServiceProvider).loadDashboard();
}, retry: noProviderRetry);
