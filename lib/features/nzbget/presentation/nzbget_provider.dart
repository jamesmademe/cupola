import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/providers/provider_retry.dart';
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
  return _nzbgetClient(ref, instanceId: null);
});

/// NZBGet client for an explicitly named connection.
///
/// Empty and active ids collapse to the ordinary lens-bound provider. Other
/// ids create one client that remains alive — including its request counter
/// and Dio transport — until Riverpod disposes this family entry.
final nzbgetClientForProvider = Provider.family<NzbgetClient, String>((
  ref,
  instanceId,
) {
  final activeId = ref.read(activeInstanceProvider(ServiceKey.nzbget))?.id;
  if (instanceId.isEmpty || instanceId == activeId) {
    return ref.watch(nzbgetClientProvider);
  }

  return _nzbgetClient(ref, instanceId: instanceId);
});

/// Builds one client against a named connection.
///
/// One builder rather than two copies, matching NPM, Plex, Jellyfin and Unraid
/// which landed beside this. The construction carries `certFingerprint`, which
/// ADR-6 makes load-bearing: two copies of it is two places to forget the pin,
/// and a client built without one silently stops trusting the certificate the
/// user accepted for that origin.
NzbgetClient _nzbgetClient(Ref ref, {required String? instanceId}) {
  // `watchTransport`, selected rather than watching the whole model: this
  // builder registers a dispose that closes a live Dio, so an unrelated
  // settings write must not rebuild it.
  final transport = watchTransport(
    ref,
    ServiceKey.nzbget,
    instanceId: instanceId,
  );
  if (!transport.configured) {
    throw Exception('NZBGet not configured');
  }
  final client = NzbgetClient(
    url: transport.url,
    username: transport.username.isEmpty ? null : transport.username,
    password: transport.apiKey.isEmpty ? null : transport.apiKey,
    certFingerprint: transport.pin,
    accessHeaders: transport.access.headers(),
  );
  ref.onDispose(client.close);
  return client;
}

/// Global download status.
///
/// The three reads below carry `retry: noProviderRetry`, and the reason is the
/// derivation rule rather than a screen: Riverpod's default re-runs a failed
/// build ten times behind an exponential backoff and **holds the future until
/// it has**, so a dark NZBGet spends forty seconds as a spinner before any
/// surface can draw its unreachable band or offer its own Retry. (The "not
/// configured" throw never needed the flag: it arrives as a `ProviderException`,
/// which `defaultRetry` declines on its own.)
final nzbgetStatusProvider = FutureProvider<NzbgetStatus>((ref) async {
  return ref.watch(nzbgetClientProvider).status();
}, retry: noProviderRetry);

/// The active download queue.
final nzbgetQueueProvider = FutureProvider<List<NzbgetGroup>>((ref) async {
  return ref.watch(nzbgetClientProvider).listGroups();
}, retry: noProviderRetry);

/// Recent completed/failed downloads.
final nzbgetHistoryProvider = FutureProvider<List<NzbgetHistoryItem>>((
  ref,
) async {
  return ref.watch(nzbgetClientProvider).history();
}, retry: noProviderRetry);

final nzbgetFeedsProvider = FutureProvider<List<NzbgetFeed>>((ref) async {
  return ref.watch(nzbgetClientProvider).feeds();
}, retry: noProviderRetry);

final nzbgetMessagesProvider = FutureProvider<List<NzbgetMessage>>((ref) async {
  return ref.watch(nzbgetClientProvider).messages();
}, retry: noProviderRetry);
