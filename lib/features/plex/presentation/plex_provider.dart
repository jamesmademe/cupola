import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/features/plex/data/plex_client.dart';
import 'package:cupola/features/plex/domain/models/plex_models.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';
import 'package:cupola/features/stream/domain/models/stream_item.dart';
import 'package:cupola/features/stream/domain/models/stream_library.dart';
import 'package:cupola/features/stream/domain/models/stream_session.dart';
import 'package:cupola/features/stream/domain/stream_server_client.dart';
import 'package:cupola/core/providers/provider_retry.dart';

/// Plex client bound to the current settings.
///
/// Throws if Plex is not configured; widgets must check
/// `settings.isServiceConfigured(ServiceKey.plex)` before reading. The exact
/// `'not configured'` wording is load-bearing — `AsyncValueWidget` matches on it
/// to render `NotConfiguredPlaceholder` instead of an error.
///
/// Follows the **lens**. It used to read the flat `plexUrl`/`plexToken`
/// projections, which are always the *first* connection, so a second Plex could
/// be configured and never read.
///
/// `plexClientId` deliberately stays off the lens and is **shared by every Plex
/// connection**: it identifies this *install*, not any one server, so two
/// servers each see one device for this app. Minting a per-connection id is what
/// would litter the user's admin panel with a second device row, which is why
/// [SettingsModel.plexClientId] is not on `ServiceInstance` and why
/// `SettingsService` mints it exactly once.
///
/// `watchTransport` rather than a bare watch of the whole `SettingsModel`, for
/// the same reason `jellyfinClientProvider` does it: this provider closes a live
/// `Dio` in `onDispose`, so any rebuild kills in-flight requests and cascades an
/// invalidation through every Stream surface. Watching the whole settings object
/// meant a theme-mode toggle did that.
final plexClientProvider = Provider<PlexClient>((ref) {
  return _plexClient(ref, instanceId: null);
});

/// Plex bound to one named connection, whatever the lens is pointing at.
///
/// The dashboard's folded matrix has to ask a second Plex for its own figures;
/// reading [plexClientProvider] there would silently answer with the lens's
/// server under the other connection's label. The lens's own id collapses back
/// onto the plain provider so tests and screens keep one client per active
/// connection.
final plexClientForProvider = Provider.family<PlexClient, String>((
  ref,
  instanceId,
) {
  final lens = ref.read(activeInstanceProvider(ServiceKey.plex))?.id ?? '';
  if (instanceId.isEmpty || instanceId == lens) {
    return ref.watch(plexClientProvider);
  }
  return _plexClient(ref, instanceId: instanceId);
});

PlexClient _plexClient(Ref ref, {required String? instanceId}) {
  final transport = watchTransport(
    ref,
    ServiceKey.plex,
    instanceId: instanceId,
  );
  final clientId = ref.watch(
    currentSettingsProvider.select((s) => s.plexClientId),
  );
  if (!transport.configured) {
    throw Exception('Plex not configured');
  }
  final client = PlexClient(
    url: transport.url,
    token: transport.apiKey,
    clientIdentifier: clientId,
    pinnedCertFingerprint: transport.pin,
  );
  ref.onDispose(client.close);
  return client;
}

/// The same client, seen through the interface the Stream surfaces are written
/// against.
///
/// The Jellyfin side has always had this; Plex was missing it, which meant a
/// screen meant to serve both servers had to name one of them. Nothing above the
/// data layer should know which media server it is talking to — that is the whole
/// reason `StreamServerClient` exists.
final plexServerProvider = Provider<StreamServerClient>((ref) {
  return ref.watch(plexClientProvider);
});

/// `GET /` — friendly name, version, and the Plex Pass flag that decides whether
/// a "stop stream" affordance is offered at all.
final plexCapabilitiesProvider = FutureProvider<PlexServerCapabilities?>((
  ref,
) async {
  return ref.watch(plexClientProvider).getCapabilities();
  // No automatic retry, for the reason [jellyfinLibrariesProvider] gives: the
  // default one holds the future through ten backing-off attempts, so a dark
  // Plex is a spinner rather than an unreachable band with a Retry on it.
}, retry: noProviderRetry);

/// Everything playing right now, most expensive first.
///
/// Not self-polling: the Stream board owns its own refresh cadence, and a timer
/// here would keep hitting `/status/sessions` while the user is three screens
/// away. `ref.invalidate(plexSessionsProvider)` is the refresh.
final plexSessionsProvider = FutureProvider<List<StreamSession>>((ref) async {
  return ref.watch(plexClientProvider).getSessions();
  // No automatic retry, for the reason [jellyfinSessionsProvider] gives.
}, retry: noProviderRetry);

/// The libraries ("sections") this server exposes.
final plexLibrariesProvider = FutureProvider<List<StreamLibrary>>((ref) async {
  return ref.watch(plexClientProvider).getLibraries();
}, retry: noProviderRetry);

/// One item at any depth — film, show, season, episode, album or track.
final plexItemProvider = FutureProvider.autoDispose.family<StreamItem?, String>(
  (ref, ratingKey) async {
    return ref.watch(plexClientProvider).getItem(ratingKey);
  },
  retry: noProviderRetry,
);

/// The children of a show, season or album.
final plexChildrenProvider = FutureProvider.autoDispose
    .family<List<StreamItem>, String>((ref, ratingKey) async {
      return ref.watch(plexClientProvider).getChildren(ratingKey);
    }, retry: noProviderRetry);

/// Sessions with the transport failure preserved, for the surfaces that state
/// a **figure** rather than draw a board.
///
/// Written when `getSessions()` still answered an unreachable server with
/// `const []` — wrong for a counter, where `0 streams` is a claim nobody made,
/// and, it turned out, wrong for the board too. Both now throw; the KPI rail
/// and the reachability signal keep reading this one.
///
/// It is a provider and not a call the KPI layer makes on the client itself,
/// which is the part worth keeping: read straight off the client, every rebuild
/// of an `autoDispose` rail was a fresh `/status/sessions` on the wire, the Overview's
/// own copy of the same request could not be shared with it, and a fake client
/// was the only thing a test could substitute. A provider caches, invalidates
/// with everything else, and can be overridden by name.
final plexStrictSessionsProvider = FutureProvider<List<StreamSession>>(
  (ref) => ref.watch(plexClientProvider).getSessionsOrThrow(),
  retry: noProviderRetry,
);

/// The libraries, with the failure preserved. See
/// [plexStrictSessionsProvider] for why this exists beside
/// [plexLibrariesProvider] rather than replacing it.
final plexStrictLibrariesProvider = FutureProvider<List<StreamLibrary>>(
  (ref) => ref.watch(plexClientProvider).getLibrariesOrThrow(),
  retry: noProviderRetry,
);

final plexOnDeckTabProvider = FutureProvider<List<StreamItem>>((ref) async {
  return ref.watch(plexClientProvider).getContinueWatching(count: 100);
}, retry: noProviderRetry);

final plexDevicesProvider = FutureProvider<List<PlexDevice>>((ref) async {
  return ref.watch(plexClientProvider).getDevices();
}, retry: noProviderRetry);

final plexPlaylistsProvider = FutureProvider<List<PlexPlaylist>>((ref) async {
  return ref.watch(plexClientProvider).getPlaylists();
}, retry: noProviderRetry);
