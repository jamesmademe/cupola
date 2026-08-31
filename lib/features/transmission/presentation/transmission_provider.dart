import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/transmission/data/transmission_client.dart';
import 'package:cupola/features/transmission/domain/models/transmission_models.dart';

/// Transmission client bound to the current settings.
///
/// Throws if Transmission is not configured; widgets must check
/// `settings.isServiceConfigured(ServiceKey.transmission)` before reading.
///
/// Deliberately **one long-lived client per configuration** rather than one per
/// call. Two pieces of state make that load-bearing: the CSRF session id, which
/// costs an extra round trip to relearn, and the sticky credentials-rejected
/// flag, which is what stops a polling screen from spending the daemon's
/// hundred allowed login failures and locking the user out until they restart
/// it. A fresh client per request would throw both away every tick.
final transmissionClientProvider = Provider<TransmissionClient>((ref) {
  // `watchTransport`, which is the same narrow select this used to spell out by
  // hand plus the one thing the hand-written version could not do: follow the
  // lens. Spelled out here, the four fields resolved to `transmissionUrl` and
  // friends — the FIRST connection — so moving the lens to the seedbox changed
  // the badge in the app bar and nothing else. The label said one daemon and
  // every torrent on screen came from the other.
  final transport = watchTransport(ref, ServiceKey.transmission);
  if (!transport.configured) {
    throw Exception('Transmission not configured');
  }
  final client = TransmissionClient(
    url: transport.url,
    username: transport.username.isEmpty ? null : transport.username,
    password: transport.apiKey.isEmpty ? null : transport.apiKey,
    certFingerprint: transport.pin,
  );
  ref.onDispose(() => client.close());
  return client;
});

/// Every torrent the daemon knows about.
final transmissionTorrentsProvider = FutureProvider<List<TransmissionTorrent>>((
  ref,
) async {
  return ref.watch(transmissionClientProvider).torrents();
});

/// Aggregate counters — speeds and torrent counts.
final transmissionStatsProvider = FutureProvider<TransmissionStats>((
  ref,
) async {
  return ref.watch(transmissionClientProvider).stats();
});

/// Daemon settings: version, global limits, turtle mode.
final transmissionSessionProvider = FutureProvider<TransmissionSession>((
  ref,
) async {
  return ref.watch(transmissionClientProvider).session();
});
