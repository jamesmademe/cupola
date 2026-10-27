import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/lifecycle/gated_poll.dart';

import 'package:cupola/core/providers/provider_retry.dart';
import 'package:cupola/core/status/read_clock.dart';

import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/data/connection_providers.dart';
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
final transmissionClientProvider = _transmission.lens;

final transmissionClientForProvider = _transmission.forConnection;

final _transmission = ConnectionProviders<TransmissionClient>.transport(
  ServiceKey.transmission,
  create: (ref, transport) => TransmissionClient(
    url: transport.url,
    username: transport.usernameOrNull,
    password: transport.secretOrNull,
    certFingerprint: transport.pin,
    accessHeaders: transport.access.headers(),
    onlyAtHome: transport.onlyAtHomeOf(ServiceKey.transmission),
  ),
  close: (client) => client.close(),
);

/// Every torrent the daemon knows about.
///
/// Noted as read (`ReadClock`) right after the answer lands, for the connection
/// this build resolved, so a page that keeps this list under a fault band can
/// say how old it is.
final transmissionTorrentsProvider = FutureProvider<List<TransmissionTorrent>>((
  ref,
) async {
  final client = ref.watch(transmissionClientProvider);
  final noteRead = ref.queueReadNoter(ServiceKey.transmission);
  // Only the queue's poll reads a delta; every other read is the whole list.
  final torrents = await client.torrentsSynced();
  noteRead();
  return torrents;
}, retry: noProviderRetry);

/// Aggregate counters: speeds and torrent counts.
final transmissionStatsProvider = FutureProvider<TransmissionStats>((
  ref,
) async {
  return ref.watch(transmissionClientProvider).stats();
}, retry: noProviderRetry);

/// Daemon settings: version, global limits, turtle mode.
final transmissionSessionProvider = FutureProvider<TransmissionSession>((
  ref,
) async {
  return ref.watch(transmissionClientProvider).session();
}, retry: noProviderRetry);

/// The queue's live refresh, for as long as the queue is the page on screen
/// (`watchWhileLive`): every three seconds, as qBittorrent's, and never over a
/// read still in flight, which a black-holed host would otherwise keep
/// restarting before it could fail. Without it the queue stayed as it was
/// opened, a stopped container's downloads still `Downloading`.
final transmissionPollingProvider = Provider.autoDispose<void>((ref) {
  ref.gatedPoll(
    id: 'transmission.queue',
    interval: const Duration(seconds: 3),
    onTick: () {
      // This read may be a delta: the list's own three-second read, asked for
      // with only what moved, and in full every half minute.
      ref.read(transmissionClientProvider).allowDeltaRead();
      ref.readAgainUnlessInFlight([
        transmissionTorrentsProvider,
        transmissionStatsProvider,
        transmissionSessionProvider,
      ]);
      // The page's band reads the probe: asked on its own, so a list stuck
      // in flight does not hold back the word that the server went quiet.
      readProbeAgainUnlessInFlight(ref, ServiceKey.transmission);
    },
  );
});
