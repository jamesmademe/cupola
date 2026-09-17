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
  final transport = watchTransport(ref, ServiceKey.plex);
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
});

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
