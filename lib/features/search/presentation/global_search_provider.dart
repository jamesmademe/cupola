import 'dart:async';
import 'dart:collection';

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
import 'package:cupola/features/jellyfin/presentation/jellyfin_provider.dart';
import 'package:cupola/features/plex/presentation/plex_provider.dart';
import 'package:cupola/features/search/domain/arr_add_request.dart';
import 'package:cupola/features/search/domain/global_search_result.dart';
import 'package:cupola/features/series/data/sonarr_service.dart';
import 'package:cupola/features/stream/domain/models/stream_item.dart';
import 'package:cupola/features/stream/domain/models/stream_search_group.dart';
import 'package:cupola/features/stream/domain/stream_server_client.dart';
import 'package:cupola/features/series/domain/models/sonarr_series.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

final globalSearchQueryProvider = StateProvider<String>((ref) => '');

/// Bumped to run the query already in the field again, without touching it.
///
/// ⌘R and re-tapping the Search tab are opposite commands — one re-runs, the
/// other clears — and they used to share one channel,
/// `navigationRefreshProvider(NavigationSection.search)`, whose only listener
/// cleared the query. So ⌘R silently erased what the user had typed. This is
/// the other half of that split: the window's Refresh command bumps this, the
/// tab re-tap keeps the clear, and neither can be mistaken for the other.
final globalSearchRerunProvider = StateProvider<int>((ref) => 0);

/// How many legs may be in the air at once.
///
/// Five services with one connection each was a `Future.wait` over five. With
/// several connections each it is a fan-out over as many as the user has
/// configured, all against home servers on one link — so it is bounded. Four
/// rather than the release search's two: these are cheap lookups, and an arr is
/// not rate-limited against its owner the way an indexer is.
const _maxLegsInFlight = 4;

/// How long one lane may take before it is reported as not having answered.
///
/// It needs a deadline of its own because "still searching" is only an honest
/// word against a bounded promise. Without one a lane inherits the transport's
/// 15 s receive timeout (`redirect_guard._receiveTimeout`), which means the
/// lane's verdict and the socket's arrive together and the screen can never say
/// *the query* timed out — only that something, somewhere, gave up.
///
/// Ten seconds: above the slowest cold `movie/lookup` through a metadata proxy,
/// and under the transport's so this verdict always lands first and always
/// lands the same way. The lane cancels its own token on the way out, so the
/// pool slot and the socket are both released rather than held to 15 s.
const _laneDeadline = Duration(seconds: 10);

/// The services the global search fans out to, in the order their sections
/// appear.
///
/// Read off the registry rather than repeated here. It used to be a private
/// const beside a `ServiceKey.isSearchable` the chip strip and the empty-state
/// copy read instead — two lists that agreed only by coincidence, so adding a
/// service to one promised a lane the other never ran (or hid one it did).
///
/// **Prowlarr is deliberately not in it**, and that is the registry's answer
/// too: an indexer search is a release search against trackers, not a title
/// lookup, and it belongs on Prowlarr's own page. A tracker query is also the
/// one leg that is rate-limited against its owner, which is the second reason
/// it is not fired on every keystroke of a global search.
///
/// **Jellyfin and Plex are added on top of `isSearchable`, not through it.**
/// Both now answer a title query — `GET /Search/Hints` and `GET /hubs/search`,
/// behind the one `StreamServerClient.search` — so the registry flag is simply
/// stale: it still carries the argument that a media server has nothing to look
/// up, which stopped being true when those two reads landed. Correcting the
/// flag is a registry edit and belongs with the registry; naming the two here
/// keeps one list for the whole feature in the meantime, because the chip strip
/// and the empty-state copy read *this* and not the flag. If the flag is ever
/// widened, this predicate collapses back to `isSearchable` alone and nothing
/// else moves. It stays a single `where` over `ServiceKey.values` rather than a
/// spread of two lists so that section order is the registry's own by
/// construction, however the predicate grows.
final globalSearchServices = ServiceKey.values
    .where(
      (service) =>
          service.isSearchable ||
          service == ServiceKey.jellyfin ||
          service == ServiceKey.plex,
    )
    .toList(growable: false);

/// The connections the global search asks, in section order.
///
/// One leg per configured connection rather than per service, so two Radarr
/// answer as two sections. That is what makes the fan-out cheap to read: a
/// section is one server, so nothing has to be reconciled between them, and
/// "which of my libraries has it" is answered by where the row is rather than
/// by a chip on it. It is also what removes the deduplication problem entirely
/// — two instances never meet in one list, so Lidarr and Bazarr having no
/// external id stops mattering.
///
/// The query is deliberately *not* watched here: the list of servers to ask
/// does not change because a letter was typed, and rebuilding it on every
/// keystroke would mint a new key for every lane and throw away the lane states
/// the screen is drawing.
final globalSearchLegsProvider = Provider.autoDispose<List<SearchLeg>>((ref) {
  // The connections this fans out to, as one comparable scalar. Not the whole
  // model — a theme toggle would abort the user's in-flight search and start it
  // again — and not a `List`, which compares by identity and would never
  // settle. Every field that decides which server is reached is in here, so a
  // connection edited mid-search re-runs and nothing else does.
  ref.watch(
    currentSettingsProvider.select((s) {
      final parts = <String>[];
      for (final service in globalSearchServices) {
        for (final instance in s.configuredInstancesOf(service)) {
          // The name too: it is on the lane's heading, and a heading that
          // kept the old name after a rename would be naming nothing.
          parts.add(
            '${instance.id}|${instance.url}|${instance.credential}'
            '|${s.pinForUrl(instance.url)}|${s.connectionName(instance.id)}'
            // The access by its hash, so the stamp never holds a secret.
            '|${instance.access.hashCode}',
          );
        }
      }
      return parts.join(';');
    }),
  );

  final settings = ref.read(currentSettingsProvider);
  return <SearchLeg>[
    for (final service in globalSearchServices)
      if (service.searchesPerConnection)
        for (final instance in settings.configuredInstancesOf(service))
          (
            instance: instance,
            // Named only when there is something to tell apart: a stack with
            // one Radarr must not grow a label naming the only Radarr there is.
            name: settings.connectionName(instance.id) ?? '',
          )
      else
        // One leg, on the lens. Seerr, Bazarr, Jellyfin and Plex have no way
        // to open a named connection from a row — see
        // `ServiceKeyExtension.searchesPerConnection` — and two sections with
        // identical contents under two different names is a worse answer than
        // the one section they had before. The section still says which of
        // the user's connections it asked, once there are two: an unlabelled
        // Jellyfin lane over the living room's server reads as the whole
        // household's answer.
        for (final instance in [ref.watch(activeInstanceProvider(service))])
          if (instance != null && instance.isConfigured)
            (
              instance: instance,
              name: settings.connectionName(instance.id) ?? '',
            ),
  ];
});

/// One leg of the fan-out, keyed on the connection it asks.
///
/// This family is the whole of the design's core promise. The search used to be
/// a single `FutureProvider` awaiting a `Future.wait`, which meant there was no
/// such thing as a half-answered screen: one configured-but-switched-off server
/// held every other section behind its timeout, a lane could not shimmer while
/// its neighbour showed rows, and Retry had nothing to invalidate that was not
/// the entire page. A family gives all three away for free — a lane's state is
/// its own provider's state, and Retry is
/// `ref.invalidate(globalSearchLegProvider(leg))`.
///
/// It never completes with an error. A leg that fails resolves to a lane in the
/// matching [SearchLaneState], because a failure here is a thing the page draws
/// rather than a thing that stops it.
final globalSearchLegProvider = FutureProvider.autoDispose
    .family<GlobalSearchServiceResults, SearchLeg>((ref, leg) {
      final query = ref.watch(globalSearchQueryProvider).trim();
      if (query.isEmpty) {
        return Future.value(GlobalSearchServiceResults(leg: leg));
      }

      // One token per leg per round. Riverpod disposes this build before it
      // starts the next one, so the moment a keystroke supersedes the query the
      // request still in flight for the old one is aborted rather than run to
      // completion — a dozen servers answering a question nobody is asking.
      final cancelToken = CancelToken();
      ref.onDispose(cancelToken.cancel);

      return ref.read(_legPoolProvider).run(() {
        // Superseded while queued behind the pool. Skipping the request is the
        // point of the check: a slot spent on a question nobody is asking is a
        // slot the *current* query waits for. Riverpod discards whatever a
        // disposed build returns, so this lane is never drawn.
        if (cancelToken.isCancelled) {
          return Future.value(
            GlobalSearchServiceResults(
              leg: leg,
              state: SearchLaneState.searching,
            ),
          );
        }
        return _runLeg(ref, leg, query, cancelToken);
      });
    });

/// Every lane as it stands right now, in section order.
///
/// Emitted synchronously and re-emitted the moment any single lane moves, which
/// is what lets the page draw a Radarr that has answered next to a Bazarr that
/// is still shimmering. Nothing here waits for anything.
final globalSearchLanesProvider =
    Provider.autoDispose<List<GlobalSearchServiceResults>>((ref) {
      final query = ref.watch(globalSearchQueryProvider).trim();
      if (query.isEmpty) return const <GlobalSearchServiceResults>[];

      // Slots in the legs' own order, never in the order the servers happened
      // to answer: a section that jumps up the page as its server replies is a
      // page nobody can read while it is loading.
      return [
        for (final leg in ref.watch(globalSearchLegsProvider))
          _laneOf(leg, ref.watch(globalSearchLegProvider(leg))),
      ];
    });

/// Re-runs every lane against the query already in the field.
///
/// A loop over per-leg invalidations rather than one invalidate of a page-wide
/// provider, because there is no page-wide provider any more — and because the
/// lanes that have already answered redraw from their own new round rather than
/// all collapsing to one shimmer.
void rerunGlobalSearch(WidgetRef ref) {
  for (final leg in ref.read(globalSearchLegsProvider)) {
    ref.invalidate(globalSearchLegProvider(leg));
  }
}

/// The lane a leg's provider state stands for.
///
/// [AsyncValue.isLoading] is asked *before* the value, and that order is the
/// rule rather than a style choice: Riverpod carries the previous answer across
/// an invalidate, so reading the value first would redraw the failure the user
/// just pressed Retry on and make the button look inert.
GlobalSearchServiceResults _laneOf(
  SearchLeg leg,
  AsyncValue<GlobalSearchServiceResults> value,
) {
  if (value.isLoading) {
    return GlobalSearchServiceResults(
      leg: leg,
      state: SearchLaneState.searching,
    );
  }
  final lane = value.asData?.value;
  if (lane != null) return lane;
  // The leg swallows its own failures, so this is only reachable if one escapes
  // — and a lane that cannot say why it stopped still has to say that it did.
  return GlobalSearchServiceResults.fault(leg, value.error);
}

/// Caps how many legs are on the wire at once.
///
/// Alive for the app rather than per round on purpose. An `autoDispose` pool is
/// torn down and rebuilt in the gap between two rounds, which resets the
/// counter while the previous round's four requests are still on the wire — so
/// the bound the fan-out advertises would quietly double exactly when the user
/// is typing fastest. It holds two integers and a queue of completers; nothing
/// in it is worth disposing.
final _legPoolProvider = Provider<_LegPool>(
  (ref) => _LegPool(_maxLegsInFlight),
);

/// A small async semaphore: [limit] bodies run, the rest queue in arrival
/// order.
///
/// It replaced a hand-rolled worker loop, which only worked while one provider
/// owned the whole fan-out and pulled legs off a cursor. With a leg per
/// provider every member fires at once, so the bound has to live somewhere both
/// of them can see.
class _LegPool {
  _LegPool(this.limit);

  final int limit;
  var _inFlight = 0;
  final Queue<Completer<void>> _waiting = Queue<Completer<void>>();

  Future<T> run<T>(FutureOr<T> Function() body) async {
    if (_inFlight >= limit) {
      final slot = Completer<void>();
      _waiting.add(slot);
      // The releaser hands its slot straight over, so `_inFlight` is already
      // accounted for when this resumes.
      await slot.future;
    } else {
      _inFlight++;
    }
    try {
      return await body();
    } finally {
      // Hand the slot to the next waiter instead of decrementing and letting it
      // race: a caller arriving between the decrement and the waiter waking up
      // would take the slot too, and the pool would run limit + 1.
      if (_waiting.isNotEmpty) {
        _waiting.removeFirst().complete();
      } else {
        _inFlight--;
      }
    }
  }
}

Future<GlobalSearchServiceResults> _runLeg(
  Ref ref,
  SearchLeg leg,
  String query,
  CancelToken cancelToken,
) {
  final instance = leg.instance;
  return switch (instance.service) {
    ServiceKey.seerr => _loadLeg(
      leg: leg,
      cancelToken: cancelToken,
      // `reportFailure`, like the arr lanes: without it a Seerr that did not
      // answer, or refused the key, came back as `[]` — a lane reading
      // "0 results" and counted as answered.
      loadItems: () => ref
          .read(seerrServiceProvider)
          .search(query, cancelToken: cancelToken, reportFailure: true),
      toResult: (item, index) => _seerrResult(item, instance, index),
    ),
    ServiceKey.radarr => _loadLeg(
      leg: leg,
      cancelToken: cancelToken,
      loadItems: () => ref
          .read(radarrServiceForProvider(instance.id))
          .lookupMovies(query, cancelToken: cancelToken, reportFailure: true),
      toResult: (item, index) => _radarrResult(item, instance, index),
    ),
    ServiceKey.sonarr => _loadLeg(
      leg: leg,
      cancelToken: cancelToken,
      loadItems: () => ref
          .read(sonarrServiceForProvider(instance.id))
          .lookupSeries(query, cancelToken: cancelToken, reportFailure: true),
      toResult: (item, index) => _sonarrResult(item, instance, index),
    ),
    ServiceKey.lidarr => _loadLeg(
      leg: leg,
      cancelToken: cancelToken,
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
    ServiceKey.bazarr => _loadLeg(
      leg: leg,
      cancelToken: cancelToken,
      loadItems: () => ref
          .read(bazarrServiceProvider)
          .searchLibrary(query, cancelToken: cancelToken),
      toResult: (item, index) => _bazarrResult(item, instance, index),
    ),
    // The two media servers share one arm because they share one interface:
    // `StreamServerClient.search` is the whole difference between them, and it
    // is the client that knows whether the bands came from typed hints or from
    // the server's own hubs.
    ServiceKey.jellyfin => _loadStreamLeg(
      leg: leg,
      client: ref.read(jellyfinServerProvider),
      query: query,
      cancelToken: cancelToken,
    ),
    ServiceKey.plex => _loadStreamLeg(
      leg: leg,
      client: ref.read(plexServerProvider),
      query: query,
      cancelToken: cancelToken,
    ),
    // Unreachable while `globalSearchLegsProvider` builds its legs out of
    // `globalSearchServices` — and spelled out rather than folded into a
    // catch-all for exactly that reason. Bazarr used to sit on the `_` arm, so
    // adding a service to the fan-out without giving it an arm silently ran the
    // new lane against Bazarr's library and labelled the rows with the new
    // service's name. A lane that admits it has no leg is recoverable; one that
    // answers with another server's contents is not.
    _ => Future.value(
      GlobalSearchServiceResults.fault(
        leg,
        StateError('no search leg for ${instance.service.title}'),
      ),
    ),
  };
}

/// A media server's lane: one `search`, rendered in the bands the server gave.
///
/// The groups are concatenated **in the order they arrive and never re-sorted**.
/// Plex ranks both its hubs and the rows inside them with a relevance model this
/// app cannot reproduce, and Jellyfin's bands come back in the declared order
/// with the server's own relevance preserved inside each — so imposing an order
/// here would be replacing an answer with a guess. The band's name rides along
/// as the row's tag, because a lane heading names the *connection* and would
/// otherwise be the only thing on screen saying what kind of hit this is.
///
/// Empty bands are dropped on the way in, and that is not a contradiction of
/// [StreamSearchGroup]'s "an empty group is a result": a zero pill is something
/// the service's own search page draws from the group list, and this lane has no
/// strip to draw it on — one flat list of rows under one heading. The
/// distinction it *does* keep is the one that matters here, below.
Future<GlobalSearchServiceResults> _loadStreamLeg({
  required SearchLeg leg,
  required StreamServerClient client,
  required String query,
  required CancelToken cancelToken,
}) {
  return _loadLeg<({StreamSearchGroup group, StreamItem item})>(
    leg: leg,
    cancelToken: cancelToken,
    loadItems: () async {
      final groups = await client.search(query, cancelToken: cancelToken);
      // `StreamServerClient.search` degrades to `[]` rather than throwing, and
      // its contract makes that shape mean one specific thing: **no groups at
      // all is "the question could not be asked"**, while a list of empty
      // groups is "asked, and nothing matched". Without this throw a media
      // server that is switched off would report "0 results" in the same words
      // a working one uses for a query it does not hold — which is the exact
      // confusion the per-connection fan-out exists to end. The reason is
      // coarser than the arr legs' (`reportFailure: true` carries the real one
      // up), so this lands on "Search failed" rather than on "Unreachable": a
      // fault the user can retry, and not a claim about why.
      if (groups.isEmpty) {
        throw const _StreamSearchUnanswered();
      }
      return [
        for (final group in groups)
          for (final item in group.items) (group: group, item: item),
      ];
    },
    toResult: (row, index) =>
        _streamResult(row.item, row.group, leg.instance, client, index),
  );
}

/// Thrown when a media server's search came back with no bands at all.
///
/// A type rather than a bare `Exception` so the intent survives a stack trace:
/// this is the client's documented "could not ask" shape being re-raised, not a
/// parse failure.
class _StreamSearchUnanswered implements Exception {
  const _StreamSearchUnanswered();

  @override
  String toString() => 'the server did not answer the search';
}

Future<GlobalSearchServiceResults> _loadLeg<T>({
  required SearchLeg leg,
  required CancelToken cancelToken,
  required Future<List<T>> Function() loadItems,
  required GlobalSearchResult Function(T item, int index) toResult,
}) async {
  try {
    final items = await loadItems().timeout(
      _laneDeadline,
      onTimeout: () {
        // Let go of the socket as well as of the wait. Without this the request
        // runs on to the transport's own 15 s deadline holding a pool slot the
        // lanes behind it are queued for — the lane would say "did not answer
        // in time" while still being the reason nothing else could ask.
        cancelToken.cancel();
        throw TimeoutException('$_laneDeadline search deadline', _laneDeadline);
      },
    );
    return GlobalSearchServiceResults(
      leg: leg,
      results: [for (var i = 0; i < items.length; i++) toResult(items[i], i)],
    );
  } catch (error) {
    // Classified rather than stored raw: the lane's tone, its word and whether
    // it offers a Retry all come from the reason, and `classifyConnectionFailure`
    // is the app's single answer to "why did that fail" — see the tone argument
    // on `GlobalSearchServiceResults.fault`.
    return GlobalSearchServiceResults.fault(leg, error);
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
    // The connection that listed it. A row in the Away section adds to Away,
    // whatever the lens is pointing at.
    // No TMDB id, no add: the id is what Radarr keys the new entry on, and it
    // is also what `libraryKey` remembers the add under — so a row without one
    // would both fail on the server and share `…:0` with every other row in the
    // same state, flipping them all to owned when any one of them was added.
    // The same shape as the Hero-tag collision that `_heroTag` documents.
    addRequest: inLibrary || item.tmdbId <= 0
        ? null
        : RadarrAddRequest(instanceId: instance.id, movie: item),
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
    // No TVDB id, no add — and Sonarr really does return such rows, for shows
    // it can only match on TMDB. See the note in `_radarrResult`.
    addRequest: inLibrary || item.tvdbId <= 0
        ? null
        : SonarrAddRequest(instanceId: instance.id, series: item),
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

/// The poster width asked of a media server for a search row.
///
/// The row carries a 50×75 plate, so this is that at 3x and nothing more: both
/// servers resize far more cheaply than Flutter does, and asking for the full
/// artwork would ship a 2000px poster per row over the same link the rest of the
/// fan-out is queued on.
const _streamSearchPosterWidth = 160;

GlobalSearchResult _streamResult(
  StreamItem item,
  StreamSearchGroup group,
  ServiceInstance instance,
  StreamServerClient client,
  int index,
) {
  final path = item.posterPath;
  // The client owns the credential, so it — and not this file — turns a
  // relative key into something loadable. Null when the item carries no
  // artwork, which reads as "does not fly" the same way a Bazarr row does.
  final image = path == null || path.isEmpty
      ? null
      : client.imageFor(path, width: _streamSearchPosterWidth);
  final heroTag = 'search_${instance.id}_${item.kind.name}_${item.id}_$index';
  final year = item.year;
  return GlobalSearchResult(
    service: instance.service,
    // Nothing reads this on a stream row, and there is nothing honest to put in
    // it: a media server's id is an opaque string — a Jellyfin GUID, a Plex
    // `ratingKey` — that does not fit an int. The real id travels where it is
    // actually used, in the route and in the hero tag, and the tag's position
    // tiebreak is what keeps two zero-id rows from colliding.
    id: 0,
    title: item.title,
    // The server's own second line where it has one (series name for an
    // episode, artist for a track), the year otherwise. Never both invented:
    // a film with no year prints one line, not "· ".
    subtitle: item.subtitle ?? (year == null ? '' : '$year'),
    imageUrl: image?.url ?? '',
    imageHeaders: image?.headers,
    // The band the server put this hit in, verbatim. Deriving a word from
    // `kind` instead would rename the server's own vocabulary — and a localised
    // Plex titles its hubs in its own language.
    tags: [group.label],
    // No "In library" and no plus. Every row here is *already* on the server
    // that listed it, so the tag would repeat the heading on every row, and
    // there is no library on a media server this app can write into.
    heroTag: heroTag,
    route: instance.service == ServiceKey.jellyfin
        ? ServiceRoutes.jellyfinItem(item.id)
        : ServiceRoutes.plexItem(item.id),
    // The item itself, so the detail page can draw before its own fetch lands.
    routeExtra: item,
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
    // No id, no plus. Lidarr keys an artist on its MusicBrainz id and refuses
    // an add without one, so a row the lookup returned without it gets no
    // affordance rather than one that cannot be honoured.
    addRequest: inLibrary || item.foreignArtistId.isEmpty
        ? null
        : LidarrAddRequest(instanceId: instance.id, artist: item),
    heroTag: heroTag,
    route: ServiceRoutes.lidarrArtist(
      item.id,
      heroTag: heroTag,
      instanceId: instance.id,
    ),
    routeExtra: item,
  );
}
