import 'package:flutter_riverpod/flutter_riverpod.dart';

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
/// domain APIs below watches this single client, so they all follow with it —
/// the breadth of the surface was never the obstacle it looked like.
///
/// Moving the lens tears the socket down and opens another, which is exactly
/// what editing the address already did.
final truenasClientProvider = Provider<TrueNasWsClient>((ref) {
  final transport = watchTransport(ref, ServiceKey.truenas);
  if (!transport.configured) {
    throw const TrueNasException('TrueNAS not configured');
  }
  final client = TrueNasWsClient(
    baseUrl: transport.url,
    apiKey: transport.apiKey,
    certFingerprint: transport.pin,
  );
  ref.onDispose(client.close);
  return client;
});

/// TrueNAS client bound to one configured connection id.
///
/// Empty and active ids collapse to the lens client so callers do not open a
/// second WebSocket for the same NAS. A non-active id bypasses the lens and is
/// disposed with its own WebSocket when the family entry is released.
final truenasClientForProvider = Provider.family<TrueNasWsClient, String>((
  ref,
  instanceId,
) {
  final activeId =
      ref.read(activeInstanceProvider(ServiceKey.truenas))?.id ?? '';
  if (instanceId.isEmpty || instanceId == activeId) {
    return ref.watch(truenasClientProvider);
  }
  return _truenasClient(ref, instanceId: instanceId);
});

TrueNasWsClient _truenasClient(Ref ref, {required String? instanceId}) {
  final transport = watchTransport(
    ref,
    ServiceKey.truenas,
    instanceId: instanceId,
  );
  if (!transport.configured) {
    throw const TrueNasException('TrueNAS not configured');
  }
  final client = TrueNasWsClient(
    baseUrl: transport.url,
    apiKey: transport.apiKey,
    certFingerprint: transport.pin,
  );
  ref.onDispose(client.close);
  return client;
}

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
});

/// The dashboard snapshot (system, pools, alerts, services).
final truenasDashboardProvider = FutureProvider.autoDispose((ref) async {
  // Keep the client alive for the life of this fetch.
  ref.watch(truenasClientProvider);
  return ref.watch(truenasServiceProvider).loadDashboard();
});
