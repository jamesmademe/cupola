import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/providers/provider_retry.dart';
import 'package:cupola/features/sabnzbd/data/sabnzbd_client.dart';
import 'package:cupola/features/sabnzbd/domain/models/sabnzbd_models.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// SABnzbd client bound to the current settings.
///
/// Throws if SABnzbd is not configured; widgets must check
/// `settings.isServiceConfigured(ServiceKey.sabnzbd)` before reading.
final sabnzbdClientProvider = Provider<SabnzbdClient>((ref) {
  // Selected rather than watching the whole model: this provider closes a live
  // Dio on dispose, so an unrelated settings write must not rebuild it.
  return _sabnzbdClient(ref, instanceId: null);
});

/// SABnzbd client for an explicitly named connection.
///
/// The empty and active ids reuse [sabnzbdClientProvider], keeping the legacy
/// lens path on one live Dio. A non-active id owns one client for the lifetime
/// of this family entry and is closed when that entry is disposed.
final sabnzbdClientForProvider = Provider.family<SabnzbdClient, String>((
  ref,
  instanceId,
) {
  final activeId = ref.read(activeInstanceProvider(ServiceKey.sabnzbd))?.id;
  if (instanceId.isEmpty || instanceId == activeId) {
    return ref.watch(sabnzbdClientProvider);
  }

  return _sabnzbdClient(ref, instanceId: instanceId);
});

/// Builds one client against a named connection.
///
/// One builder rather than two copies, matching NPM, Plex, Jellyfin and Unraid
/// which landed beside this. The construction carries `certFingerprint`, which
/// ADR-6 makes load-bearing: two copies of it is two places to forget the pin,
/// and a client built without one silently stops trusting the certificate the
/// user accepted for that origin.
SabnzbdClient _sabnzbdClient(Ref ref, {required String? instanceId}) {
  // `watchTransport`, selected rather than watching the whole model: this
  // builder registers a dispose that closes a live Dio, so an unrelated
  // settings write must not rebuild it.
  final transport = watchTransport(
    ref,
    ServiceKey.sabnzbd,
    instanceId: instanceId,
  );
  if (!transport.configured) {
    throw Exception('SABnzbd not configured');
  }
  final client = SabnzbdClient(
    url: transport.url,
    apiKey: transport.apiKey,
    certFingerprint: transport.pin,
  );
  ref.onDispose(client.close);
  return client;
}

/// The current download queue.
///
/// All four reads below carry `retry: noProviderRetry`, for the reason
/// [nzbgetStatusProvider] states: the default retry holds the future through
/// ten backing-off attempts, so a dark SABnzbd is a spinner for forty seconds
/// instead of an unreachable band with a Retry on it.
final sabnzbdQueueProvider = FutureProvider<SabnzbdQueue>((ref) async {
  return ref.watch(sabnzbdClientProvider).getQueue();
}, retry: noProviderRetry);

/// Recent completed/failed downloads.
final sabnzbdHistoryProvider = FutureProvider<List<SabnzbdHistorySlot>>((
  ref,
) async {
  return ref.watch(sabnzbdClientProvider).getHistory();
}, retry: noProviderRetry);

/// Aggregate transfer statistics (total downloaded, etc.).
final sabnzbdServerStatsProvider = FutureProvider<SabnzbdServerStats>((
  ref,
) async {
  return ref.watch(sabnzbdClientProvider).getServerStats();
}, retry: noProviderRetry);

final sabnzbdServersProvider = FutureProvider<List<SabnzbdServerConfig>>((
  ref,
) async {
  return ref.watch(sabnzbdClientProvider).getServers();
}, retry: noProviderRetry);

/// The configured categories, for the add-NZB dialog.
final sabnzbdCategoriesProvider = FutureProvider<List<String>>((ref) async {
  return ref.watch(sabnzbdClientProvider).getCategories();
}, retry: noProviderRetry);
