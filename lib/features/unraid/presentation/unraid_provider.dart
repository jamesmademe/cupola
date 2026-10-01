import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/providers/provider_retry.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/unraid/data/unraid_client.dart';
import 'package:cupola/features/unraid/domain/models/unraid_models.dart';

/// Unraid client bound to the current settings.
///
/// Throws if Unraid is not configured; widgets must check
/// `settings.isServiceConfigured(ServiceKey.unraid)` before reading.
final unraidClientProvider = Provider<UnraidClient>((ref) {
  // Selected rather than watching the whole model: this provider closes a live
  // Dio on dispose, so an unrelated settings write must not rebuild it.
  final transport = watchTransport(ref, ServiceKey.unraid);
  if (!transport.configured) {
    throw Exception('Unraid not configured');
  }
  final client = UnraidClient(
    url: transport.url,
    apiKey: transport.apiKey,
    certFingerprint: transport.pin,
    accessHeaders: transport.access.headers(),
  );
  ref.onDispose(() => client.close());
  return client;
});

/// Unraid client bound to one configured connection id.
///
/// Empty and active ids collapse to the lens client. Explicit non-active ids
/// resolve their own transport and own their Dio lifecycle independently.
final unraidClientForProvider = Provider.family<UnraidClient, String>((
  ref,
  instanceId,
) {
  final activeId =
      ref.read(activeInstanceProvider(ServiceKey.unraid))?.id ?? '';
  if (instanceId.isEmpty || instanceId == activeId) {
    return ref.watch(unraidClientProvider);
  }
  return _unraidClient(ref, instanceId: instanceId);
});

UnraidClient _unraidClient(Ref ref, {required String? instanceId}) {
  final transport = watchTransport(
    ref,
    ServiceKey.unraid,
    instanceId: instanceId,
  );
  if (!transport.configured) {
    throw Exception('Unraid not configured');
  }
  final client = UnraidClient(
    url: transport.url,
    apiKey: transport.apiKey,
    certFingerprint: transport.pin,
    accessHeaders: transport.access.headers(),
  );
  ref.onDispose(client.close);
  return client;
}

/// Storage array status.
///
/// `retry: noProviderRetry`, like every other document this service reads.
/// Riverpod's default re-runs a throwing build ten times on a backoff climbing
/// to a 6.4s ceiling — roughly forty seconds during which this provider has not
/// settled, so nothing awaiting `.future` has either. The Overview folds this
/// into a section beside one folded from `info`, which already refused the
/// backoff: with the default here, an unreachable Unraid reported its System
/// region in one round trip while Array and Docker sat in a skeleton for the
/// rest of the minute. Three regions of one page, two failure clocks.
///
/// Nothing is lost by refusing it. Every surface that reads this one — the two
/// Overview sections, the Array and Docker tabs, and the pull-to-refresh above
/// all of them — offers a Retry that invalidates it, so recovery is a gesture
/// rather than a timer nobody can see.
final unraidArrayProvider = FutureProvider<UnraidArray>((ref) async {
  return ref.watch(unraidClientProvider).getArray();
}, retry: noProviderRetry);

/// Docker containers. `noProviderRetry` for the reason [unraidArrayProvider]
/// states — these two are read side by side and must fail on one clock.
final unraidDockerProvider = FutureProvider<List<UnraidDockerContainer>>((
  ref,
) async {
  return ref.watch(unraidClientProvider).getDockerContainers();
}, retry: noProviderRetry);

final unraidVmsProvider = FutureProvider<List<UnraidVm>>((ref) async {
  return ref.watch(unraidClientProvider).getVms();
}, retry: noProviderRetry);

final unraidNotificationsProvider = FutureProvider<UnraidNotifications>((
  ref,
) async {
  return ref.watch(unraidClientProvider).getNotifications();
}, retry: noProviderRetry);

final unraidSharesProvider = FutureProvider<List<UnraidShare>>((ref) async {
  return ref.watch(unraidClientProvider).getShares();
}, retry: noProviderRetry);
