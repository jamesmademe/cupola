/// Checking that a media server's answer to "do you have this arr title" is
/// that title.
///
/// **Why this exists.** Both servers are asked by external id: Jellyfin through
/// `anyProviderIdEquals`, Plex through `?guid=`, and both used to trust the
/// first row that came back. A server that ignores the filter does not fail: it
/// answers 200 with the start of the whole library, so every Radarr and Sonarr
/// page said "On Jellyfin · Ready to watch" and opened an arbitrary item. And a
/// server that honours the filter still answers more than one thing: the query
/// is an OR over the ids, TMDB numbers films and shows in two separate
/// namespaces, and an episode carries TVDB and IMDb ids of its own. The first
/// row of that set is not "the title" either.
///
/// So a candidate is accepted only on its own evidence: the ids the server
/// reports *for the item*, compared with the ones the arr asked about, and the
/// best-supported candidate wins. When nothing clears the bar the answer is
/// null, and the caller renders nothing: a missing "On Jellyfin" card is a lost
/// convenience, a wrong one is a false statement with a button on it.
///
/// Every function here is pure and top-level, like the mappers, so a client can
/// run it next to its own parse and the provider can run it again as a gate.
library;

import 'package:flutter/foundation.dart';

import 'package:cupola/features/stream/domain/models/stream_item.dart';

/// What an arr is asking a media server about: one film or one show.
@immutable
class StreamExternalQuery {
  /// The ids the arr knows the title by. At least one is needed for a query to
  /// be made at all: a title is never the *search* key, only a tie-breaker
  /// (see [title]).
  final String? tmdbId;
  final String? tvdbId;
  final String? imdbId;

  /// The kind the arr's record is, when the caller says: Radarr asks about a
  /// [StreamItemKind.movie], Sonarr about a [StreamItemKind.series].
  ///
  /// Null still narrows to those two. An arr detail page is a film or a show,
  /// never a season, an episode or a track, but cannot tell them apart, and
  /// TMDB numbers films and shows separately: Sonarr's TMDB id for a series can
  /// be some film's TMDB id too. Callers that know the kind should pass it.
  final StreamItemKind? kind;

  /// The arr's title and year, used **only** for a candidate whose ids cannot
  /// be compared with the query's (it reports none of the providers asked
  /// about). Both must be present and both must agree exactly after
  /// [normaliseStreamTitle]; otherwise such a candidate is refused.
  final String? title;
  final int? year;

  const StreamExternalQuery({
    this.tmdbId,
    this.tvdbId,
    this.imdbId,
    this.kind,
    this.title,
    this.year,
  });

  /// Whether there is any id to ask with.
  bool get hasIds =>
      _normaliseId(tmdbId) != null ||
      _normaliseId(tvdbId) != null ||
      _normaliseId(imdbId) != null;

  /// How many ids the query carries: the score a candidate needs to be
  /// confirmed by every one of them.
  int get idCount =>
      [tmdbId, tvdbId, imdbId].where((id) => _normaliseId(id) != null).length;
}

/// How well [candidate] is supported as the answer to [query], or null when it
/// is not the title the arr asked about.
///
/// The rules, in order:
///
/// 1. **Kind.** With [StreamExternalQuery.kind] the candidate must be that
///    kind; without it, a film or a show.
/// 2. **Ids decide wherever they can.** For every provider both sides report,
///    the values must be equal; a single disagreement refuses the candidate,
///    whatever else agrees, because two databases naming different titles is
///    exactly the case this cannot resolve. The score is the number of
///    providers that agree.
/// 3. **Only when no provider can be compared** does the title decide: exact
///    normalised title *and* year, both required on both sides, scoring zero.
///
/// A candidate with nothing comparable and no title evidence is refused. The
/// server's say-so that it matched the filter is precisely what cannot be
/// trusted.
int? streamExternalMatchScore(StreamItem candidate, StreamExternalQuery query) {
  final kind = query.kind;
  if (kind != null) {
    if (candidate.kind != kind) return null;
  } else if (candidate.kind != StreamItemKind.movie &&
      candidate.kind != StreamItemKind.series) {
    return null;
  }

  final ids = candidate.externalIds;
  var compared = 0;
  var agreed = 0;
  for (final (asked, held) in [
    (query.tmdbId, ids.tmdb),
    (query.tvdbId, ids.tvdb),
    (query.imdbId, ids.imdb),
  ]) {
    final askedId = _normaliseId(asked);
    final heldId = _normaliseId(held);
    if (askedId == null || heldId == null) continue;
    compared++;
    if (askedId != heldId) return null;
    agreed++;
  }
  if (compared > 0) return agreed;

  final title = normaliseStreamTitle(query.title);
  final year = query.year;
  if (title == null || year == null || year <= 0) return null;
  if (candidate.year != year) return null;
  if (normaliseStreamTitle(candidate.title) != title) return null;
  return 0;
}

/// What one media server answered when asked for a title by its ids.
///
/// Three answers, because "no match" was two facts in one null: the server
/// has nothing under those ids (**not in the library**, a claim the page may
/// make, "Not on Jellyfin"), or it has rows that do not verify as the title
/// (**not verified**, the brand book's case f, which makes no claim either
/// way). A server that did not answer is neither: the lookup throws, and the
/// caller classifies the failure.
enum StreamLookupOutcome { found, notInLibrary, notVerified }

@immutable
class StreamExternalLookup {
  const StreamExternalLookup.found(StreamItem this.item)
    : outcome = StreamLookupOutcome.found;

  const StreamExternalLookup.notInLibrary()
    : outcome = StreamLookupOutcome.notInLibrary,
      item = null;

  const StreamExternalLookup.notVerified()
    : outcome = StreamLookupOutcome.notVerified,
      item = null;

  /// The verdict over the rows a server returned for [query]: the
  /// best-supported one when any clears the bar, "not verified" when rows came
  /// back and none did, and "not in the library" when none came back at all.
  factory StreamExternalLookup.of(
    Iterable<StreamItem> candidates,
    StreamExternalQuery query,
  ) {
    final rows = candidates.toList(growable: false);
    if (rows.isEmpty) return const StreamExternalLookup.notInLibrary();
    final best = bestStreamExternalMatch(rows, query);
    return best == null
        ? const StreamExternalLookup.notVerified()
        : StreamExternalLookup.found(best);
  }

  final StreamLookupOutcome outcome;

  /// The verified item, on [StreamLookupOutcome.found] only.
  final StreamItem? item;
}

/// The best-supported candidate for [query], or null when none is supported.
///
/// Ties keep the server's order: the same film in a 4K and an HD library is two
/// equally right answers, and either opens the same title.
StreamItem? bestStreamExternalMatch(
  Iterable<StreamItem> candidates,
  StreamExternalQuery query,
) {
  StreamItem? best;
  var bestScore = -1;
  for (final candidate in candidates) {
    final score = streamExternalMatchScore(candidate, query);
    if (score != null && score > bestScore) {
      best = candidate;
      bestScore = score;
    }
  }
  return best;
}

/// A title reduced to what two catalogues reliably agree on: lower case, every
/// run of punctuation and spacing collapsed to one space, trimmed. Null when
/// nothing is left.
///
/// Deliberately no stemming, article dropping or transliteration: this is a
/// last-resort *check*, and every loosening is a way for two different films
/// to compare equal.
String? normaliseStreamTitle(String? title) {
  if (title == null) return null;
  final normalised = title.toLowerCase().replaceAll(_nonWordRun, ' ').trim();
  return normalised.isEmpty ? null : normalised;
}

final RegExp _nonWordRun = RegExp(r'[^\p{L}\p{N}]+', unicode: true);

/// Ids compare case-insensitively (`tt0133093` and `TT0133093` are one IMDb
/// id) and an empty one is no id.
String? _normaliseId(String? id) {
  final trimmed = id?.trim().toLowerCase();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}
