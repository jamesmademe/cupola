/// What the Prowlarr Overview reads, and the pure functions that shape it.
///
/// Prowlarr's work is the **indexer table**: which indexers answer, how fast,
/// and which are failing. Two rules govern the whole file:
///
///  * **faults are amber, not red.** A refused query is a state the indexer
///    reported; red stays for a Prowlarr that does not answer at all, which is
///    the unreachable band's job and not a row's.
///  * **every figure carries its window.** `indexerstats` is fetched over
///    [prowlarrStatsWindow] (twenty-four hours), so a query or grab count on
///    this page is a day's work and the section that draws it says so. A figure
///    whose label contradicts its window is the defect this file exists to
///    avoid.
///
/// Every windowing rule is a top-level pure function taking an explicit `now`,
/// so the boundaries are testable without a clock or a container.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/providers/provider_retry.dart';
import 'package:cupola/core/status/media_status.dart';
import 'package:cupola/core/utils/arr_activity_display.dart';
import 'package:cupola/core/utils/unit_space.dart';
import 'package:cupola/features/activity/presentation/widgets/activity_formatters.dart'
    show formatRelativeDateTime;
import 'package:cupola/features/prowlarr/domain/models/prowlarr_models.dart';
import 'package:cupola/features/prowlarr/presentation/prowlarr_history_format.dart';
import 'package:cupola/features/prowlarr/presentation/prowlarr_provider.dart';
import 'package:cupola/features/services/domain/services_semantics.dart';

/// Indexer rows the table draws before the header's count is the only place the
/// rest are reported.
const int prowlarrIndexerPreviewLimit = 6;

/// Rows the Recent section draws.
const int prowlarrRecentPreviewLimit = 3;

/// Health checks whose subject is an indexer's failure state.
///
/// Excluded from Needs attention because the indexer-status rows already say
/// the same thing with the indexer's own name on it; left in, every failing
/// indexer would appear twice: once by name and once as "Indexers unavailable
/// due to failures".
const Set<String> prowlarrIndexerStatusChecks = {
  'IndexerStatusCheck',
  'IndexerLongTermStatusCheck',
};

/// One row of the Prowlarr Overview.
@immutable
class ProwlarrOverviewRow {
  const ProwlarrOverviewRow({
    required this.headline,
    required this.detail,
    required this.tone,
    this.trailing,
    this.indexerId,
  });

  /// `Nyaa`, `Dune.Part.Three.2026.2160p · grabbed`.
  final String headline;

  /// `torrent · private · 380 ms`, `failed · disabled until 15:40`.
  final String detail;

  final StatusTone tone;

  /// The right-hand figure on an indexer row: `298 queries`, or `—` for an
  /// indexer the stats window has no sample for.
  final String? trailing;

  /// The indexer this row is about, where it is about one.
  final int? indexerId;

  /// The row as one sentence, with the layout's `·` turned back into commas.
  String get spoken => joinSpokenParts([
    spokenFromDotted(headline),
    spokenFromDotted(detail),
    trailing,
  ]);
}

/// A section's preview rows and the count they were cut from.
typedef ProwlarrOverviewSection = ({List<ProwlarrOverviewRow> rows, int total});

/// What an unmeasured figure prints. An em dash, never `0`.
const String prowlarrNoSample = '—';

// ─── Needs attention ────────────────────────────────────────────────────────

/// `disabled until 15:40` while the block is in force, `retrying now` after.
///
/// The boundary is `isAfter(now)`, so a `disabledTill` that has just elapsed
/// reads as retrying rather than as a block with a time in the past, which is
/// how a stale row ends up claiming an indexer is disabled when Prowlarr has
/// already gone back to it.
String? prowlarrDisabledLabel(String? disabledTill, {required DateTime now}) {
  final until = _parseLocal(disabledTill);
  if (until == null) return null;
  if (!until.isAfter(now.toLocal())) return 'retrying now';
  final hour = until.hour.toString().padLeft(2, '0');
  final minute = until.minute.toString().padLeft(2, '0');
  return 'disabled until $hour:$minute';
}

/// The failing indexers, as rows.
///
/// **Amber, every one of them.** `indexerstatus` only ever returns indexers
/// with an active problem, so the presence of a record *is* the fault; red is
/// not available here and is not wanted: it belongs to a Prowlarr that did not
/// answer this call at all.
List<ProwlarrOverviewRow> prowlarrIndexerFaultRows(
  List<ProwlarrIndexerStatus> statuses,
  List<ProwlarrIndexer> indexers, {
  required DateTime now,
}) {
  final names = {
    for (final indexer in indexers)
      indexer.id: indexer.name ?? indexer.definitionName,
  };

  return List.unmodifiable([
    for (final status in statuses)
      ProwlarrOverviewRow(
        headline: names[status.indexerId]?.trim().isNotEmpty == true
            ? names[status.indexerId]!.trim()
            : 'Indexer ${status.indexerId}',
        detail: joinDisplayParts([
          'failing',
          prowlarrDisabledLabel(status.disabledTill, now: now),
          _lastFailure(status, now: now),
        ]),
        tone: StatusTone.warning,
        indexerId: status.indexerId,
      ),
  ]);
}

String? _lastFailure(ProwlarrIndexerStatus status, {required DateTime now}) {
  final last = _parseLocal(status.mostRecentFailure);
  if (last == null) return null;
  return 'last failed ${formatRelativeDateTime(last, now: now)}';
}

/// The health issues that are not already said by an indexer fault row.
///
/// Amber for the same reason: a health check is Prowlarr reporting a condition
/// it found, not Prowlarr being unreachable.
List<ProwlarrOverviewRow> prowlarrHealthRows(
  List<ProwlarrHealthIssue> issues,
) => List.unmodifiable([
  for (final issue in issues)
    if (!prowlarrIndexerStatusChecks.contains(issue.source))
      ProwlarrOverviewRow(
        headline: issue.source?.trim().isNotEmpty == true
            ? issue.source!.trim()
            : 'Health check',
        detail: issue.message?.trim() ?? '',
        tone: StatusTone.warning,
      ),
]);

/// Faults first, then the health checks that say something else.
ProwlarrOverviewSection prowlarrNeedsAttention(
  List<ProwlarrIndexerStatus> statuses,
  List<ProwlarrIndexer> indexers,
  List<ProwlarrHealthIssue> issues, {
  required DateTime now,
}) {
  final rows = <ProwlarrOverviewRow>[
    ...prowlarrIndexerFaultRows(statuses, indexers, now: now),
    ...prowlarrHealthRows(issues),
  ];
  return (rows: List.unmodifiable(rows), total: rows.length);
}

// ─── The indexer table ──────────────────────────────────────────────────────

/// `torrent · private · 380 ms`.
///
/// The response time reads `—` rather than `0 ms` when the window holds no
/// sample for this indexer: nobody measured it, which is not the same as it
/// answering instantly.
String prowlarrIndexerDetail(
  ProwlarrIndexer indexer,
  ProwlarrIndexerStat? stat, {
  bool failing = false,
}) => joinDisplayParts([
  indexer.protocol,
  indexer.privacy,
  if (failing)
    'failing'
  else if (!indexer.enable)
    // Deliberately disabled is a choice, so it is stated rather than flagged.
    'disabled'
  else
    null,
  stat == null || stat.numberOfQueries == 0
      ? prowlarrNoSample
      : withUnit(stat.averageResponseTime, 'ms'),
]);

/// The indexer table, ordered by the window's query count, busiest first.
///
/// Sorted by queries because that is what the board says it is sorted by, and a
/// table whose header claims an order it does not keep is a lie the eye checks
/// first.
ProwlarrOverviewSection prowlarrIndexerRows(
  List<ProwlarrIndexer> indexers,
  ProwlarrIndexerStats stats,
  List<ProwlarrIndexerStatus> statuses, {
  int limit = prowlarrIndexerPreviewLimit,
}) {
  final byId = {for (final stat in stats.indexers) stat.indexerId: stat};
  final failing = {for (final status in statuses) status.indexerId};

  final ordered = List<ProwlarrIndexer>.of(indexers)
    ..sort((a, b) {
      final queriesA = byId[a.id]?.numberOfQueries ?? 0;
      final queriesB = byId[b.id]?.numberOfQueries ?? 0;
      if (queriesA != queriesB) return queriesB.compareTo(queriesA);
      return (a.name ?? '').toLowerCase().compareTo(
        (b.name ?? '').toLowerCase(),
      );
    });

  return (
    rows: List.unmodifiable([
      for (final indexer in ordered.take(limit))
        ProwlarrOverviewRow(
          headline: indexer.name?.trim().isNotEmpty == true
              ? indexer.name!.trim()
              : indexer.displayImplementation,
          detail: prowlarrIndexerDetail(
            indexer,
            byId[indexer.id],
            failing: failing.contains(indexer.id),
          ),
          // Amber only for an indexer Prowlarr has actually flagged; the rest
          // of the table is an inventory, not a status board.
          tone: failing.contains(indexer.id)
              ? StatusTone.warning
              : StatusTone.neutral,
          trailing: byId[indexer.id] == null
              ? prowlarrNoSample
              : '${byId[indexer.id]!.numberOfQueries} queries',
          indexerId: indexer.id,
        ),
    ]),
    total: indexers.length,
  );
}

// ─── Recent ─────────────────────────────────────────────────────────────────

/// The newest history records, as rows.
///
/// A refused query is amber and a grab is green: the same two arms
/// [prowlarrEventStyle] already walks, read here as tones so the row and the
/// badge cannot drift.
List<ProwlarrOverviewRow> prowlarrRecentRows(
  List<ProwlarrHistoryItem> records, {
  required DateTime now,
  int limit = prowlarrRecentPreviewLimit,
}) => List.unmodifiable([
  for (final item in records.take(limit))
    ProwlarrOverviewRow(
      headline: joinDisplayParts([
        prowlarrHistoryTitle(item),
        prowlarrEventLabel(item),
      ]),
      detail: joinDisplayParts([
        prowlarrHistorySource(item),
        _when(item.date, now: now),
      ]),
      tone: prowlarrEventTone(item),
      indexerId: item.indexerId,
    ),
]);

/// `grabbed`, `query`, `query failed`.
String prowlarrEventLabel(ProwlarrHistoryItem item) {
  final verb = switch (item.eventType) {
    'releaseGrabbed' => 'grabbed',
    'indexerQuery' => 'query',
    'indexerRss' => 'RSS sync',
    'indexerAuth' => 'auth',
    _ => (item.eventType ?? 'event'),
  };
  return item.successful ? verb : '$verb failed';
}

/// Green complete, amber fault, blue informational; never red.
StatusTone prowlarrEventTone(ProwlarrHistoryItem item) {
  // Amber, and this is the rule the whole service follows: a refused query is a
  // fault the indexer reported. Red is kept for a Prowlarr that did not answer.
  if (!item.successful) return StatusTone.warning;
  return switch (item.eventType) {
    'releaseGrabbed' => StatusTone.success,
    'indexerAuth' => StatusTone.info,
    _ => StatusTone.neutral,
  };
}

String? _when(String? iso, {required DateTime now}) {
  final date = _parseLocal(iso);
  return date == null ? null : formatRelativeDateTime(date, now: now);
}

/// Parses a Prowlarr ISO timestamp into local time, or null when it is absent
/// or unreadable.
///
/// Local, always: every label on this page is read against a local wall clock,
/// and Prowlarr answers in UTC.
DateTime? _parseLocal(String? raw) {
  final value = raw?.trim();
  if (value == null || value.isEmpty) return null;
  return DateTime.tryParse(value)?.toLocal();
}

// ─── Providers ──────────────────────────────────────────────────────────────

/// The Overview's first region: what is broken.
final prowlarrOverviewAttentionProvider =
    FutureProvider.autoDispose<ProwlarrOverviewSection>((ref) async {
      final statuses = await ref.watch(prowlarrIndexerStatusProvider.future);
      final indexers = await ref.watch(prowlarrIndexersProvider.future);
      final health = await ref.watch(prowlarrHealthProvider.future);
      return prowlarrNeedsAttention(
        statuses,
        indexers,
        health,
        now: DateTime.now(),
      );
    }, retry: noProviderRetry);

/// The Overview's second region: the indexer table over
/// [prowlarrStatsWindow].
final prowlarrOverviewIndexersProvider =
    FutureProvider.autoDispose<ProwlarrOverviewSection>((ref) async {
      final indexers = await ref.watch(prowlarrIndexersProvider.future);
      final stats = await ref.watch(prowlarrIndexerStatsProvider.future);
      final statuses = await ref.watch(prowlarrIndexerStatusProvider.future);
      return prowlarrIndexerRows(indexers, stats, statuses);
    }, retry: noProviderRetry);

/// The Overview's third region: what happened lately.
final prowlarrOverviewRecentProvider =
    FutureProvider.autoDispose<List<ProwlarrOverviewRow>>((ref) async {
      final page = await ref.watch(prowlarrRecentHistoryProvider.future);
      return prowlarrRecentRows(page.records, now: DateTime.now());
    }, retry: noProviderRetry);
