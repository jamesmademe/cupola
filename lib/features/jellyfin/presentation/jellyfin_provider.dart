import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/features/jellyfin/data/jellyfin_client.dart';
import 'package:cupola/features/jellyfin/domain/models/jellyfin_models.dart';
import 'package:cupola/features/settings/data/connection_providers.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/stream/domain/models/stream_item.dart';
import 'package:cupola/features/stream/domain/models/stream_library.dart';
import 'package:cupola/features/stream/domain/models/stream_session.dart';
import 'package:cupola/features/stream/domain/stream_server_client.dart';
import 'package:cupola/core/providers/provider_retry.dart';

/// Jellyfin client bound to the current settings.
///
/// Throws if Jellyfin is not configured; widgets must check
/// `settings.isServiceConfigured(ServiceKey.jellyfin)` before reading. The throw
/// is a `ServiceNotConfigured`, which `AsyncValueWidget` answers with
/// `NotConfiguredPlaceholder` instead of an error.
///
/// Follows the **lens**, like every other service's client. It used to read the
/// flat `jellyfinUrl`/`jellyfinApiKey`/`jellyfinUserId` projections, which are
/// always the *first* connection, so a second Jellyfin could be configured,
/// probed and counted and never once read.
///
/// The chosen viewer is read here rather than passed per call, so picking a
/// different household member rebuilds this provider and invalidates every
/// dependent lens. That is why nothing downstream is keyed by viewer: the viewer
/// is part of *which client you are talking to*, not part of a query's identity.
/// It comes off the resolved instance for the same reason the address does:
/// two servers have two user tables.
///
/// `watchTransport`, not a bare `watch` of the whole `SettingsModel`, and that is
/// a correctness point rather than a micro-optimisation: this provider closes a
/// live `Dio` in `onDispose`, so rebuilding it cancels every in-flight Stream
/// request and invalidates every surface downstream. Watching the whole object
/// made a theme-mode toggle do exactly that.
final jellyfinClientProvider = _jellyfin.lens;

final jellyfinClientForProvider = _jellyfin.forConnection;

final _jellyfin = ConnectionProviders<JellyfinClient>.transport(
  ServiceKey.jellyfin,
  create: (ref, transport) {
    // The viewer is read from the **instance**, not from
    // `settings.jellyfinUserId`: that projection is the first connection's, so
    // following the lens without this would have every user-scoped query on the
    // second server carry a user id from the first server's user table, an id
    // that does not exist there.
    final viewerId = ref.watch(
      currentSettingsProvider.select(
        (s) => s.instanceById(transport.instanceId)?.viewerId ?? '',
      ),
    );
    return JellyfinClient(
      baseUrl: transport.url,
      apiKey: transport.apiKey,
      userId: viewerId,
      pinnedCertFingerprint: transport.pin,
      accessHeaders: transport.access.headers(),
      onlyAtHome: transport.onlyAtHomeOf(ServiceKey.jellyfin),
    );
  },
  close: (client) => client.close(),
);

/// The same client, seen through the interface the Stream surfaces are written
/// against.
///
/// Widgets should depend on this one: nothing above the data layer has any
/// business knowing whether it is talking to Jellyfin or Plex, and a screen that
/// takes the interface can be reused for both, which is the entire point of
/// having it. `cancelToken` now lives on `StreamServerClient` itself, so even the
/// cancellable per-item fetches below go through here; the concrete provider
/// stays public only for the Jellyfin-specific extras (`getViewers` filtering,
/// the raw item mapper) that genuinely have no cross-server meaning.
final jellyfinServerProvider = Provider<StreamServerClient>((ref) {
  return ref.watch(jellyfinClientProvider);
});

/// Everything playing right now, most expensive first.
///
/// Not polled from here: the dashboard owns its own refresh cadence the way
/// `torrentDetailPollingProvider` does, and a timer buried in a data provider
/// would keep firing behind a screen nobody is looking at.
final jellyfinSessionsProvider = FutureProvider<List<StreamSession>>((
  ref,
) async {
  return ref.watch(jellyfinServerProvider).getSessions();
  // `retry: noProviderRetry` below, because `streamActivityProvider` awaits
  // this inside a `try` written to carry on without a dark server, and it
  // walks the media servers one at a time, so ten backing-off retries here are
  // spent before Plex is even asked. See [noProviderRetry].
}, retry: noProviderRetry);

/// The libraries this server exposes.
///
/// `retry: noProviderRetry` from here down, for the reason
/// [jellyfinSessionsProvider] gives one step above: the default retry re-runs a
/// failed build ten times behind an exponential backoff and holds the future
/// until it has, so a server that has gone dark is a spinner for the better
/// part of a minute before any surface can say "unreachable" and offer the
/// Retry it already draws. (The "not configured" throw never needed the flag;
/// it reaches a watcher as a `ProviderException`, which `defaultRetry`
/// declines on its own.)
final jellyfinLibrariesProvider = FutureProvider<List<StreamLibrary>>((
  ref,
) async {
  return ref.watch(jellyfinServerProvider).getLibraries();
}, retry: noProviderRetry);

/// The server's own id, per connection: what a Jellyfin app needs to open an
/// item on it. Null while the server does not say.
final jellyfinServerIdProvider = FutureProvider.autoDispose
    .family<String?, String>((ref, instanceId) async {
      return ref.watch(jellyfinClientForProvider(instanceId)).publicServerId();
    }, retry: noProviderRetry);

/// The same list, from one named connection.
///
/// What the settings picker reads: it is filling in a viewer for the connection
/// whose form is on screen, and a user id is only meaningful against the server
/// that issued it. Empty id means the lens, which is what every caller meant
/// before Jellyfin could have two.
final jellyfinViewersForProvider =
    FutureProvider.family<List<StreamViewer>, String>((ref, instanceId) async {
      return ref.watch(jellyfinClientForProvider(instanceId)).getViewers();
    }, retry: noProviderRetry);

/// One item at any depth, by id.
///
/// Resolves from the id alone so `ServiceRoutes.jellyfinItem` works as a deep
/// link; `state.extra` stays preload/Hero data only.
///
/// `autoDispose` for two reasons: every item ever opened would otherwise be
/// retained forever, and the cancellation below would never fire.
final jellyfinItemProvider = FutureProvider.autoDispose
    .family<StreamItem?, String>((ref, itemId) async {
      final client = ref.watch(jellyfinServerProvider);
      final cancelToken = CancelToken();
      ref.onDispose(cancelToken.cancel);
      return client.getItem(itemId, cancelToken: cancelToken);
    }, retry: noProviderRetry);

/// The children of a series, season or album: seasons, episodes or tracks.
///
/// Empty for a leaf item, which the client answers without a request.
final jellyfinItemChildrenProvider = FutureProvider.autoDispose
    .family<List<StreamItem>, String>((ref, itemId) async {
      final client = ref.watch(jellyfinServerProvider);
      final cancelToken = CancelToken();
      ref.onDispose(cancelToken.cancel);
      return client.getChildren(itemId, cancelToken: cancelToken);
    }, retry: noProviderRetry);

/// The libraries with the transport failure preserved, for the surfaces that
/// state a **figure** rather than draw a board (the KPI rail).
///
/// Written when `getLibraries()` still answered an unreachable server with
/// `const []`, wrong for a counter, where `0 libraries` is a claim nobody
/// made. A provider rather than a call the KPI layer makes on the client: it
/// caches, invalidates with everything else, and can be overridden by name.
/// The sessions had a twin of this too; it went once both reads threw, because
/// two caches of one sessions read let the figure and Now playing disagree.
final jellyfinStrictLibrariesProvider = FutureProvider<List<StreamLibrary>>(
  (ref) => ref.watch(jellyfinClientProvider).getLibrariesOrThrow(),
  retry: noProviderRetry,
);

/// Which credential kind the lens connection's slot holds. Never fails: an
/// unanswered probe is [JellyfinCredentialKind.unknown].
///
/// `noProviderRetry`, because the tabs that read it wait on it before they
/// decide between their list and the administrator placeholder.
final jellyfinCredentialKindProvider = FutureProvider<JellyfinCredentialKind>(
  (ref) => ref.watch(jellyfinClientProvider).getCredentialKind(),
  retry: noProviderRetry,
);

/// Which credential kind one named connection's slot holds.
///
/// A credential is a connection's, not the service's: the Jellyfin at home
/// can hold an API key while the one at the cabin holds a household member's
/// token, and the surfaces that read every connection (Activity, the
/// figures) have to ask each one. The lens's own id, and the empty id,
/// collapse onto [jellyfinCredentialKindProvider], so the lens's pages and
/// those surfaces share one `/Users/Me`.
///
/// Not part of the capability layer, on purpose: that layer describes the
/// writes a credential may make, and a non-administrator loses reads.
final jellyfinCredentialKindForProvider =
    FutureProvider.family<JellyfinCredentialKind, String>((
      ref,
      instanceId,
    ) async {
      final lens =
          ref.watch(activeInstanceProvider(ServiceKey.jellyfin))?.id ?? '';
      if (instanceId.isEmpty || instanceId == lens) {
        return ref.watch(jellyfinCredentialKindProvider.future);
      }
      return ref
          .watch(jellyfinClientForProvider(instanceId))
          .getCredentialKind();
    }, retry: noProviderRetry);

/// Whether the elevated reads are known to be out of reach for the lens
/// connection. False while the probe is out and when it did not answer, so a
/// healthy administrator never sees the placeholder flash.
final jellyfinLacksAdministratorProvider = Provider<bool>(
  (ref) =>
      ref
          .watch(jellyfinCredentialKindProvider)
          .asData
          ?.value
          .lacksAdministrator ??
      false,
);

/// [jellyfinLacksAdministratorProvider], for one named connection. Same rule:
/// false until `/Users/Me` has said the token is a non-administrator's.
///
/// The lens's own id, and the empty id, collapse onto the plain provider, so
/// an override of either still reaches both.
final jellyfinLacksAdministratorForProvider = Provider.family<bool, String>((
  ref,
  instanceId,
) {
  final lens = ref.watch(activeInstanceProvider(ServiceKey.jellyfin))?.id ?? '';
  if (instanceId.isEmpty || instanceId == lens) {
    return ref.watch(jellyfinLacksAdministratorProvider);
  }
  return ref
          .watch(jellyfinCredentialKindForProvider(instanceId))
          .asData
          ?.value
          .lacksAdministrator ??
      false;
});

final jellyfinUsersProvider = FutureProvider<List<JellyfinUserDto>>((
  ref,
) async {
  return ref.watch(jellyfinClientProvider).getUsers();
}, retry: noProviderRetry);

final jellyfinDevicesProvider = FutureProvider<List<JellyfinDevice>>((
  ref,
) async {
  return ref.watch(jellyfinClientProvider).getDevices();
}, retry: noProviderRetry);

final jellyfinTasksProvider = FutureProvider<List<JellyfinScheduledTask>>((
  ref,
) async {
  return ref.watch(jellyfinClientProvider).getScheduledTasks();
}, retry: noProviderRetry);

/// [jellyfinUsersProvider] for one named connection; empty is the lens.
///
/// A visit that has a connection in view reads that connection's users on
/// every tab. The lens's own id collapses onto the plain provider, so an
/// override of either still reaches both, and so do the pages that read the
/// lens. `retry: noProviderRetry` for the reason the plain one carries it.
final jellyfinUsersForProvider =
    FutureProvider.family<List<JellyfinUserDto>, String>((
      ref,
      instanceId,
    ) async {
      final lens =
          ref.watch(activeInstanceProvider(ServiceKey.jellyfin))?.id ?? '';
      if (instanceId.isEmpty || instanceId == lens) {
        return ref.watch(jellyfinUsersProvider.future);
      }
      return ref.watch(jellyfinClientForProvider(instanceId)).getUsers();
    }, retry: noProviderRetry);

/// [jellyfinDevicesProvider] for one named connection; empty is the lens. See
/// [jellyfinUsersForProvider].
final jellyfinDevicesForProvider =
    FutureProvider.family<List<JellyfinDevice>, String>((
      ref,
      instanceId,
    ) async {
      final lens =
          ref.watch(activeInstanceProvider(ServiceKey.jellyfin))?.id ?? '';
      if (instanceId.isEmpty || instanceId == lens) {
        return ref.watch(jellyfinDevicesProvider.future);
      }
      return ref.watch(jellyfinClientForProvider(instanceId)).getDevices();
    }, retry: noProviderRetry);

/// [jellyfinTasksProvider] for one named connection; empty is the lens. See
/// [jellyfinUsersForProvider].
final jellyfinTasksForProvider =
    FutureProvider.family<List<JellyfinScheduledTask>, String>((
      ref,
      instanceId,
    ) async {
      final lens =
          ref.watch(activeInstanceProvider(ServiceKey.jellyfin))?.id ?? '';
      if (instanceId.isEmpty || instanceId == lens) {
        return ref.watch(jellyfinTasksProvider.future);
      }
      return ref
          .watch(jellyfinClientForProvider(instanceId))
          .getScheduledTasks();
    }, retry: noProviderRetry);
