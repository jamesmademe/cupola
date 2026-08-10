import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/features/jellyfin/data/jellyfin_client.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/stream/domain/models/stream_item.dart';
import 'package:cupola/features/stream/domain/models/stream_library.dart';
import 'package:cupola/features/stream/domain/models/stream_session.dart';
import 'package:cupola/features/stream/domain/stream_server_client.dart';

/// Jellyfin client bound to the current settings.
///
/// Throws if Jellyfin is not configured; widgets must check
/// `settings.isServiceConfigured(ServiceKey.jellyfin)` before reading. The
/// `'not configured'` substring is load-bearing — `AsyncValueWidget` string-matches
/// it to render `NotConfiguredPlaceholder` instead of an error.
///
/// `jellyfinUserId` is read here rather than passed per call, so choosing a
/// different household member in settings rebuilds this provider and invalidates
/// every dependent lens. That is why nothing downstream is keyed by viewer: the
/// viewer is part of *which client you are talking to*, not part of a query's
/// identity.
/// Field-by-field `select`, not a bare `watch` of the whole `SettingsModel`, and
/// that is a correctness point rather than a micro-optimisation: this provider
/// closes a live `Dio` in `onDispose`, so rebuilding it cancels every in-flight
/// Stream request and invalidates every surface downstream. Watching the whole
/// object made a theme-mode toggle do exactly that. Same shape as
/// `truenasClientProvider`.
final jellyfinClientProvider = Provider<JellyfinClient>((ref) {
  final url = ref.watch(currentSettingsProvider.select((s) => s.jellyfinUrl));
  final apiKey = ref.watch(
    currentSettingsProvider.select((s) => s.jellyfinApiKey),
  );
  final userId = ref.watch(
    currentSettingsProvider.select((s) => s.jellyfinUserId),
  );
  final certFingerprint = ref.watch(
    currentSettingsProvider.select((s) => s.pinForUrl(s.jellyfinUrl)),
  );
  if (url.isEmpty || apiKey.isEmpty) {
    throw Exception('Jellyfin not configured');
  }
  final client = JellyfinClient(
    baseUrl: url,
    apiKey: apiKey,
    userId: userId,
    pinnedCertFingerprint: certFingerprint,
  );
  ref.onDispose(client.close);
  return client;
});

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
});

/// The libraries this server exposes.
final jellyfinLibrariesProvider = FutureProvider<List<StreamLibrary>>((
  ref,
) async {
  return ref.watch(jellyfinServerProvider).getLibraries();
});

/// Household members whose watch state a library can be read through.
///
/// Sourced from `/Users`, which is the only place a user id exists: the API key
/// authenticates as an administrator with no user attached, so this list is what
/// the settings picker fills `jellyfinUserId` from.
final jellyfinViewersProvider = FutureProvider<List<StreamViewer>>((ref) async {
  return ref.watch(jellyfinServerProvider).getViewers();
});

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
    });

/// The children of a series, season or album — seasons, episodes or tracks.
///
/// Empty for a leaf item, which the client answers without a request.
final jellyfinItemChildrenProvider = FutureProvider.autoDispose
    .family<List<StreamItem>, String>((ref, itemId) async {
      final client = ref.watch(jellyfinServerProvider);
      final cancelToken = CancelToken();
      ref.onDispose(cancelToken.cancel);
      return client.getChildren(itemId, cancelToken: cancelToken);
    });
