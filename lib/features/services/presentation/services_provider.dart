import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/providers/provider_retry.dart';
import 'package:cupola/core/api/api_client.dart';
import 'package:cupola/core/api/base_arr_service.dart';
import 'package:cupola/core/capability/role_gate_provider.dart';
import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/status/arr_queue_snapshot.dart';
import 'package:cupola/core/status/lexicon.dart';
import 'package:cupola/core/status/media_names.dart';
import 'package:cupola/core/utils/arr_activity_display.dart';
import 'package:cupola/core/utils/dynamic_map_utils.dart';
import 'package:cupola/core/utils/image_utils.dart';
import 'package:cupola/features/dockge/data/dockge_client.dart';
import 'package:cupola/features/jellyfin/data/jellyfin_client.dart';
import 'package:cupola/features/plex/data/plex_client.dart';
import 'package:cupola/features/dockge/data/dockge_service.dart';
import 'package:cupola/features/nzbget/data/nzbget_client.dart';
import 'package:cupola/features/nzbget/presentation/nzbget_provider.dart';
import 'package:cupola/features/readarr/presentation/readarr_provider.dart';
import 'package:cupola/features/sabnzbd/data/sabnzbd_client.dart';
import 'package:cupola/features/sabnzbd/presentation/sabnzbd_provider.dart';
import 'package:cupola/features/discover/domain/seerr_grant.dart';
import 'package:cupola/features/discover/presentation/discover_provider.dart';
import 'package:cupola/features/discover/data/seerr_service.dart';
import 'package:cupola/features/discover/data/seerr_session.dart';
import 'package:cupola/features/movies/data/radarr_service.dart';
import 'package:cupola/features/movies/presentation/movies_provider.dart';
import 'package:cupola/features/music/data/lidarr_service.dart';
import 'package:cupola/features/music/domain/lidarr_queue_snapshots.dart';
import 'package:cupola/features/music/domain/models/lidarr_album.dart';
import 'package:cupola/features/music/presentation/music_provider.dart';
import 'package:cupola/features/series/data/sonarr_service.dart';
import 'package:cupola/features/series/domain/sonarr_queue_snapshots.dart';
import 'package:cupola/features/series/presentation/series_provider.dart';
import 'package:cupola/features/qbittorrent/data/qbittorrent_client_provider.dart';
import 'package:cupola/features/qbittorrent/domain/models/parse_utils.dart';
import 'package:cupola/features/qbittorrent/presentation/qbittorrent_provider.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/features/discover/domain/models/seerr_request.dart';
import 'package:cupola/features/dockge/domain/models/dockge_stack.dart';
import 'package:cupola/features/dockge/presentation/dockge_provider.dart';
import 'package:cupola/features/npm/domain/models/npm_models.dart';
import 'package:cupola/features/npm/presentation/npm_provider.dart';
import 'package:cupola/features/prowlarr/domain/models/prowlarr_models.dart';
import 'package:cupola/features/prowlarr/presentation/prowlarr_provider.dart';
import 'package:cupola/features/services/domain/arr_import.dart';
import 'package:cupola/features/services/domain/dashboard_decision.dart';
import 'package:cupola/features/services/domain/download_client_faults.dart';
import 'package:cupola/features/services/domain/download_join.dart';
import 'package:cupola/features/services/domain/download_names.dart';
import 'package:cupola/features/services/domain/in_flight.dart';
import 'package:cupola/features/services/domain/recently_added.dart';
import 'package:cupola/features/services/domain/request_ordering.dart';
import 'package:cupola/features/services/domain/service_signal.dart';
import 'package:cupola/features/services/domain/service_summary.dart';
import 'package:cupola/features/services/domain/source_coverage.dart';
import 'package:cupola/features/services/presentation/service_kpi_provider.dart';
import 'package:cupola/features/settings/data/service_status_probe.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/connection_access.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';
import 'package:cupola/features/npm/data/npm_client.dart';
import 'package:cupola/features/transmission/data/transmission_client.dart';
import 'package:cupola/features/transmission/presentation/transmission_provider.dart';
import 'package:cupola/features/truenas/data/truenas_service.dart';
import 'package:cupola/features/truenas/data/truenas_ws_client.dart';
import 'package:cupola/features/unraid/data/unraid_client.dart';

/// A live reachability probe for one service.
///
/// The `select` is load-bearing rather than a micro-optimisation, because of
/// what this provider *is*: one family entry per service, each of which opens a
/// connection and waits out a 5–8 second timeout ([_loadVersion] builds a fresh
/// SABnzbd/NZBGet/Unraid client per call). Watching the whole
/// `SettingsModel` meant that every settings write — a theme-mode toggle
/// included — re-probed every service, and a single Save can write twice
/// because answering the cert-trust prompt writes again. Keyed on the service's
/// own connection details, only the service that actually changed re-probes.
/// The ids of every connection of [service], in order, as a stable value.
///
/// Joined and re-split rather than selected as a `List`: `instancesOf` builds a
/// fresh one on every call and lists compare by identity, so selecting one
/// would rebuild every consumer on every unrelated settings write.
final serviceInstanceIdsProvider = Provider.family<List<String>, ServiceKey>((
  ref,
  service,
) {
  final joined = ref.watch(
    currentSettingsProvider.select(
      (s) => s.instancesOf(service).map((i) => i.id).join(','),
    ),
  );
  return joined.isEmpty ? const [] : joined.split(',');
});

/// Health for a service folded across all of its connections.
///
/// [offline] is what the matrix needs and what a per-service probe cannot say:
/// with three Radarr and one unreachable, "online" is a lie and "offline" is a
/// different one. The cell reports the worst state it contains and how many are
/// in it, so a folded card never claims to be healthier than its worst
/// connection.
///
/// `offline` counts the connections that **did not answer**, and nothing else.
/// `faulted` counts the ones that answered with a refusal or a fault — a
/// refused key, a 5xx — which are amber, and which the band that names what
/// did not answer must never name.
typedef FoldedServiceHealth = ({
  int total,
  int offline,
  int faulted,
  int checking,
});

final foldedServiceHealthProvider =
    Provider.family<FoldedServiceHealth, ServiceKey>((ref, service) {
      final ids = ref.watch(serviceInstanceIdsProvider(service));
      var offline = 0;
      var faulted = 0;
      var checking = 0;
      for (final id in ids) {
        final summary = ref.watch(
          instanceSummaryProvider((service: service, instanceId: id)),
        );
        switch (summary) {
          case AsyncData(:final value):
            if (value.didNotAnswer) offline++;
            // A Seerr account that signed out was asked nothing and is the
            // person's step: beside a working connection it is no fault.
            if (value.isFault &&
                value.failureReason != ServiceFailureReason.sessionEnded) {
              faulted++;
            }
          case AsyncError(:final error):
            if (failureDidNotAnswer(classifyConnectionFailure(error))) {
              offline++;
            } else {
              faulted++;
            }
          default:
            checking++;
        }
      }
      return (
        total: ids.length,
        offline: offline,
        faulted: faulted,
        checking: checking,
      );
    });

/// One connection, named by what it is as well as by which one.
///
/// The service travels with the id so a probe for a connection that has since
/// been removed can still say what kind of thing it was. Keyed on the id alone,
/// the "gone" branch had nothing to answer with and named `ServiceKey.radarr` —
/// a Plex cell removed mid-flight reported an offline *Radarr*.
typedef InstanceRef = ({ServiceKey service, String instanceId});

/// A live reachability probe for one *connection*.
///
/// Keyed by connection, because two Radarr behind two addresses are two
/// different answers to "is it up" and the matrix has to be able to say which
/// one is down. [serviceSummaryProvider] is the per-service view of this.
final instanceSummaryProvider =
    FutureProvider.family<ServiceSummary, InstanceRef>((ref, key) async {
      // Watch the narrow key; read the whole model for the work. The
      // per-client branches in [_loadVersion] each reach for their own fields,
      // and none of them is anything but a projection of the key below.
      ref.watch(
        currentSettingsProvider.select(
          (s) => _connectionOfInstance(s, key.instanceId),
        ),
      );
      final settings = ref.read(currentSettingsProvider);
      final instance = settings.instanceById(key.instanceId);
      if (instance == null) {
        return _offlineSummary(key.service, host: '');
      }
      return _loadServiceSummary(ref, instance, settings);
    });

/// The health of the connection [service] is currently seen through.
///
/// Delegates rather than probing: a screen asking "is Prowlarr up" means the
/// Prowlarr it is reading, which is the lens's, not whichever happens to be
/// first. Two dozen call sites keep their shape and quietly become lens-aware.
final serviceSummaryProvider =
    FutureProvider.family<ServiceSummary, ServiceKey>((ref, service) async {
      final instance = ref.watch(activeInstanceProvider(service));
      if (instance == null) {
        return _offlineSummary(
          service,
          host:
              service.extractHost(
                ref.read(currentSettingsProvider).urlFor(service),
              ) ??
              '',
        );
      }
      return ref.watch(
        instanceSummaryProvider((
          service: service,
          instanceId: instance.id,
        )).future,
      );
    });

/// Everything a status probe reads about one service, as a single comparable
/// value.
///
/// A record, so `select` gets structural equality for free. The password is not
/// a separate field on purpose: `SettingsModel.passwordFor` *is* `apiKeyFor` for
/// the credential-authenticated services, so [apiKey] already covers it.
typedef _ServiceConnection = ({
  bool configured,
  String url,
  String apiKey,
  String username,
  String? certFingerprint,
  ConnectionAccess access,

  /// A Seerr account's session: signing in again probes again.
  String session,
});

/// One configured connection a merged Home region reads, and what its rows
/// and its coverage are stamped with.
///
/// [name] is the connection's name by the app's one rule, null while its
/// service has a single connection; [connection] is what the reads need of it
/// (the poster URLs carry its address and key).
typedef _MergeConnection = ({
  ServiceKey service,
  String instanceId,
  String? name,
  bool isLens,
  _ServiceConnection connection,
});

/// Every configured connection of [service], in the user's order, for a
/// region that reads them all.
///
/// Home folds every connection of a service, the way its header does: a
/// stall, a failed import or a request on the second Radarr is the user's as
/// much as one on the first. Each connection is watched on its own narrow
/// key, so editing one re-reads it and a theme toggle re-reads nothing. The
/// lens is watched too, because which connection the shared lens providers
/// stand for moves with it.
List<_MergeConnection> _watchMergeConnections(Ref ref, ServiceKey service) {
  final ids = ref.watch(serviceInstanceIdsProvider(service));
  final lens = ref.watch(activeInstanceProvider(service))?.id ?? '';
  final merged = <_MergeConnection>[];
  for (final id in ids) {
    final connection = ref.watch(
      currentSettingsProvider.select((s) => _connectionOfInstance(s, id)),
    );
    if (!connection.configured) continue;
    merged.add((
      service: service,
      instanceId: id,
      name: ref.watch(connectionNameProvider(id)),
      isLens: id == lens,
      connection: connection,
    ));
  }
  return merged;
}

_ServiceConnection _connectionOfInstance(
  SettingsModel settings,
  String instanceId,
) {
  final instance = settings.instanceById(instanceId);
  if (instance == null) {
    return (
      configured: false,
      url: '',
      apiKey: '',
      username: '',
      certFingerprint: null,
      access: const NoAccess(),
      session: '',
    );
  }
  return (
    configured: instance.isConfigured,
    url: instance.url,
    apiKey: instance.credential,
    username: instance.username,
    certFingerprint: settings.pinForUrl(instance.url),
    access: instance.access,
    session: instance.account?.session ?? '',
  );
}

typedef ServiceStatusClientFactory =
    ApiClient Function({
      required String baseUrl,
      required String apiKey,
      String? pinnedCertFingerprint,
      Map<String, String> accessHeaders,
    });

final serviceStatusClientFactoryProvider = Provider<ServiceStatusClientFactory>(
  (ref) =>
      ({
        required String baseUrl,
        required String apiKey,
        String? pinnedCertFingerprint,
        Map<String, String> accessHeaders = const {},
      }) => ApiClient(
        baseUrl: baseUrl,
        apiKey: apiKey,
        pinnedCertFingerprint: pinnedCertFingerprint,
        accessHeaders: accessHeaders,
      ),
);

Future<ServiceSummary> _loadServiceSummary(
  Ref ref,
  ServiceInstance instance,
  SettingsModel settings,
) async {
  final service = instance.service;
  final host = service.extractHost(instance.url) ?? '';
  if (!instance.isConfigured) {
    // Signed out is not a dark box: nothing was asked, and the one step left
    // is the person's own. Read as the ended session, blue.
    if (instance.isSignedOut) {
      return ServiceSummary.failed(
        service,
        host: host,
        error: const SeerrSessionEnded(),
      );
    }
    return _offlineSummary(service, host: host);
  }

  final String? version;
  try {
    version = await _loadVersion(ref, settings, instance);
  } catch (error) {
    // Classified, never flattened: a refused key is the service answering, and
    // painting it with the same red as a box that is switched off sent people
    // to check a cable when the fix was the key in the form.
    return ServiceSummary.failed(service, host: host, error: error);
  }

  return ServiceSummary(
    service: service,
    status: ServiceSummaryStatus.online,
    host: host,
    version: version,
  );
}

ServiceSummary _offlineSummary(ServiceKey service, {required String host}) {
  return ServiceSummary(
    service: service,
    status: ServiceSummaryStatus.offline,
    host: host,
    version: null,
  );
}

Future<String?> _loadVersion(
  Ref ref,
  SettingsModel settings,
  ServiceInstance instance,
) async {
  final service = instance.service;
  if (service == ServiceKey.qbittorrent) {
    // The connection's own client, never a throwaway one. A probe that built
    // its own sent the login again on every refresh, so with a wrong password
    // each pull counted toward qBittorrent's ban of the address. The shared
    // client holds a refused sign-in until the credentials change or a user's
    // Retry lifts it, and it is not this probe's to close.
    final client = ref.watch(qbittorrentClientForProvider(instance.id));
    // Login-then-version is two hops on a cold client, so this gets the same
    // headroom as Transmission's 409 handshake pair.
    return _versionOrNull(
      client.getVersion,
      timeout: const Duration(seconds: 8),
      close: () {},
    );
  }

  // The two long-lived clients, and the two that used to lie. Their providers
  // are built from the flat projections — the FIRST instance of the service —
  // so probing the second connection through them asked the first one whether
  // it was up and painted the answer on the second one's cell: a box that was
  // switched off reading green, and `foldedServiceHealthProvider` counting zero
  // offline. The branches below build a throwaway client from `instance`,
  // which is what makes a per-connection probe per-connection; these two now
  // do the same, and close it either way like the rest. (qBittorrent, above,
  // reads its connection's own client, which is per connection too.)
  if (service == ServiceKey.truenas) {
    final client = TrueNasWsClient(
      baseUrl: instance.url,
      apiKey: instance.credential,
      certFingerprint: settings.pinForUrl(instance.url),
      accessHeaders: instance.access.headers(),
    );
    return _versionOrNull(
      () async => (await TrueNasService(client).getSystemInfo()).version ?? '',
      timeout: const Duration(seconds: 8),
      close: client.close,
    );
  }

  if (service == ServiceKey.dockge) {
    final client = DockgeClient(
      baseUrl: instance.url,
      username: instance.username.isEmpty ? null : instance.username,
      password: instance.credential.isEmpty ? null : instance.credential,
      certFingerprint: settings.pinForUrl(instance.url),
      accessHeaders: instance.access.headers(),
    );
    return _versionOrNull(
      () async => await DockgeService(client).fetchVersion() ?? '',
      timeout: const Duration(seconds: 8),
      close: client.close,
    );
  }

  if (service == ServiceKey.sabnzbd) {
    final client = SabnzbdClient(
      url: instance.url,
      apiKey: instance.credential,
      certFingerprint: settings.pinForUrl(instance.url),
      accessHeaders: instance.access.headers(),
    );
    // Keyed, not `mode=version`: that one needs no key, and a probe that
    // cannot see a wrong key paints it as answering. Two hops, hence the room.
    return _versionOrNull(
      client.checkKeyAndVersion,
      timeout: const Duration(seconds: 6),
      close: client.close,
    );
  }

  // The two media servers, through their own clients: each authenticates with
  // a header the shared `ApiClient` does not send, and each one's status route
  // is anonymous, so the generic branch below read any token as answering.
  if (service == ServiceKey.jellyfin) {
    final client = JellyfinClient(
      baseUrl: instance.url,
      apiKey: instance.credential,
      pinnedCertFingerprint: settings.pinForUrl(instance.url),
      accessHeaders: instance.access.headers(),
    );
    return _versionOrNull(
      () async => await client.checkCredentialAndVersion() ?? '',
      timeout: const Duration(seconds: 6),
      close: client.close,
    );
  }

  if (service == ServiceKey.plex) {
    final client = PlexClient(
      url: instance.url,
      token: instance.credential,
      clientIdentifier: settings.plexClientId,
      pinnedCertFingerprint: settings.pinForUrl(instance.url),
      accessHeaders: instance.access.headers(),
    );
    return _versionOrNull(
      () async => await client.checkCredentialAndVersion() ?? '',
      timeout: const Duration(seconds: 6),
      close: client.close,
    );
  }

  if (service == ServiceKey.nzbget) {
    final client = NzbgetClient(
      url: instance.url,
      username: instance.username.isEmpty ? null : instance.username,
      password: instance.credential.isEmpty ? null : instance.credential,
      certFingerprint: settings.pinForUrl(instance.url),
      accessHeaders: instance.access.headers(),
    );
    return _versionOrNull(
      client.version,
      timeout: const Duration(seconds: 5),
      close: client.close,
    );
  }

  if (service == ServiceKey.transmission) {
    final client = TransmissionClient(
      url: instance.url,
      username: instance.username.isEmpty ? null : instance.username,
      password: instance.credential.isEmpty ? null : instance.credential,
      certFingerprint: settings.pinForUrl(instance.url),
      accessHeaders: instance.access.headers(),
    );
    // Two hops on a cold client — the 409 handshake, then the real call — so
    // this gets the same headroom as qBittorrent's login-then-version pair.
    return _versionOrNull(
      client.version,
      timeout: const Duration(seconds: 8),
      close: client.close,
    );
  }

  if (service == ServiceKey.nginxProxyManager) {
    final client = NpmClient(
      url: instance.url,
      identity: instance.username.isEmpty ? null : instance.username,
      secret: instance.credential.isEmpty ? null : instance.credential,
      certFingerprint: settings.pinForUrl(instance.url),
      accessHeaders: instance.access.headers(),
    );
    // `GET /api/` is unauthenticated, so on its own it read a wrong password
    // as answering. The token exchange is what proves the account, and it is
    // paid once per probe: this provider is keyed on the connection's own
    // fields, so it re-runs when this connection changes or is re-checked, not
    // on every settings write.
    return _versionOrNull(
      client.checkCredentialAndVersion,
      timeout: const Duration(seconds: 8),
      close: client.close,
    );
  }

  if (service == ServiceKey.unraid) {
    final client = UnraidClient(
      url: instance.url,
      apiKey: instance.credential,
      certFingerprint: settings.pinForUrl(instance.url),
      accessHeaders: instance.access.headers(),
    );
    return _versionOrNull(
      client.version,
      timeout: const Duration(seconds: 6),
      close: client.close,
    );
  }

  final url = instance.url;
  if (service == ServiceKey.seerr) {
    // Seerr's own client: the key or the account's session, never a client
    // that knows only the key.
    final client = ref.watch(seerrClientFactoryProvider)(
      instance,
      pinnedCertFingerprint: settings.pinForUrl(url),
      // A session the probe finds ended is emptied, as any request's is.
      events: seerrAccountEvents(ref, instance.id),
    );
    try {
      // Seerr's status endpoint is public. Probe one authenticated request
      // first, otherwise a wrong API key paints the dashboard green while
      // Activity and Overview fail with 403 later.
      await SeerrService(
        client,
      ).testConnection().timeout(const Duration(seconds: 5));
      return await readServiceStatus(client, service, url: url);
    } finally {
      client.close();
    }
  }

  final createClient = ref.watch(serviceStatusClientFactoryProvider);
  final client = createClient(
    baseUrl: url,
    apiKey: instance.credential,
    pinnedCertFingerprint: settings.pinForUrl(url),
    accessHeaders: instance.access.headers(),
  );

  try {
    // Who answered, not only that something did: the reading the connection
    // test shares, so Home and Settings name the same answer.
    return await readServiceStatus(client, service, url: url);
  } finally {
    client.close();
  }
}

/// The envelope the per-client version reads share: one call under this
/// service's own deadline, an empty string reported as no version at all, and
/// the client closed whichever way it went.
///
/// Nothing is caught here, on purpose. A throw is what tells
/// [_loadServiceSummary] the service is offline, so swallowing it would report
/// an unreachable box as online with a blank version. The qBittorrent branch
/// used to do exactly that — it caught everything and returned null, so a
/// refusing or unreachable qBittorrent still showed ONLINE while the other five
/// clients reported offline. All six now share this envelope.
///
/// [close] is a `FutureOr` so a client with an asynchronous shutdown could share
/// this path without the synchronous Dio ones changing shape.
Future<String?> _versionOrNull(
  Future<String> Function() read, {
  required Duration timeout,
  required FutureOr<void> Function() close,
}) async {
  try {
    final version = await read().timeout(timeout);
    return version.isNotEmpty ? version : null;
  } finally {
    final closing = close();
    if (closing is Future) await closing;
  }
}

final servicesRequestsProvider = requestsProvider;
final servicesMoviesProvider = moviesProvider;
final servicesSeriesProvider = seriesProvider;
final servicesMusicProvider = musicProvider;

/// The Radarr queue of one named connection, indexed by movie id.
///
/// A queue is a property of a server, and the ids in it are that server's. Read
/// through the lens while the page it badges belongs to a different connection,
/// every badge is answering about a different film that happens to share an id.
/// Empty id means the lens, which is what [radarrQueueSnapshotProvider] passes.
final radarrQueueSnapshotForProvider =
    FutureProvider.family<ArrQueueSnapshot, String>((ref, instanceId) async {
      final service = instanceId.isEmpty
          ? ref.watch(radarrServiceProvider)
          : ref.watch(radarrServiceForProvider(instanceId));
      return _loadArrQueueSnapshot(
        service,
        service.getQueuePage,
        (item) => [
          intOrNull(mapOrNull(item['movie'])?['id'] ?? item['movieId']),
        ],
      );
    });

/// The Radarr queue indexed by movie id.
///
/// Every surface that badges a movie — grid, poster rail, detail page — reads
/// this one snapshot, so they cannot disagree about what is downloading. A
/// queue that did not answer is a failed snapshot, never an empty one, and a
/// badge reads it through `queueUnknown: !snapshot.isWhole`
/// (`radarrMovieStatus`), so a film being downloaded never reads `Missing`
/// because its queue could not be asked.
/// Delegates to the connection the lens points at, so the surfaces that never
/// name one keep the shape they always had.
final radarrQueueSnapshotProvider = FutureProvider<ArrQueueSnapshot>((
  ref,
) async {
  final lens = ref.watch(activeInstanceProvider(ServiceKey.radarr))?.id ?? '';
  return ref.watch(radarrQueueSnapshotForProvider(lens).future);
});

/// A queue snapshot as a screen reads it off its provider: the snapshot last
/// read, the failure when the read itself threw, and
/// [ArrQueueSnapshot.unknown] while nothing has been read yet.
///
/// Never [ArrQueueSnapshot.empty] for a queue nobody read: a badge passes
/// `queueUnknown: !snapshot.isWhole`, so a title with nothing on disk reads
/// unknown until the queue answers, and `Missing` only once it answered whole
/// without it.
ArrQueueSnapshot queueSnapshotOf(AsyncValue<ArrQueueSnapshot> queue) =>
    switch (queue) {
      AsyncValue(:final value?) => value,
      AsyncValue(:final error?) => ArrQueueSnapshot.failed(error),
      _ => ArrQueueSnapshot.unknown,
    };

/// [queueSnapshotOf] for Lidarr's two indexes of one queue.
LidarrQueueSnapshots lidarrQueueSnapshotsOf(
  AsyncValue<LidarrQueueSnapshots> queue,
) => switch (queue) {
  AsyncValue(:final value?) => value,
  AsyncValue(:final error?) => LidarrQueueSnapshots.failed(error),
  _ => LidarrQueueSnapshots.unknown,
};

/// The Sonarr queue of one named connection, indexed by series, episode and
/// season from one read. Empty id means the lens.
///
/// Degrades to a **failed** snapshot, never an empty one, or to the last
/// answer kept as stale: see [_loadArrQueueSnapshot]. Invalidate this family,
/// not the series index derived from it, to read the queue again.
final sonarrQueueSnapshotsForProvider =
    FutureProvider.family<SonarrQueueSnapshots, String>((
      ref,
      instanceId,
    ) async {
      final service = instanceId.isEmpty
          ? ref.watch(sonarrServiceProvider)
          : ref.watch(sonarrServiceForProvider(instanceId));
      try {
        final page = await service.getQueuePage();
        return _lastSonarrQueue[service] = SonarrQueueSnapshots.fromQueueItems(
          page.records,
          cutShort: page.cutShort,
        );
      } catch (error) {
        // The last answer, stale, over a refresh that failed: see
        // [_lastArrQueue].
        return _lastSonarrQueue[service]?.staleAfter(error) ??
            SonarrQueueSnapshots.failed(error);
      }
    });

/// [sonarrQueueSnapshotsForProvider]'s three snapshots as a screen reads them
/// off the provider: see [queueSnapshotOf].
SonarrQueueSnapshots sonarrQueueSnapshotsOf(
  AsyncValue<SonarrQueueSnapshots> queue,
) => switch (queue) {
  AsyncValue(:final value?) => value,
  AsyncValue(:final error?) => SonarrQueueSnapshots.failed(error),
  _ => SonarrQueueSnapshots.unknown,
};

/// The Sonarr queue of one named connection, indexed by series id. See
/// [radarrQueueSnapshotForProvider]. A view of
/// [sonarrQueueSnapshotsForProvider], so the series grid and the episode rows
/// read one queue.
final sonarrQueueSnapshotForProvider =
    FutureProvider.family<ArrQueueSnapshot, String>((ref, instanceId) async {
      return (await ref.watch(
        sonarrQueueSnapshotsForProvider(instanceId).future,
      )).bySeries;
    });

/// The Sonarr queue indexed by series id.
final sonarrQueueSnapshotProvider = FutureProvider<ArrQueueSnapshot>((
  ref,
) async {
  final lens = ref.watch(activeInstanceProvider(ServiceKey.sonarr))?.id ?? '';
  return ref.watch(sonarrQueueSnapshotForProvider(lens).future);
});

/// How many artists the album → artist fallback may probe, and how many of
/// those requests may be in flight at once.
///
/// The fallback exists for Lidarr queue records that name an album but not its
/// artist, and there is no endpoint that maps one to the other — the only route
/// is `/album?artistId=` per artist. Unbounded, that walks the entire artist
/// library one request at a time, so a four-thousand-artist library could fire
/// four thousand sequential requests to badge one queue row. The guard above
/// makes it rare; this makes it bounded when it does happen. An unresolved
/// album simply badges nothing, which is the same outcome as the request
/// failing.
const int _lidarrAlbumLookupCap = 40;
const int _lidarrAlbumLookupConcurrency = 4;

/// The Lidarr queue indexed by artist *and* album id.
///
/// Delegates to the connection the lens points at, so the surfaces that never
/// name one keep the shape they always had. See
/// [lidarrQueueSnapshotsForProvider].
final lidarrQueueSnapshotsProvider = FutureProvider<LidarrQueueSnapshots>((
  ref,
) async {
  final lens = ref.watch(activeInstanceProvider(ServiceKey.lidarr))?.id ?? '';
  return ref.watch(lidarrQueueSnapshotsForProvider(lens).future);
});

/// The Lidarr queue of one named connection, indexed by artist and album id.
///
/// A queue is a property of a server, and the ids in it are that server's: an
/// artist page opened on the second Lidarr that read the lens's queue badged
/// its albums with the other server's downloads. Empty id means the lens,
/// which is what [lidarrQueueSnapshotsProvider] passes. The Radarr and Sonarr
/// pages read theirs the same way ([radarrQueueSnapshotForProvider]).
final lidarrQueueSnapshotsForProvider =
    FutureProvider.family<LidarrQueueSnapshots, String>((
      ref,
      instanceId,
    ) async {
      final service = instanceId.isEmpty
          ? ref.watch(lidarrServiceProvider)
          : ref.watch(lidarrServiceForProvider(instanceId));
      return _loadLidarrQueueSnapshots(service);
    });

Future<LidarrQueueSnapshots> _loadLidarrQueueSnapshots(
  LidarrService service,
) async {
  try {
    return _lastLidarrQueue[service] = await _readLidarrQueueSnapshots(service);
  } catch (error) {
    // Failed, not empty, and the last answer kept as stale when there was
    // one: see [_loadArrQueueSnapshot].
    return _lastLidarrQueue[service]?.staleAfter(error) ??
        LidarrQueueSnapshots.failed(error);
  }
}

Future<LidarrQueueSnapshots> _readLidarrQueueSnapshots(
  LidarrService service,
) async {
  int? directArtistId(Map<String, dynamic> item) => intOrNull(
    mapOrNull(item['artist'])?['id'] ??
        mapOrNull(item['album'])?['artistId'] ??
        item['artistId'],
  );
  int? albumIdOf(Map<String, dynamic> item) =>
      intOrNull(mapOrNull(item['album'])?['id'] ?? item['albumId']);

  final page = await service.getQueuePage();
  final queueItems = page.records
      .whereType<Map>()
      .map(stringKeyMap)
      .toList(growable: false);
  if (queueItems.isEmpty && !page.cutShort) {
    return LidarrQueueSnapshots.empty;
  }

  // Only records that do not already name their artist are worth the album
  // lookup below, which costs one request per artist.
  final unresolvedAlbumIds = <int>{};
  for (final item in queueItems) {
    final artistId = directArtistId(item);
    if (artistId != null && artistId > 0) continue;

    final albumId = albumIdOf(item);
    if (albumId != null && albumId > 0) {
      unresolvedAlbumIds.add(albumId);
    }
  }

  final albumToArtist = <int, int>{};
  if (unresolvedAlbumIds.isNotEmpty) {
    final pending = {...unresolvedAlbumIds};
    final candidates = (await service.getArtists())
        .where((artist) => artist.albumCount > 0)
        .take(_lidarrAlbumLookupCap)
        .toList(growable: false);

    for (
      var start = 0;
      start < candidates.length && pending.isNotEmpty;
      start += _lidarrAlbumLookupConcurrency
    ) {
      final batch = candidates.skip(start).take(_lidarrAlbumLookupConcurrency);
      final fetched = await Future.wait(
        batch.map((artist) async {
          try {
            return (
              artist: artist.id,
              albums: await service.getAlbums(artist.id),
            );
          } catch (_) {
            // One artist that will not answer must not abandon the rest of
            // the batch.
            return (artist: artist.id, albums: const <LidarrAlbum>[]);
          }
        }),
      );

      for (final result in fetched) {
        for (final album in result.albums) {
          if (pending.remove(album.id)) {
            albumToArtist[album.id] = result.artist;
          }
        }
      }
    }
  }

  return LidarrQueueSnapshots(
    byArtist: ArrQueueSnapshot.fromQueueItems(
      queueItems,
      cutShort: page.cutShort,
      idsFor: (item) {
        final direct = directArtistId(item);
        if (direct != null && direct > 0) return [direct];

        final albumId = albumIdOf(item);
        final resolved = albumId == null ? null : albumToArtist[albumId];
        return resolved == null ? const <int>[] : [resolved];
      },
    ),
    byAlbum: ArrQueueSnapshot.fromQueueItems(
      queueItems,
      cutShort: page.cutShort,
      idsFor: (item) {
        final albumId = albumIdOf(item);
        return albumId == null ? const <int>[] : [albumId];
      },
    ),
  );
}

/// How many items the merged Recently Added rail shows.
///
/// Six, down from twelve, and the number is the region's anatomy speaking: the
/// phone draws six 60×90 tiles clipped by a right-edge fade, and a rail that
/// scrolls twice as far as it shows is a rail whose fade is a lie.
const int servicesRecentlyAddedLimit = 6;

/// How many history records each arr is asked for.
///
/// One page, unfiltered — see `domain/arr_import.dart` for why the brief's
/// `eventType` filter cannot be sent. Twenty rather than ten because the page is
/// unfiltered: a busy evening's history is mostly `grabbed`, and ten records can
/// contain no imports at all on a stack that is downloading faster than it
/// imports. Twenty is still one request and still one page.
const int servicesHistoryPageSize = 20;

/// Whether one page of history is a window onto more of it.
///
/// Home reads one page per connection, the newest [pageSize] records. A page
/// that came back short is every record there is. One that came back full is
/// not, unless the server's own total says it is: the records past it are
/// older imports and older failures nobody read, so what is counted over the
/// page is the least there is (`20+`). A full page with no total at all is a
/// window too, because nothing says otherwise.
bool historyPageIsWindow(ArrRecordPage page, {required int pageSize}) {
  if (page.records.length < pageSize) return false;
  final total = page.total;
  return total == null || total > page.records.length;
}

/// One \*arr history record, reduced to what the two regions that read it need.
///
/// A projection rather than the raw map, for the reason `RecentlyAddedItem` is
/// one: the map is heterogeneous per event type and every reader would have to
/// re-learn which keys mean what.
class ArrHistoryEntry {
  const ArrHistoryEntry({
    required this.service,
    required this.id,
    required this.mediaId,
    required this.title,
    required this.unitId,
    required this.detail,
    required this.posterUrl,
    required this.outcome,
    required this.at,
    required this.reason,
    this.instanceId = '',
    this.connectionName,
  });

  final ServiceKey service;

  /// What tells [instanceId] apart from the service's other connections, by
  /// the app's one rule, or null while the service has only the one.
  final String? connectionName;

  /// The connection this record came off.
  ///
  /// A history record id and the media id in it are that server's: each
  /// Radarr numbers from one, so "film 3" names a different film on each. The
  /// manual import a failed record becomes has to open on this connection,
  /// never on whatever the lens is on when the user taps Fix. Empty only for a
  /// record built without one, which falls back to the lens.
  final String instanceId;

  /// The history record's own id. Unique per connection, and what the decision
  /// row is keyed on — a media id is not, since one film can fail twice.
  final int id;

  /// The library item this record is about, for the route. Zero when the record
  /// does not name one, which is normal for a failed grab of something the arr
  /// never added.
  final int mediaId;

  final String title;

  /// The season (Sonarr) or album id (Lidarr) the record belongs to — what
  /// Recently added folds on. Null on Radarr and when the record does not say.
  final int? unitId;

  /// The record's own piece: `S1 E3`, or the artist behind an album.
  final String? detail;

  final String posterUrl;
  final ArrImportOutcome outcome;
  final DateTime? at;

  /// Why it failed, when the record says. Null on an import.
  final String? reason;
}

/// One history page per arr, and which arrs answered for it.
typedef ArrHistory = ({List<ArrHistoryEntry> entries, SourceCoverage coverage});

/// One history page per arr, read once and shared by the two regions that need
/// it.
///
/// Recently added asks it what landed; the decisions region asks it what did
/// not. One provider so the answer is one request, and so the two regions cannot
/// disagree about the same record.
///
/// A dark arr still degrades to no records, and now also says so in
/// [ArrHistory.coverage]: the rail can show what the others answered, but the
/// count above it cannot claim to be the whole without knowing who is missing.
final servicesArrHistoryProvider = FutureProvider<ArrHistory>((ref) async {
  // Every configured connection of each arr, each on its own narrow watch:
  // watching the whole `SettingsModel` refetched every history page on any
  // settings write, a theme toggle included.
  Future<ArrHistory> from(_MergeConnection source) async {
    try {
      // The page, not the bare records: whether the page holds the whole
      // history is what decides if a count over it is a total or a floor.
      final page = await switch (source.service) {
        ServiceKey.radarr =>
          ref
              .watch(radarrServiceForProvider(source.instanceId))
              .getHistoryPage(pageSize: servicesHistoryPageSize),
        ServiceKey.sonarr =>
          ref
              .watch(sonarrServiceForProvider(source.instanceId))
              .getHistoryPage(pageSize: servicesHistoryPageSize),
        // Lidarr's records DO arrive with their artist and their album:
        // `LidarrService` overrides `getHistoryPage`, which this `getHistory`
        // delegates through, and injects `includeArtist`/`includeAlbum` there.
        // So the title resolves to the album (`arrPrimaryMediaTitle` reads
        // `album` then `artist`) rather than falling back to the raw
        // `sourceTitle`, and the tile's artwork is the album cover — see
        // `_historyPosterUrl`.
        _ =>
          ref
              .watch(lidarrServiceForProvider(source.instanceId))
              .getHistoryPage(pageSize: servicesHistoryPageSize),
      };
      return (
        entries: page.records
            .whereType<Map>()
            .map(stringKeyMap)
            .map(
              (record) => _historyEntryFrom(
                source.service,
                record,
                // The connection these records come off, stamped on each, so
                // a remedy bound to one connection opens on this one, whatever
                // the lens is on when the user taps.
                instanceId: source.instanceId,
                connectionName: source.name,
                baseUrl: source.connection.url,
                apiKey: source.connection.apiKey,
              ),
            )
            .toList(growable: false),
        // A page that came back full is a window onto more history, so what
        // is counted over it is a floor (`20+`), never the total.
        coverage: SourceCoverage.answeredBy(
          source.service,
          cutShort: historyPageIsWindow(
            page,
            pageSize: servicesHistoryPageSize,
          ),
          instanceId: source.instanceId,
          name: source.name,
        ),
      );
    } catch (error) {
      // The convention: a browse degrades to `[]` rather than taking the region
      // down — but the failure is kept, classified, so the count above the
      // rail can leave this connection out by name instead of counting it as
      // zero. A second Radarr that did not answer leaves the first one's
      // imports on the rail.
      return (
        entries: const <ArrHistoryEntry>[],
        coverage: SourceCoverage.failure(
          source.service,
          error,
          instanceId: source.instanceId,
          name: source.name,
        ),
      );
    }
  }

  final results = await Future.wait([
    for (final service in const [
      ServiceKey.radarr,
      ServiceKey.sonarr,
      ServiceKey.lidarr,
    ])
      for (final source in _watchMergeConnections(ref, service)) from(source),
  ]);

  return (
    entries: results.expand((result) => result.entries).toList(growable: false),
    coverage: SourceCoverage.merge(results.map((result) => result.coverage)),
  );
});

ArrHistoryEntry _historyEntryFrom(
  ServiceKey service,
  Map<String, dynamic> record, {
  required String instanceId,
  String? connectionName,
  required String baseUrl,
  required String apiKey,
}) {
  final data = mapOrNull(record['data']);
  final title =
      arrPrimaryMediaTitle(record) ?? arrReleaseTitle(record) ?? 'Unknown item';

  return ArrHistoryEntry(
    service: service,
    instanceId: instanceId,
    connectionName: connectionName,
    id: intOrNull(record['id']) ?? 0,
    mediaId:
        intOrNull(record['movieId']) ??
        intOrNull(record['seriesId']) ??
        intOrNull(record['artistId']) ??
        0,
    title: title,
    unitId: switch (service) {
      ServiceKey.sonarr => intOrNull(
        mapOrNull(record['episode'])?['seasonNumber'] ?? record['seasonNumber'],
      ),
      ServiceKey.lidarr => intOrNull(
        record['albumId'] ?? mapOrNull(record['album'])?['id'],
      ),
      _ => null,
    },
    detail: switch (service) {
      ServiceKey.sonarr => arrEpisodeCode(record),
      ServiceKey.lidarr => arrArtistName(record),
      _ => null,
    },
    posterUrl: _historyPosterUrl(record, baseUrl: baseUrl, apiKey: apiKey),
    outcome: classifyHistoryEvent(stringOrNull(record['eventType'])),
    at: parseAddedTimestamp(stringOrNull(record['date'])),
    // `statusMessages` is where an \*arr puts the reason an import failed, and
    // `message` is where a failed *grab* puts it. Neither is always present, and
    // a decision row with no reason still says what it is.
    reason:
        stringOrNull(data?['statusMessages']) ?? stringOrNull(data?['message']),
  );
}

/// The artwork a history record carries in its embedded media.
///
/// On Lidarr the album's cover comes first and the artist's poster second: the
/// Recently added row folds on the album, so the album is what it should look
/// like, and an album whose cover Lidarr has not fetched yet still has a face.
/// Both embeds are already on the record (`includeAlbum`/`includeArtist`), so
/// this costs no request.
String _historyPosterUrl(
  Map<String, dynamic> record, {
  required String baseUrl,
  required String apiKey,
}) {
  String from(Object? media, List<String> coverTypes) {
    final images = mapOrNull(media)?['images'];
    if (images is! List) return '';
    return ImageUtils.extractPosterUrl(
      images,
      baseUrl: baseUrl,
      apiKey: apiKey,
      coverTypes: coverTypes,
    ).url;
  }

  const posterTypes = ['poster', 'cover'];
  for (final (media, coverTypes) in [
    (record['movie'], posterTypes),
    (record['series'], posterTypes),
    (record['album'], const ['cover', 'disc']),
    (record['artist'], const ['poster', 'fanart']),
  ]) {
    final url = from(media, coverTypes);
    if (url.isNotEmpty) return url;
  }
  return '';
}

/// What the arrs actually imported, newest first.
///
/// One region and one channel — the old "Finished today" band folded into it, so
/// a failed import is named here (in amber, in the eyebrow) and *acted on* in
/// the decisions region above, rather than sitting in a band of its own where a
/// failure went to die.
///
/// The fetch is the history read, not the library browse it used to be: three
/// full `fetchAllItems` walks for six tiles, on every pull-to-refresh.
///
/// Carries the history's coverage through, so the eyebrow counts only the
/// libraries that answered.
///
/// Every row, newest first, and **not** cut to the rail: the eyebrow is a
/// count, and it used to count the six tiles the rail draws, so with a second
/// Radarr's imports folded in, a busy evening read "6 imported" whatever had
/// landed. The rail takes its [servicesRecentlyAddedLimit] off the front.
final servicesRecentlyAddedProvider = FutureProvider<ServicesRecentlyAdded>((
  ref,
) async {
  final history = await ref.watch(servicesArrHistoryProvider.future);

  final items = [
    for (final entry in history.entries)
      if (entry.outcome != ArrImportOutcome.other)
        RecentlyAddedItem(
          service: entry.service,
          instanceId: entry.instanceId,
          connectionName: entry.connectionName,
          id: entry.mediaId,
          title: entry.title,
          posterUrl: entry.posterUrl,
          addedAt: entry.at,
          failed: entry.outcome == ArrImportOutcome.failed,
          unitId: entry.unitId,
          detail: entry.detail,
        ),
  ];

  final rows = groupRecentlyAdded(items);
  return (
    items: sortRecentlyAdded(rows, limit: rows.length),
    coverage: history.coverage,
  );
});

/// What the Recently added region counts, newest first, and which libraries
/// answered for it. The rail draws the first [servicesRecentlyAddedLimit].
typedef ServicesRecentlyAdded = ({
  List<RecentlyAddedItem> items,
  SourceCoverage coverage,
});

/// How many in-flight items the hub shows before deferring to `/activity`.
///
/// Raised from three when the provider stopped being Radarr-plus-Sonarr: with
/// seven possible sources, three slots meant a busy usenet queue could hide every
/// torrent on the screen.
const int servicesQueuePreviewLimit = 5;

/// Everything a transfer row prints, per source, in one shape.
///
/// The fields are the row's grammar rather than one service's vocabulary — see
/// `domain/in_flight.dart`. It used to carry a pre-joined `subtitle` composed by
/// each loader in its own words, which is why a Radarr row and a SABnzbd row
/// could not be read down a column: they were two different sentences that
/// happened to be the same length.
class ServiceQueueItem {
  const ServiceQueueItem({
    required this.service,
    required this.title,
    required this.progress,
    required this.clientLabel,
    this.id = '',
    this.quality,
    this.doneBytes,
    this.totalBytes,
    this.etaSeconds,
    this.fault,
    this.stalledSince,
    this.warning,
    this.clientRateBytesPerSecond,
    this.route,
    this.detail,
    this.downloadId,
    this.clientService,
    this.instanceId = '',
    this.connectionName,
    this.clientInstanceId = '',
    this.mediaId,
    this.outputPath,
    this.category,
    this.held = false,
    MediaNames? names,
  }) : _names = names;

  final ServiceKey service;

  /// The client's own id for this transfer — a torrent hash, an nzo id, a queue
  /// record id. Keys the row and the decision it can become.
  final String id;

  final String title;

  /// Fraction complete, or null when the client did not say. Null is not zero:
  /// a usenet item that has not started reports nothing, and sorting it as 0%
  /// would bury the transfer about to finish.
  final double? progress;

  /// The release's quality, when the source has one. A download client knows the
  /// file size, not the profile the \*arr grabbed it under.
  final String? quality;

  final int? doneBytes;
  final int? totalBytes;
  final int? etaSeconds;

  /// Who is moving the bytes, in words. For an \*arr row this is the download
  /// client named in the queue record — the arr is the one that asked, not the
  /// one that is transferring.
  final String clientLabel;

  /// Why this stopped being a transfer, or null while it still is one. A row
  /// with a fault leaves this region entirely and becomes a decision — which
  /// decision, and so which remedy, is what the value says. See
  /// [InFlightFault].
  final InFlightFault? fault;

  /// When it stopped being a transfer, as near as the source can date it —
  /// qBittorrent's last activity, or the \*arr's `added`. Feeds the decision's
  /// ranking.
  final DateTime? stalledSince;

  /// The source's own message about this row, when there is one.
  final String? warning;

  /// The rate of the **client**, not of this row, carried on every row that
  /// client contributes.
  ///
  /// A byte rate is a countable unit and sums, but only once per client: adding
  /// it per row would multiply one client's throughput by its queue depth. The
  /// eyebrow sums over distinct clients for exactly that reason, and an \*arr
  /// carries none — the bytes it is waiting on are already being counted by the
  /// client that is moving them.
  final int? clientRateBytesPerSecond;

  /// Where the row leads.
  final String? route;

  /// Extra facts a decision row prints that a transfer row does not — seeds, the
  /// current rate, the arr's own warning.
  final String? detail;

  /// The download client's id for the transfer an \*arr row is tracking — the
  /// torrent hash, the SABnzbd `nzo_id`, the NZBGet id. The key
  /// [joinQueueSources] joins an \*arr row to the client row moving the same
  /// bytes on. Null on a client's own row, whose [id] already is that id.
  final String? downloadId;

  /// The connected client moving these bytes: itself on a client's own row,
  /// and on an \*arr row only once [joinQueueSources] has matched it to one.
  ///
  /// What the eyebrow keys the rate on, since an \*arr row that absorbed a
  /// torrent carries the torrent's client rate.
  final ServiceKey? clientService;

  /// The connection the row was read from, for a remedy that opens a flow
  /// bound to one connection — the import wizard's `?i=` — and for a route
  /// into a detail page, whose ids are that server's.
  final String instanceId;

  /// What tells [instanceId] apart from the service's other connections, by
  /// the app's one rule, or null while the service has only the one. On the
  /// row's line, so two Radarr rows say which Radarr.
  final String? connectionName;

  /// The connection of the download client moving these bytes: the row's own
  /// on a client's row, and the client row's on an \*arr row joined to one.
  /// Empty while nothing has said which. What "Open in qBittorrent" opens,
  /// and what the eyebrow keys a client's rate on.
  final String clientInstanceId;

  /// The library item an \*arr row belongs to — the movie, series, artist or
  /// author — which a manual import is filed under. Null when the record names
  /// none, or when several records folded into this row name different ones.
  final int? mediaId;

  /// Where the client is writing, as the \*arr reports it — what a manual
  /// import is seeded from.
  final String? outputPath;

  final MediaNames? _names;

  /// What the transfer is and which copy it is ([MediaNames]): on an \*arr
  /// row, the arr's item and the release it grabbed, which a row joined to
  /// its client keeps; on a client's own row that no arr claims, its raw
  /// name, until something recognises it. [title] is what the row draws
  /// today; these are what the row is.
  MediaNames get names => _names ?? MediaNames.raw(title);

  /// The download client's category (or Transmission's first label) on a
  /// client's own row: which arr the name can be put to
  /// ([arrForClientCategory]). Null on an \*arr row.
  final String? category;

  /// This row named [names]: everything else as it was.
  ServiceQueueItem withNames(MediaNames names) => ServiceQueueItem(
    service: service,
    title: title,
    progress: progress,
    clientLabel: clientLabel,
    id: id,
    quality: quality,
    doneBytes: doneBytes,
    totalBytes: totalBytes,
    etaSeconds: etaSeconds,
    fault: fault,
    stalledSince: stalledSince,
    warning: warning,
    clientRateBytesPerSecond: clientRateBytesPerSecond,
    route: route,
    detail: detail,
    downloadId: downloadId,
    clientService: clientService,
    instanceId: instanceId,
    connectionName: connectionName,
    clientInstanceId: clientInstanceId,
    mediaId: mediaId,
    outputPath: outputPath,
    category: category,
    held: held,
    names: names,
  );

  /// A download somebody stopped on purpose, with bytes still to come:
  /// backlog, not in flight and not a fault, on every client alike. An \*arr
  /// row is held while its record says paused, or while the client row it
  /// joined is held.
  final bool held;

  /// Whether this transfer is genuinely moving, or waiting to.
  bool get isActive => fault == null && !held;
}

/// Everything currently transferring, across every configured source.
///
/// This is the region the old dashboard put *last*, below three browse rails,
/// while sourcing it from Radarr and Sonarr only — so the most time-sensitive
/// thing on a control-room screen was both buried and mostly blind. It now covers
/// the two arr services it always did, plus Lidarr and Readarr, plus the four
/// download clients that actually move the bytes.
///
/// Stalls are **not** filtered out here: they are in the list, flagged, because
/// the decisions region reads the same provider and a second fetch to find the
/// stuck ones would be the same queue asked twice. `servicesInFlightProvider` is
/// the filtered view the region draws.
///
/// Every source is gated on being configured and degrades to `[]` on failure, so
/// one unreachable client cannot empty or block the region. The failure is
/// kept, classified, in [ServicesQueue.coverage]: the rows can do without a dark
/// client, but the count above them cannot count it as zero.
final servicesQueueProvider = FutureProvider<ServicesQueue>((ref) async {
  // Every configured connection of the eight sources, each watched on its own
  // narrow key rather than the whole model. A bare
  // `ref.watch(currentSettingsProvider)` re-ran every queue fetch on every
  // settings write — including a theme-mode toggle, which cannot change a
  // queue.
  //
  // Every connection rather than the lens: Home counts the whole household,
  // the way its header does. A stall on the second Radarr, or a blocked
  // import on it, is the user's as much as one on the first, and reading the
  // lens alone left it off Home with nothing saying so.
  final arrQueues = [
    for (final service in const [
      ServiceKey.radarr,
      ServiceKey.sonarr,
      ServiceKey.lidarr,
      ServiceKey.readarr,
    ])
      for (final source in _watchMergeConnections(ref, service))
        _readQueueSource(source, () => _loadServiceQueueItems(ref, source)),
  ];
  final clientQueues = _readDownloadClients(ref);
  final namer = _watchDownloadNamer(ref);
  final results = await Future.wait([...arrQueues, ...clientQueues]);

  // One row per transfer, not one per source that can see it. A Radarr grab
  // moving through qBittorrent is in both queues, and concatenating them drew
  // it twice and counted it twice — and a stall in it became two decisions.
  final joined = joinQueueSources(
    arr: results
        .take(arrQueues.length)
        .expand((result) => result.items)
        .toList(growable: false),
    clients: results
        .skip(arrQueues.length)
        .expand((result) => result.items)
        .toList(growable: false),
  );
  // A client row no arr claims has only its raw name: the arrs are asked to
  // read it, within this read's cap.
  final items = await _nameClientRows(namer, joined);

  // Closest to landing first. An item whose client reports no progress sorts
  // last rather than as zero: unknown is not the same as "just started", and
  // pushing it to the top would bury the transfer that is about to finish.
  //
  // Decorated with the source index because `List.sort` is not guaranteed
  // stable. Without it, several progress-less items — normal for a usenet queue
  // that has not started — could come back in a different order on each build,
  // which reads on screen as rows shuffling for no reason.
  final ordered =
      List.generate(
        items.length,
        (index) => (index: index, item: items[index]),
        growable: false,
      )..sort((a, b) {
        final progressA = a.item.progress;
        final progressB = b.item.progress;
        if (progressA != progressB) {
          if (progressA == null) return 1;
          if (progressB == null) return -1;
          final byProgress = progressB.compareTo(progressA);
          if (byProgress != 0) return byProgress;
        }
        return a.index.compareTo(b.index);
      });

  return (
    items: ordered.map((entry) => entry.item).toList(growable: false),
    coverage: SourceCoverage.merge(results.map((result) => result.coverage)),
  );
});

/// One source's queue rows, and whether the walk that read them stopped short
/// of the end ([ArrRecordPage.cutShort]).
typedef _QueueRead = ({List<ServiceQueueItem> items, bool cutShort});

/// One connection's queue, read, with whether it answered.
///
/// One connection that fails takes its own rows out and nobody else's, and
/// its failure is kept, classified, so a count over the rest can say what it
/// leaves out.
Future<ServicesQueue> _readQueueSource(
  _MergeConnection source,
  Future<_QueueRead> Function() load,
) async {
  try {
    final read = await load();
    return (
      items: read.items,
      // A walk that stopped short answered, with part of its queue: the
      // count over it is a floor.
      coverage: SourceCoverage.answeredBy(
        source.service,
        cutShort: read.cutShort,
        instanceId: source.instanceId,
        name: source.name,
      ),
    );
  } catch (error) {
    return (
      items: const <ServiceQueueItem>[],
      coverage: SourceCoverage.failure(
        source.service,
        error,
        instanceId: source.instanceId,
        name: source.name,
      ),
    );
  }
}

/// Every configured download client connection's own queue, one read each.
///
/// [fresh] asks the lens's connection through its client too, rather than
/// through the list its own page holds and polls. Home shares that list with
/// the page; a surface with a poll of its own (Activity) would read it as it
/// stood whenever the page last ran.
List<Future<ServicesQueue>> _readDownloadClients(
  Ref ref, {
  bool fresh = false,
}) {
  // The clients answer with their whole queue in one read, so there is no
  // walk to stop short.
  Future<_QueueRead> whole(Future<List<ServiceQueueItem>> items) async =>
      (items: await items, cutShort: false);
  _MergeConnection asked(_MergeConnection source) => fresh
      ? (
          service: source.service,
          instanceId: source.instanceId,
          name: source.name,
          isLens: false,
          connection: source.connection,
        )
      : source;
  return [
    for (final source in _watchMergeConnections(ref, ServiceKey.qbittorrent))
      _readQueueSource(
        source,
        () => whole(_loadQbittorrentQueueItems(ref, asked(source))),
      ),
    for (final source in _watchMergeConnections(ref, ServiceKey.transmission))
      _readQueueSource(
        source,
        () => whole(_loadTransmissionQueueItems(ref, asked(source))),
      ),
    for (final source in _watchMergeConnections(ref, ServiceKey.sabnzbd))
      _readQueueSource(
        source,
        () => whole(_loadSabnzbdQueueItems(ref, asked(source))),
      ),
    for (final source in _watchMergeConnections(ref, ServiceKey.nzbget))
      _readQueueSource(
        source,
        () => whole(_loadNzbgetQueueItems(ref, asked(source))),
      ),
  ];
}

/// How many `/parse` requests one read may send.
///
/// A name is put to an arr once and its answer kept ([DownloadNameCache]), so
/// a list of new names is read a few per read rather than all in one burst; a
/// name past the cap keeps its raw form until a later read reaches it.
const int downloadNameParseCap = 6;

/// The arrs' readings of download names, per connection and name, for the
/// life of the app.
///
/// Only answers are kept. A connection that did not answer recognised
/// nothing, and is asked again on the next read.
class DownloadNameCache {
  final Map<String, MediaNames?> _answers = {};

  bool has(String key) => _answers.containsKey(key);

  MediaNames? operator [](String key) => _answers[key];

  void operator []=(String key, MediaNames? names) => _answers[key] = names;
}

final downloadNameCacheProvider = Provider<DownloadNameCache>(
  (ref) => DownloadNameCache(),
);

/// A download to name: the client's id for it, its raw name, its category.
typedef UnnamedDownload = ({String id, String name, String? category});

/// The arrs that can read a download's name, each with its client, and their
/// kept answers.
///
/// Taken at the start of a read, before it awaits anything
/// ([_watchDownloadNamer]), so naming never reaches back into a provider
/// that may have been rebuilt or dropped while its requests were out.
class _DownloadNamer {
  _DownloadNamer(this._cache, this._arrs);

  final DownloadNameCache _cache;
  final Map<
    ServiceKey,
    List<({_MergeConnection source, ArrActivityMixin parser})>
  >
  _arrs;

  /// Names [downloads] no arr's queue claims, by asking the arrs to read them
  /// (`parseTitle`), and answers each one's names by its id.
  ///
  /// The arrs asked are the one the client's category points at
  /// ([arrForClientCategory]) when it is set up, every set-up one otherwise,
  /// in [parsingArrs]'s order and each connection in the user's. A library
  /// item from any of them wins; the first parser reading stands otherwise;
  /// with neither, the raw name is the title. At most [cap] requests leave per
  /// call, and every answer is kept, so a name is read once.
  Future<Map<String, MediaNames>> name(
    List<UnnamedDownload> downloads, {
    int cap = downloadNameParseCap,
  }) async {
    if (downloads.isEmpty) return const {};
    var budget = cap;

    Future<MediaNames> read(UnnamedDownload download) async {
      final hint = arrForClientCategory(download.category);
      final asked = hint != null && (_arrs[hint]?.isNotEmpty ?? false)
          ? _arrs[hint]!
          : [for (final service in parsingArrs) ...?_arrs[service]];
      MediaNames? parsed;
      for (final (:source, :parser) in asked) {
        final key = [
          source.service.name,
          source.instanceId,
          source.connection.url,
          download.name,
        ].join('|');
        MediaNames? answer;
        if (_cache.has(key)) {
          answer = _cache[key];
        } else {
          if (budget <= 0) break;
          budget--;
          try {
            final reply = await parser.parseTitle(download.name);
            answer = namesFromParse(source.service, download.name, reply);
            _cache[key] = answer;
          } catch (_) {
            // Silent or refusing: it recognised nothing this time, and is
            // asked again next time.
            continue;
          }
        }
        if (answer?.source == MediaTitleSource.library) return answer!;
        parsed ??= answer;
      }
      return parsed ?? MediaNames.raw(download.name);
    }

    final named = await Future.wait(downloads.map(read));
    return {
      for (final (index, download) in downloads.indexed)
        download.id: named[index],
    };
  }
}

/// The arrs a read may put names to, watched on their narrow keys: call it
/// before the read's first `await`.
_DownloadNamer _watchDownloadNamer(Ref ref) =>
    _DownloadNamer(ref.read(downloadNameCacheProvider), {
      for (final service in parsingArrs)
        service: [
          for (final source in _watchMergeConnections(ref, service))
            (source: source, parser: _parserOf(ref, source)),
        ],
    });

ArrActivityMixin _parserOf(
  Ref ref,
  _MergeConnection source,
) => switch (source.service) {
  ServiceKey.radarr => ref.watch(radarrServiceForProvider(source.instanceId)),
  ServiceKey.sonarr => ref.watch(sonarrServiceForProvider(source.instanceId)),
  ServiceKey.lidarr => ref.watch(lidarrServiceForProvider(source.instanceId)),
  _ => throw ArgumentError.value(source.service, 'service'),
};

/// [rows] with every client row no arr claims named by the arrs
/// ([_DownloadNamer.name]); the rest as they are.
Future<List<ServiceQueueItem>> _nameClientRows(
  _DownloadNamer namer,
  List<ServiceQueueItem> rows,
) async {
  // Keyed on the connection too: two NZBGet both number their jobs from one.
  String key(ServiceQueueItem row) =>
      '${row.service.name}|${row.clientInstanceId}|${row.id}';
  final unnamed = [
    for (final row in rows)
      if (row.clientService == row.service && row.names.isRaw && !row.held)
        (id: key(row), name: row.title, category: row.category),
  ];
  if (unnamed.isEmpty) return rows;
  final names = await namer.name(unnamed);
  return [
    for (final row in rows)
      if (row.clientService == row.service && names[key(row)] != null)
        row.withNames(names[key(row)]!)
      else
        row,
  ];
}

/// Every download in one client connection's own list, named: the arr's item
/// for a download an arr's queue claims ([joinDownloads], the join In flight
/// and Activity read), the arrs' reading for the rest ([_nameDownloads]),
/// keyed on the client's id for it. Its machine name is the client's own
/// name for it, as the client reported it.
///
/// What the clients' own pages read their rows' names off; the rows keep
/// their look until those pages are redrawn. An arr whose queue does not
/// answer claims nothing, and its downloads are asked about by name instead.
final downloadClientNamesProvider = FutureProvider.autoDispose
    .family<Map<String, MediaNames>, InstanceRef>((ref, client) async {
      // Every read and every watch started before the first await: see
      // [_DownloadNamer].
      final list = _clientList(ref, client);
      final queues = Future.wait([
        for (final service in const [
          ServiceKey.radarr,
          ServiceKey.sonarr,
          ServiceKey.lidarr,
          ServiceKey.readarr,
        ])
          for (final source in _watchMergeConnections(ref, service))
            _readQueueSource(source, () => _loadServiceQueueItems(ref, source)),
      ]);
      final namer = _watchDownloadNamer(ref);
      final rows = await list;
      final arrQueues = await queues;
      final join = joinDownloads<ServiceQueueItem, UnnamedDownload>(
        arr: [for (final queue in arrQueues) ...queue.items],
        clients: rows,
        arrDownloadId: (row) => row.downloadId,
        clientDownloadId: (row) => row.id,
      );
      final claimed = <String, MediaNames>{};
      for (final (:arr, :client) in join.joined) {
        if (client == null || claimed.containsKey(client.id)) continue;
        final title = arr.names.title;
        claimed[client.id] = arr.names.isRaw || title == client.name
            ? MediaNames.raw(client.name)
            : MediaNames(
                title: title,
                machineName: client.name,
                machineKind: MachineNameKind.release,
                source: arr.names.source,
              );
      }
      return {...claimed, ...await namer.name(join.unclaimed)};
    }, retry: noProviderRetry);

/// One client connection's whole list, every download in it: the torrent
/// library, the usenet queue.
Future<List<UnnamedDownload>> _clientList(Ref ref, InstanceRef client) async {
  final id = client.instanceId;
  return switch (client.service) {
    ServiceKey.qbittorrent => [
      for (final torrent
          in await ref.watch(qbittorrentServiceForProvider(id)).getTorrents())
        (id: torrent.hash, name: torrent.name, category: torrent.category),
    ],
    ServiceKey.transmission => [
      for (final torrent
          in await ref.watch(transmissionClientForProvider(id)).torrents())
        (
          id: torrent.hashString,
          name: torrent.name,
          category: torrent.labels.firstOrNull,
        ),
    ],
    ServiceKey.sabnzbd => [
      for (final slot
          in (await ref
                  .watch(sabnzbdClientForProvider(id))
                  .getQueue(limit: SabnzbdClient.wholeQueue))
              .slots)
        (id: slot.nzoId, name: slot.filename, category: slot.category),
    ],
    ServiceKey.nzbget => [
      for (final group
          in await ref.watch(nzbgetClientForProvider(id)).listGroups())
        (id: group.downloadId, name: group.name, category: group.category),
    ],
    _ => throw ArgumentError.value(client.service, 'service', 'not a client'),
  };
}

/// Every configured download client's own queue, as transfer rows, and which
/// of the clients answered.
///
/// What a surface outside Home joins its \*arr records against
/// ([joinDownloads]): Activity reads the same four clients, by the same rules
/// (`download_client_faults.dart`), as In flight does. Read fresh, every
/// connection through its own client: see [_readDownloadClients].
Future<ServicesQueue> downloadClientQueues(Ref ref) async {
  final reads = await Future.wait(_readDownloadClients(ref, fresh: true));
  return (
    items: [for (final read in reads) ...read.items],
    coverage: SourceCoverage.merge(reads.map((read) => read.coverage)),
  );
}

/// Every transfer the configured sources reported, and which of them answered.
typedef ServicesQueue = ({
  List<ServiceQueueItem> items,
  SourceCoverage coverage,
});

/// The transfers the IN FLIGHT region draws, and the numbers above them.
///
/// Active only: a faulted transfer is not in flight, it is a decision, and the
/// region says so in a footnote rather than silently showing a different count
/// from the client's own queue.
///
/// [preview] and [activeCount] are two fields because they answer two
/// questions. The rows are capped at [servicesQueuePreviewLimit]; the eyebrow
/// states how many transfers there are, and it used to state it by counting
/// the capped list — thirty downloads read "5 downloading".
///
/// [coverage] is the queue's: [activeCount] is a count over the sources that
/// answered, and only over them.
typedef ServicesInFlight = ({
  List<ServiceQueueItem> preview,
  int activeCount,
  List<ServiceQueueItem> faults,
  int held,
  int? rateBytesPerSecond,
  int clients,
  SourceCoverage coverage,
});

final servicesInFlightProvider = FutureProvider<ServicesInFlight>((ref) async {
  final queue = await ref.watch(servicesQueueProvider.future);
  final items = queue.items;
  final active = items.where((item) => item.isActive).toList(growable: false);
  final faults = items
      .where((item) => item.fault != null)
      .toList(growable: false);
  // Paused on purpose: neither moving nor a decision, and counted only so the
  // region does not call a paused queue an empty one.
  final held = items.where((item) => item.fault == null && item.held).length;

  // Summed once per client, never once per row — see
  // [ServiceQueueItem.clientRateBytesPerSecond]. Keyed on the client rather
  // than on the row's service, because an \*arr row that absorbed a torrent
  // carries that torrent's client rate.
  // Keyed on the client's connection too: two qBittorrent are two clients,
  // and keyed on the service alone the second one's rate replaced the
  // first's.
  final rates = <(ServiceKey, String), int>{};
  for (final item in items) {
    final rate = item.clientRateBytesPerSecond;
    final client = item.clientService;
    if (rate != null && client != null) {
      rates[(client, item.clientInstanceId)] = rate;
    }
  }

  return (
    preview: active.take(servicesQueuePreviewLimit).toList(growable: false),
    activeCount: active.length,
    faults: faults,
    held: held,
    rateBytesPerSecond: rates.isEmpty
        ? null
        : rates.values.fold(0, (sum, rate) => sum + rate),
    clients: rates.length,
    coverage: queue.coverage,
  );
});

/// Joins the \*arr queues to the download-client queues, one row per transfer.
///
/// The match is [joinDownloads], the one Activity's records go through too:
/// an \*arr row names the client's own id for the transfer in `downloadId`.
/// The \*arr row wins: it knows the title, the quality and whether the file
/// can be imported. The client row lends it what only the client measures —
/// progress, bytes, time left, rate — and a stall the \*arr has not noticed
/// yet. A client row no \*arr claims (a torrent added by hand) stays a row of
/// its own.
///
/// Pure and top-level, so the rule is testable without a container.
List<ServiceQueueItem> joinQueueSources({
  required List<ServiceQueueItem> arr,
  required List<ServiceQueueItem> clients,
}) {
  final join = joinDownloads<ServiceQueueItem, ServiceQueueItem>(
    arr: arr,
    clients: clients,
    arrDownloadId: (row) => row.downloadId,
    clientDownloadId: (row) => row.id,
  );
  return [
    for (final (:arr, :client) in join.joined)
      client == null ? arr : _joinedQueueItem(arr, client),
    ...join.unclaimed,
  ];
}

ServiceQueueItem _joinedQueueItem(
  ServiceQueueItem arr,
  ServiceQueueItem client,
) {
  // The \*arr's fault first: an import it refuses is the more specific truth.
  // The client's stall second — the \*arr polls its client on a minute's delay
  // and can still be calling a dead transfer "downloading".
  final fault = arr.fault ?? client.fault;
  final faultFromClient = arr.fault == null && client.fault != null;
  // The byte pair travels together: one side's done over the other's total
  // is a figure neither source reported.
  final clientMeasured = client.totalBytes != null;

  return ServiceQueueItem(
    service: arr.service,
    id: arr.id,
    title: arr.title,
    progress: client.progress ?? arr.progress,
    clientLabel: arr.clientLabel,
    quality: arr.quality,
    doneBytes: clientMeasured ? client.doneBytes : arr.doneBytes,
    totalBytes: clientMeasured ? client.totalBytes : arr.totalBytes,
    etaSeconds: client.etaSeconds ?? arr.etaSeconds,
    fault: fault,
    stalledSince: faultFromClient ? client.stalledSince : arr.stalledSince,
    warning: arr.warning ?? client.warning,
    clientRateBytesPerSecond: client.clientRateBytesPerSecond,
    route: arr.route,
    detail: faultFromClient ? client.detail : arr.detail,
    downloadId: arr.downloadId,
    clientService: client.clientService,
    instanceId: arr.instanceId,
    connectionName: arr.connectionName,
    clientInstanceId: client.clientInstanceId,
    mediaId: arr.mediaId,
    outputPath: arr.outputPath,
    // The client's word on a pause, which is fresher than the arr's.
    held: fault == null && client.held,
    // The arr's names, and the release the client is moving when the arr's
    // record did not carry one: a matched row never loses its release name.
    names: arr.names.withMachineName(client.title, MachineNameKind.release),
  );
}

/// Active torrents, and any torrent reporting a fault, as in-flight items.
///
/// Filters to transfers that are genuinely moving or waiting to: a seeding
/// library of four hundred torrents is not "in flight", and unfiltered it would
/// crowd out every other source. A torrent in `error` or `missingFiles` is
/// kept whatever it was doing, as a fault: see [qbittorrentInFlight].
Future<List<ServiceQueueItem>> _loadQbittorrentQueueItems(
  Ref ref,
  _MergeConnection source,
) async {
  // The lens's own list is the one the qBittorrent page already holds; any
  // other connection is asked through its own long-lived client.
  final torrents = source.isLens
      ? await ref.watch(allTorrentsProvider.future)
      : await ref
            .watch(qbittorrentServiceForProvider(source.instanceId))
            .getTorrents();
  final read = [
    for (final torrent in torrents)
      if (qbittorrentInFlight(torrent.state) case final reading?)
        (torrent: torrent, reading: reading),
  ];

  // The client's rate, summed over what it is actually downloading, and carried
  // on each of its rows.
  final clientRate = read.fold<int>(0, (sum, row) => sum + row.torrent.dlSpeed);

  return [
    for (final (:torrent, :reading) in read)
      ServiceQueueItem(
        service: ServiceKey.qbittorrent,
        id: torrent.hash,
        title: torrent.name,
        progress: torrent.progress.clamp(0, 1).toDouble(),
        // No quality: a torrent client sees a file name, not a profile.
        doneBytes: torrent.downloaded > 0
            ? torrent.downloaded
            : (torrent.size * torrent.progress).round(),
        totalBytes: torrent.size > 0 ? torrent.size : null,
        etaSeconds: _qbEta(torrent.eta),
        // Named when there are two, so a stall says which qBittorrent.
        clientLabel: serviceWithConnection(
          ServiceKey.qbittorrent,
          source.name,
          joiner: ' ',
        ),
        clientService: ServiceKey.qbittorrent,
        instanceId: source.instanceId,
        clientInstanceId: source.instanceId,
        clientRateBytesPerSecond: clientRate,
        // A stall looks identical to a slow download until you notice it has
        // not moved, and a torrent in error looked like nothing at all: it was
        // dropped with the seeding library. Both leave the region as a
        // decision now, each by its own fault.
        fault: reading.fault,
        warning: reading.reason,
        held: reading.held,
        stalledSince: reading.fault == null
            ? null
            : _epochSeconds(torrent.lastActivity),
        detail: joinDisplayParts([
          formatSpeed(torrent.dlSpeed),
          countedNoun(torrent.seeders, 'seed', 'seeds'),
        ]),
        route: ServiceRoutes.qbittorrentTorrent(torrent.hash),
        category: torrent.category,
      ),
  ];
}

/// Transmission's torrents, as in-flight items: the incoming ones, and any
/// torrent reporting a fault. See [transmissionInFlight] for the rule.
///
/// It used to be no source at all. A Sonarr grab moving through Transmission
/// was drawn off the arr's queue alone, with the arr's minute-old progress and
/// no rate, and a torrent added by hand was not on Home anywhere.
Future<List<ServiceQueueItem>> _loadTransmissionQueueItems(
  Ref ref,
  _MergeConnection source,
) async {
  // As qBittorrent: the lens's list is the one the Transmission page holds.
  final torrents = source.isLens
      ? await ref.watch(transmissionTorrentsProvider.future)
      : await ref
            .watch(transmissionClientForProvider(source.instanceId))
            .torrents();
  final read = [
    for (final torrent in torrents)
      if (transmissionInFlight(torrent) case final reading?)
        (torrent: torrent, reading: reading),
  ];

  // `rateDownload` is per torrent; the client's rate is their sum, carried on
  // each of its rows and counted once.
  final clientRate = read.fold<int>(
    0,
    (sum, row) => sum + row.torrent.rateDownload,
  );

  return [
    for (final (:torrent, :reading) in read)
      ServiceQueueItem(
        service: ServiceKey.transmission,
        id: torrent.hashString,
        title: torrent.name,
        progress: torrent.progress,
        // `sizeWhenDone` is what this torrent will weigh with its unwanted
        // files skipped, and `leftUntilDone` is measured against it, so the
        // pair is taken together or not at all.
        doneBytes: torrent.sizeWhenDone > 0
            ? torrent.sizeWhenDone - torrent.leftUntilDone
            : null,
        totalBytes: torrent.sizeWhenDone > 0 ? torrent.sizeWhenDone : null,
        // Negative is "not available" (-1) or "unknown" (-2), never a time.
        etaSeconds: torrent.eta < 0 ? null : torrent.eta,
        clientLabel: serviceWithConnection(
          ServiceKey.transmission,
          source.name,
          joiner: ' ',
        ),
        clientService: ServiceKey.transmission,
        instanceId: source.instanceId,
        clientInstanceId: source.instanceId,
        clientRateBytesPerSecond: clientRate,
        fault: reading.fault,
        warning: reading.reason,
        held: reading.held,
        stalledSince: reading.fault == null
            ? null
            : _epochSeconds(torrent.activityDate),
        detail: joinDisplayParts([
          formatSpeed(torrent.rateDownload),
          countedNoun(torrent.peersSendingToUs, 'peer', 'peers'),
        ]),
        route: ServiceRoutes.forService(ServiceKey.transmission),
        category: torrent.labels.firstOrNull,
      ),
  ];
}

/// qBittorrent's "no estimate" sentinel, in seconds (100 days).
///
/// Printed literally it reads `100 d left`, which is not an estimate — it is the
/// client saying it has none. Mapped to null so the row prints `—`.
const int _qbNoEta = 8640000;

int? _qbEta(int eta) => eta <= 0 || eta >= _qbNoEta ? null : eta;

DateTime? _epochSeconds(int seconds) =>
    seconds <= 0 ? null : DateTime.fromMillisecondsSinceEpoch(seconds * 1000);

/// SABnzbd's queue, as in-flight items, with its faults: a job SABnzbd paused
/// itself, and every job of a queue its disk stopped. See
/// [sabnzbdSlotInFlight].
Future<List<ServiceQueueItem>> _loadSabnzbdQueueItems(
  Ref ref,
  _MergeConnection source,
) async {
  final queue = source.isLens
      ? await ref.watch(sabnzbdQueueProvider.future)
      : await ref
            .watch(sabnzbdClientForProvider(source.instanceId))
            .getQueue(limit: SabnzbdClient.wholeQueue);
  final rate = (queue.kbPerSec * 1024).round();
  const megabyte = 1024 * 1024;
  const gigabyte = 1024 * megabyte;
  final free = queue.downloadDiskFreeGb;
  final stoppedByDisk = usenetQueueStoppedByDisk(
    paused: queue.paused,
    timedPause: queue.isTimedPause,
    freeBytes: free == null ? null : (free * gigabyte).round(),
    remainingBytes: [
      for (final slot in queue.slots)
        if (slot.status.toLowerCase() != 'paused')
          (slot.mbLeft * megabyte).round(),
    ],
  );

  // A queue somebody paused holds every job in it; one its disk stopped
  // stalls them.
  final pausedOnPurpose = queue.paused && !stoppedByDisk;
  final read = [
    for (final slot in queue.slots)
      (
        slot: slot,
        reading: sabnzbdSlotInFlight(
          slot,
          stoppedByDisk: stoppedByDisk,
          pausedOnPurpose: pausedOnPurpose,
        ),
      ),
  ];

  return [
    for (final (:slot, :reading) in read)
      ServiceQueueItem(
        service: ServiceKey.sabnzbd,
        id: slot.nzoId,
        title: slot.filename,
        progress: slot.progress,
        // The slot's own `mb` (what the job weighs) and `mbleft` (what is
        // still to come), taken together or not at all: a slot that carried
        // no usable `mb` reads `—`, never a total inferred from the
        // percentage.
        doneBytes: switch (slot.mb) {
          final double total => ((total - slot.mbLeft) * megabyte).round(),
          null => null,
        },
        totalBytes: switch (slot.mb) {
          final double total => (total * megabyte).round(),
          null => null,
        },
        etaSeconds: parseClockDuration(slot.timeLeft),
        clientLabel: serviceWithConnection(
          ServiceKey.sabnzbd,
          source.name,
          joiner: ' ',
        ),
        clientService: ServiceKey.sabnzbd,
        instanceId: source.instanceId,
        clientInstanceId: source.instanceId,
        clientRateBytesPerSecond: rate,
        fault: reading.fault,
        // A job or a queue paused on purpose is stopped *on purpose*, which
        // the tone rule files under neutral: held, not a fault, not a
        // decision, and not in flight. A queue its disk stopped is a fault,
        // and says so.
        held: reading.held,
        warning: reading.reason,
        route: ServiceRoutes.forService(ServiceKey.sabnzbd),
        category: slot.category,
      ),
  ];
}

Future<List<ServiceQueueItem>> _loadNzbgetQueueItems(
  Ref ref,
  _MergeConnection source,
) async {
  // The queue and the client's status, side by side: `listgroups` carries no
  // rate at all, and NZBGet reports one only for the whole client, in
  // `status`. Read without it, NZBGet's bytes were the one transfer the
  // eyebrow's sum left out.
  final (groups, status) = source.isLens
      ? await (
          ref.watch(nzbgetQueueProvider.future),
          ref.watch(nzbgetStatusProvider.future),
        ).wait
      : await (
          ref.watch(nzbgetClientForProvider(source.instanceId)).listGroups(),
          ref.watch(nzbgetClientForProvider(source.instanceId)).status(),
        ).wait;
  const megabyte = 1024 * 1024;
  final free = status.writingDiskFreeMb;
  final stoppedByDisk = usenetQueueStoppedByDisk(
    paused: status.paused,
    timedPause: status.isDeliberateStop,
    freeBytes: free == null ? null : free * megabyte,
    remainingBytes: [
      for (final group in groups)
        if (group.status.toUpperCase() != 'PAUSED' &&
            nzbgetIsFetching(group.status))
          switch (group.remainingSizeMb) {
            final int left => left * megabyte,
            null => null,
          },
    ],
  );

  return groups
      .map(
        (group) => (
          group: group,
          reading: nzbgetGroupInFlight(
            group,
            stoppedByDisk: stoppedByDisk,
            pausedOnPurpose: status.paused && !stoppedByDisk,
          ),
        ),
      )
      .map(
        (row) => ServiceQueueItem(
          service: ServiceKey.nzbget,
          // The key an \*arr row names this job by — its `drone` parameter,
          // else the NZBID — so [joinQueueSources] can meet the two.
          id: row.group.downloadId,
          title: row.group.name,
          progress: row.group.progress,
          // Both sizes are nullable now — NZBGet reporting neither the `*MB`
          // key nor the `*Hi`/`*Lo` pair used to read as zero megabytes, which
          // made an unmeasured job render as a finished one.
          doneBytes: switch ((
            row.group.fileSizeMb,
            row.group.remainingSizeMb,
          )) {
            (final int total, final int left) => (total - left) * megabyte,
            _ => null,
          },
          totalBytes: switch (row.group.fileSizeMb) {
            final int total => total * megabyte,
            _ => null,
          },
          // NZBGet reports a rate for the whole client and none per group, so
          // there is nothing to divide into an estimate. `—`, not a guess.
          etaSeconds: null,
          clientLabel: serviceWithConnection(
            ServiceKey.nzbget,
            source.name,
            joiner: ' ',
          ),
          clientService: ServiceKey.nzbget,
          instanceId: source.instanceId,
          clientInstanceId: source.instanceId,
          clientRateBytesPerSecond: status.downloadRateBytes,
          fault: row.reading.fault,
          warning: row.reading.reason,
          held: row.reading.held,
          route: ServiceRoutes.forService(ServiceKey.nzbget),
          category: row.group.category,
        ),
      )
      .toList(growable: false);
}

/// `0:03:21` / `00:03:21.5` → seconds. Null when the source said nothing.
///
/// Shared by the \*arr `timeleft` field and SABnzbd's, which are the same shape
/// for the same reason: both are a .NET/Python duration printed for a human.
int? parseClockDuration(String? value) {
  final raw = value?.trim();
  if (raw == null || raw.isEmpty) return null;
  final parts = raw.split(':');
  if (parts.length != 3) return null;
  final hours = int.tryParse(parts[0]);
  final minutes = int.tryParse(parts[1]);
  final seconds = int.tryParse(parts[2].split('.').first);
  if (hours == null || minutes == null || seconds == null) return null;
  return hours * 3600 + minutes * 60 + seconds;
}

/// Walks a `/queue` and indexes it, degrading on failure so a badge never
/// blocks on an unreachable service.
///
/// Degrading to a **failed** snapshot, not to [ArrQueueSnapshot.empty]. The
/// empty one is an answer, a queue with nothing in it, and every detail page
/// read it as one: with the queue endpoint down, each film that was
/// downloading read `Missing`. A walk that stopped short says so too
/// ([ArrQueueSnapshot.cutShort]), for the same reason: an id missing from the
/// rows it read may be in the rows it did not.
///
/// A refresh that fails after [client] has answered once degrades to that
/// answer instead, kept as stale ([ArrQueueSnapshot.staleAfter]): see
/// [_lastArrQueue]. Only a first read that fails is the failed snapshot.
Future<ArrQueueSnapshot> _loadArrQueueSnapshot(
  Object client,
  Future<ArrRecordPage> Function() loadPage,
  Iterable<int?> Function(Map<String, dynamic> item) idsFor,
) async {
  try {
    final page = await loadPage();
    return _lastArrQueue[client] = ArrQueueSnapshot.fromQueueItems(
      page.records,
      idsFor: (item) => idsFor(item).whereType<int>(),
      cutShort: page.cutShort,
    );
  } catch (error) {
    return _lastArrQueue[client]?.staleAfter(error) ??
        ArrQueueSnapshot.failed(error);
  }
}

/// The last queue each client answered with, so a refresh that fails keeps
/// it rather than throwing it away.
///
/// A queue refresh that failed used to replace the reading with a failed
/// snapshot: every badge went `Unknown` and the download a page was showing
/// a minute ago disappeared from it. The reading stays now, stale, and the
/// page says how old it is.
///
/// Keyed on the client, and weakly. A connection whose address or key
/// changes gets a new client and starts with nothing kept, which is the
/// point: the ids in the old answer may be another server's. A client that
/// goes away takes its answer with it.
final Expando<ArrQueueSnapshot> _lastArrQueue = Expando('last queue answer');

/// [_lastArrQueue] for Sonarr's three indexes of one queue.
final Expando<SonarrQueueSnapshots> _lastSonarrQueue = Expando(
  'last Sonarr queue answer',
);

/// [_lastArrQueue] for Lidarr's two indexes of one queue.
final Expando<LidarrQueueSnapshots> _lastLidarrQueue = Expando(
  'last Lidarr queue answer',
);

/// One \*arr's queue as in-flight items. Throws when the queue cannot be read:
/// the caller keeps the failure, so a dark arr is named rather than counted as
/// an empty queue.
///
/// Read off the walk's envelope rather than its bare rows, so a walk that
/// stopped on a full page with no total says so: the region counted its rows
/// and stated them as the queue, `200 downloading` for a queue of any length
/// behind a proxy that drops `totalRecords`. The rows are grouped into
/// downloads before they are counted, so the server's record total is never a
/// figure here; a short walk only makes the count a floor.
Future<_QueueRead> _loadServiceQueueItems(
  Ref ref,
  _MergeConnection source,
) async {
  // The connection these records come off, stamped on each row so a remedy
  // that opens a flow bound to one connection (the import wizard) opens it on
  // this one, and the row's route opens this server's film, whatever the lens
  // is on by the time the user taps.
  final id = source.instanceId;
  final page = switch (source.service) {
    ServiceKey.radarr =>
      await ref.watch(radarrServiceForProvider(id)).getQueuePage(),
    ServiceKey.sonarr =>
      await ref.watch(sonarrServiceForProvider(id)).getQueuePage(),
    ServiceKey.lidarr =>
      await ref.watch(lidarrServiceForProvider(id)).getQueuePage(),
    ServiceKey.readarr =>
      await ref.watch(readarrServiceForProvider(id)).getQueuePage(),
    // The download clients are not `/queue` shaped and have their own loaders;
    // the rest have no queue at all.
    ServiceKey.seerr ||
    ServiceKey.qbittorrent ||
    ServiceKey.transmission ||
    ServiceKey.bazarr ||
    ServiceKey.truenas ||
    ServiceKey.dockge ||
    ServiceKey.prowlarr ||
    ServiceKey.sabnzbd ||
    ServiceKey.nzbget ||
    ServiceKey.unraid ||
    // A reverse proxy moves no bytes on anyone's behalf; it has nothing to
    // contribute to an in-flight queue.
    ServiceKey.nginxProxyManager ||
    // A media server has no acquisition queue at all. Its live work is
    // outbound playback, which is a different record with different actions
    // and does not belong in a queue row.
    ServiceKey.jellyfin ||
    ServiceKey.plex => const ArrRecordPage(records: [], total: 0),
  };
  final records = page.records.whereType<Map>().map(stringKeyMap);
  return (
    items: [
      for (final download in _groupQueueRecordsByDownload(records))
        _queueItemFromRecords(
          source.service,
          download,
          instanceId: id,
          connectionName: source.name,
        ),
    ],
    cutShort: page.cutShort,
  );
}

/// The records of one \*arr queue, one list per download.
///
/// A season pack is one torrent and **one record per episode** in Sonarr's
/// queue, every one of them carrying the same `downloadId` and the same
/// `size`/`sizeleft` — the torrent's. Drawn a row per record, one transfer
/// read as ten, and "10 downloading" counted episodes rather than downloads.
/// Records with no `downloadId` are each their own download: nothing says
/// otherwise. First-seen order.
List<List<Map<String, dynamic>>> _groupQueueRecordsByDownload(
  Iterable<Map<String, dynamic>> records,
) {
  final groups = <List<Map<String, dynamic>>>[];
  final byDownload = <String, List<Map<String, dynamic>>>{};
  for (final record in records) {
    final id = stringOrNull(record['downloadId'])?.trim().toLowerCase();
    if (id == null || id.isEmpty) {
      groups.add([record]);
      continue;
    }
    final existing = byDownload[id];
    if (existing != null) {
      existing.add(record);
      continue;
    }
    final group = [record];
    byDownload[id] = group;
    groups.add(group);
  }
  return groups;
}

/// Which fault wins when a download's records disagree: the one whose remedy
/// is least likely to clear by itself.
int _faultWeight(InFlightFault? fault) => switch (fault) {
  InFlightFault.needsImport => 3,
  InFlightFault.failed => 2,
  InFlightFault.stalled => 1,
  null => 0,
};

ServiceQueueItem _queueItemFromRecords(
  ServiceKey service,
  List<Map<String, dynamic>> records, {
  required String instanceId,
  String? connectionName,
}) {
  // One download, so its figures are the first record's: every record of a
  // pack reports the pack's size, and summing them would multiply it.
  final typedItem = records.first;
  final title = records.length == 1
      ? joinDisplayParts([
          arrPrimaryMediaTitle(typedItem) ??
              arrReleaseTitle(typedItem) ??
              'Unknown release',
          if (service == ServiceKey.sonarr) arrEpisodeCode(typedItem),
        ])
      : _packTitle(service, records);
  final size = intOrNull(typedItem['size']);
  final left = intOrNull(typedItem['sizeleft']);
  // The release the arr grabbed, the queue record's `title`, as it sent it.
  final release = stringOrNull(typedItem['title']);
  final names = records.length == 1
      ? MediaNames.ofRecord(typedItem, machineName: release)
      : _packNames(service, records, title: title, release: release);

  // The download's fault is its worst record's: one blocked episode is a
  // manual import for the pack.
  InFlightFault? fault;
  Map<String, dynamic> faulted = typedItem;
  for (final record in records) {
    final recordFault = arrQueueFault(record);
    if (_faultWeight(recordFault) > _faultWeight(fault)) {
      fault = recordFault;
      faulted = record;
    }
  }
  final warning =
      stringOrNull(faulted['errorMessage']) ?? arrQueueWarningMessage(faulted);

  final mediaIds = {for (final record in records) _queueMediaId(record)};
  final mediaId = mediaIds.length == 1 ? mediaIds.single : null;

  return ServiceQueueItem(
    service: service,
    id: '${intOrNull(typedItem['id']) ?? 0}',
    title: title,
    progress: queueProgress(typedItem),
    quality: _queueQualityLabel(typedItem['quality']),
    // Derived from the two figures the record actually carries, and only when
    // both are there: `size - sizeleft` is what has landed. An arr that reports
    // neither prints `—`, never `0` — a transfer nobody could measure has not
    // downloaded nothing.
    doneBytes: size == null || left == null ? null : size - left,
    totalBytes: size,
    etaSeconds: parseClockDuration(stringOrNull(typedItem['timeleft'])),
    // The client moving the bytes, which is the answer the row owes. The arr is
    // the one that asked for them — it is already the row's glyph and accent.
    clientLabel:
        stringOrNull(typedItem['downloadClient']) ??
        _queueTypeLabel(service) ??
        service.title,
    // Classified by what the record *is* — stalled, blocked, failed — and not
    // by whether it carries a warning. "Any warning is a stall" made a finished
    // download the arr could not import into a stalled transfer, with a remedy
    // in the one place that cannot fix it. A record merely carrying a warning
    // while its bytes still move stays in flight.
    fault: fault,
    stalledSince: parseAddedTimestamp(stringOrNull(typedItem['added'])),
    warning: warning,
    detail: warning,
    downloadId: stringOrNull(typedItem['downloadId']),
    instanceId: instanceId,
    connectionName: connectionName,
    mediaId: mediaId,
    outputPath: stringOrNull(typedItem['outputPath']),
    names: names,
    // The arr's own record of a pause, standing until a client row says
    // otherwise.
    held:
        fault == null &&
        ArrQueueEntry.fromQueueItem(typedItem)?.pipeline ==
            MediaPipeline.paused,
    // With the connection: a queue record's ids are its server's, and the
    // same film id names a different film on the other Radarr.
    route: switch (service) {
      ServiceKey.radarr =>
        intOrNull(typedItem['movieId']) == null
            ? null
            : ServiceRoutes.radarrMovie(
                intOrNull(typedItem['movieId'])!,
                instanceId: instanceId,
              ),
      ServiceKey.sonarr =>
        intOrNull(typedItem['seriesId']) == null
            ? null
            : ServiceRoutes.sonarrSeries(
                intOrNull(typedItem['seriesId'])!,
                instanceId: instanceId,
              ),
      ServiceKey.lidarr =>
        intOrNull(typedItem['artistId']) == null
            ? null
            : ServiceRoutes.lidarrArtist(
                intOrNull(typedItem['artistId'])!,
                instanceId: instanceId,
              ),
      _ => ServiceRoutes.forService(service),
    },
  );
}

/// The library item a queue record belongs to, or null when it names none.
int? _queueMediaId(Map<String, dynamic> record) {
  final id =
      intOrNull(record['movieId']) ??
      intOrNull(record['seriesId']) ??
      intOrNull(record['artistId']) ??
      intOrNull(record['authorId']);
  return id == null || id <= 0 ? null : id;
}

/// `The Boys · 8 episodes` — one row for a download the \*arr filed as several
/// records.
String _packTitle(ServiceKey service, List<Map<String, dynamic>> records) {
  final first = records.first;
  final (name, unit) = switch (service) {
    ServiceKey.sonarr => (arrSeriesTitle(first), 'episodes'),
    ServiceKey.lidarr => (
      arrArtistName(first) ?? arrAlbumTitle(first),
      'albums',
    ),
    ServiceKey.readarr => (
      arrAuthorName(first) ?? arrBookTitle(first),
      'books',
    ),
    _ => (arrMovieTitle(first), 'movies'),
  };
  return joinDisplayParts([
    name ?? arrReleaseTitle(first) ?? 'Unknown release',
    '${records.length} $unit',
  ]);
}

/// A pack's names: `The Boys · 8 episodes` and the pack's release, or the
/// raw release when the records name no series, artist or author.
MediaNames _packNames(
  ServiceKey service,
  List<Map<String, dynamic>> records, {
  required String title,
  required String? release,
}) {
  final first = records.first;
  final named = switch (service) {
    ServiceKey.sonarr => arrSeriesTitle(first),
    ServiceKey.lidarr => arrArtistName(first) ?? arrAlbumTitle(first),
    ServiceKey.readarr => arrAuthorName(first) ?? arrBookTitle(first),
    _ => arrMovieTitle(first),
  };
  if (named == null || release == null || release.trim().isEmpty) {
    return MediaNames.raw(title);
  }
  return MediaNames(
    title: title,
    machineName: release.trim(),
    machineKind: MachineNameKind.release,
  );
}

String? _queueTypeLabel(ServiceKey service) {
  return switch (service) {
    ServiceKey.radarr => 'Movie',
    ServiceKey.sonarr => 'Series',
    ServiceKey.lidarr => 'Music',
    ServiceKey.readarr => 'Book',
    // Nothing for the rest. Only an arr reaches this — the download clients
    // build their own rows, and each already opens with the client's name,
    // which is the whole point of the row: the bytes are coming through this
    // client rather than through an arr, and the media type is in the release
    // name behind it.
    ServiceKey.seerr ||
    ServiceKey.qbittorrent ||
    ServiceKey.transmission ||
    ServiceKey.bazarr ||
    ServiceKey.truenas ||
    ServiceKey.dockge ||
    ServiceKey.prowlarr ||
    ServiceKey.sabnzbd ||
    ServiceKey.nzbget ||
    ServiceKey.unraid ||
    ServiceKey.nginxProxyManager ||
    ServiceKey.jellyfin ||
    ServiceKey.plex => null,
  };
}

String? _queueQualityLabel(dynamic value) {
  if (value is Map) {
    final quality = mapOrNull(value['quality']);
    return stringOrNull(quality?['name']) ?? stringOrNull(value['name']);
  }

  return stringOrNull(value);
}

/// Decisions, and which sources answered for them.
typedef DashboardDecisions = ({
  List<DashboardDecision> decisions,
  SourceCoverage coverage,
});

/// One source's decisions — see [DecisionSource] for why each is read alone.
///
/// Reads what the page has already loaded — the requests it was going to show,
/// the queue the in-flight region reads, the history the recently-added rail
/// reads, and the three infrastructure providers the stack cards' KPIs already
/// watch. Nothing here is a new request; the region is a **view** of the page's
/// own data, which is why it can afford to be first on the screen.
///
/// Gated on its service being configured, and never throws: a failure is kept
/// in the coverage, classified, so the region can tell "nothing is waiting"
/// from "nobody could be asked". `retry: noProviderRetry` because the stack
/// source derives from Dockge's list, which carries it.
final dashboardDecisionSourceProvider =
    FutureProvider.family<DashboardDecisions, DecisionSource>((
      ref,
      source,
    ) async {
      switch (source) {
        case DecisionSource.requests:
          // Every Seerr, each answering for itself: a request waiting on the
          // second one is waiting on the user as much as one on the first.
          return _pendingRequestDecisions(ref);
        // Every connection of each, each answering for itself, like the
        // requests: a failing indexer on the second Prowlarr needs somebody as
        // much as one on the first, and its Test has to reach that Prowlarr.
        case DecisionSource.indexers:
          return _decisionsOnEveryConnection(
            ref,
            ServiceKey.prowlarr,
            (source) => _failingIndexerDecisions(ref, source),
          );
        case DecisionSource.stacks:
          return _decisionsOnEveryConnection(
            ref,
            ServiceKey.dockge,
            (source) => _stoppedStackDecisions(ref, source),
          );
        case DecisionSource.certificates:
          return _decisionsOnEveryConnection(
            ref,
            ServiceKey.nginxProxyManager,
            (source) => _expiringCertificateDecisions(ref, source),
          );
        case DecisionSource.queue:
          // Not gated on one service: the faults come from whichever of eight
          // sources reported one, and the queue has already gated each of those
          // and kept which of them answered.
          final inFlight = await ref.watch(servicesInFlightProvider.future);
          return (
            decisions: inFlight.faults
                .map(_queueFaultDecision)
                .toList(growable: false),
            coverage: inFlight.coverage,
          );
        case DecisionSource.history:
          final history = await ref.watch(servicesArrHistoryProvider.future);
          return (
            decisions: history.entries
                .where((entry) => entry.outcome == ArrImportOutcome.failed)
                .map(_failedImportDecision)
                .toList(growable: false),
            coverage: history.coverage,
          );
      }
    }, retry: noProviderRetry);

/// One source's decisions, read on every configured connection of [service].
///
/// They used to be read through the lens alone, because their controls (Test,
/// Start, Renew) called the lens: a stack that exited on the second Dockge
/// never reached Home. Each connection is its own source now, as each Seerr
/// is for the requests: one that fails is named under the region and takes
/// only its own decisions with it, and every decision carries the connection
/// it came off, so its control acts on that server.
Future<DashboardDecisions> _decisionsOnEveryConnection(
  Ref ref,
  ServiceKey service,
  Future<List<DashboardDecision>> Function(_MergeConnection source) load,
) async {
  Future<DashboardDecisions> from(_MergeConnection source) async {
    try {
      return (
        decisions: await load(source),
        coverage: SourceCoverage.answeredBy(
          service,
          instanceId: source.instanceId,
          name: source.name,
        ),
      );
    } catch (error) {
      // Degrades to no decisions — a region that answers "what needs me" must
      // not itself become the thing that needs you — but says who failed.
      return (
        decisions: const <DashboardDecision>[],
        coverage: SourceCoverage.failure(
          service,
          error,
          instanceId: source.instanceId,
          name: source.name,
        ),
      );
    }
  }

  final sources = _watchMergeConnections(ref, service);
  if (sources.isEmpty) {
    return (
      decisions: const <DashboardDecision>[],
      coverage: SourceCoverage.none,
    );
  }
  final results = await Future.wait([
    for (final source in sources) from(source),
  ]);
  return (
    decisions: results
        .expand((result) => result.decisions)
        .toList(growable: false),
    coverage: SourceCoverage.merge(results.map((result) => result.coverage)),
  );
}

/// Everything waiting on a human, from every source, merged and ranked as each
/// source answers.
///
/// Synchronous over the sources' states rather than an `await` of all of them:
/// the decisions of the sources that answered are here as soon as they are,
/// and a source still out is [SourceCoverage.pending] rather than a wait. A
/// source being read again keeps its last answer while it is — `value`, not
/// `asData` — so a Dockge push does not blank the region between two lists.
final dashboardDecisionsProvider = Provider<DashboardDecisions>((ref) {
  final decisions = <DashboardDecision>[];
  final parts = <SourceCoverage>[];
  for (final source in DecisionSource.values) {
    final read = ref.watch(dashboardDecisionSourceProvider(source));
    final value = read.value;
    if (value != null) {
      decisions.addAll(value.decisions);
      parts.add(value.coverage);
    } else if (read.hasError) {
      // The sources catch their own failures; this is one that escaped, and it
      // is still a source that could not be read rather than an empty one.
      parts.add(
        SourceCoverage.merge([
          for (final service in source.services)
            SourceCoverage.failure(service, read.error),
        ]),
      );
    } else {
      parts.add(SourceCoverage.pendingOf(source.services));
    }
  }

  // Folded before ranking, so a group ranks where its oldest member would have.
  return (
    decisions: rankDecisions(groupDecisions(decisions)),
    coverage: SourceCoverage.merge(parts),
  );
});

/// The requests waiting on a person, from every configured Seerr.
///
/// Each connection is its own source: one that does not answer is named under
/// the region and takes nobody else's requests with it. A request carries the
/// connection it came off, because a Seerr request id is per server and the
/// row's Approve has to reach the Seerr that holds it.
Future<DashboardDecisions> _pendingRequestDecisions(Ref ref) async {
  Future<DashboardDecisions> from(_MergeConnection source) async {
    // The gate of this Seerr: a requester decides nothing, so her waiting
    // requests are no decision of hers; an account of the operator's that
    // may not approve keeps the row, its answers dimmed. Who asked is named
    // only where the connection sees everyone's requests.
    final gate = ref.watch(roleGateOfProvider(source.instanceId));
    final decides = gate.operatorAction(SeerrAbility.approve).isDrawn;
    final namesWho = gate.showsRequesterNames;
    try {
      final requests = await ref.watch(
        requestsForProvider(source.instanceId).future,
      );
      return (
        decisions: [
          for (final request in requests)
            // `isAwaitingApproval` keys off the request's own status, never
            // `displayStatus` — a request for media that already exists
            // reports "Available" while nobody has approved it. See
            // `request_ordering.dart`.
            if (decides && isAwaitingApproval(request))
              DashboardDecision(
                kind: DecisionKind.pendingRequest,
                id: 'seerr-${source.instanceId}-${request.id}',
                service: ServiceKey.seerr,
                title: request.media?.title ?? 'Unknown media',
                detail: joinDisplayParts([
                  'Request',
                  if (source.name != null)
                    serviceWithConnection(
                      ServiceKey.seerr,
                      source.name,
                      joiner: ' ',
                    ),
                  if (namesWho) request.requestedBy?.displayName,
                  request.type == 'tv' ? 'Series' : 'Movie',
                ]),
                occurredAt: parseAddedTimestamp(request.createdAt),
                actionId: request.id,
                instanceId: source.instanceId,
                connectionName: source.name,
                posterUrl: ImageUtils.buildTmdbPosterUrl(
                  request.media?.posterPath,
                ),
                // Discover resolves through the lens end to end, so a request
                // off another Seerr opens that Seerr's own requests list,
                // which honours `?i=`, rather than a media page asking the
                // lens.
                route: source.isLens
                    ? _seerrRequestRoute(request)
                    : _seerrRequestsListRoute(source.instanceId),
              ),
        ],
        coverage: SourceCoverage.answeredBy(
          ServiceKey.seerr,
          instanceId: source.instanceId,
          name: source.name,
        ),
      );
    } catch (error) {
      return (
        decisions: const <DashboardDecision>[],
        coverage: SourceCoverage.failure(
          ServiceKey.seerr,
          error,
          instanceId: source.instanceId,
          name: source.name,
        ),
      );
    }
  }

  final results = await Future.wait([
    for (final source in _watchMergeConnections(ref, ServiceKey.seerr))
      from(source),
  ]);
  return (
    decisions: results
        .expand((result) => result.decisions)
        .toList(growable: false),
    coverage: SourceCoverage.merge(results.map((result) => result.coverage)),
  );
}

/// The requests list of one Seerr connection, the one destination that
/// honours a connection in its link.
String _seerrRequestsListRoute(String instanceId) => Uri(
  path: '/activity/discover',
  queryParameters: {'i': instanceId},
).toString();

String _seerrRequestRoute(SeerrRequest request) {
  final media = request.media;
  final id = media?.tmdbId ?? media?.id;
  if (id == null || id <= 0) return ServiceRoutes.seerr;
  return ServiceRoutes.seerrDetail(
    mediaType: request.type == 'tv' ? 'tv' : 'movie',
    id: id,
  );
}

Future<List<DashboardDecision>> _failingIndexerDecisions(
  Ref ref,
  _MergeConnection source,
) async {
  // `/indexerstatus` returns only the indexers with an active problem, so this
  // list *is* the fault list — no filtering, and no counting against the total.
  final results = await Future.wait([
    ref.watch(prowlarrIndexerStatusForProvider(source.instanceId).future),
    ref.watch(prowlarrIndexersForProvider(source.instanceId).future),
  ]);
  final statuses = results[0] as List<ProwlarrIndexerStatus>;
  final indexers = results[1] as List<ProwlarrIndexer>;
  final names = {for (final indexer in indexers) indexer.id: indexer.name};

  return [
    for (final status in statuses)
      DashboardDecision(
        kind: DecisionKind.failingIndexer,
        // With the connection: two Prowlarr both number their indexers from
        // one.
        id: 'prowlarr-${source.instanceId}-${status.indexerId}',
        service: ServiceKey.prowlarr,
        title: names[status.indexerId] ?? 'Indexer ${status.indexerId}',
        detail: joinDisplayParts([
          'Failing',
          // Which Prowlarr, once there are two to tell apart.
          serviceWithConnection(ServiceKey.prowlarr, source.name, joiner: ' '),
          status.disabledTill == null ? null : 'disabled for now',
        ]),
        instanceId: source.instanceId,
        connectionName: source.name,
        actionInstanceId: source.instanceId,
        // The *first* failure, not the most recent one: an indexer that has been
        // failing since breakfast outranks one that failed a minute ago, and the
        // most recent failure of a long outage is always a minute ago.
        occurredAt:
            parseAddedTimestamp(status.initialFailure) ??
            parseAddedTimestamp(status.mostRecentFailure),
        actionId: status.indexerId,
        route: ServiceRoutes.prowlarrIndexer(status.indexerId),
      ),
  ];
}

Future<List<DashboardDecision>> _stoppedStackDecisions(
  Ref ref,
  _MergeConnection source,
) async {
  // The lens reads the live list the Dockge pages read, through the agent
  // they are looking at. Another connection is read once, through the hub of
  // its own login, which is where its Start goes too.
  final stacks = source.isLens
      ? await ref.watch(dockgeStackListProvider.future)
      : await ref
            .watch(dockgeServiceForProvider(source.instanceId))
            .fetchStacks();
  return [
    for (final stack in stacks)
      // `exited` only. A stack that is `inactive` was never started and a stack
      // the user stopped on purpose is not a fault — decision 15's "stopped on
      // purpose is neutral". An *exited* container is one that was running and
      // is not any more.
      if (stack.status == DockgeStackStatus.exited)
        DashboardDecision(
          kind: DecisionKind.stoppedStack,
          id: 'dockge-${source.instanceId}-${stack.endpoint}-${stack.name}',
          service: ServiceKey.dockge,
          title: stack.name,
          detail: joinDisplayParts([
            'Stack stopped',
            serviceWithConnection(ServiceKey.dockge, source.name, joiner: ' '),
          ]),
          instanceId: source.instanceId,
          connectionName: source.name,
          actionInstanceId: source.instanceId,
          // Dockge dates nothing: its stack list carries a status and a name and
          // no timestamp at all. Undated sorts last inside its kind rather than
          // inheriting "just now", which would put every stopped stack above
          // every dated fault.
          occurredAt: null,
          route: ServiceRoutes.dockgeStack(stack.name),
        ),
  ];
}

Future<List<DashboardDecision>> _expiringCertificateDecisions(
  Ref ref,
  _MergeConnection source,
) async {
  final certificates = await ref.watch(
    npmCertificatesForProvider(source.instanceId).future,
  );
  final now = DateTime.now();
  return [
    for (final certificate in certificates)
      if (certificate.isExpiringSoon(now))
        DashboardDecision(
          kind: DecisionKind.expiringCertificate,
          id: 'npm-cert-${source.instanceId}-${certificate.id}',
          service: ServiceKey.nginxProxyManager,
          title: certificate.domainNames.isEmpty
              ? certificate.niceName
              : certificate.domainNames.first,
          // An uploaded certificate does not renew: the row names it as one,
          // so a control without Renew reads as the truth rather than a gap.
          // It drops the service's name: beside "Open certificates", which is
          // wider than Renew, any longer line lost its last words to the
          // ellipsis on a 390pt phone, and the glyph already names the service.
          // Which of two it is on stays, by the connection's own name alone.
          detail: joinDisplayParts([
            _certificateExpiry(certificate, now),
            if (certificate.isLetsEncrypt)
              serviceWithConnection(
                ServiceKey.nginxProxyManager,
                source.name,
                joiner: ' ',
              )
            else
              source.name,
          ]),
          renewable: certificate.isLetsEncrypt,
          instanceId: source.instanceId,
          connectionName: source.name,
          actionInstanceId: source.instanceId,
          // The expiry date, standing in for "when did this start needing me".
          // Ordering by it puts the certificate closest to lapsing first, which
          // is what "oldest first" means for a deadline.
          occurredAt: certificate.expiresOn,
          route: ServiceRoutes.forService(ServiceKey.nginxProxyManager),
        ),
  ];
}

String _certificateExpiry(NpmCertificate certificate, DateTime now) {
  final noun = certificate.isLetsEncrypt
      ? 'Certificate'
      : 'Uploaded certificate';
  final expiresOn = certificate.expiresOn;
  if (expiresOn == null) return '$noun expiring';
  final days = expiresOn.difference(now).inDays;
  if (days < 0) return '$noun expired';
  if (days == 0) return '$noun expires today';
  if (days == 1) return '$noun expires tomorrow';
  return '$noun expires in $days days';
}

/// The decision a faulted transfer becomes, by what its fault is.
///
/// A blocked import is a manual import, filed under the library item and seeded
/// with the download's folder, on the connection the record came off. A stall
/// or a failure is a jump into the client. Before the fault had a kind, all
/// three were the second.
DashboardDecision _queueFaultDecision(ServiceQueueItem item) {
  if (item.fault == InFlightFault.needsImport) {
    return DashboardDecision(
      kind: DecisionKind.importBlocked,
      // With the connection: two Radarr both number their queues from one.
      id: 'import-blocked-${item.service.routeParam}-${item.instanceId}-${item.id}',
      service: item.service,
      title: item.title,
      // The shape `_failedImportDecision` prints, so the two import faults read
      // alike. No client: the bytes are on disk, and the client is not where
      // this is fixed. The connection is named when there are two.
      detail: joinDisplayParts([
        'Import blocked',
        serviceWithConnection(item.service, item.connectionName, joiner: ' '),
        item.warning,
      ]),
      occurredAt: item.stalledSince,
      route: item.route,
      actionId: item.mediaId,
      instanceId: item.instanceId,
      connectionName: item.connectionName,
      actionInstanceId: item.instanceId,
      importPath: item.outputPath,
    );
  }

  final isClientRow = item.clientService == item.service;
  return DashboardDecision(
    kind: DecisionKind.stalledDownload,
    // The cause, when the source gave one: what a folded row of several keeps
    // if they all share it.
    reason: item.warning,
    id: 'stall-${item.service.routeParam}-${item.instanceId}-${item.id}',
    service: item.service,
    title: item.title,
    detail: joinDisplayParts([
      item.warning ??
          switch (item.fault) {
            InFlightFault.failed => 'Failed',
            InFlightFault.stalled ||
            InFlightFault.needsImport ||
            null => StateWord.stuck.label,
          },
      item.detail == item.warning ? null : item.detail,
      // Which arr asked for it, once there are two to tell apart. A client's
      // own row is already named by its client label.
      if (!isClientRow && item.connectionName != null)
        serviceWithConnection(item.service, item.connectionName, joiner: ' '),
      item.clientLabel,
    ]),
    occurredAt: item.stalledSince,
    route: item.route,
    instanceId: item.instanceId,
    connectionName: item.connectionName,
    // The client the control opens, on the connection moving the bytes.
    actionInstanceId: item.clientInstanceId,
    // The decision acts on the client, which may not be a service this user has
    // set up at all — an \*arr can name a download client Cupola has no
    // connection to. The control stays drawn and tappable either way; see the
    // row.
    requiresService: _clientServiceFor(item),
  );
}

/// Which service the "open this transfer" control would jump to.
///
/// Null when the row already *is* the client: qBittorrent's own stalled torrent
/// opens in qBittorrent, which is not a cross-service jump and owes no hint.
/// An \*arr row joined to its client's row knows the client exactly; otherwise
/// the \*arr's own name for it is all there is.
ServiceKey? _clientServiceFor(ServiceQueueItem item) {
  final client = item.clientService;
  if (client != null) return client == item.service ? null : client;
  if (item.service == ServiceKey.qbittorrent) return null;
  return switch (item.clientLabel.toLowerCase()) {
    final label when label.contains('qbittorrent') => ServiceKey.qbittorrent,
    final label when label.contains('sab') => ServiceKey.sabnzbd,
    final label when label.contains('nzbget') => ServiceKey.nzbget,
    final label when label.contains('transmission') => ServiceKey.transmission,
    _ => null,
  };
}

DashboardDecision _failedImportDecision(ArrHistoryEntry entry) =>
    DashboardDecision(
      kind: DecisionKind.failedImport,
      // With the connection: each arr numbers its history from one.
      id: 'import-${entry.service.routeParam}-${entry.instanceId}-${entry.id}',
      service: entry.service,
      title: entry.title,
      detail: joinDisplayParts([
        'Import failed',
        serviceWithConnection(entry.service, entry.connectionName, joiner: ' '),
        entry.reason,
      ]),
      occurredAt: entry.at,
      // The library item a manual import would be filed under. Zero — a failed
      // grab of something the \*arr never added — leaves the wizard to ask.
      actionId: entry.mediaId <= 0 ? null : entry.mediaId,
      // The connection the record came off: the wizard files into that
      // server's library, under that server's id for the film.
      instanceId: entry.instanceId,
      connectionName: entry.connectionName,
      actionInstanceId: entry.instanceId,
      posterUrl: entry.posterUrl,
      route: entry.mediaId <= 0
          ? ServiceRoutes.forService(entry.service)
          : switch (entry.service) {
              ServiceKey.radarr => ServiceRoutes.radarrMovie(
                entry.mediaId,
                instanceId: entry.instanceId,
              ),
              ServiceKey.sonarr => ServiceRoutes.sonarrSeries(
                entry.mediaId,
                instanceId: entry.instanceId,
              ),
              ServiceKey.lidarr => ServiceRoutes.lidarrArtist(
                entry.mediaId,
                instanceId: entry.instanceId,
              ),
              _ => ServiceRoutes.forService(entry.service),
            },
    );

/// The two live figures one stack card shows.
///
/// Lives here rather than beside `serviceSignalProvider` because it is a
/// Dashboard concern: the deck, the status bar and the Portal's picker all want
/// exactly one figure and are right to. The card wants two, and reduces the same
/// KPI list through the same ranking — see `resolveServiceSignalPair` — so the
/// card's primary and the deck's single figure can never disagree about which
/// metric matters.
///
/// Note the deliberate lack of error handling: an unreachable service leaves
/// this in `AsyncError`, and the cell renders its reachability instead. Swallowing
/// the error into a null pair here would make "no metric to report" and "this
/// service is down" the same value.
final serviceSignalPairProvider = FutureProvider.autoDispose
    .family<ServiceSignalPair?, ServiceKey>((ref, service) async {
      final kpis = await ref.watch(serviceKpiProvider(service).future);
      return resolveServiceSignalPair(kpis);
      // Derived from `serviceKpiProvider`, which carries the flag: without it
      // a failed read bounced between shimmer and dash on the default backoff.
    }, retry: noProviderRetry);

/// The two figures a **folded** card shows: the fleet's, not the lens's.
///
/// A card carrying `×2` beside one server's numbers is the lens wearing the
/// fleet's clothes — it reads as a total and is short by whatever the other
/// server holds. This reduces the aggregate through the same ranking
/// [serviceSignalPairProvider] uses, so a single-connection service cannot
/// disagree with itself depending on which provider the cell happened to watch.
///
/// Null where there is no aggregate to show — a dark connection, a connection
/// the app cannot yet read on its own, or figures that do not fold. See
/// [foldedServiceKpisProvider]. The card then draws `×N` and no figure, which
/// is what the design asks for and the only honest reading available.
final foldedServiceSignalPairProvider = FutureProvider.autoDispose
    .family<ServiceSignalPair?, ServiceKey>((ref, service) async {
      final kpis = await ref.watch(foldedServiceKpisProvider(service).future);
      return kpis == null ? null : resolveServiceSignalPair(kpis);
      // Derived from `serviceKpiProvider`, which carries the flag: without it
      // a failed read bounced between shimmer and dash on the default backoff.
    }, retry: noProviderRetry);
