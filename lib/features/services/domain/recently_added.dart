/// The cross-service "Recently Added" rail on `/services`.
///
/// ## What this replaces, and why it is a correctness fix
///
/// The hub used to carry two rails titled "Recently Added · Movies" and
/// "Recently Added · Series". Neither was sorted. Both read
/// `moviesProvider` / `seriesProvider` — which fetch the **entire** library
/// through `fetchAllItems`, in whatever order the service returns it — and then
/// took the first eight. So the rails showed eight arbitrary items from the
/// library under a heading claiming they were the newest, and the `added`
/// timestamp that every one of these models already carries went unread.
///
/// A wrong sort is worse here than no rail: a user checking whether last night's
/// grab landed was being shown a stable list that never changed.
library;

import 'package:cupola/core/status/lexicon.dart';
import 'package:cupola/core/utils/arr_activity_display.dart';
import 'package:cupola/features/services/domain/source_coverage.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';

/// One library item, flattened to just what the rail paints and sorts on.
///
/// A projection rather than a union of the three models on purpose: the rail
/// needs a handful of fields, and building the small struct up front means the
/// sort runs over those instead of over full library objects.
///
/// Built one per history record, then folded by [groupRecentlyAdded] — a
/// season that lands as six episode imports is one row saying so, not six rows
/// with the same poster and the same title.
class RecentlyAddedItem {
  final ServiceKey service;

  /// The connection the record came off. Its [id] is that server's: each
  /// Radarr numbers its films from one, so the same id names a different
  /// film on the other, and the tile has to open this one's.
  final String instanceId;

  /// What tells [instanceId] apart from the service's other connections, by
  /// the app's one rule, or null while the service has only the one.
  final String? connectionName;

  final int id;
  final String title;
  final String posterUrl;

  /// When the service says it was imported. Null when the service did not say,
  /// which sorts last — see [sortRecentlyAdded]. On a folded row, the newest of
  /// its records.
  final DateTime? addedAt;

  /// Whether the import failed.
  ///
  /// A failed import is a **fault**, which is amber, and it is also a *decision*
  /// — its actionable row lives in the decisions region, where the fix is. It is
  /// still named here because this region is now the record of what the arrs did
  /// today, and a record that silently drops the failures is a record that says
  /// the day went better than it did.
  final bool failed;

  /// What this record is one piece of, and therefore what rows fold on: the
  /// season number on Sonarr, the album id on Lidarr. Null on Radarr, where the
  /// movie is its own unit, and whenever the record does not say.
  final int? unitId;

  /// The record's own piece, as the service names it: `S1 E3` for an episode,
  /// the artist behind an album. Null when there is none.
  final String? detail;

  /// How many history records this row stands for. One until
  /// [groupRecentlyAdded] folds a season or an album together.
  final int count;

  const RecentlyAddedItem({
    required this.service,
    this.instanceId = '',
    this.connectionName,
    required this.id,
    required this.title,
    required this.posterUrl,
    required this.addedAt,
    this.failed = false,
    this.unitId,
    this.detail,
    this.count = 1,
  });

  /// The line under the title: `Season 1 · 6 episodes`, `S1 E3`,
  /// `Cindy Lee · 12 tracks`. Empty on a movie.
  ///
  /// A folded season drops the episode code rather than listing six of them —
  /// the count is the fact, and the codes are what the series page is for.
  String get subtitle => switch (service) {
    ServiceKey.sonarr when count > 1 => joinDisplayParts([
      _seasonLabel(unitId),
      '$count episodes',
    ]),
    ServiceKey.sonarr => detail ?? '',
    ServiceKey.lidarr => joinDisplayParts([
      detail,
      if (count > 1) '$count tracks',
    ]),
    _ => '',
  };

  /// Hero tag shared with the destination screen.
  ///
  /// Carries the connection, the unit and the outcome as well as the id: film
  /// 3 on the HD Radarr and film 3 on the 4K, two seasons of one series, or a
  /// season that half landed and half failed, are two rows, and two heroes
  /// with one tag assert on the flight.
  String get heroTag => [
    'services_recent_${service.routeParam}_$id',
    if (instanceId.isNotEmpty) instanceId,
    if (unitId != null) '$unitId',
    if (failed) 'failed',
  ].join('_');

  RecentlyAddedItem _foldedWith(RecentlyAddedItem other) {
    final newer = _newerFirst(this, other) <= 0 ? this : other;
    return RecentlyAddedItem(
      service: service,
      instanceId: instanceId,
      connectionName: connectionName,
      id: id,
      title: title,
      // The first record that carried a poster keeps it: history embeds the
      // same series on every record, but an older record is no worse a source.
      posterUrl: posterUrl.isNotEmpty ? posterUrl : other.posterUrl,
      addedAt: newer.addedAt,
      failed: failed,
      unitId: unitId,
      detail: newer.detail ?? detail ?? other.detail,
      count: count + other.count,
    );
  }
}

String? _seasonLabel(int? season) => switch (season) {
  null => null,
  0 => 'Specials',
  _ => 'Season $season',
};

/// Folds the records of one season, one album, or one movie into one row.
///
/// The key is service, library item, unit and outcome. The outcome is in it on
/// purpose: a season whose episodes half landed and half failed is two facts,
/// and folding them would either paint successes amber or hide the failure.
/// A record that names no library item (`id <= 0` — a failed grab of something
/// the arr never added) is never folded: there is nothing to say it and its
/// neighbour are the same thing.
///
/// Folds **before** [sortRecentlyAdded] caps the list, so the cap counts rows
/// rather than records — six episodes of one season no longer spend the whole
/// region on one show.
List<RecentlyAddedItem> groupRecentlyAdded(List<RecentlyAddedItem> items) {
  final groups = <Object, RecentlyAddedItem>{};
  var loose = 0;
  for (final item in items) {
    final Object key = item.id <= 0
        ? loose++
        : (item.service, item.instanceId, item.id, item.unitId, item.failed);
    final existing = groups[key];
    groups[key] = existing == null ? item : existing._foldedWith(item);
  }
  return groups.values.toList(growable: false);
}

/// The region's eyebrow: `5 imported · 1 failed`.
///
/// The failed half is drawn in amber by the caller and is simply absent at zero
/// — a permanent "0 failed" is a counter nobody reads on the day it moves. The
/// two halves are returned separately because only one of them is coloured.
///
/// Counted over the libraries [coverage] says answered. With none of them
/// answering the figure is `— imported` and there is no failed half: an empty
/// rail over three libraries that did not answer is not "0 imported". A
/// history page that came back full is a window onto more history
/// ([SourceCoverage.isFloor]), so both halves are floors: `20+ imported`,
/// `2+ failed`.
({String imported, String? failed}) recentlyAddedEyebrow(
  List<RecentlyAddedItem> items, {
  SourceCoverage coverage = SourceCoverage.none,
}) {
  if (coverage.everySourceFailed) {
    return (imported: '${Lexicon.noFigure} imported', failed: null);
  }
  // Records, not rows: a folded season of six is six imports, which is what the
  // row under this eyebrow says too.
  var failed = 0;
  var imported = 0;
  for (final item in items) {
    if (item.failed) {
      failed += item.count;
    } else {
      imported += item.count;
    }
  }
  String figure(int count) =>
      coverage.isFloor ? Lexicon.floor(count) : '$count';
  return (
    imported: '${figure(imported)} imported',
    failed: failed == 0 ? null : '${figure(failed)} failed',
  );
}

/// What one poster tile announces: `title · detail · service · time`.
///
/// The rail is six tiles wide and each one is a tap target, so the accessible
/// name has to carry the facts the tile's own 60×90 box cannot show — the
/// season or album among them, since the tile paints only the title. Time is spoken as a clock reading rather than "4 hours ago": these are
/// today's imports, and the hour is what tells two grabs of the same show apart.
String recentlyAddedTileLabel(
  RecentlyAddedItem item, {
  required String timeLabel,
}) => [
  item.title,
  if (item.subtitle.isNotEmpty) item.subtitle,
  // `Radarr 4K` once there are two, said as the eye reads it on the row.
  serviceWithConnection(item.service, item.connectionName, joiner: ' '),
  if (item.failed) 'failed import',
  if (timeLabel.isNotEmpty) timeLabel,
].join(', ');

/// `08:12` — the import's own clock time, or empty when it has none.
///
/// Time-only on purpose: every row in this region landed within the last day or
/// so, and a date on all six is a column of the same string.
String formatImportedAt(DateTime? at) {
  if (at == null) return '';
  final local = at.toLocal();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${two(local.hour)}:${two(local.minute)}';
}

/// Parses an arr `added` field, which is an ISO 8601 string or absent.
///
/// Returns null rather than throwing or defaulting to the epoch: a bad timestamp
/// must not sort an item to the top of a "newest first" rail, and it must not
/// take the rail down either.
DateTime? parseAddedTimestamp(String? added) {
  final raw = added?.trim();
  if (raw == null || raw.isEmpty) return null;
  return DateTime.tryParse(raw);
}

/// Newest first, capped at [limit].
///
/// Items without a timestamp sort to the end and are therefore the first to be
/// dropped by [limit] — they cannot be placed honestly, so they lose to anything
/// that can.
///
/// Runs on the UI thread deliberately. The project sends large **JSON mapping**
/// to `Isolate.run`, and that already happened upstream in each service; this is
/// a comparison sort over a five-field struct. Hopping isolates would deep-copy
/// every item across the boundary to save a sort measured in microseconds, which
/// is a slower design wearing the costume of a faster one.
List<RecentlyAddedItem> sortRecentlyAdded(
  List<RecentlyAddedItem> items, {
  required int limit,
}) {
  final sorted = List<RecentlyAddedItem>.of(items)..sort(_newerFirst);

  return sorted.take(limit).toList(growable: false);
}

int _newerFirst(RecentlyAddedItem a, RecentlyAddedItem b) {
  final addedA = a.addedAt;
  final addedB = b.addedAt;
  if (addedA == null && addedB == null) return 0;
  if (addedA == null) return 1;
  if (addedB == null) return -1;
  return addedB.compareTo(addedA);
}
