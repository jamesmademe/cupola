import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/providers/provider_retry.dart';
import 'package:cupola/core/api/api_client.dart';
import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/status/arr_queue_snapshot.dart';
import 'package:cupola/core/status/lexicon.dart';
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
import 'package:cupola/features/discover/presentation/discover_provider.dart';
import 'package:cupola/features/discover/data/seerr_service.dart';
import 'package:cupola/features/movies/data/radarr_service.dart';
import 'package:cupola/features/movies/presentation/movies_provider.dart';
import 'package:cupola/features/music/data/lidarr_service.dart';
import 'package:cupola/features/music/domain/lidarr_queue_snapshots.dart';
import 'package:cupola/features/music/domain/models/lidarr_album.dart';
import 'package:cupola/features/music/presentation/music_provider.dart';
import 'package:cupola/features/series/data/sonarr_service.dart';
import 'package:cupola/features/series/presentation/series_provider.dart';
import 'package:cupola/features/qbittorrent/data/qbittorrent_client.dart';
import 'package:cupola/features/qbittorrent/domain/models/parse_utils.dart';
import 'package:cupola/features/qbittorrent/domain/models/torrent.dart';
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
import 'package:cupola/features/services/domain/in_flight.dart';
import 'package:cupola/features/services/domain/recently_added.dart';
import 'package:cupola/features/services/domain/request_ordering.dart';
import 'package:cupola/features/services/domain/service_signal.dart';
import 'package:cupola/features/services/domain/service_summary.dart';
import 'package:cupola/features/services/domain/source_coverage.dart';
import 'package:cupola/features/services/presentation/service_kpi_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';
import 'package:cupola/features/npm/data/npm_client.dart';
import 'package:cupola/features/transmission/data/transmission_client.dart';
import 'package:cupola/features/truenas/data/truenas_service.dart';
import 'package:cupola/features/truenas/data/truenas_ws_client.dart';
import 'package:cupola/features/unraid/data/unraid_client.dart';

/// A live reachability probe for one service.
///
/// The `select` is load-bearing rather than a micro-optimisation, because of
/// what this provider *is*: one family entry per service, each of which opens a
/// connection and waits out a 5–8 second timeout ([_loadVersion] builds a fresh
/// qBittorrent/SABnzbd/NZBGet/Unraid client per call). Watching the whole
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
            if (value.isFault) faulted++;
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
});

/// The connection key for whichever instance of [service] is currently being
/// read.
///
/// Two watches, both narrow. Keying on the *first* instance instead would leave
/// every derived fetch stale the moment the lens moved: the clients underneath
/// are lens-aware, so they would go to the new server while the key that decides
/// whether to refetch still described the old one.
_ServiceConnection _watchConnection(Ref ref, ServiceKey service) {
  final instanceId = ref.watch(activeInstanceProvider(service))?.id ?? '';
  return ref.watch(
    currentSettingsProvider.select((s) => _connectionOfInstance(s, instanceId)),
  );
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
    );
  }
  return (
    configured: instance.isConfigured,
    url: instance.url,
    apiKey: instance.credential,
    username: instance.username,
    certFingerprint: settings.pinForUrl(instance.url),
  );
}

typedef ServiceStatusClientFactory =
    ApiClient Function({
      required String baseUrl,
      required String apiKey,
      String? pinnedCertFingerprint,
    });

final serviceStatusClientFactoryProvider = Provider<ServiceStatusClientFactory>(
  (ref) =>
      ({
        required String baseUrl,
        required String apiKey,
        String? pinnedCertFingerprint,
      }) => ApiClient(
        baseUrl: baseUrl,
        apiKey: apiKey,
        pinnedCertFingerprint: pinnedCertFingerprint,
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
    final client = QbittorrentClient(
      url: instance.url,
      username: instance.username.isNotEmpty ? instance.username : null,
      password: instance.credential.isNotEmpty ? instance.credential : null,
      certFingerprint: settings.pinForUrl(instance.url),
    );
    // Login-then-version is two hops on a cold client, so this gets the same
    // headroom as Transmission's 409 handshake pair.
    return _versionOrNull(
      client.getVersion,
      timeout: const Duration(seconds: 8),
      close: client.close,
    );
  }

  // The two long-lived clients, and the two that used to lie. Their providers
  // are built from the flat projections — the FIRST instance of the service —
  // so probing the second connection through them asked the first one whether
  // it was up and painted the answer on the second one's cell: a box that was
  // switched off reading green, and `foldedServiceHealthProvider` counting zero
  // offline. Every other branch here already builds a throwaway client from
  // `instance`, which is what makes a per-connection probe per-connection;
  // these two now do the same, and close it either way like the rest.
  if (service == ServiceKey.truenas) {
    final client = TrueNasWsClient(
      baseUrl: instance.url,
      apiKey: instance.credential,
      certFingerprint: settings.pinForUrl(instance.url),
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
    );
    return _versionOrNull(
      client.version,
      timeout: const Duration(seconds: 6),
      close: client.close,
    );
  }

  final createClient = ref.watch(serviceStatusClientFactoryProvider);
  final url = instance.url;
  final client = createClient(
    baseUrl: url,
    apiKey: instance.credential,
    pinnedCertFingerprint: settings.pinForUrl(url),
  );

  try {
    if (service == ServiceKey.seerr) {
      // Seerr's status endpoint is public. Probe one authenticated request
      // first, otherwise a wrong API key paints the dashboard green while
      // Activity and Overview fail with 403 later.
      await SeerrService(
        client,
      ).testConnection().timeout(const Duration(seconds: 5));
    }
    final response = await client
        .get(service.statusEndpoint)
        .timeout(const Duration(seconds: 5));
    final data = response.data;
    if (data is Map<String, dynamic>) {
      if (service == ServiceKey.bazarr) {
        final nested = mapOrNull(data['data']);
        return stringOrNull(nested?['bazarr_version']);
      }
      return (data['version'] ?? data['appVersion'])?.toString();
    }
    return null;
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
        service.getQueue,
        (item) => [
          intOrNull(mapOrNull(item['movie'])?['id'] ?? item['movieId']),
        ],
      );
    });

/// The Radarr queue indexed by movie id.
///
/// Every surface that badges a movie — grid, poster rail, detail page — reads
/// this one snapshot, so they cannot disagree about what is downloading.
/// Delegates to the connection the lens points at, so the surfaces that never
/// name one keep the shape they always had.
final radarrQueueSnapshotProvider = FutureProvider<ArrQueueSnapshot>((
  ref,
) async {
  final lens = ref.watch(activeInstanceProvider(ServiceKey.radarr))?.id ?? '';
  return ref.watch(radarrQueueSnapshotForProvider(lens).future);
});

/// The Sonarr queue of one named connection. See
/// [radarrQueueSnapshotForProvider].
final sonarrQueueSnapshotForProvider =
    FutureProvider.family<ArrQueueSnapshot, String>((ref, instanceId) async {
      final service = instanceId.isEmpty
          ? ref.watch(sonarrServiceProvider)
          : ref.watch(sonarrServiceForProvider(instanceId));
      return _loadArrQueueSnapshot(
        service.getQueue,
        (item) => [
          intOrNull(mapOrNull(item['series'])?['id'] ?? item['seriesId']),
        ],
      );
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
final lidarrQueueSnapshotsProvider = FutureProvider<LidarrQueueSnapshots>((
  ref,
) async {
  final service = ref.watch(lidarrServiceProvider);

  int? directArtistId(Map<String, dynamic> item) => intOrNull(
    mapOrNull(item['artist'])?['id'] ??
        mapOrNull(item['album'])?['artistId'] ??
        item['artistId'],
  );
  int? albumIdOf(Map<String, dynamic> item) =>
      intOrNull(mapOrNull(item['album'])?['id'] ?? item['albumId']);

  try {
    final queueItems = (await service.getQueue())
        .whereType<Map>()
        .map(stringKeyMap)
        .toList(growable: false);
    if (queueItems.isEmpty) {
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
        final batch = candidates
            .skip(start)
            .take(_lidarrAlbumLookupConcurrency);
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
        idsFor: (item) {
          final albumId = albumIdOf(item);
          return albumId == null ? const <int>[] : [albumId];
        },
      ),
    );
  } catch (_) {
    return LidarrQueueSnapshots.empty;
  }
});

/// Queued movie ids, derived from [radarrQueueSnapshotProvider].
final radarrQueuedMovieIdsProvider = FutureProvider<Set<int>>((ref) async {
  final snapshot = await ref.watch(radarrQueueSnapshotProvider.future);
  return snapshot.entriesById.keys.toSet();
});

/// Queued series ids, derived from [sonarrQueueSnapshotProvider].
final sonarrQueuedSeriesIdsProvider = FutureProvider<Set<int>>((ref) async {
  final snapshot = await ref.watch(sonarrQueueSnapshotProvider.future);
  return snapshot.entriesById.keys.toSet();
});

/// Queued artist ids, derived from [lidarrQueueSnapshotsProvider].
final lidarrQueuedArtistIdsProvider = FutureProvider<Set<int>>((ref) async {
  final snapshots = await ref.watch(lidarrQueueSnapshotsProvider.future);
  return snapshots.byArtist.entriesById.keys.toSet();
});

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
  });

  final ServiceKey service;

  /// The history record's own id. Unique per service, and what the decision row
  /// is keyed on — a media id is not, since one film can fail twice.
  final int id;

  /// The library item this record is about, for the route. Zero when the record
  /// does not name one, which is normal for a failed grab of something the arr
  /// never added.
  final int mediaId;

  final String title;

  /// The season (Sonarr) or album id (Lidarr) the record belongs to — what
  /// Recently added folds on. Null on Radarr and when the record does not say.
  final int? unitId;

  /// The record's own piece: `S01E03`, or the artist behind an album.
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
  // One narrow watch per source rather than the whole `SettingsModel`: this
  // depends on three URL/key pairs, and watching the object refetched every
  // history page on any settings write, a theme toggle included.
  final connections = {
    for (final service in const [
      ServiceKey.radarr,
      ServiceKey.sonarr,
      ServiceKey.lidarr,
    ])
      service: _watchConnection(ref, service),
  };

  Future<ArrHistory> from(
    ServiceKey service,
    Future<List<dynamic>> Function() load,
  ) async {
    final connection = connections[service];
    if (connection == null || !connection.configured) {
      return (
        entries: const <ArrHistoryEntry>[],
        coverage: SourceCoverage.none,
      );
    }
    try {
      final records = await load();
      return (
        entries: records
            .whereType<Map>()
            .map(stringKeyMap)
            .map(
              (record) => _historyEntryFrom(
                service,
                record,
                baseUrl: connection.url,
                apiKey: connection.apiKey,
              ),
            )
            .toList(growable: false),
        coverage: SourceCoverage.answeredBy(service),
      );
    } catch (error) {
      // The convention: a browse degrades to `[]` rather than taking the region
      // down — but the failure is kept, classified, so the count above the
      // rail can leave this arr out by name instead of counting it as zero.
      return (
        entries: const <ArrHistoryEntry>[],
        coverage: SourceCoverage.failure(service, error),
      );
    }
  }

  final results = await Future.wait([
    from(
      ServiceKey.radarr,
      () => ref
          .watch(radarrServiceProvider)
          .getHistory(pageSize: servicesHistoryPageSize),
    ),
    from(
      ServiceKey.sonarr,
      () => ref
          .watch(sonarrServiceProvider)
          .getHistory(pageSize: servicesHistoryPageSize),
    ),
    // Lidarr's records DO arrive with their artist and their album:
    // `LidarrService` overrides `getHistoryPage`, which this `getHistory`
    // delegates through, and injects `includeArtist`/`includeAlbum` there. So
    // the title resolves to the album (`arrPrimaryMediaTitle` reads `album`
    // then `artist`) rather than falling back to the raw `sourceTitle`, and
    // the tile's artwork is the album cover — see `_historyPosterUrl`.
    from(
      ServiceKey.lidarr,
      () => ref
          .watch(lidarrServiceProvider)
          .getHistory(pageSize: servicesHistoryPageSize),
    ),
  ]);

  return (
    entries: results.expand((result) => result.entries).toList(growable: false),
    coverage: SourceCoverage.merge(results.map((result) => result.coverage)),
  );
});

ArrHistoryEntry _historyEntryFrom(
  ServiceKey service,
  Map<String, dynamic> record, {
  required String baseUrl,
  required String apiKey,
}) {
  final data = mapOrNull(record['data']);
  final title =
      arrPrimaryMediaTitle(record) ?? arrReleaseTitle(record) ?? 'Unknown item';

  return ArrHistoryEntry(
    service: service,
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
final servicesRecentlyAddedProvider = FutureProvider<ServicesRecentlyAdded>((
  ref,
) async {
  final history = await ref.watch(servicesArrHistoryProvider.future);

  final items = [
    for (final entry in history.entries)
      if (entry.outcome != ArrImportOutcome.other)
        RecentlyAddedItem(
          service: entry.service,
          id: entry.mediaId,
          title: entry.title,
          posterUrl: entry.posterUrl,
          addedAt: entry.at,
          failed: entry.outcome == ArrImportOutcome.failed,
          unitId: entry.unitId,
          detail: entry.detail,
        ),
  ];

  return (
    items: sortRecentlyAdded(
      groupRecentlyAdded(items),
      limit: servicesRecentlyAddedLimit,
    ),
    coverage: history.coverage,
  );
});

/// What the Recently added rail draws, and which libraries answered for it.
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
    this.mediaId,
    this.outputPath,
  });

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

  /// The connection an \*arr row was read from, for a remedy that opens a flow
  /// bound to one connection — the import wizard's `?i=`.
  final String instanceId;

  /// The library item an \*arr row belongs to — the movie, series, artist or
  /// author — which a manual import is filed under. Null when the record names
  /// none, or when several records folded into this row name different ones.
  final int? mediaId;

  /// Where the client is writing, as the \*arr reports it — what a manual
  /// import is seeded from.
  final String? outputPath;

  /// Whether this transfer is genuinely moving, or waiting to.
  bool get isActive => fault == null;
}

/// Everything currently transferring, across every configured source.
///
/// This is the region the old dashboard put *last*, below three browse rails,
/// while sourcing it from Radarr and Sonarr only — so the most time-sensitive
/// thing on a control-room screen was both buried and mostly blind. It now covers
/// the two arr services it always did, plus Lidarr and Readarr, plus the three
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
  // Watch the seven connections this actually depends on, not the whole model.
  // A bare `ref.watch(currentSettingsProvider)` re-ran seven concurrent queue
  // fetches on every settings write — including a theme-mode toggle, which
  // cannot change a queue. Same shape as `serviceSummaryProvider`: watch the
  // narrow keys, read the model for the work.
  //
  // A record rather than a list, and that is the load-bearing part: `select`
  // compares with `==`, and a `List` has identity equality, so a list would
  // report a change on every rebuild and quietly preserve the bug it was meant
  // to fix. Records compare structurally, nested records included.
  final connections = {
    for (final service in const [
      ServiceKey.radarr,
      ServiceKey.sonarr,
      ServiceKey.lidarr,
      ServiceKey.readarr,
      ServiceKey.qbittorrent,
      ServiceKey.sabnzbd,
      ServiceKey.nzbget,
    ])
      service: _watchConnection(ref, service),
  };

  Future<ServicesQueue> from(
    ServiceKey service,
    Future<List<ServiceQueueItem>> Function() load,
  ) async {
    // The connection the loaders below actually read, not the service. Gated on
    // `isServiceConfigured` — true as soon as *any* instance is set up — this
    // asked the second Radarr for its queue on the first one's account, and the
    // failure went into the `catch` as an empty list.
    if (!(connections[service]?.configured ?? false)) {
      return (items: const <ServiceQueueItem>[], coverage: SourceCoverage.none);
    }
    try {
      return (
        items: await load(),
        coverage: SourceCoverage.answeredBy(service),
      );
    } catch (error) {
      return (
        items: const <ServiceQueueItem>[],
        coverage: SourceCoverage.failure(service, error),
      );
    }
  }

  final arrQueues = [
    for (final service in const [
      ServiceKey.radarr,
      ServiceKey.sonarr,
      ServiceKey.lidarr,
      ServiceKey.readarr,
    ])
      from(service, () => _loadServiceQueueItems(ref, service)),
  ];
  final clientQueues = [
    from(ServiceKey.qbittorrent, () => _loadQbittorrentQueueItems(ref)),
    from(ServiceKey.sabnzbd, () => _loadSabnzbdQueueItems(ref)),
    from(ServiceKey.nzbget, () => _loadNzbgetQueueItems(ref)),
  ];
  final results = await Future.wait([...arrQueues, ...clientQueues]);

  // One row per transfer, not one per source that can see it. A Radarr grab
  // moving through qBittorrent is in both queues, and concatenating them drew
  // it twice and counted it twice — and a stall in it became two decisions.
  final items = joinQueueSources(
    arr: results
        .take(arrQueues.length)
        .expand((result) => result.items)
        .toList(growable: false),
    clients: results
        .skip(arrQueues.length)
        .expand((result) => result.items)
        .toList(growable: false),
  );

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
  int? rateBytesPerSecond,
  int clients,
  SourceCoverage coverage,
});

final servicesInFlightProvider = FutureProvider<ServicesInFlight>((ref) async {
  final queue = await ref.watch(servicesQueueProvider.future);
  final items = queue.items;
  final active = items.where((item) => item.isActive).toList(growable: false);
  final faults = items.where((item) => !item.isActive).toList(growable: false);

  // Summed once per client, never once per row — see
  // [ServiceQueueItem.clientRateBytesPerSecond]. Keyed on the client rather
  // than on the row's service, because an \*arr row that absorbed a torrent
  // carries that torrent's client rate.
  final rates = <ServiceKey, int>{};
  for (final item in items) {
    final rate = item.clientRateBytesPerSecond;
    final client = item.clientService;
    if (rate != null && client != null) rates[client] = rate;
  }

  return (
    preview: active.take(servicesQueuePreviewLimit).toList(growable: false),
    activeCount: active.length,
    faults: faults,
    rateBytesPerSecond: rates.isEmpty
        ? null
        : rates.values.fold(0, (sum, rate) => sum + rate),
    clients: rates.length,
    coverage: queue.coverage,
  );
});

/// Joins the \*arr queues to the download-client queues, one row per transfer.
///
/// An \*arr queue record names the client's own id for the transfer it tracks
/// in `downloadId` — the torrent hash (upper case; qBittorrent reports it in
/// lower), the SABnzbd `nzo_id`, the NZBGet job's `drone` parameter (its NZBID
/// only when it has none) — so the two rows for one grab
/// are the same key in two spellings. The \*arr row wins: it knows the title,
/// the quality and whether the file can be imported. The client row lends it
/// what only the client measures — progress, bytes, time left, rate — and a
/// stall the \*arr has not noticed yet. A client row no \*arr claims (a torrent
/// added by hand) stays a row of its own.
///
/// Pure and top-level, so the rule is testable without a container.
List<ServiceQueueItem> joinQueueSources({
  required List<ServiceQueueItem> arr,
  required List<ServiceQueueItem> clients,
}) {
  String key(String? id) => id?.trim().toLowerCase() ?? '';

  final byId = <String, int>{};
  for (var index = 0; index < clients.length; index++) {
    final id = key(clients[index].id);
    if (id.isNotEmpty) byId.putIfAbsent(id, () => index);
  }

  final claimed = <int>{};
  final joined = <ServiceQueueItem>[];
  for (final item in arr) {
    final index = byId[key(item.downloadId)];
    if (index == null || !claimed.add(index)) {
      joined.add(item);
      continue;
    }
    joined.add(_joinedQueueItem(item, clients[index]));
  }

  return [
    ...joined,
    for (var index = 0; index < clients.length; index++)
      if (!claimed.contains(index)) clients[index],
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
    mediaId: arr.mediaId,
    outputPath: arr.outputPath,
  );
}

/// Active torrents, as in-flight items.
///
/// Filters to transfers that are genuinely moving or waiting to: a seeding
/// library of four hundred torrents is not "in flight", and unfiltered it would
/// crowd out every other source.
Future<List<ServiceQueueItem>> _loadQbittorrentQueueItems(Ref ref) async {
  final torrents = await ref.watch(allTorrentsProvider.future);
  final moving = torrents
      .where(
        (torrent) => switch (torrent.parsedState) {
          // `stalled` is only ever `stalledDL` — a stalled *upload* parses as
          // seeding — so it belongs here rather than being filtered out with the
          // rest of the seeding library. It arrives flagged and leaves this
          // region for the decisions above it.
          TorrentState.downloading ||
          TorrentState.metaDownloading ||
          TorrentState.stalled ||
          TorrentState.queuedDl => true,
          TorrentState.seeding ||
          TorrentState.checking ||
          TorrentState.paused ||
          TorrentState.queuedUp ||
          TorrentState.error ||
          TorrentState.unknown => false,
        },
      )
      .toList(growable: false);

  // The client's rate, summed over what it is actually downloading, and carried
  // on each of its rows.
  final clientRate = moving.fold<int>(
    0,
    (sum, torrent) => sum + torrent.dlSpeed,
  );

  return moving
      .map(
        (torrent) => ServiceQueueItem(
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
          clientLabel: ServiceKey.qbittorrent.title,
          clientService: ServiceKey.qbittorrent,
          clientRateBytesPerSecond: clientRate,
          // A stalled transfer is the one qBittorrent state worth surfacing on a
          // hub: it looks identical to a slow download until you notice it has
          // not moved.
          fault: torrent.parsedState == TorrentState.stalled
              ? InFlightFault.stalled
              : null,
          stalledSince: torrent.parsedState == TorrentState.stalled
              ? _epochSeconds(torrent.lastActivity)
              : null,
          detail: joinDisplayParts([
            formatSpeed(torrent.dlSpeed),
            '${torrent.seeders} seeds',
          ]),
          route: ServiceRoutes.qbittorrentTorrent(torrent.hash),
        ),
      )
      .toList(growable: false);
}

/// qBittorrent's "no estimate" sentinel, in seconds (100 days).
///
/// Printed literally it reads `100 d left`, which is not an estimate — it is the
/// client saying it has none. Mapped to null so the row prints `—`.
const int _qbNoEta = 8640000;

int? _qbEta(int eta) => eta <= 0 || eta >= _qbNoEta ? null : eta;

DateTime? _epochSeconds(int seconds) =>
    seconds <= 0 ? null : DateTime.fromMillisecondsSinceEpoch(seconds * 1000);

Future<List<ServiceQueueItem>> _loadSabnzbdQueueItems(Ref ref) async {
  final queue = await ref.watch(sabnzbdQueueProvider.future);
  final rate = (queue.kbPerSec * 1024).round();

  return queue.slots
      .map(
        (slot) => ServiceQueueItem(
          service: ServiceKey.sabnzbd,
          id: slot.nzoId,
          title: slot.filename,
          progress: slot.progress,
          // SABnzbd reports what is *left*, not what the job weighs:
          // `SabnzbdQueueSlot` parses `mbleft` and the response's `mb` is not
          // modelled at all. So the pair is unknown rather than inferred from
          // the percentage — a computed total is a number the server never
          // said, and this row would be the only place in the app printing one.
          doneBytes: null,
          totalBytes: null,
          etaSeconds: parseClockDuration(slot.timeLeft),
          clientLabel: ServiceKey.sabnzbd.title,
          clientService: ServiceKey.sabnzbd,
          clientRateBytesPerSecond: rate,
          // A paused queue is stopped *on purpose*, which the tone rule files
          // under neutral — not a fault, and not a decision.
          warning: queue.paused ? StateWord.stopped.label : null,
          route: ServiceRoutes.forService(ServiceKey.sabnzbd),
        ),
      )
      .toList(growable: false);
}

Future<List<ServiceQueueItem>> _loadNzbgetQueueItems(Ref ref) async {
  final groups = await ref.watch(nzbgetQueueProvider.future);
  const megabyte = 1024 * 1024;

  return groups
      .map(
        (group) => ServiceQueueItem(
          service: ServiceKey.nzbget,
          // The key an \*arr row names this job by — its `drone` parameter,
          // else the NZBID — so [joinQueueSources] can meet the two.
          id: group.downloadId,
          title: group.name,
          progress: group.progress,
          // Both sizes are nullable now — NZBGet reporting neither the `*MB`
          // key nor the `*Hi`/`*Lo` pair used to read as zero megabytes, which
          // made an unmeasured job render as a finished one.
          doneBytes: switch ((group.fileSizeMb, group.remainingSizeMb)) {
            (final int total, final int left) => (total - left) * megabyte,
            _ => null,
          },
          totalBytes: switch (group.fileSizeMb) {
            final int total => total * megabyte,
            _ => null,
          },
          // NZBGet reports a rate for the whole client and none per group, so
          // there is nothing to divide into an estimate. `—`, not a guess.
          etaSeconds: null,
          clientLabel: ServiceKey.nzbget.title,
          clientService: ServiceKey.nzbget,
          route: ServiceRoutes.forService(ServiceKey.nzbget),
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

/// Fetches a `/queue` and indexes it, degrading to an empty snapshot on failure
/// so a badge never blocks on an unreachable service.
Future<ArrQueueSnapshot> _loadArrQueueSnapshot(
  Future<List<dynamic>> Function() loadItems,
  Iterable<int?> Function(Map<String, dynamic> item) idsFor,
) async {
  try {
    return ArrQueueSnapshot.fromQueueItems(
      await loadItems(),
      idsFor: (item) => idsFor(item).whereType<int>(),
    );
  } catch (_) {
    return ArrQueueSnapshot.empty;
  }
}

/// One \*arr's queue as in-flight items. Throws when the queue cannot be read:
/// the caller keeps the failure, so a dark arr is named rather than counted as
/// an empty queue.
Future<List<ServiceQueueItem>> _loadServiceQueueItems(
  Ref ref,
  ServiceKey service,
) async {
  // The connection these records come off — the lens, which is what the
  // service providers below resolve to. Stamped on each row so a remedy that
  // opens a flow bound to one connection (the import wizard) opens it on this
  // one, even if the lens has moved by the time the user taps.
  final instanceId = ref.watch(activeInstanceProvider(service))?.id ?? '';
  final items = switch (service) {
    ServiceKey.radarr => await ref.watch(radarrServiceProvider).getQueue(),
    ServiceKey.sonarr => await ref.watch(sonarrServiceProvider).getQueue(),
    ServiceKey.lidarr => await ref.watch(lidarrServiceProvider).getQueue(),
    ServiceKey.readarr => await ref.watch(readarrServiceProvider).getQueue(),
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
    ServiceKey.plex => const <dynamic>[],
  };
  final records = items.whereType<Map>().map(stringKeyMap);
  return [
    for (final download in _groupQueueRecordsByDownload(records))
      _queueItemFromRecords(service, download, instanceId: instanceId),
  ];
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
    mediaId: mediaId,
    outputPath: stringOrNull(typedItem['outputPath']),
    route: switch (service) {
      ServiceKey.radarr =>
        intOrNull(typedItem['movieId']) == null
            ? null
            : ServiceRoutes.radarrMovie(intOrNull(typedItem['movieId'])!),
      ServiceKey.sonarr =>
        intOrNull(typedItem['seriesId']) == null
            ? null
            : ServiceRoutes.sonarrSeries(intOrNull(typedItem['seriesId'])!),
      ServiceKey.lidarr =>
        intOrNull(typedItem['artistId']) == null
            ? null
            : ServiceRoutes.lidarrArtist(intOrNull(typedItem['artistId'])!),
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

/// Everything waiting on a human, from every source, merged and ranked.
///
/// Reads what the page has already loaded — the requests it was going to show,
/// the queue the in-flight region reads, the history the recently-added rail
/// reads, and the three infrastructure providers the stack cards' KPIs already
/// watch. Nothing here is a new request; the region is a **view** of the page's
/// own data, which is why it can afford to be first on the screen.
///
/// Each source is gated on its service being configured and degrades to nothing
/// on failure: a region that answers "what needs me" must not itself become the
/// thing that needs you.
final dashboardDecisionsProvider = FutureProvider<List<DashboardDecision>>((
  ref,
) async {
  final settings = ref.watch(currentSettingsProvider);
  final decisions = <DashboardDecision>[];

  Future<void> collect(
    ServiceKey service,
    Future<List<DashboardDecision>> Function() load,
  ) async {
    if (!settings.isServiceConfigured(service)) return;
    try {
      decisions.addAll(await load());
    } catch (_) {
      // Degrades to nothing. See the doc above.
    }
  }

  await Future.wait([
    collect(ServiceKey.seerr, () => _pendingRequestDecisions(ref)),
    collect(ServiceKey.prowlarr, () => _failingIndexerDecisions(ref)),
    collect(ServiceKey.dockge, () => _stoppedStackDecisions(ref)),
    collect(
      ServiceKey.nginxProxyManager,
      () => _expiringCertificateDecisions(ref),
    ),
  ]);

  // Not gated on one service: the faults come from whichever of seven sources
  // reported one, and the queue provider has already gated each of those.
  try {
    final inFlight = await ref.watch(servicesInFlightProvider.future);
    decisions.addAll(inFlight.faults.map(_queueFaultDecision));
  } catch (_) {}

  try {
    final history = await ref.watch(servicesArrHistoryProvider.future);
    decisions.addAll(
      history.entries
          .where((entry) => entry.outcome == ArrImportOutcome.failed)
          .map(_failedImportDecision),
    );
  } catch (_) {}

  // Folded before ranking, so a group ranks where its oldest member would have.
  return rankDecisions(groupDecisions(decisions));
});

Future<List<DashboardDecision>> _pendingRequestDecisions(Ref ref) async {
  final requests = await ref.watch(servicesRequestsProvider.future);
  return [
    for (final request in requests)
      // `isAwaitingApproval` keys off the request's own status, never
      // `displayStatus` — a request for media that already exists reports
      // "Available" while nobody has approved it. See `request_ordering.dart`.
      if (isAwaitingApproval(request))
        DashboardDecision(
          kind: DecisionKind.pendingRequest,
          id: 'seerr-${request.id}',
          service: ServiceKey.seerr,
          title: request.media?.title ?? 'Unknown media',
          detail: joinDisplayParts([
            'Request',
            request.requestedBy?.displayName,
            request.type == 'tv' ? 'Series' : 'Movie',
          ]),
          occurredAt: parseAddedTimestamp(request.createdAt),
          actionId: request.id,
          posterUrl: ImageUtils.buildTmdbPosterUrl(request.media?.posterPath),
          route: _seerrRequestRoute(request),
        ),
  ];
}

String _seerrRequestRoute(SeerrRequest request) {
  final media = request.media;
  final id = media?.tmdbId ?? media?.id;
  if (id == null || id <= 0) return ServiceRoutes.seerr;
  return ServiceRoutes.seerrDetail(
    mediaType: request.type == 'tv' ? 'tv' : 'movie',
    id: id,
  );
}

Future<List<DashboardDecision>> _failingIndexerDecisions(Ref ref) async {
  // `/indexerstatus` returns only the indexers with an active problem, so this
  // list *is* the fault list — no filtering, and no counting against the total.
  final results = await Future.wait([
    ref.watch(prowlarrIndexerStatusProvider.future),
    ref.watch(prowlarrIndexersProvider.future),
  ]);
  final statuses = results[0] as List<ProwlarrIndexerStatus>;
  final indexers = results[1] as List<ProwlarrIndexer>;
  final names = {for (final indexer in indexers) indexer.id: indexer.name};

  return [
    for (final status in statuses)
      DashboardDecision(
        kind: DecisionKind.failingIndexer,
        id: 'prowlarr-${status.indexerId}',
        service: ServiceKey.prowlarr,
        title: names[status.indexerId] ?? 'Indexer ${status.indexerId}',
        detail: joinDisplayParts([
          'Failing',
          ServiceKey.prowlarr.title,
          status.disabledTill == null ? null : 'disabled for now',
        ]),
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

Future<List<DashboardDecision>> _stoppedStackDecisions(Ref ref) async {
  final stacks = await ref.watch(dockgeStackListProvider.future);
  return [
    for (final stack in stacks)
      // `exited` only. A stack that is `inactive` was never started and a stack
      // the user stopped on purpose is not a fault — decision 15's "stopped on
      // purpose is neutral". An *exited* container is one that was running and
      // is not any more.
      if (stack.status == DockgeStackStatus.exited)
        DashboardDecision(
          kind: DecisionKind.stoppedStack,
          id: 'dockge-${stack.endpoint}-${stack.name}',
          service: ServiceKey.dockge,
          title: stack.name,
          detail: joinDisplayParts(['Stack stopped', ServiceKey.dockge.title]),
          // Dockge dates nothing: its stack list carries a status and a name and
          // no timestamp at all. Undated sorts last inside its kind rather than
          // inheriting "just now", which would put every stopped stack above
          // every dated fault.
          occurredAt: null,
          route: ServiceRoutes.dockgeStack(stack.name),
        ),
  ];
}

Future<List<DashboardDecision>> _expiringCertificateDecisions(Ref ref) async {
  final certificates = await ref.watch(npmCertificatesProvider.future);
  final now = DateTime.now();
  return [
    for (final certificate in certificates)
      if (certificate.isExpiringSoon(now))
        DashboardDecision(
          kind: DecisionKind.expiringCertificate,
          id: 'npm-cert-${certificate.id}',
          service: ServiceKey.nginxProxyManager,
          title: certificate.domainNames.isEmpty
              ? certificate.niceName
              : certificate.domainNames.first,
          detail: joinDisplayParts([
            _certificateExpiry(certificate, now),
            ServiceKey.nginxProxyManager.title,
          ]),
          // The expiry date, standing in for "when did this start needing me".
          // Ordering by it puts the certificate closest to lapsing first, which
          // is what "oldest first" means for a deadline.
          occurredAt: certificate.expiresOn,
          route: ServiceRoutes.forService(ServiceKey.nginxProxyManager),
        ),
  ];
}

String _certificateExpiry(NpmCertificate certificate, DateTime now) {
  final expiresOn = certificate.expiresOn;
  if (expiresOn == null) return 'Certificate expiring';
  final days = expiresOn.difference(now).inDays;
  if (days < 0) return 'Certificate expired';
  if (days == 0) return 'Certificate expires today';
  if (days == 1) return 'Certificate expires tomorrow';
  return 'Certificate expires in $days days';
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
      id: 'import-blocked-${item.service.routeParam}-${item.id}',
      service: item.service,
      title: item.title,
      // The shape `_failedImportDecision` prints, so the two import faults read
      // alike. No client: the bytes are on disk, and the client is not where
      // this is fixed.
      detail: joinDisplayParts([
        'Import blocked',
        item.service.title,
        item.warning,
      ]),
      occurredAt: item.stalledSince,
      route: item.route,
      actionId: item.mediaId,
      instanceId: item.instanceId,
      importPath: item.outputPath,
    );
  }

  return DashboardDecision(
    kind: DecisionKind.stalledDownload,
    id: 'stall-${item.service.routeParam}-${item.id}',
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
      item.clientLabel,
    ]),
    occurredAt: item.stalledSince,
    route: item.route,
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
      id: 'import-${entry.service.routeParam}-${entry.id}',
      service: entry.service,
      title: entry.title,
      detail: joinDisplayParts([
        'Import failed',
        entry.service.title,
        entry.reason,
      ]),
      occurredAt: entry.at,
      // The library item a manual import would be filed under. Zero — a failed
      // grab of something the \*arr never added — leaves the wizard to ask.
      actionId: entry.mediaId <= 0 ? null : entry.mediaId,
      posterUrl: entry.posterUrl,
      route: entry.mediaId <= 0
          ? ServiceRoutes.forService(entry.service)
          : switch (entry.service) {
              ServiceKey.radarr => ServiceRoutes.radarrMovie(entry.mediaId),
              ServiceKey.sonarr => ServiceRoutes.sonarrSeries(entry.mediaId),
              ServiceKey.lidarr => ServiceRoutes.lidarrArtist(entry.mediaId),
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
