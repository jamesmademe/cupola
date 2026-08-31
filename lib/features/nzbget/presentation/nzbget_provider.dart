import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/features/nzbget/data/nzbget_client.dart';
import 'package:cupola/features/nzbget/domain/models/nzbget_models.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// NZBGet client bound to the current settings.
///
/// Throws if NZBGet is not configured; widgets must check
/// `settings.isServiceConfigured(ServiceKey.nzbget)` before reading.
final nzbgetClientProvider = Provider<NzbgetClient>((ref) {
  // Selected rather than watching the whole model: this provider closes a live
  // Dio on dispose, so an unrelated settings write must not rebuild it.
  final transport = watchTransport(ref, ServiceKey.nzbget);
  if (!transport.configured) {
    throw Exception('NZBGet not configured');
  }
  final client = NzbgetClient(
    url: transport.url,
    username: transport.username.isEmpty ? null : transport.username,
    password: transport.apiKey.isEmpty ? null : transport.apiKey,
    certFingerprint: transport.pin,
  );
  ref.onDispose(() => client.close());
  return client;
});

/// Global download status.
final nzbgetStatusProvider = FutureProvider<NzbgetStatus>((ref) async {
  return ref.watch(nzbgetClientProvider).status();
});

/// The active download queue.
final nzbgetQueueProvider = FutureProvider<List<NzbgetGroup>>((ref) async {
  return ref.watch(nzbgetClientProvider).listGroups();
});

/// Recent completed/failed downloads.
final nzbgetHistoryProvider = FutureProvider<List<NzbgetHistoryItem>>((
  ref,
) async {
  return ref.watch(nzbgetClientProvider).history();
});
