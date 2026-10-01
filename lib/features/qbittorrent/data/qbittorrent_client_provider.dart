import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderFamily;

import 'package:cupola/features/qbittorrent/data/qbittorrent_client.dart';
import 'package:cupola/features/qbittorrent/data/qbittorrent_refusal_store.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// The one qBittorrent client of each connection, keyed by the connection's id.
///
/// One client per connection, and everything that talks to that connection
/// goes through it: the qBittorrent pages, Home's reads of every connection,
/// the Dashboard's probe and the Settings readouts. The client carries the
/// login state, and a refused sign-in is held on it (see [QbittorrentClient])
/// and, for the connection, in [qbittorrentRefusalStoreProvider].
/// A probe that built a client of its own sent the login again on every
/// refresh, so with a wrong password each pull, each theme toggle that
/// rebuilt a readout and each "Test all" counted toward qBittorrent's ban of
/// the address (five failures by default, an hour each).
///
/// Rebuilt, and the outgoing client closed, only when this connection's own
/// address, credentials, access or pinned certificate change: new credentials
/// are what lift a held refusal on their own. An empty id means the connection
/// the lens is on, resolved to that connection's entry, never a second client
/// for it.
final ProviderFamily<QbittorrentClient, String> qbittorrentClientForProvider =
    Provider.family<QbittorrentClient, String>((ref, instanceId) {
      if (instanceId.isEmpty) {
        final lens = ref.watch(
          activeInstanceProvider(
            ServiceKey.qbittorrent,
          ).select((instance) => instance?.id ?? ''),
        );
        if (lens.isEmpty) throw Exception('qBittorrent not configured');
        return ref.watch(qbittorrentClientForProvider(lens));
      }

      final transport = watchTransport(
        ref,
        ServiceKey.qbittorrent,
        instanceId: instanceId,
      );
      if (!transport.configured) {
        throw Exception('qBittorrent not configured');
      }
      final client = QbittorrentClient(
        url: transport.url,
        username: transport.username.isNotEmpty ? transport.username : null,
        password: transport.apiKey.isNotEmpty ? transport.apiKey : null,
        certFingerprint: transport.pin,
        accessHeaders: transport.access.headers(),
        // The refusal is the connection's, kept where the next client of it
        // (the next launch, a check in the background) reads it first.
        connectionId: instanceId,
        refusalStore: ref.watch(qbittorrentRefusalStoreProvider),
      );
      // The outgoing client owns a Dio and a cookie jar; close it so neither
      // leaks.
      ref.onDispose(client.close);
      return client;
    });

/// Where every connection's refused qBittorrent sign-in is kept
/// ([QbittorrentRefusalStore]).
///
/// In memory unless startup overrides it with the secure-storage store, as
/// `main.dart` does, so a refusal outlives the run. A test that stands up no
/// storage still gets one store per container, shared by every client in it.
final qbittorrentRefusalStoreProvider = Provider<QbittorrentRefusalStore>(
  (ref) => MemoryQbittorrentRefusalStore(),
);

/// Lets the next call of each of [connectionIds] sign in again, after a held
/// refusal.
///
/// For a **user's** explicit ask at the failure only: a Retry beside it, or a
/// connection test. Never from a poll tick or a refresh: a timer, or a pull
/// that re-reads everything, that lifted the hold would be the loop that gets
/// the address banned. Ids that name no configured qBittorrent are skipped.
void liftQbittorrentRefusals(WidgetRef ref, Iterable<String> connectionIds) {
  final settings = ref.read(currentSettingsProvider);
  for (final id in connectionIds) {
    final instance = settings.instanceById(id);
    if (instance == null ||
        instance.service != ServiceKey.qbittorrent ||
        !instance.isConfigured) {
      continue;
    }
    ref.read(qbittorrentClientForProvider(id)).clearLoginRefusal();
  }
}
