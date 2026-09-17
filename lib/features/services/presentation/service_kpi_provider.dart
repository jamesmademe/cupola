import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/models/service_kpi.dart';
import 'package:cupola/core/providers/provider_retry.dart';
import 'package:cupola/core/status/media_status.dart';
import 'package:cupola/features/bazarr/presentation/bazarr_provider.dart';
import 'package:cupola/features/dockge/domain/models/dockge_stack.dart';
import 'package:cupola/features/dockge/presentation/dockge_provider.dart';
import 'package:cupola/features/discover/domain/models/seerr_request.dart';
import 'package:cupola/features/discover/presentation/discover_provider.dart';
import 'package:cupola/features/movies/data/radarr_service.dart';
import 'package:cupola/features/movies/domain/models/radarr_movie.dart';
import 'package:cupola/features/music/data/lidarr_service.dart';
import 'package:cupola/features/music/domain/models/lidarr_artist.dart';
import 'package:cupola/features/series/data/sonarr_service.dart';
import 'package:cupola/features/series/domain/models/sonarr_series.dart';
import 'package:cupola/features/jellyfin/presentation/jellyfin_provider.dart';
import 'package:cupola/features/plex/presentation/plex_provider.dart';
import 'package:cupola/features/stream/domain/models/stream_library.dart';
import 'package:cupola/features/stream/domain/models/stream_session.dart';
import 'package:cupola/features/movies/presentation/movies_provider.dart';
import 'package:cupola/features/prowlarr/domain/models/prowlarr_models.dart';
import 'package:cupola/features/prowlarr/presentation/prowlarr_provider.dart';
import 'package:cupola/features/nzbget/domain/models/nzbget_models.dart';
import 'package:cupola/features/nzbget/presentation/nzbget_provider.dart';
import 'package:cupola/features/readarr/domain/models/readarr_models.dart';
import 'package:cupola/features/readarr/presentation/readarr_provider.dart';
import 'package:cupola/features/sabnzbd/presentation/sabnzbd_provider.dart';
import 'package:cupola/features/qbittorrent/domain/models/parse_utils.dart';
import 'package:cupola/features/qbittorrent/domain/models/torrent.dart';
import 'package:cupola/features/qbittorrent/presentation/qbittorrent_provider.dart';
import 'package:cupola/features/services/domain/kpi_aggregate.dart';
import 'package:cupola/features/services/domain/service_signal.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/npm/domain/models/npm_models.dart';
import 'package:cupola/features/npm/presentation/npm_provider.dart';
import 'package:cupola/features/transmission/domain/models/transmission_models.dart';
import 'package:cupola/features/transmission/presentation/transmission_provider.dart';
import 'package:cupola/features/truenas/presentation/truenas_provider.dart';
import 'package:cupola/features/unraid/domain/models/unraid_models.dart';
import 'package:cupola/features/unraid/presentation/unraid_provider.dart';

/// KPIs shown in the [ServiceKpiPeek] at the top of each service page.
///
/// Derives metrics from the library providers the pages already load, so it
/// adds no extra network calls and stays live-consistent with the list views.
final serviceKpiProvider = FutureProvider.autoDispose
    .family<List<ServiceKpi>, ServiceKey>((ref, service) async {
      switch (service) {
        case ServiceKey.radarr:
          return _radarrKpis(ref);
        case ServiceKey.sonarr:
          return _sonarrKpis(ref);
        case ServiceKey.lidarr:
          return _lidarrKpis(ref);
        case ServiceKey.qbittorrent:
          return _qbittorrentKpis(ref);
        case ServiceKey.seerr:
          return _seerrKpis(ref);
        case ServiceKey.bazarr:
          return _bazarrKpis(ref);
        case ServiceKey.truenas:
          return _truenasKpis(ref);
        case ServiceKey.dockge:
          return _dockgeKpis(ref);
        case ServiceKey.prowlarr:
          return _prowlarrKpis(ref);
        case ServiceKey.readarr:
          return _readarrKpis(ref);
        case ServiceKey.sabnzbd:
          return _sabnzbdKpis(ref);
        case ServiceKey.nzbget:
          return _nzbgetKpis(ref);
        case ServiceKey.unraid:
          return _unraidKpis(ref);
        case ServiceKey.transmission:
          return _transmissionKpis(ref);
        case ServiceKey.nginxProxyManager:
          return _npmKpis(ref);
        case ServiceKey.jellyfin:
          return _streamKpis(
            ref.watch(jellyfinSessionsProvider.future),
            ref.watch(jellyfinLibrariesProvider.future),
          );
        case ServiceKey.plex:
          return _streamKpis(
            ref.watch(plexSessionsProvider.future),
            ref.watch(plexLibrariesProvider.future),
          );
      }
    });

/// The same KPIs, for one **named connection** rather than for the lens.
///
/// The Dashboard's stack card needs this: a service with two connections draws
/// `×2` and the fleet's figures, and there is no fleet figure to compute while
/// the only thing the app can ask is "what does the lens say". Keyed on
/// [InstanceRef] and not on a bare id, for the reason that record already
/// carries — a probe for a connection that has since been removed still has to
/// know what kind of thing it was.
///
/// The lens's own id collapses back onto [serviceKpiProvider] rather than
/// fetching the same server twice, which is the same collapse
/// `requestsForProvider` and the `*ServiceFor` families make, and what keeps an
/// override of the plain provider from being bypassed in tests.
///
/// **Null means this connection cannot be read on its own yet**, which is not
/// the same as having no figures. Four services can answer per connection today
/// — Radarr, Sonarr, Lidarr and Seerr, the four with a `*ServiceForProvider` to
/// build a client from an id. The other thirteen (qBittorrent, SABnzbd, NZBGet,
/// Transmission, Prowlarr, Bazarr, Readarr, Dockge, TrueNAS, Unraid, NPM,
/// Jellyfin, Plex) have no per-connection client provider at all: their client
/// providers read `activeInstanceProvider` themselves and take no id, so there
/// is nothing to ask a second server with. That is the missing piece, named
/// rather than stubbed — a fold that guessed would print the lens's rate as the
/// fleet's, which is the bug this provider exists to end.
final serviceKpiForProvider = FutureProvider.autoDispose
    .family<List<ServiceKpi>?, InstanceRef>((ref, key) async {
      final lens = ref.watch(activeInstanceProvider(key.service))?.id ?? '';
      if (key.instanceId.isEmpty || key.instanceId == lens) {
        return ref.watch(serviceKpiProvider(key.service).future);
      }
      return switch (key.service) {
        ServiceKey.radarr => await _radarrKpisFor(ref, key.instanceId),
        ServiceKey.sonarr => await _sonarrKpisFor(ref, key.instanceId),
        ServiceKey.lidarr => await _lidarrKpisFor(ref, key.instanceId),
        ServiceKey.seerr => await _seerrKpisFor(ref, key.instanceId),
        _ => null,
      };
    });

/// The whole service's figures, folded across every connection it has.
///
/// Null when there is no aggregate to show, and the three reasons are all the
/// same refusal:
///
///  * **a connection is dark.** Gated on `offline == 0` before anything is
///    fetched: the fold is never partial, because a sum missing a term looks
///    exactly like a sum.
///  * **a connection cannot be read per connection** — see
///    [serviceKpiForProvider].
///  * **the figures do not fold** — see [aggregateServiceKpis], which is where
///    the arithmetic and, more importantly, the refusals live.
///
/// A single-connection service folds to itself, so the card does not have to
/// know whether it is looking at one server or six.
final foldedServiceKpisProvider = FutureProvider.autoDispose
    .family<List<ServiceKpi>?, ServiceKey>((ref, service) async {
      final settings = ref.watch(currentSettingsProvider);
      final connections = settings.configuredInstancesOf(service);
      if (connections.isEmpty) return null;

      // Lens first. `aggregateServiceKpis` falls back to the head of this list
      // for every figure whose unit cannot be added — a percentage, a ratio, a
      // state word — and the lens is the connection the rest of the app is
      // already pointed at, so it is the only defensible one to keep.
      final lens = ref.watch(activeInstanceProvider(service))?.id;
      final ordered = [
        for (final connection in connections)
          if (connection.id == lens) connection,
        for (final connection in connections)
          if (connection.id != lens) connection,
      ];

      // Reachability first, and **awaited**. Reading the synchronous fold
      // instead was the bug this line replaces: on a cold open every probe is
      // still in flight, so `offline` is zero, the gate opens, and the fold
      // publishes a sum over however many servers happened to have answered.
      // The figure has to wait for every connection to have said something,
      // because that is the whole claim it makes.
      final answers = await Future.wait([
        for (final connection in ordered)
          _connectionAnswers(ref, (
            service: service,
            instanceId: connection.id,
          )),
      ]);
      if (answers.contains(false)) return null;

      final perConnection = await Future.wait([
        for (final connection in ordered)
          ref.watch(
            serviceKpiForProvider((
              service: service,
              instanceId: connection.id,
            )).future,
          ),
      ]);
      return aggregateServiceKpis(perConnection);
    });

/// Whether one connection answered, with a probe that threw counted as a no.
///
/// `instanceSummaryProvider` normally reports an unreachable server as an
/// offline summary rather than by throwing, but the fold must not be the place
/// that finds out otherwise: an error escaping here would take the card into
/// `AsyncError` and lose the reading for every connection that *was* fine.
Future<bool> _connectionAnswers(Ref ref, InstanceRef key) async {
  try {
    return (await ref.watch(instanceSummaryProvider(key).future)).isOnline;
  } catch (_) {
    return false;
  }
}

/// The single live figure a service contributes to the stack matrix on
/// `/services`.
///
/// Reads [serviceKpiProvider] and reduces it through [resolveServiceSignal], so
/// the matrix costs nothing beyond what the KPI rails already fetch and the
/// hub's cell agrees with the service page's peek by construction.
///
/// Note the deliberate lack of error handling: an unreachable service leaves
/// this in `AsyncError`, and the cell renders its reachability instead of a
/// signal. Swallowing the error into a null signal here would make "no metric to
/// report" and "this service is down" the same value.
final serviceSignalProvider = FutureProvider.autoDispose
    .family<ServiceSignal?, ServiceKey>((ref, service) async {
      final kpis = await ref.watch(serviceKpiProvider(service).future);
      return resolveServiceSignal(kpis);
    });

int _statInt(Map<String, dynamic>? stats, String key) =>
    (stats?[key] as num?)?.toInt() ?? 0;

/// Flags a metric as a **fault** — something that was meant to be working and
/// is not, and the only one of the three that earns amber.
StatusTone? _faultIf(bool condition) => condition ? StatusTone.warning : null;

/// Flags a metric as **backlog** — work that has not happened yet.
///
/// Noteworthy, because a pile of missing films is why you opened the service;
/// untoned, because it is the resting state of a media manager and not a
/// problem with one. This is the distinction the old single `_warnIf` could not
/// express, and the reason every \*arr shipped with its baseline painted in the
/// alarm colour.
StatusTone? _backlogIf(bool condition) => condition ? StatusTone.neutral : null;

/// Flags a metric as **activity** rather than as a problem: bytes are moving,
/// or somebody is watching, because the stack is doing its job.
StatusTone? _activityIf(bool condition) => condition ? StatusTone.info : null;

/// One figure, or the em dash that stands in for it.
///
/// A null [value] means *nobody answered*, which is the case every \*arr
/// builder below used to print as `0`. Routing both readings of a card through
/// one call is what keeps the label and the icon written once: the rail shows
/// the same four cards whether the server replied or not, so a reader can see
/// *which* figure is missing rather than watching the strip change shape.
ServiceKpi _figure({
  required String label,
  required IconData icon,
  required String? value,
  StatusTone? tone,
  String? note,
}) => value == null
    ? ServiceKpi.unavailable(label: label, icon: icon, note: note)
    : ServiceKpi(label: label, value: value, icon: icon, tone: tone);

/// What an unanswered figure says instead of a number.
///
/// Carried by the **first** card only. The note replaces the label on the card
/// that holds it (the rail is two lines tall by construction), so putting it on
/// all four would leave a strip of four identical reasons and no way to tell
/// which absence is which.
String _notAnswering(ServiceKey service) => '${service.title} not answering';

/// The shared KPI set for a media server, identical for Jellyfin and Plex.
///
/// Three metrics, and the order is load-bearing in two ways that
/// `resolveServiceSignal` depends on.
///
/// **`Streams` is first, so it is the resting fallback.** With nothing flagged
/// the matrix cell shows `kpis.first`, and `0 streams` is both true and live —
/// unlike a library total, which DESIGN.md rightly calls the least live thing you
/// could put on a control-room screen.
///
/// **`Streams` is only flagged while nothing is transcoding.** The cell shows the
/// *first* flagged KPI, so gating it this way lets the more urgent fact win
/// without teaching the resolver about precedence: idle reads `0 streams` in
/// neutral, a healthy stream reads `2 streaming` in info blue, and the moment the
/// box starts re-encoding it reads `1 transcode` in warning amber. One rule, three
/// correct readings, no special-casing in the shared resolver.
///
/// **There is no aggregate bitrate metric, deliberately.** Neither server reports
/// measured outbound throughput: Jellyfin only carries a bitrate while
/// transcoding, and Plex's `Session.bandwidth` is a reservation. Summing those
/// would add two different units together and present the result as the box's
/// egress — a fabricated number. Per-session bitrate is shown on the board, where
/// `StreamSession.bitrateIsNominal` can say what it actually is.
Future<List<ServiceKpi>> _streamKpis(
  Future<List<StreamSession>> sessionsFuture,
  Future<List<StreamLibrary>> librariesFuture,
) async {
  final sessions = await sessionsFuture;
  final libraries = await librariesFuture;
  final transcodes = sessions.where((s) => s.playMethod.isTranscode).length;

  return [
    ServiceKpi(
      label: 'Streams',
      value: '${sessions.length}',
      icon: Icons.play_circle_outline_rounded,
      tone: _activityIf(sessions.isNotEmpty && transcodes == 0),
    ),
    ServiceKpi(
      label: 'Transcodes',
      value: '$transcodes',
      icon: Icons.memory_rounded,
      tone: _faultIf(transcodes > 0),
    ),
    ServiceKpi(
      label: 'Libraries',
      value: '${libraries.length}',
      icon: Icons.video_library_outlined,
    ),
  ];
}

/// The Radarr library, read so that a failure survives the fetch.
///
/// Not [moviesProvider]: that one goes through `fetchAllItems`, which swallows
/// every failure into `[]`, so an unreachable Radarr resolved it *successfully*
/// and the rail printed `Movies 0 · Monitored 0 · Missing 0` under an identity
/// band whose own probe already read Unreachable. See `getMoviesOrThrow`.
///
/// Plain, not `autoDispose`, matching `moviesProvider` beside it: the library
/// is a session-scoped read, and `serviceKpiProvider` *is* `autoDispose` — a
/// disposing source under it would turn one `GET /movie` per session into one
/// per visit to the Dashboard and to every Radarr tab. Pull-to-refresh
/// invalidates it explicitly.
///
/// **`retry: noProviderRetry` is load-bearing**, not hygiene. Riverpod's
/// default retry re-runs a throwing build ten times with backoff, and a
/// `DioException` is an `Exception`, so it engages on every network failure —
/// which means `await ref.watch(...future)` inside the `catch` below does not
/// settle for some forty seconds. The `catch` exists precisely to report that
/// the server did not answer, so holding it until the retries run out is the
/// rail sitting in its skeleton state instead of saying so. Measured: the four
/// tests for this timed out at thirty seconds each before the policy went on.
/// See `lib/core/providers/provider_retry.dart`.
final radarrKpiLibraryProvider = FutureProvider<List<RadarrMovie>>((ref) {
  return ref.watch(radarrServiceProvider).getMoviesOrThrow();
}, retry: noProviderRetry);

/// The Sonarr library. See [radarrKpiLibraryProvider].
///
/// Its own rather than a share of `sonarrOverviewSeriesProvider`, which reads
/// the same endpoint the same way: that one carries the default retry, on
/// purpose, because the Overview watches it as an `AsyncValue` and wants the
/// blip to heal itself. This one is *awaited* in a `catch`, and the two
/// policies cannot both hold on one provider.
final sonarrKpiLibraryProvider = FutureProvider<List<SonarrSeries>>((ref) {
  return ref.watch(sonarrServiceProvider).getSeriesOrThrow();
}, retry: noProviderRetry);

/// The Lidarr library. See [radarrKpiLibraryProvider].
final lidarrKpiLibraryProvider = FutureProvider<List<LidarrArtist>>((ref) {
  return ref.watch(lidarrServiceProvider).getArtistsOrThrow();
}, retry: noProviderRetry);

/// The Readarr library. See [radarrKpiLibraryProvider].
final readarrKpiLibraryProvider = FutureProvider<List<ReadarrAuthor>>((ref) {
  return ref.watch(readarrServiceProvider).getAuthorsOrThrow();
}, retry: noProviderRetry);

Future<List<ServiceKpi>> _radarrKpis(Ref ref) async {
  final List<RadarrMovie> movies;
  try {
    movies = await ref.watch(radarrKpiLibraryProvider.future);
  } catch (_) {
    // The queue figure goes too. It comes off the same server through
    // `radarrQueueSnapshotProvider`, which degrades to an empty snapshot — so
    // once the library has told us the server is dark, `Queue 0` is the same
    // fabrication wearing a different label.
    return _radarrKpisFrom(null, null, note: _notAnswering(ServiceKey.radarr));
  }
  final queued = await ref.watch(radarrQueuedMovieIdsProvider.future);
  return _radarrKpisFrom(movies, queued.length);
}

/// The same four figures for one **named** connection, whatever the lens is on.
///
/// Only ever called for a connection that is *not* the lens — see
/// [serviceKpiForProvider], which collapses the lens back onto the plain
/// builder so the card and the library screen keep reading one cache.
Future<List<ServiceKpi>> _radarrKpisFor(Ref ref, String instanceId) async {
  final List<RadarrMovie> movies;
  try {
    movies = await ref
        .watch(radarrServiceForProvider(instanceId))
        .getMoviesOrThrow();
  } catch (_) {
    return _radarrKpisFrom(null, null, note: _notAnswering(ServiceKey.radarr));
  }
  final queue = await ref.watch(
    radarrQueueSnapshotForProvider(instanceId).future,
  );
  return _radarrKpisFrom(movies, queue.entriesById.length);
}

/// Null means the server did not answer — see [_figure]. Never `[]`, which is
/// an answer: it says the library is there and empty.
List<ServiceKpi> _radarrKpisFrom(
  List<RadarrMovie>? movies,
  int? queued, {
  String? note,
}) {
  final monitored = movies?.where((m) => m.monitored).length;
  final missing = movies?.where((m) => m.monitored && !m.hasFile).length;
  return [
    _figure(
      label: 'Movies',
      value: movies == null ? null : '${movies.length}',
      icon: Icons.movie_rounded,
      note: note,
    ),
    _figure(
      label: 'Monitored',
      value: monitored == null ? null : '$monitored',
      icon: Icons.visibility_rounded,
    ),
    _figure(
      label: 'Missing',
      value: missing == null ? null : '$missing',
      icon: Icons.report_gmailerrorred_rounded,
      tone: _backlogIf(missing != null && missing > 0),
    ),
    _figure(
      label: 'Queue',
      value: queued == null ? null : '$queued',
      icon: Icons.download_rounded,
    ),
  ];
}

Future<List<ServiceKpi>> _sonarrKpis(Ref ref) async {
  try {
    // [sonarrKpiLibraryProvider], not `seriesProvider`: the latter reads
    // `getSeries`, which swallows its own failure into `[]`, and every figure
    // below it was a confident zero for a question nobody answered.
    return _sonarrKpisFrom(await ref.watch(sonarrKpiLibraryProvider.future));
  } catch (_) {
    return _sonarrKpisFrom(null, note: _notAnswering(ServiceKey.sonarr));
  }
}

/// See [_radarrKpisFor].
Future<List<ServiceKpi>> _sonarrKpisFor(Ref ref, String instanceId) async {
  try {
    return _sonarrKpisFrom(
      await ref.watch(sonarrServiceForProvider(instanceId)).getSeriesOrThrow(),
    );
  } catch (_) {
    return _sonarrKpisFrom(null, note: _notAnswering(ServiceKey.sonarr));
  }
}

/// Null means the server did not answer. See [_radarrKpisFrom].
List<ServiceKpi> _sonarrKpisFrom(List<SonarrSeries>? series, {String? note}) {
  var epHave = 0;
  var epTotal = 0;
  var monitored = 0;
  for (final s in series ?? const <SonarrSeries>[]) {
    if (s.monitored) monitored++;
    epHave += _statInt(s.statistics, 'episodeFileCount');
    epTotal += _statInt(s.statistics, 'episodeCount');
  }
  final missing = (epTotal - epHave).clamp(0, epTotal);
  final answered = series != null;
  return [
    _figure(
      label: 'Series',
      value: answered ? '${series.length}' : null,
      icon: Icons.tv_rounded,
      note: note,
    ),
    _figure(
      label: 'Episodes',
      value: answered ? '$epHave/$epTotal' : null,
      icon: Icons.playlist_play_rounded,
    ),
    _figure(
      label: 'Missing',
      value: answered ? '$missing' : null,
      icon: Icons.report_gmailerrorred_rounded,
      tone: _backlogIf(answered && missing > 0),
    ),
    _figure(
      label: 'Monitored',
      value: answered ? '$monitored' : null,
      icon: Icons.visibility_rounded,
    ),
  ];
}

Future<List<ServiceKpi>> _lidarrKpis(Ref ref) async {
  try {
    // [lidarrKpiLibraryProvider], not `musicProvider`: see [_radarrKpis].
    return _lidarrKpisFrom(await ref.watch(lidarrKpiLibraryProvider.future));
  } catch (_) {
    return _lidarrKpisFrom(null, note: _notAnswering(ServiceKey.lidarr));
  }
}

/// See [_radarrKpisFor].
Future<List<ServiceKpi>> _lidarrKpisFor(Ref ref, String instanceId) async {
  try {
    return _lidarrKpisFrom(
      await ref.watch(lidarrServiceForProvider(instanceId)).getArtistsOrThrow(),
    );
  } catch (_) {
    return _lidarrKpisFrom(null, note: _notAnswering(ServiceKey.lidarr));
  }
}

/// Null means the server did not answer. See [_radarrKpisFrom].
List<ServiceKpi> _lidarrKpisFrom(List<LidarrArtist>? artists, {String? note}) {
  var albums = 0;
  var trackHave = 0;
  var trackTotal = 0;
  for (final a in artists ?? const <LidarrArtist>[]) {
    albums += a.albumCount;
    trackHave += a.trackFileCount;
    trackTotal += a.trackCount;
  }
  final missing = (trackTotal - trackHave).clamp(0, trackTotal);
  final answered = artists != null;
  return [
    _figure(
      label: 'Artists',
      value: answered ? '${artists.length}' : null,
      icon: Icons.person_rounded,
      note: note,
    ),
    _figure(
      label: 'Albums',
      value: answered ? '$albums' : null,
      icon: Icons.album_rounded,
    ),
    _figure(
      label: 'Tracks',
      value: answered ? '$trackHave/$trackTotal' : null,
      icon: Icons.music_note_rounded,
    ),
    _figure(
      label: 'Missing',
      value: answered ? '$missing' : null,
      icon: Icons.report_gmailerrorred_rounded,
      tone: _backlogIf(answered && missing > 0),
    ),
  ];
}

Future<List<ServiceKpi>> _qbittorrentKpis(Ref ref) async {
  final torrents = await ref.watch(allTorrentsProvider.future);
  var active = 0;
  var downloading = 0;
  var seeding = 0;
  var dl = 0;
  var up = 0;
  for (final t in torrents) {
    final state = TorrentState.fromString(t.state);
    if (state.isActive) active++;
    if (state == TorrentState.downloading ||
        state == TorrentState.metaDownloading) {
      downloading++;
    }
    if (state == TorrentState.seeding) seeding++;
    dl += t.dlSpeed;
    up += t.upSpeed;
  }
  return [
    ServiceKpi(label: 'Active', value: '$active', icon: Icons.bolt_rounded),
    ServiceKpi(
      label: 'Down',
      value: formatSpeed(dl),
      icon: Icons.south_rounded,
      tone: _activityIf(dl > 0),
    ),
    ServiceKpi(label: 'Up', value: formatSpeed(up), icon: Icons.north_rounded),
    ServiceKpi(label: 'Seeding', value: '$seeding', icon: Icons.upload_rounded),
    ServiceKpi(
      label: 'Downloading',
      value: '$downloading',
      icon: Icons.download_rounded,
    ),
  ];
}

Future<List<ServiceKpi>> _seerrKpis(Ref ref) async =>
    _seerrKpisFrom(await ref.watch(requestsProvider.future));

/// See [_radarrKpisFor]. Seerr already owned its per-connection read, because a
/// request id is per instance and a merged list cannot be acted on by id alone.
Future<List<ServiceKpi>> _seerrKpisFor(Ref ref, String instanceId) async =>
    _seerrKpisFrom(await ref.watch(requestsForProvider(instanceId).future));

List<ServiceKpi> _seerrKpisFrom(List<SeerrRequest> requests) {
  var pending = 0;
  var processing = 0;
  var available = 0;
  for (final r in requests) {
    // Pending counts the requests that still need a decision, so it reads the
    // request's OWN status — the same source `request_ordering.dart`,
    // `seerr_request_filter.dart` and the /activity tiles read, and for the same
    // documented reason. `displayStatus` answers a different question: it lets
    // the media's availability override the request, so a request still in
    // pendingApproval whose media Radarr already holds reports "Available" —
    // which is how this KPI came to show "Pending 0" while /activity was
    // offering an Approve button for that very record.
    if (r.status == RequestStatus.pendingApproval) pending++;

    // The other two stay on displayStatus, which is the right source for them:
    // they describe where the media is, not what the request needs.
    switch (r.displayStatus.kind) {
      case SeerrRequestDisplayKind.approved:
      case SeerrRequestDisplayKind.processing:
        processing++;
      case SeerrRequestDisplayKind.available:
      case SeerrRequestDisplayKind.partiallyAvailable:
      case SeerrRequestDisplayKind.completed:
        available++;
      case SeerrRequestDisplayKind.pending:
      case SeerrRequestDisplayKind.declined:
      case SeerrRequestDisplayKind.failed:
      case SeerrRequestDisplayKind.deleted:
      case SeerrRequestDisplayKind.unknown:
        break;
    }
  }
  return [
    ServiceKpi(
      label: 'Requests',
      value: '${requests.length}',
      icon: Icons.inbox_rounded,
    ),
    ServiceKpi(
      label: 'Pending',
      value: '$pending',
      icon: Icons.hourglass_top_rounded,
      tone: _backlogIf(pending > 0),
    ),
    ServiceKpi(
      label: 'Processing',
      value: '$processing',
      icon: Icons.sync_rounded,
    ),
    ServiceKpi(
      label: 'Available',
      value: '$available',
      icon: Icons.check_circle_rounded,
    ),
  ];
}

Future<List<ServiceKpi>> _truenasKpis(Ref ref) async {
  final dashboard = await ref.watch(truenasDashboardProvider.future);
  final pools = dashboard.pools;
  final maxUsed = pools
      .map((p) => p.usedFraction ?? 0)
      .fold<double>(0, (max, v) => v > max ? v : max);
  final activeAlerts = dashboard.activeAlerts.length;
  final running = dashboard.services.where((s) => s.running).length;
  return [
    ServiceKpi(
      label: 'Pools',
      value: '${pools.length}',
      icon: Icons.dns_rounded,
    ),
    ServiceKpi(
      label: 'Used',
      value: '${(maxUsed * 100).round()}%',
      icon: Icons.pie_chart_rounded,
      tone: _faultIf(maxUsed >= 0.8),
    ),
    ServiceKpi(
      label: 'Alerts',
      value: '$activeAlerts',
      icon: Icons.warning_amber_rounded,
      tone: _faultIf(activeAlerts > 0),
    ),
    ServiceKpi(label: 'Services', value: '$running', icon: Icons.bolt_rounded),
  ];
}

Future<List<ServiceKpi>> _dockgeKpis(Ref ref) async {
  final stacks = await ref.watch(dockgeStackListProvider.future);
  final running = stacks
      .where((s) => s.status == DockgeStackStatus.running)
      .length;
  final exited = stacks
      .where((s) => s.status == DockgeStackStatus.exited)
      .length;
  final inactive = stacks.length - running - exited;
  return [
    ServiceKpi(
      label: 'Stacks',
      value: '${stacks.length}',
      icon: Icons.layers_rounded,
    ),
    ServiceKpi(
      label: 'Running',
      value: '$running',
      icon: Icons.play_circle_rounded,
    ),
    ServiceKpi(
      label: 'Exited',
      value: '$exited',
      icon: Icons.stop_circle_rounded,
      tone: _faultIf(exited > 0),
    ),
    ServiceKpi(
      label: 'Inactive',
      value: '$inactive',
      icon: Icons.pause_circle_rounded,
    ),
  ];
}

Future<List<ServiceKpi>> _bazarrKpis(Ref ref) async {
  final b = await ref.watch(bazarrBadgesProvider.future);
  return [
    ServiceKpi(
      label: 'Wanted',
      value: '${b.totalWanted}',
      icon: Icons.subtitles_off_rounded,
      tone: _backlogIf(b.totalWanted > 0),
    ),
    ServiceKpi(
      label: 'Episodes',
      value: '${b.episodes}',
      icon: Icons.tv_rounded,
    ),
    ServiceKpi(
      label: 'Movies',
      value: '${b.movies}',
      icon: Icons.movie_rounded,
    ),
    ServiceKpi(
      label: 'Providers',
      value: '${b.providers}',
      icon: Icons.cloud_rounded,
    ),
  ];
}

Future<List<ServiceKpi>> _prowlarrKpis(Ref ref) async {
  // The two fetches are independent; run them in parallel.
  final results = await Future.wait([
    ref.watch(prowlarrIndexersProvider.future),
    ref.watch(prowlarrIndexerStatsProvider.future),
  ]);
  final indexers = results[0] as List<ProwlarrIndexer>;
  final stats = results[1] as ProwlarrIndexerStats;
  final active = indexers.where((i) => i.enable).length;
  return [
    ServiceKpi(
      label: 'Indexers',
      value: '$active',
      icon: Icons.travel_explore_rounded,
    ),
    ServiceKpi(
      label: 'Queries',
      value: '${stats.totalQueries}',
      icon: Icons.search_rounded,
    ),
    ServiceKpi(
      label: 'Grabs',
      value: '${stats.totalGrabs}',
      icon: Icons.download_rounded,
    ),
    ServiceKpi(
      label: 'Fails',
      value: '${stats.totalFailures}',
      icon: Icons.error_outline_rounded,
      tone: _faultIf(stats.totalFailures > 0),
    ),
  ];
}

Future<List<ServiceKpi>> _readarrKpis(Ref ref) async {
  // [readarrKpiLibraryProvider], not [readarrAuthorsProvider]: see
  // [_radarrKpis]. The two fetches fail independently — a library that answers
  // over a queue endpoint that does not is the ordinary case on a Readarr
  // mid-upgrade — so each figure says for itself whether it was answered.
  List<ReadarrAuthor>? authors;
  try {
    authors = await ref.watch(readarrKpiLibraryProvider.future);
  } catch (_) {
    authors = null;
  }
  int? queued;
  try {
    queued = (await ref.watch(readarrQueueProvider.future)).length;
  } catch (_) {
    queued = null;
  }

  var books = 0;
  var have = 0;
  for (final a in authors ?? const <ReadarrAuthor>[]) {
    books += a.bookCount;
    have += a.bookFileCount;
  }
  final missing = (books - have).clamp(0, books);
  final answered = authors != null;
  return [
    _figure(
      label: 'Authors',
      value: answered ? '${authors.length}' : null,
      icon: Icons.person_rounded,
      note: answered ? null : _notAnswering(ServiceKey.readarr),
    ),
    _figure(
      label: 'Books',
      value: answered ? '$books' : null,
      icon: Icons.menu_book_rounded,
    ),
    _figure(
      label: 'Missing',
      value: answered ? '$missing' : null,
      icon: Icons.report_gmailerrorred_rounded,
      tone: _backlogIf(answered && missing > 0),
    ),
    _figure(
      label: 'Queue',
      value: queued == null ? null : '$queued',
      icon: Icons.download_rounded,
      // Its own reason, because it is its own fetch: a Readarr whose library
      // reads fine and whose queue endpoint is down used to print `Queue 0` —
      // an idle downloader rather than an unread one.
      note: queued == null ? 'queue not answering' : null,
    ),
  ];
}

Future<List<ServiceKpi>> _sabnzbdKpis(Ref ref) async {
  final queue = await ref.watch(sabnzbdQueueProvider.future);
  final kpis = [
    ServiceKpi(
      label: 'Down',
      value: queue.speedLabel,
      icon: Icons.south_rounded,
      tone: _activityIf(queue.kbPerSec > 0),
    ),
    ServiceKpi(
      // [SabnzbdQueue.jobCount], never `slots.length`: the client asks for a
      // 50-slot page, so a queue deeper than the page read `50` forever — a
      // figure that stops moving exactly when there is something to watch.
      // `jobCount` prefers the server's own `noofslots_total` and falls back to
      // the rows in hand when the payload carried no total.
      label: 'Queue',
      value: '${queue.jobCount}',
      icon: Icons.list_rounded,
    ),
    ServiceKpi(
      label: 'Remaining',
      value: queue.sizeLeftLabel,
      icon: Icons.hourglass_bottom_rounded,
    ),
    ServiceKpi(
      label: 'Status',
      value: queue.paused ? 'Paused' : 'Active',
      icon: queue.paused
          ? Icons.pause_circle_rounded
          : Icons.play_circle_rounded,
      // Pausing the queue is something the user did on purpose, so it is
      // neither a fault nor a backlog — it is the client obeying. It used to be
      // flagged amber, which put "you pressed pause" in the same colour as
      // "your disk is full" (decision 15).
    ),
  ];
  // Lifetime total is a nice-to-have; a stats failure must not drop the whole
  // KPI row, so it is fetched defensively and simply omitted on error.
  try {
    final stats = await ref.watch(sabnzbdServerStatsProvider.future);
    kpis.add(
      ServiceKpi(
        label: 'Total',
        value: stats.totalLabel,
        icon: Icons.download_done_rounded,
      ),
    );
  } catch (_) {
    // Ignore — the four queue KPIs above are enough.
  }
  return kpis;
}

Future<List<ServiceKpi>> _nzbgetKpis(Ref ref) async {
  final results = await Future.wait([
    ref.watch(nzbgetStatusProvider.future),
    ref.watch(nzbgetQueueProvider.future),
  ]);
  final status = results[0] as NzbgetStatus;
  final groups = results[1] as List<NzbgetGroup>;
  return [
    ServiceKpi(
      label: 'Down',
      value: status.rateLabel,
      icon: Icons.south_rounded,
      tone: _activityIf(status.downloadRateBytes > 0),
    ),
    ServiceKpi(
      label: 'Queue',
      value: '${groups.length}',
      icon: Icons.list_rounded,
    ),
    ServiceKpi(
      label: 'Remaining',
      value: status.remainingLabel,
      icon: Icons.hourglass_bottom_rounded,
    ),
    ServiceKpi(
      label: 'Status',
      value: status.paused ? 'Paused' : 'Active',
      icon: status.paused
          ? Icons.pause_circle_rounded
          : Icons.play_circle_rounded,
      // Deliberate: see the SABnzbd twin above.
    ),
  ];
}

/// Transmission's rail, shaped like qBittorrent's so the two torrent clients
/// read the same way in the matrix — `Down` first, flagged while bytes are
/// actually moving, so the resting cell says "0 B/s" rather than a library
/// total.
Future<List<ServiceKpi>> _transmissionKpis(Ref ref) async {
  final results = await Future.wait([
    ref.watch(transmissionStatsProvider.future),
    ref.watch(transmissionTorrentsProvider.future),
  ]);
  final stats = results[0] as TransmissionStats;
  final torrents = results[1] as List<TransmissionTorrent>;
  final downloading = torrents.where((t) => t.status.isIncoming).length;
  final stalled = torrents.where((t) => t.warning != null).length;

  return [
    ServiceKpi(
      label: 'Down',
      value: stats.downloadSpeedLabel,
      icon: Icons.south_rounded,
      tone: _activityIf(stats.downloadSpeed > 0),
    ),
    ServiceKpi(
      label: 'Up',
      value: stats.uploadSpeedLabel,
      icon: Icons.north_rounded,
    ),
    ServiceKpi(
      label: 'Active',
      value: '${stats.activeTorrentCount}',
      icon: Icons.bolt_rounded,
    ),
    ServiceKpi(
      label: 'Downloading',
      value: '$downloading',
      icon: Icons.download_rounded,
    ),
    ServiceKpi(
      label: 'Stalled',
      value: '$stalled',
      icon: Icons.report_gmailerrorred_rounded,
      tone: _faultIf(stalled > 0),
    ),
  ];
}

/// Nginx Proxy Manager's rail.
///
/// `Offline` is the metric that earns its place: a reverse proxy is either
/// serving every hostname it claims or it is not, and a host that is switched on
/// while nginx has refused its configuration is invisible from every other
/// screen in the app — the site simply stops answering. Expiring certificates
/// are the second, for the same reason a day later.
Future<List<ServiceKpi>> _npmKpis(Ref ref) async {
  final results = await Future.wait([
    ref.watch(npmProxyHostsProvider.future),
    ref.watch(npmCertificatesProvider.future),
  ]);
  final hosts = results[0] as List<NpmProxyHost>;
  final certificates = results[1] as List<NpmCertificate>;
  final now = DateTime.now();
  final broken = hosts.where((h) => h.hasConfigError).length;
  final disabled = hosts.where((h) => !h.enabled).length;
  final expiring = certificates.where((c) => c.isExpiringSoon(now)).length;

  return [
    ServiceKpi(
      label: 'Offline',
      value: '$broken',
      icon: Icons.error_outline_rounded,
      tone: _faultIf(broken > 0),
    ),
    ServiceKpi(
      label: 'Hosts',
      value: '${hosts.length}',
      icon: Icons.alt_route_rounded,
    ),
    ServiceKpi(
      label: 'Expiring',
      value: '$expiring',
      icon: Icons.lock_clock_rounded,
      tone: _faultIf(expiring > 0),
    ),
    ServiceKpi(
      label: 'Certificates',
      value: '${certificates.length}',
      icon: Icons.lock_outline_rounded,
    ),
    ServiceKpi(
      label: 'Disabled',
      value: '$disabled',
      icon: Icons.pause_circle_rounded,
    ),
  ];
}

Future<List<ServiceKpi>> _unraidKpis(Ref ref) async {
  final results = await Future.wait([
    ref.watch(unraidArrayProvider.future),
    ref.watch(unraidDockerProvider.future),
  ]);
  final array = results[0] as UnraidArray;
  final containers = results[1] as List<UnraidDockerContainer>;
  final running = containers.where((c) => c.running).length;
  // Null when the array answered with no capacity block, which is nullable in
  // the committed SDL. `Used 0%` would read as an empty array — the one
  // conclusion a user acts on — and would contradict the Overview's Array
  // section, whose capacity clause correctly disappears for the same input.
  final usedPercent = array.usedPercent;
  return [
    ServiceKpi(label: 'Array', value: array.state, icon: Icons.dns_rounded),
    if (usedPercent == null)
      const ServiceKpi.unavailable(
        label: 'Used',
        icon: Icons.pie_chart_rounded,
        note: 'no capacity reported',
      )
    else
      ServiceKpi(
        label: 'Used',
        value: '$usedPercent%',
        icon: Icons.pie_chart_rounded,
        tone: _faultIf(usedPercent >= 80),
      ),
    ServiceKpi(
      label: 'Containers',
      value: '$running/${containers.length}',
      icon: Icons.widgets_rounded,
    ),
    // Same rule for the census: `disks` is nullable too, and a `0` here is an
    // assertion that the array has no drives, built out of silence.
    if (array.reportedDisks)
      ServiceKpi(
        label: 'Disks',
        value: '${array.disks.length}',
        icon: Icons.storage_rounded,
      )
    else
      const ServiceKpi.unavailable(
        label: 'Disks',
        icon: Icons.storage_rounded,
        note: 'no slots reported',
      ),
  ];
}
