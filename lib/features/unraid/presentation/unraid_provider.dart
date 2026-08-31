import 'package:flutter_riverpod/flutter_riverpod.dart';

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
  );
  ref.onDispose(() => client.close());
  return client;
});

/// Storage array status.
final unraidArrayProvider = FutureProvider<UnraidArray>((ref) async {
  return ref.watch(unraidClientProvider).getArray();
});

/// Docker containers.
final unraidDockerProvider = FutureProvider<List<UnraidDockerContainer>>((
  ref,
) async {
  return ref.watch(unraidClientProvider).getDockerContainers();
});
