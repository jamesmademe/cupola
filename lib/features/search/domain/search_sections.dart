import 'package:cupola/features/discover/domain/seerr_numbering.dart';
import 'package:cupola/features/discover/domain/seerr_status.dart';
import 'package:cupola/features/media/domain/media_key.dart';
import 'package:cupola/features/search/domain/global_search_result.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// One title the search found, folded across every source that found it:
/// the film Seerr, Radarr and Jellyfin each list is one row.
class SearchTitle {
  const SearchTitle({
    required this.kind,
    required this.key,
    required this.title,
    required this.year,
    required this.score,
    required this.imageUrl,
    required this.imageHeaders,
    required this.heroTag,
    required this.route,
    required this.routeExtra,
    required this.seerrInfo,
    required this.libraries,
    required this.servers,
    required this.held,
    required this.addable,
  });

  /// Movie or series.
  final SearchHitKind kind;

  /// The title across services; null for a row whose source named no id.
  final MediaKey? key;

  final String title;
  final int? year;

  /// TMDB's score, from Seerr; null without Seerr or for a title nobody rated.
  final double? score;

  /// The artwork, TMDB's where Seerr found the title (it needs no
  /// credential), else the server's own with its headers. Empty for none.
  final String imageUrl;
  final Map<String, String>? imageHeaders;

  /// The tag of the poster, already stamped into [route].
  final String heroTag;

  /// Where a tap goes: the title's page opened on the copy that holds it.
  final String route;
  final Object? routeExtra;

  /// Seerr's record of the title, when Seerr found it.
  final Map<String, dynamic>? seerrInfo;

  /// The arr connections whose library holds it, as their lanes are called
  /// (`Radarr`, `Radarr · 4K`).
  final List<String> libraries;

  /// The media servers that found it, as their lanes are called (`Jellyfin`,
  /// `Jellyfin · Cabin` once there are two).
  final List<String> servers;

  /// On the server: a media server has it, Seerr says it is there in whole or
  /// in part, or an arr's library holds it.
  final bool held;

  /// The operator may add it from the row: its arr is set up, every one of
  /// that arr's connections answered, none of them holds it, and the row
  /// carries the id the arr keys it on.
  final bool addable;

  bool get isMovie => kind == SearchHitKind.movie;

  /// Radarr for a movie, Sonarr for a series.
  ServiceKey get arr => isMovie ? ServiceKey.radarr : ServiceKey.sonarr;

  bool get canFlyPoster => imageUrl.isNotEmpty;
}

/// What a search found, by kind rather than by service: what is on
/// the server first, then the catalogue's movies and series, then people.
class SearchSections {
  const SearchSections({
    this.onServer = const [],
    this.movies = const [],
    this.series = const [],
    this.people = const [],
    this.peopleAsked = false,
    this.peopleFirst = false,
    this.silent = const [],
    this.searching = false,
  });

  final List<SearchTitle> onServer;
  final List<SearchTitle> movies;
  final List<SearchTitle> series;

  /// The people Seerr found, in its order.
  final List<GlobalSearchResult> people;

  /// Whether Seerr answered, so the People section can say "No one called"
  /// rather than leave a question it never asked looking answered.
  final bool peopleAsked;

  /// Seerr ranked a person first (`tom hanks`): the people lead the
  /// catalogue's movies and series, under what is on the server.
  final bool peopleFirst;

  /// The sources that stopped short of an answer, in the registry's order:
  /// each draws one quiet line saying what is missing.
  final List<GlobalSearchServiceResults> silent;

  /// A source is still out.
  final bool searching;

  bool get isEmpty =>
      onServer.isEmpty && movies.isEmpty && series.isEmpty && people.isEmpty;

  /// Every source answered or stopped.
  bool get settled => !searching;
}

/// Folds the lanes of a search into its sections.
///
/// Titles meet on their [MediaKey]: Seerr's row leads (its words, TMDB's
/// artwork and score, its order, which is TMDB's relevance), then each arr's,
/// then each media server's; a row with no key stands alone. Within a section
/// the order is the order the titles were first found in, so a source that
/// answers late adds to a section rather than reshuffling it.
///
/// A lane still out or stopped adds nothing: a Radarr that did not answer is
/// never read as one that holds nothing, so no title is addable while its arr
/// is silent.
SearchSections searchSections(
  List<GlobalSearchServiceResults> lanes, {
  SeerrNumbering? numbering,
}) {
  final ordered = [...lanes]
    ..sort((a, b) => _rank(a.service).compareTo(_rank(b.service)));
  final folds = <_Fold>[];
  final byKey = <MediaKey, _Fold>{};
  final people = <GlobalSearchResult>[];
  var peopleAsked = false;
  var peopleFirst = false;

  for (final lane in ordered) {
    if (lane.state != SearchLaneState.answered) continue;
    if (lane.service == ServiceKey.seerr) {
      peopleAsked = true;
      peopleFirst = lane.results.firstOrNull?.kind == SearchHitKind.person;
    }
    for (final hit in lane.results) {
      switch (hit.kind) {
        case SearchHitKind.person:
          people.add(hit);
          continue;
        case SearchHitKind.other:
          continue;
        case SearchHitKind.movie || SearchHitKind.series:
          break;
      }
      final key = hit.key;
      final fold = key == null
          ? _byTitle(folds, hit, lane.service)
          : byKey[key];
      if (fold != null) {
        fold.add(lane, hit);
      } else {
        final created = _Fold(lane, hit);
        folds.add(created);
        if (key != null) byKey[key] = created;
      }
    }
  }

  // Which arr may add: set up (it has lanes) and every one of its lanes
  // answered.
  bool arrAnswered(ServiceKey arr) {
    final own = lanes.where((lane) => lane.service == arr);
    return own.isNotEmpty &&
        own.every((lane) => lane.state == SearchLaneState.answered);
  }

  final radarrAnswered = arrAnswered(ServiceKey.radarr);
  final sonarrAnswered = arrAnswered(ServiceKey.sonarr);

  final onServer = <SearchTitle>[];
  final movies = <SearchTitle>[];
  final series = <SearchTitle>[];
  for (final fold in folds) {
    final title = fold.build(
      numbering: numbering,
      arrAnswered: fold.isMovie ? radarrAnswered : sonarrAnswered,
    );
    if (title.held) {
      onServer.add(title);
    } else if (title.isMovie) {
      movies.add(title);
    } else {
      series.add(title);
    }
  }

  return SearchSections(
    onServer: onServer,
    movies: movies,
    series: series,
    people: people,
    peopleAsked: peopleAsked,
    peopleFirst: peopleFirst,
    silent: [
      for (final lane in lanes)
        if (lane.hasFault) lane,
    ],
    searching: lanes.any((lane) => lane.state == SearchLaneState.searching),
  );
}

/// The fold a media server's hit with no key belongs to: Jellyfin's search
/// carries no TMDB id, so its Fight Club meets Seerr's and Radarr's by kind,
/// name and year, or by name alone when the server gave no year and only one
/// title of that kind has the name. Null for any other source, and when the
/// name is ambiguous: two rows are a smaller fault than one wrong one.
_Fold? _byTitle(List<_Fold> folds, GlobalSearchResult hit, ServiceKey source) {
  if (_rank(source) < 2) return null;
  final name = _plain(hit.title);
  final same = [
    for (final fold in folds)
      if (fold.first.kind == hit.kind && fold.names.contains(name)) fold,
  ];
  final year = hit.year;
  if (year != null) {
    return same.where((fold) => fold.years.contains(year)).firstOrNull;
  }
  return same.length == 1 ? same.single : null;
}

/// A title as two sources would both spell it: case and punctuation aside.
String _plain(String title) => title.toLowerCase().replaceAll(
  RegExp(r'[^\p{L}\p{N}]+', unicode: true),
  '',
);

/// Seerr leads a fold, then the arrs, then the media servers.
int _rank(ServiceKey service) => switch (service) {
  ServiceKey.seerr => 0,
  ServiceKey.radarr || ServiceKey.sonarr => 1,
  _ => 2,
};

/// The hits of one title as they arrive, source by source.
class _Fold {
  _Fold(GlobalSearchServiceResults lane, GlobalSearchResult hit) : first = hit {
    add(lane, hit);
  }

  final GlobalSearchResult first;
  GlobalSearchResult? seerr;
  GlobalSearchResult? held;
  final libraries = <String>[];
  final servers = <String>[];
  GlobalSearchResult? artwork;

  bool get isMovie => first.kind == SearchHitKind.movie;

  /// Every spelling and year the sources gave it, for [_byTitle].
  final names = <String>{};
  final years = <int>{};

  void add(GlobalSearchServiceResults lane, GlobalSearchResult hit) {
    names.add(_plain(hit.title));
    if (hit.year case final year?) years.add(year);
    switch (hit.service) {
      case ServiceKey.seerr:
        seerr ??= hit;
      case ServiceKey.radarr || ServiceKey.sonarr:
        if (hit.inLibrary) {
          libraries.add(lane.laneTitle);
          held ??= hit;
        }
      default:
        if (!servers.contains(lane.laneTitle)) servers.add(lane.laneTitle);
        held ??= hit;
    }
    if (artwork == null && hit.imageUrl.isNotEmpty) artwork = hit;
  }

  SearchTitle build({
    required SeerrNumbering? numbering,
    required bool arrAnswered,
  }) {
    final lead = seerr ?? first;
    // TMDB's artwork where Seerr has it: no credential, and the same poster
    // the title's page shows.
    final art = (seerr?.imageUrl.isNotEmpty ?? false) ? seerr : artwork;
    // The page opens on the copy that holds the title; else on Seerr's or the
    // first source's row.
    final opens = held ?? seerr ?? first;
    final key = lead.key ?? first.key;
    final isHeld =
        libraries.isNotEmpty ||
        servers.isNotEmpty ||
        seerrHolds(seerr?.seerrInfo, numbering: numbering);
    return SearchTitle(
      kind: first.kind,
      key: key,
      title: lead.title,
      year: lead.year ?? first.year,
      score: seerr?.score,
      imageUrl: art?.imageUrl ?? '',
      imageHeaders: art?.imageHeaders,
      heroTag: opens.heroTag,
      route: opens.route,
      routeExtra: opens.routeExtra,
      seerrInfo: seerr?.seerrInfo,
      libraries: List.unmodifiable(libraries),
      servers: List.unmodifiable(servers),
      held: isHeld,
      // A key is the id the arr is asked by: TMDB's for a movie, TMDB's or
      // TVDB's for a series.
      addable: !isHeld && arrAnswered && key != null,
    );
  }
}
