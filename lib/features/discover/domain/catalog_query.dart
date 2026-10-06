import 'package:flutter/foundation.dart';

import 'package:cupola/core/models/media_preview.dart';

/// Which half of the catalogue a page reads. TMDB keeps films and series
/// apart, and so does every Seerr discover call but trending.
enum CatalogKind {
  movie('movie', 'movies', 'Movies'),
  tv('tv', 'tv', 'Series');

  const CatalogKind(this.mediaType, this.segment, this.label);

  /// The media type a title of this kind opens as (`movie`, `tv`).
  final String mediaType;

  /// The kind's segment in Seerr's discover paths (`/discover/movies`).
  final String segment;

  final String label;

  /// The kind a route spells, or null for one this app does not know.
  static CatalogKind? parse(String? value) => switch (value) {
    'movie' || 'movies' => CatalogKind.movie,
    'tv' || 'series' => CatalogKind.tv,
    _ => null,
  };
}

/// What a catalogue page is about: every door of the atrium and every
/// "See all" lands on one of these.
enum CatalogBase {
  /// The whole catalogue of one kind.
  all,

  /// TMDB's trending titles, films and series mixed.
  trending,

  /// Titles not out yet.
  upcoming,
  genre,

  /// A television network: series only.
  network,

  /// A film studio: movies only.
  studio,

  /// A TMDB keyword, which the atrium calls a mood.
  keyword,

  /// The original language.
  language,
  decade,
}

/// How a catalogue page orders its titles.
enum CatalogSort {
  popular('Popular'),
  topRated('Top rated'),
  newest('Newest');

  const CatalogSort(this.label);
  final String label;
}

/// TMDB's two trending windows.
enum TrendingWindow {
  day('day', 'Today'),
  week('week', 'This week');

  const TrendingWindow(this.param, this.label);
  final String param;
  final String label;
}

/// The vote floor under a score filter and under every ordering by score.
///
/// TMDB's ordering by score with no floor leads with titles one person rated
/// ten (verified on the lab, 06/10: an animation page led by four titles
/// nobody had heard of). A hundred votes is where a score starts to mean
/// something.
const int catalogVoteFloor = 100;

/// The genres TMDB numbers the same way for movies and series, where a page
/// can offer both halves. Every other genre id names a different genre, or
/// none, on the other side (movie 28 is Action, series have 10759, Action &
/// Adventure).
const Set<int> sharedGenreIds = {16, 35, 80, 99, 18, 10751, 9648, 37};

/// One catalogue page's question to Seerr: the base, the kind, the filters
/// and the order. Equal queries are the same page, so it keys providers.
@immutable
class CatalogQuery {
  const CatalogQuery._({
    required this.base,
    required this.kind,
    this.id,
    this.code,
    this.name,
    this.sort = CatalogSort.popular,
    this.window = TrendingWindow.week,
    this.decadeFilter,
    this.rated = false,
    this.short = false,
  });

  const CatalogQuery.all(
    CatalogKind kind, {
    CatalogSort sort = CatalogSort.popular,
  }) : this._(base: CatalogBase.all, kind: kind, sort: sort);

  const CatalogQuery.trending({TrendingWindow window = TrendingWindow.week})
    : this._(
        base: CatalogBase.trending,
        kind: CatalogKind.movie,
        window: window,
      );

  const CatalogQuery.upcoming(CatalogKind kind)
    : this._(base: CatalogBase.upcoming, kind: kind);

  const CatalogQuery.genre(CatalogKind kind, int id, String name)
    : this._(base: CatalogBase.genre, kind: kind, id: id, name: name);

  const CatalogQuery.network(int id, String name)
    : this._(
        base: CatalogBase.network,
        kind: CatalogKind.tv,
        id: id,
        name: name,
      );

  const CatalogQuery.studio(int id, String name)
    : this._(
        base: CatalogBase.studio,
        kind: CatalogKind.movie,
        id: id,
        name: name,
      );

  const CatalogQuery.keyword(CatalogKind kind, int id, String name)
    : this._(base: CatalogBase.keyword, kind: kind, id: id, name: name);

  const CatalogQuery.language(CatalogKind kind, String code, String name)
    : this._(base: CatalogBase.language, kind: kind, code: code, name: name);

  /// The ten years from [start] (1990 is the 1990s).
  const CatalogQuery.decade(CatalogKind kind, int start)
    : this._(base: CatalogBase.decade, kind: kind, id: start);

  final CatalogBase base;
  final CatalogKind kind;

  /// The genre, network, studio or keyword id; the first year of a decade.
  final int? id;

  /// The language code.
  final String? code;

  /// The genre, network, studio, keyword or language as it is written.
  final String? name;

  final CatalogSort sort;
  final TrendingWindow window;

  /// The first year of the decade the titles came out in, as a filter over
  /// a base that is not itself a decade.
  final int? decadeFilter;

  /// TMDB 7 or more, over at least [catalogVoteFloor] votes.
  final bool rated;

  /// Movies under 100 minutes.
  final bool short;

  /// The page's heading.
  String get title => switch (base) {
    CatalogBase.all => kind.label,
    CatalogBase.trending => 'Trending',
    CatalogBase.upcoming => 'Coming soon',
    CatalogBase.decade => decadeLabel(id ?? 0),
    _ => name ?? '',
  };

  /// The kinds this page can switch between: both where both halves exist,
  /// none where there is one (a network's series, a studio's movies) or a
  /// mix (trending).
  List<CatalogKind> get kinds => switch (base) {
    CatalogBase.trending ||
    CatalogBase.network ||
    CatalogBase.studio => const [],
    CatalogBase.genre when !sharedGenreIds.contains(id) => const [],
    _ => CatalogKind.values,
  };

  /// Whether Seerr takes filters and an order on this base. Its trending
  /// and upcoming lists take a page and nothing else.
  bool get filters =>
      base != CatalogBase.trending && base != CatalogBase.upcoming;

  /// Whether the decade filter means anything here.
  bool get offersDecade => filters && base != CatalogBase.decade;

  /// Whether the runtime filter means anything here: TMDB's runtime is a
  /// film's, and a series' is an episode's.
  bool get offersShort => filters && kind == CatalogKind.movie;

  /// Whether any filter narrows the base.
  bool get filtered => decadeFilter != null || rated || short;

  CatalogQuery withKind(CatalogKind value) => _copy(
    kind: value,
    // An episode has no feature length to filter on.
    short: value == CatalogKind.movie && short,
  );

  CatalogQuery withSort(CatalogSort value) => _copy(sort: value);

  CatalogQuery withWindow(TrendingWindow value) => _copy(window: value);

  CatalogQuery withDecade(int? start) =>
      _copy(decadeFilter: start, clearDecade: start == null);

  CatalogQuery withRated(bool value) => _copy(rated: value);

  CatalogQuery withShort(bool value) => _copy(short: value);

  CatalogQuery _copy({
    CatalogKind? kind,
    CatalogSort? sort,
    TrendingWindow? window,
    int? decadeFilter,
    bool clearDecade = false,
    bool? rated,
    bool? short,
  }) => CatalogQuery._(
    base: base,
    kind: kind ?? this.kind,
    id: id,
    code: code,
    name: name,
    sort: sort ?? this.sort,
    window: window ?? this.window,
    decadeFilter: clearDecade ? null : decadeFilter ?? this.decadeFilter,
    rated: rated ?? this.rated,
    short: short ?? this.short,
  );

  /// The Seerr path this page reads.
  String get path => switch (base) {
    CatalogBase.trending => '/api/v1/discover/trending',
    CatalogBase.upcoming => '/api/v1/discover/${kind.segment}/upcoming',
    _ => '/api/v1/discover/${kind.segment}',
  };

  /// The query of page [page], each filter in the parameter Seerr 3.4.1
  /// answers to (verified on the lab, 06/10). [today] bounds the newest
  /// first ordering, which would otherwise lead with films announced for
  /// years from now.
  Map<String, Object> parameters(int page, {required DateTime today}) {
    if (base == CatalogBase.trending) {
      return {'page': page, 'timeWindow': window.param};
    }
    if (base == CatalogBase.upcoming) return {'page': page};

    final movie = kind == CatalogKind.movie;
    final from = movie ? 'primaryReleaseDateGte' : 'firstAirDateGte';
    final to = movie ? 'primaryReleaseDateLte' : 'firstAirDateLte';
    final decade = base == CatalogBase.decade ? id : decadeFilter;
    final scored = rated || sort == CatalogSort.topRated;
    // The newest first ordering stops at today, unless a decade that ended
    // already bounds it.
    final until = decade != null
        ? _date(DateTime(decade + 9, 12, 31))
        : sort == CatalogSort.newest
        ? _date(today)
        : null;

    return {
      'page': page,
      if (base == CatalogBase.genre) 'genre': ?id,
      if (base == CatalogBase.network) 'network': ?id,
      if (base == CatalogBase.studio) 'studio': ?id,
      if (base == CatalogBase.keyword) 'keywords': ?id,
      if (base == CatalogBase.language) 'language': ?code,
      if (decade != null) from: _date(DateTime(decade)),
      to: ?until,
      if (rated) 'voteAverageGte': 7,
      if (scored) 'voteCountGte': catalogVoteFloor,
      if (short && movie) 'withRuntimeLte': 100,
      'sortBy': switch (sort) {
        CatalogSort.popular => 'popularity.desc',
        CatalogSort.topRated => 'vote_average.desc',
        CatalogSort.newest =>
          movie ? 'primary_release_date.desc' : 'first_air_date.desc',
      },
    };
  }

  static String _date(DateTime day) =>
      '${day.year.toString().padLeft(4, '0')}-'
      '${day.month.toString().padLeft(2, '0')}-'
      '${day.day.toString().padLeft(2, '0')}';

  @override
  bool operator ==(Object other) =>
      other is CatalogQuery &&
      other.base == base &&
      other.kind == kind &&
      other.id == id &&
      other.code == code &&
      other.name == name &&
      other.sort == sort &&
      other.window == window &&
      other.decadeFilter == decadeFilter &&
      other.rated == rated &&
      other.short == short;

  @override
  int get hashCode => Object.hash(
    base,
    kind,
    id,
    code,
    name,
    sort,
    window,
    decadeFilter,
    rated,
    short,
  );

  @override
  String toString() => 'CatalogQuery($base, $kind, ${id ?? code})';
}

/// "1990s".
String decadeLabel(int start) => '${start}s';

/// One page of a catalogue, with what Seerr says of the whole.
@immutable
class CatalogPageResult {
  const CatalogPageResult({
    required this.items,
    required this.page,
    required this.totalPages,
    required this.totalResults,
  });

  final List<MediaPreview> items;
  final int page;
  final int totalPages;
  final int totalResults;
}

/// How many titles a catalogue holds, as a phrase that never claims more
/// than Seerr knows.
///
/// Seerr caps what it reports: a discover list past TMDB's last page says
/// 20,001 over 1,001 pages, trending says 10,000 over 500 (both seen on the
/// lab, 06/10), so a figure at a cap is a floor ("20,000+"), and only one
/// under it is a total. Null when Seerr gave no count.
String? catalogCountPhrase(int? totalResults) {
  if (totalResults == null || totalResults <= 0) return null;
  if (totalResults >= 20000) return '20,000+ titles';
  if (totalResults == 10000) return '10,000+ titles';
  final digits = totalResults.toString();
  final grouped = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) grouped.write(',');
    grouped.write(digits[i]);
  }
  return totalResults == 1 ? '1 title' : '$grouped titles';
}
