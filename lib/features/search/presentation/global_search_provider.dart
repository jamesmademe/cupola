import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// ignore: implementation_imports
import 'package:flutter_riverpod/legacy.dart';

import 'package:cupola/core/models/media_preview.dart';
import 'package:cupola/features/bazarr/data/bazarr_service.dart';
import 'package:cupola/features/bazarr/presentation/bazarr_provider.dart';
import 'package:cupola/core/utils/image_utils.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/features/discover/data/seerr_service.dart';
import 'package:cupola/features/movies/data/radarr_service.dart';
import 'package:cupola/features/movies/domain/models/radarr_movie.dart';
import 'package:cupola/features/music/data/lidarr_service.dart';
import 'package:cupola/features/music/domain/models/lidarr_artist.dart';
import 'package:cupola/features/search/domain/global_search_result.dart';
import 'package:cupola/features/series/data/sonarr_service.dart';
import 'package:cupola/features/series/domain/models/sonarr_series.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

final globalSearchQueryProvider = StateProvider<String>((ref) => '');

/// One leg of the fan-out: one service, one of its connections.
typedef _SearchLeg = ({ServiceInstance instance, bool named});

/// How many legs may be in the air at once.
///
/// Five services with one connection each was a `Future.wait` over five. With
/// several connections each it is a fan-out over as many as the user has
/// configured, all against home servers on one link — so it is bounded. Four
/// rather than the release search's two: these are cheap lookups, and an arr is
/// not rate-limited against its owner the way an indexer is.
const _maxLegsInFlight = 4;

/// The services the global search fans out to, in the order their sections
/// appear.
const _searchableServices = [
  ServiceKey.seerr,
  ServiceKey.radarr,
  ServiceKey.sonarr,
  ServiceKey.lidarr,
  ServiceKey.bazarr,
];

/// The global search, one section per **connection**.
///
/// One leg per configured connection rather than per service, so two Radarr
/// answer as two sections. That is what makes the fan-out cheap to read: a
/// section is one server, so nothing has to be reconciled between them, and
/// "which of my libraries has it" is answered by where the row is rather than
/// by a chip on it. It is also what removes the deduplication problem entirely
/// — two instances never meet in one list, so Lidarr and Bazarr having no
/// external id stops mattering.
///
/// Still a `Future` and still all-or-nothing, which is a stated cost rather
/// than an oversight: one configured-but-switched-off server holds every other
/// section behind its timeout, and fanning out multiplies how many servers can
/// be in that state. The bounded pool caps the concurrency, not the wait.
/// Rendering each leg as it lands is the fix, and it is deliberately not folded
/// in here — it turns this into a stream, which changes what `.future` means
/// for every consumer, and that belongs in a change of its own.
final globalSearchResultsProvider =
    FutureProvider.autoDispose<List<GlobalSearchServiceResults>>((ref) async {
      final query = ref.watch(globalSearchQueryProvider).trim();

      // The connections this fans out to, as one comparable scalar. Not the
      // whole model — a theme toggle would abort the user's in-flight search
      // and start it again — and not a `List`, which compares by identity and
      // would never settle. Every field that decides which server is reached is
      // in here, so a connection edited mid-search re-runs and nothing else
      // does.
      ref.watch(
        currentSettingsProvider.select((s) {
          final parts = <String>[];
          for (final service in _searchableServices) {
            for (final instance in s.configuredInstancesOf(service)) {
              parts.add(
                '${instance.id}|${instance.url}|${instance.credential}'
                '|${s.pinForUrl(instance.url)}',
              );
            }
          }
          return parts.join(';');
        }),
      );

      final settings = ref.read(currentSettingsProvider);
      if (query.isEmpty) return const <GlobalSearchServiceResults>[];

      final legs = <_SearchLeg>[
        for (final service in _searchableServices)
          if (service.searchesPerConnection)
            for (final instance in settings.configuredInstancesOf(service))
              (
                instance: instance,
                // Named only when there is something to tell apart: a stack
                // with one Radarr must not grow a label naming the only Radarr
                // there is.
                named: settings.configuredInstancesOf(service).length > 1,
              )
          else
            // One leg, on the lens, unlabelled. Seerr and Bazarr have no way to
            // open a named connection from a row — see
            // `ServiceKeyExtension.searchesPerConnection` — and two sections
            // with identical contents under two different names is a worse
            // answer than the one section they had before.
            for (final instance in [ref.watch(activeInstanceProvider(service))])
              if (instance != null && instance.isConfigured)
                (instance: instance, named: false),
      ];
      if (legs.isEmpty) return const <GlobalSearchServiceResults>[];

      // One token for the whole fan-out. Riverpod disposes this build before it
      // starts the next one, so the moment a keystroke supersedes the query
      // every request still in flight for the old one is aborted rather than
      // run to completion — a dozen servers answering a question nobody is
      // asking.
      final cancelToken = CancelToken();
      ref.onDispose(cancelToken.cancel);

      // Slots, not an append list: the sections appear in the legs' own order,
      // never in the order the servers happened to answer.
      final done = List<GlobalSearchServiceResults?>.filled(legs.length, null);

      // A hand-rolled bounded pool: four workers pulling from one cursor is the
      // whole of it, and the alternative is a dependency for eight lines.
      var cursor = 0;
      Future<void> worker() async {
        while (true) {
          final index = cursor++;
          if (index >= legs.length) return;
          done[index] = await _runLeg(ref, legs[index], query, cancelToken);
        }
      }

      await Future.wait([for (var w = 0; w < _maxLegsInFlight; w++) worker()]);
      return [
        for (final group in done)
          if (group != null) group,
      ];
    });

Future<GlobalSearchServiceResults> _runLeg(
  Ref ref,
  _SearchLeg leg,
  String query,
  CancelToken cancelToken,
) {
  final instance = leg.instance;
  final label = leg.named
      ? (instance.label.isEmpty ? instance.id : instance.label)
      : '';
  return switch (instance.service) {
    ServiceKey.seerr => _loadLeg(
      leg: leg,
      instanceLabel: label,
      loadItems: () => ref
          .read(seerrServiceProvider)
          .search(query, cancelToken: cancelToken),
      toResult: (item, index) => _seerrResult(item, instance, index),
    ),
    ServiceKey.radarr => _loadLeg(
      leg: leg,
      instanceLabel: label,
      loadItems: () => ref
          .read(radarrServiceForProvider(instance.id))
          .lookupMovies(query, cancelToken: cancelToken, reportFailure: true),
      toResult: (item, index) => _radarrResult(item, instance, index),
    ),
    ServiceKey.sonarr => _loadLeg(
      leg: leg,
      instanceLabel: label,
      loadItems: () => ref
          .read(sonarrServiceForProvider(instance.id))
          .lookupSeries(query, cancelToken: cancelToken, reportFailure: true),
      toResult: (item, index) => _sonarrResult(item, instance, index),
    ),
    ServiceKey.lidarr => _loadLeg(
      leg: leg,
      instanceLabel: label,
      loadItems: () => ref
          .read(lidarrServiceForProvider(instance.id))
          .lookupArtists(query, cancelToken: cancelToken, reportFailure: true),
      toResult: (item, index) => _lidarrResult(item, instance, index),
    ),
    // Bazarr is the one leg with no server-side search: `searchLibrary` matches
    // client side against a snapshot of the library it caches for a short
    // window, so a debounced round of keystrokes costs one download rather than
    // one each. Which is also why its token cannot abort the transfer — the
    // download in flight belongs to the next query as much as to this one. It
    // still stops the match once the round is superseded.
    _ => _loadLeg(
      leg: leg,
      instanceLabel: label,
      loadItems: () => ref
          .read(bazarrServiceProvider)
          .searchLibrary(query, cancelToken: cancelToken),
      toResult: (item, index) => _bazarrResult(item, instance, index),
    ),
  };
}

Future<GlobalSearchServiceResults> _loadLeg<T>({
  required _SearchLeg leg,
  required Future<List<T>> Function() loadItems,
  required GlobalSearchResult Function(T item, int index) toResult,
  String instanceLabel = '',
}) async {
  try {
    final items = await loadItems();
    return GlobalSearchServiceResults(
      service: leg.instance.service,
      results: [for (var i = 0; i < items.length; i++) toResult(items[i], i)],
      instanceLabel: instanceLabel,
    );
  } catch (error) {
    return GlobalSearchServiceResults(
      service: leg.instance.service,
      results: const [],
      error: error,
      // Named on the failure too: "Radarr did not answer" is a worse sentence
      // than "Radarr · 4K did not answer" when the other one did.
      instanceLabel: instanceLabel,
    );
  }
}

/// Tag shared by a result's poster and the detail page it flies into.
///
/// Four parts, and each one closes a collision that was live:
///
/// * [kind], because Bazarr and Seerr can each return a movie and a series
///   carrying the same id;
/// * the **connection**, because the same film is in both Radarr and the same
///   id names different films on each — with one section per connection, both
///   are on screen at once;
/// * the **position**, because a lookup result that is not in the library has
///   `id == 0` (the code uses `id > 0` as the library test), so two unowned
///   films in one section produced the identical tag. Two Heroes with one tag
///   on the same screen is an assert in debug, which is to say a crash — and it
///   has been true since before instances existed. Nothing caught it because
///   the search screen has never been opened on a device.
///
/// The position is only a tiebreak within one round of results and never
/// travels anywhere that outlives the list, so a reorder cannot strand it.
String _heroTag(ServiceInstance instance, String kind, int id, int index) =>
    'search_${instance.id}_${kind}_${id}_$index';

/// The word a row wears when the server that listed it already holds the title.
///
/// One string, and a deliberately modest one. The lookup endpoints every arr
/// leg calls (`movie/lookup`, `series/lookup`, `artist/lookup`) are metadata
/// proxies: they answer from TMDB/TVDB/MusicBrainz and stamp the **library id**
/// onto anything the server recognises as its own — nothing else. `hasFile` is
/// left false on every row, and `statistics` (Sonarr's episode counts,
/// Lidarr's track counts) is attached by the library controllers, never by the
/// lookup ones. Reading a badge off those fields is reading a fact about the
/// endpoint, not about the media, which is why "Aladdin (2019)" read as
/// *Missing* in search while its own detail page said *Available, 1 file*.
///
/// So the honest pair is "in library" against nothing at all, and the third
/// state the badge used to imply — in the library but without the file — is
/// simply not knowable here. `hasFile` is not consulted even as an optimistic
/// upgrade: it would put two different words on two rows in the same state
/// depending on which Radarr answered, and a row that says nothing is a
/// smaller lie than one that says the wrong thing.
///
/// Nothing is said about a row the server does not have. The section it sits
/// under already names the library that was asked, so "not in library" would
/// be the heading repeated once per row.
const _inLibraryTag = 'In library';

GlobalSearchResult _seerrResult(
  MediaPreview item,
  ServiceInstance instance,
  int index,
) {
  final type = item.mediaType == 'tv' ? 'Series' : 'Movie';
  final year = item.year;
  final imageUrl = ImageUtils.buildTmdbPosterUrl(item.posterPath);
  final heroTag = _heroTag(instance, item.mediaType, item.id, index);
  return GlobalSearchResult(
    service: ServiceKey.seerr,
    id: item.id,
    title: item.title,
    subtitle: [type, year].where((part) => part.isNotEmpty).join(' · '),
    imageUrl: imageUrl,
    imageHeaders: null,
    tags: [type, if (year.isNotEmpty) year],
    heroTag: heroTag,
    // Seerr has no `routeExtra` to preload from, so the poster travels in the
    // URL: the detail page paints real art during its lookup instead of
    // landing the flight on an empty gradient.
    route: ServiceRoutes.seerrDetail(
      mediaType: item.mediaType,
      id: item.id,
      heroTag: heroTag,
      posterUrl: imageUrl,
      // No `i` here on purpose: Discover resolves through the lens end to end,
      // so a connection in the URL would be a claim the page cannot honour.
      // The day it can, this is the one line that changes.
    ),
  );
}

GlobalSearchResult _radarrResult(
  RadarrMovie item,
  ServiceInstance instance,
  int index,
) {
  // This connection's address and key, not the first Radarr's. A poster the
  // arr serves itself is fetched from the server that listed it.
  final image = ImageUtils.extractPosterUrl(
    item.images,
    baseUrl: instance.url,
    apiKey: instance.credential,
  );
  final heroTag = _heroTag(instance, 'movie', item.id, index);
  // `id > 0` is the library test the rest of the file already uses — see
  // `_heroTag` — and the only one this payload supports. See [_inLibraryTag].
  final inLibrary = item.id > 0;
  return GlobalSearchResult(
    service: ServiceKey.radarr,
    id: item.id,
    title: item.title,
    subtitle: [
      if (item.year > 0) item.year.toString(),
      if (inLibrary) _inLibraryTag,
    ].join(' · '),
    imageUrl: image.url,
    imageHeaders: image.headers,
    tags: ['Movie', if (inLibrary) _inLibraryTag],
    inLibrary: inLibrary,
    heroTag: heroTag,
    route: ServiceRoutes.radarrMovie(
      item.id,
      heroTag: heroTag,
      instanceId: instance.id,
    ),
    routeExtra: item,
  );
}

GlobalSearchResult _sonarrResult(
  SonarrSeries item,
  ServiceInstance instance,
  int index,
) {
  final image = ImageUtils.extractPosterUrl(
    item.images,
    // This connection's, not the first Sonarr's.
    baseUrl: instance.url,
    apiKey: instance.credential,
  );
  final heroTag = _heroTag(instance, 'series', item.id, index);
  // `status` stays: it is the *series'* own state — continuing, ended — which
  // comes from the metadata and is therefore populated on a lookup row. It has
  // never said anything about this library, which is the gap [_inLibraryTag]
  // fills. `hasFiles` is the field that would have lied here, and it is
  // deliberately not read.
  final inLibrary = item.id > 0;
  return GlobalSearchResult(
    service: ServiceKey.sonarr,
    id: item.id,
    title: item.title,
    subtitle: [
      if (item.year > 0) item.year.toString(),
      item.status,
      if (inLibrary) _inLibraryTag,
    ].join(' · '),
    imageUrl: image.url,
    imageHeaders: image.headers,
    tags: ['Series', item.status, if (inLibrary) _inLibraryTag],
    inLibrary: inLibrary,
    heroTag: heroTag,
    route: ServiceRoutes.sonarrSeries(
      item.id,
      heroTag: heroTag,
      instanceId: instance.id,
    ),
    routeExtra: item,
  );
}

GlobalSearchResult _bazarrResult(
  BazarrSearchHit item,
  ServiceInstance instance,
  int index,
) {
  final type = item.isMovie ? 'Movie' : 'Series';
  final kind = item.isMovie ? 'movie' : 'series';
  final heroTag = _heroTag(instance, kind, item.id, index);
  return GlobalSearchResult(
    service: ServiceKey.bazarr,
    id: item.id,
    title: item.title,
    subtitle: 'Subtitles · $type',
    // Bazarr's API carries no artwork, so this row does not fly (see
    // `canFlyPoster`); the tag still travels for the day it does.
    imageUrl: '',
    imageHeaders: null,
    tags: ['Subtitles', type],
    heroTag: heroTag,
    // Bazarr's id is a THIRD server's — `radarrId` / `sonarrSeriesId` — so the
    // connection stamped here is Bazarr's own, and the arr page it lands on
    // resolves through its own lens. Two Bazarr paired to two different arrs
    // would collide on the route itself, which is a knot this does not untie.
    route: item.isMovie
        ? ServiceRoutes.bazarrMovie(item.id, heroTag: heroTag)
        : ServiceRoutes.bazarrSeries(item.id, heroTag: heroTag),
  );
}

GlobalSearchResult _lidarrResult(
  LidarrArtist item,
  ServiceInstance instance,
  int index,
) {
  final image = ImageUtils.extractPosterUrl(
    item.images,
    baseUrl: instance.url,
    apiKey: instance.credential,
    coverTypes: const ['poster', 'fanart', 'banner'],
  );
  // Only when the payload carries one. `albumCount` reads `statistics`, which
  // the lookup controller does not attach, so every row said "0 albums" — a
  // fact about the endpoint dressed up as a fact about the artist.
  final albumLabel = switch (item.albumCount) {
    0 => '',
    1 => '1 album',
    final count => '$count albums',
  };
  final heroTag = _heroTag(instance, 'artist', item.id, index);
  // Same statistics gap as the album count: `hasFiles` counts track files and
  // is false for every lookup row. See [_inLibraryTag].
  final inLibrary = item.id > 0;
  return GlobalSearchResult(
    service: ServiceKey.lidarr,
    id: item.id,
    title: item.artistName,
    subtitle: albumLabel,
    imageUrl: image.url,
    imageHeaders: image.headers,
    tags: ['Artist', if (inLibrary) _inLibraryTag],
    inLibrary: inLibrary,
    heroTag: heroTag,
    route: ServiceRoutes.lidarrArtist(
      item.id,
      heroTag: heroTag,
      instanceId: instance.id,
    ),
    routeExtra: item,
  );
}
