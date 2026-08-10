import 'package:flutter_riverpod/flutter_riverpod.dart';

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
  final transport = ref.watch(
    currentSettingsProvider.select(
      (s) => (
        configured: s.isServiceConfigured(ServiceKey.sabnzbd),
        url: s.sabnzbdUrl,
        apiKey: s.sabnzbdApiKey,
        pin: s.pinForUrl(s.sabnzbdUrl),
      ),
    ),
  );
  if (!transport.configured) {
    throw Exception('SABnzbd not configured');
  }
  final client = SabnzbdClient(
    url: transport.url,
    apiKey: transport.apiKey,
    certFingerprint: transport.pin,
  );
  ref.onDispose(() => client.close());
  return client;
});

/// The current download queue.
final sabnzbdQueueProvider = FutureProvider<SabnzbdQueue>((ref) async {
  return ref.watch(sabnzbdClientProvider).getQueue();
});

/// Recent completed/failed downloads.
final sabnzbdHistoryProvider = FutureProvider<List<SabnzbdHistorySlot>>((
  ref,
) async {
  return ref.watch(sabnzbdClientProvider).getHistory();
});

/// Aggregate transfer statistics (total downloaded, etc.).
final sabnzbdServerStatsProvider = FutureProvider<SabnzbdServerStats>((
  ref,
) async {
  return ref.watch(sabnzbdClientProvider).getServerStats();
});

/// The configured categories, for the add-NZB dialog.
final sabnzbdCategoriesProvider = FutureProvider<List<String>>((ref) async {
  return ref.watch(sabnzbdClientProvider).getCategories();
});
