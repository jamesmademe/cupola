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

import 'package:cupola/features/settings/domain/service_key.dart';

/// One library item, flattened to just what the rail paints and sorts on.
///
/// A projection rather than a union of the three models on purpose: the rail
/// needs five fields, and building the small struct up front means the sort runs
/// over those instead of over full library objects.
class RecentlyAddedItem {
  final ServiceKey service;
  final int id;
  final String title;

  /// Year for a movie or series, album count for an artist — whatever the
  /// service's own idea of a one-line qualifier is. Empty when there is none.
  final String subtitle;
  final String posterUrl;

  /// When the service says it was imported. Null when the service did not say,
  /// which sorts last — see [sortRecentlyAdded].
  final DateTime? addedAt;

  /// Whether the import failed.
  ///
  /// A failed import is a **fault**, which is amber, and it is also a *decision*
  /// — its actionable row lives in the decisions region, where the fix is. It is
  /// still named here because this region is now the record of what the arrs did
  /// today, and a record that silently drops the failures is a record that says
  /// the day went better than it did.
  final bool failed;

  const RecentlyAddedItem({
    required this.service,
    required this.id,
    required this.title,
    required this.subtitle,
    required this.posterUrl,
    required this.addedAt,
    this.failed = false,
  });

  /// Hero tag shared with the destination screen.
  String get heroTag => 'services_recent_${service.routeParam}_$id';
}

/// The region's eyebrow: `5 imported · 1 failed`.
///
/// The failed half is drawn in amber by the caller and is simply absent at zero
/// — a permanent "0 failed" is a counter nobody reads on the day it moves. The
/// two halves are returned separately because only one of them is coloured.
({String imported, String? failed}) recentlyAddedEyebrow(
  List<RecentlyAddedItem> items,
) {
  final failed = items.where((item) => item.failed).length;
  final imported = items.length - failed;
  return (
    imported: '$imported imported',
    failed: failed == 0 ? null : '$failed failed',
  );
}

/// What one poster tile announces: `title · service · time`.
///
/// The rail is six tiles wide and each one is a tap target, so the accessible
/// name has to carry the three facts the tile's own 60×90 box can only show two
/// of. Time is spoken as a clock reading rather than "4 hours ago": these are
/// today's imports, and the hour is what tells two grabs of the same show apart.
String recentlyAddedTileLabel(
  RecentlyAddedItem item, {
  required String timeLabel,
}) => [
  item.title,
  item.service.title,
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
  final sorted = List<RecentlyAddedItem>.of(items)
    ..sort((a, b) {
      final addedA = a.addedAt;
      final addedB = b.addedAt;
      if (addedA == null && addedB == null) return 0;
      if (addedA == null) return 1;
      if (addedB == null) return -1;
      return addedB.compareTo(addedA);
    });

  return sorted.take(limit).toList(growable: false);
}
