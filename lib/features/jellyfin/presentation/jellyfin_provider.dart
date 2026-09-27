import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/features/jellyfin/data/jellyfin_client.dart';
import 'package:cupola/features/jellyfin/domain/models/jellyfin_models.dart';
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
/// `settings.isServiceConfigured(ServiceKey.jellyfin)` before reading. The
/// `'not configured'` substring is load-bearing — `AsyncValueWidget` string-matches
/// it to render `NotConfiguredPlaceholder` instead of an error.
///
/// Follows the **lens**, like every other service's client. It used to read the
/// flat `jellyfinUrl`/`jellyfinApiKey`/`jellyfinUserId` projections, which are
/// always the *first* connection — so a second Jellyfin could be configured,
/// probed and counted and never once read.
///
/// The chosen viewer is read here rather than passed per call, so picking a
/// different household member rebuilds this provider and invalidates every
/// dependent lens. That is why nothing downstream is keyed by viewer: the viewer
/// is part of *which client you are talking to*, not part of a query's identity.
/// It comes off the resolved instance for the same reason the address does —
/// two servers have two user tables.
///
/// `watchTransport`, not a bare `watch` of the whole `SettingsModel`, and that is
/// a correctness point rather than a micro-optimisation: this provider closes a
/// live `Dio` in `onDispose`, so rebuilding it cancels every in-flight Stream
/// request and invalidates every surface downstream. Watching the whole object
/// made a theme-mode toggle do exactly that.
final jellyfinClientProvider = Provider<JellyfinClient>((ref) {
  return _jellyfinClient(ref, instanceId: null);
});

/// Jellyfin bound to one named connection, whatever the lens is pointing at.
///
/// The same shape as `radarrServiceForProvider` — read its comment before
/// touching this one. What it buys here is the settings form: the viewer picker
/// lists `/Users` of the connection being edited, which is not necessarily the
/// one the rest of the app is reading through, and a user id only means anything
/// against the server that issued it.
///
/// The lens's own id collapses onto [jellyfinClientProvider] rather than opening
/// a second socket to the same server — and so an override of the plain provider
/// is not quietly bypassed on the path that names a connection. `read` of the
/// lens for the same reason the \*arr families give: watching it would rebuild
/// every entry whenever the lens moved, and a rebuild closes the outgoing `Dio`
/// under whatever it was carrying.
final jellyfinClientForProvider = Provider.family<JellyfinClient, String>((
  ref,
  instanceId,
) {
  final lens = ref.read(activeInstanceProvider(ServiceKey.jellyfin))?.id ?? '';
  if (instanceId.isEmpty || instanceId == lens) {
    return ref.watch(jellyfinClientProvider);
  }
  return _jellyfinClient(ref, instanceId: instanceId);
});

/// Builds a client for one connection: the lens's when [instanceId] is null.
///
/// The viewer is read from the **instance**, not from `settings.jellyfinUserId`.
/// That projection is the first connection's, so following the lens without this
/// would have every user-scoped query on the second server carry a user id from
/// the first server's user table — an id that does not exist there.
JellyfinClient _jellyfinClient(Ref ref, {required String? instanceId}) {
  final transport = watchTransport(
    ref,
    ServiceKey.jellyfin,
    instanceId: instanceId,
  );
  if (!transport.configured) {
    throw Exception('Jellyfin not configured');
  }
  final viewerId = ref.watch(
    currentSettingsProvider.select(
      (s) => s.instanceById(transport.instanceId)?.viewerId ?? '',
    ),
  );
  final client = JellyfinClient(
    baseUrl: transport.url,
    apiKey: transport.apiKey,
    userId: viewerId,
    pinnedCertFingerprint: transport.pin,
  );
  ref.onDispose(client.close);
  return client;
}

/// The same client, seen through the interface the Stream surfaces are written
/// against.
///
/// Widgets should depend on this one: nothing above the data layer has any
/// business knowing whether it is talking to Jellyfin or Plex, and a screen that
/// takes the interface can be reused for both — which is the entire point of
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
  // this inside a `try` written to carry on without a dark server — and it
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
/// Retry it already draws. (The "not configured" throw never needed the flag —
/// it reaches a watcher as a `ProviderException`, which `defaultRetry`
/// declines on its own.)
final jellyfinLibrariesProvider = FutureProvider<List<StreamLibrary>>((
  ref,
) async {
  return ref.watch(jellyfinServerProvider).getLibraries();
}, retry: noProviderRetry);

/// Household members whose watch state a library can be read through.
///
/// Sourced from `/Users`, which is the only place a user id exists: the API key
/// authenticates as an administrator with no user attached, so this list is what
/// the settings picker fills `jellyfinUserId` from.
final jellyfinViewersProvider = FutureProvider<List<StreamViewer>>((ref) async {
  return ref.watch(jellyfinServerProvider).getViewers();
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

/// The children of a series, season or album — seasons, episodes or tracks.
///
/// Empty for a leaf item, which the client answers without a request.
final jellyfinItemChildrenProvider = FutureProvider.autoDispose
    .family<List<StreamItem>, String>((ref, itemId) async {
      final client = ref.watch(jellyfinServerProvider);
      final cancelToken = CancelToken();
      ref.onDispose(cancelToken.cancel);
      return client.getChildren(itemId, cancelToken: cancelToken);
    }, retry: noProviderRetry);

/// Sessions with the transport failure preserved, for the surfaces that state
/// a **figure** rather than draw a board.
///
/// `getSessions()` answers an unreachable server with `const []`, which is
/// right for a browse — a dark server is a quiet empty board — and wrong for a
/// counter, where `0 streams` is a claim nobody made. The KPI rail and the
/// reachability signal read this instead.
///
/// It is a provider and not a call the KPI layer makes on the client itself,
/// which is the part worth keeping: read straight off the client, every rebuild
/// of an `autoDispose` rail was a fresh `/Sessions` on the wire, the Overview's
/// own copy of the same request could not be shared with it, and a fake client
/// was the only thing a test could substitute. A provider caches, invalidates
/// with everything else, and can be overridden by name.
final jellyfinStrictSessionsProvider = FutureProvider<List<StreamSession>>(
  (ref) => ref.watch(jellyfinClientProvider).getSessionsOrThrow(),
  retry: noProviderRetry,
);

/// The libraries, with the failure preserved. See
/// [jellyfinStrictSessionsProvider] for why this exists beside
/// [jellyfinLibrariesProvider] rather than replacing it.
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
