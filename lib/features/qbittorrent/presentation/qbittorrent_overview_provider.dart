/// What the qBittorrent Overview reads, and the pure functions that shape it.
///
/// Everything on this page is derived from **two** calls the app already makes:
/// `/api/v2/torrents/info` through [allTorrentsProvider], which the Queue tab
/// and the KPI rail both already hold, and `/api/v2/transfer/info` through
/// [transferInfoProvider]. Nothing here fetches on its own, so opening Overview
/// costs no round trip that the service home was not already paying for.
///
/// Every windowing and folding rule lives in a top-level pure function taking an
/// explicit `now` where it needs a clock, so the boundaries are unit-testable
/// without a container and without waiting for one.
///
/// ## The sentinel rule, which is how this client lies when it is broken
///
/// `lib/features/qbittorrent/AGENTS.md` is the contract: qB's WebUI answers with
/// non-null sentinels for "never", "no limit" and "not set", and a sentinel read
/// as a number is a printed falsehood rather than a crash. Two of them bite on
/// this page specifically:
///
///  * `last_activity` is `0` for a torrent qB has never seen move. Subtracting
///    that from `now` yields "stalled 20,761 days", so [qbittorrentIdleLabel]
///    answers null and the row simply omits the clause.
///  * the **global** rate limits in `/transfer/info` use `0` for *unlimited*,
///    which is the opposite of the **per-torrent** `dl_limit`/`up_limit`, where
///    `0` means "limit cleared" and `-1` means unlimited. Reaching for the
///    existing [formatLimit] here would print a bare `0` over an uncapped
///    gigabit link. [qbittorrentGlobalLimitLabel] exists for exactly that gap.
///
/// The rule has a second edge, and this page has been on the wrong side of it:
/// a sentinel helper applied to a field that has no sentinel prints "we could
/// not ask" over an answer that arrived. `/transfer/info`'s session counters
/// are plain counters: `0` is a fresh daemon, not a missing figure, so they
/// go through [qbittorrentSessionTotalLabel] and never through `formatSize`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/providers/provider_retry.dart';
import 'package:cupola/core/status/lexicon.dart';
import 'package:cupola/core/status/media_status.dart';
import 'package:cupola/core/utils/arr_activity_display.dart';
import 'package:cupola/core/utils/byte_format.dart';
import 'package:cupola/core/utils/percent_format.dart';
import 'package:cupola/core/utils/unit_space.dart';
import 'package:cupola/features/qbittorrent/domain/models/parse_utils.dart';
import 'package:cupola/features/qbittorrent/domain/models/torrent.dart';
import 'package:cupola/features/qbittorrent/domain/models/transfer_info.dart';
import 'package:cupola/features/qbittorrent/presentation/qbittorrent_provider.dart';
import 'package:cupola/features/services/domain/services_semantics.dart';

/// Fault rows the Needs attention section draws before the count in its header
/// is the only place the rest are reported.
const int qbittorrentAttentionLimit = 4;

/// Rows in the Queue preview.
const int qbittorrentTransferPreviewLimit = 5;

/// Rows in the Categories section.
///
/// Five, because past that the section stops being a shape of the library and
/// becomes the library, which is what the Queue tab is for.
const int qbittorrentCategoryLimit = 5;

/// What a torrent with no category is filed under.
///
/// Included rather than dropped, and that is the point: the section header
/// prints a total, and a total that silently excludes the uncategorised
/// torrents disagrees with the one the Queue tab shows two taps away.
const String qbittorrentNoCategoryLabel = 'No category';

// ─── Needs attention ────────────────────────────────────────────────────────

/// The three conditions this page treats as needing a decision.
///
/// All three are **amber**, and none of them is red: red is reserved for a
/// qBittorrent that did not answer at all, which the unreachable band says once
/// for the whole page. A torrent that failed is a fault on a server that is
/// plainly alive: it answered to tell us.
///
/// What is deliberately **not** here is a torrent the user stopped. qB reports
/// it as `pausedDL`/`stoppedUP`, and painting that amber is the single most
/// common way the five-arm tone rule gets broken: a deliberate pause is
/// **backlog**, it is neutral, and the user does not need to be told they did
/// the thing they did. It is counted in [QbittorrentQueueCounts.paused] and
/// reported as a plain figure.
///
/// **The declaration order is load-bearing**: [qbittorrentFaultRows] sorts on
/// it, worst first. A torrent qB has given up on will not recover by itself; a
/// stalled one may find a seed in the next ten minutes, so it reads last.
enum QbittorrentFaultKind {
  /// `error`: libtorrent gave up on it and said so.
  errored(Icons.error_outline_rounded),

  /// `missingFiles`: the data qB is seeding is no longer where it left it.
  /// Split from [errored] because the thing to go and fix is a filesystem, not
  /// the torrent.
  missingFiles(Icons.folder_off_rounded),

  /// `stalledDL`: connected, not moving. The user did not ask for this.
  stalled(Icons.sync_problem_rounded);

  const QbittorrentFaultKind(this.icon);

  final IconData icon;

  /// Amber for all three. See the enum's own doc for why there is no red arm.
  StatusTone get tone => StatusTone.warning;
}

/// One row of Needs attention: what broke, on what, and the evidence.
@immutable
class QbittorrentAttentionItem {
  const QbittorrentAttentionItem({
    required this.kind,
    required this.headline,
    required this.detail,
  });

  final QbittorrentFaultKind kind;

  /// The fault and its subject: `Stalled · The.Zone.of.Interest…`.
  final String headline;

  /// The evidence: how far it got, how long it has been idle, how many seeds
  /// it can see. Empty when the record carried none of them.
  final String detail;

  StatusTone get tone => kind.tone;
  IconData get icon => kind.icon;

  /// The row as one sentence, with the layout's `·` turned back into commas:
  /// `·` is decoration, and a screen reader either names it or drops it
  /// depending on the user's punctuation setting.
  String get spoken =>
      joinSpokenParts([spokenFromDotted(headline), spokenFromDotted(detail)]);
}

/// How long a torrent has been idle, or null when that cannot be said.
///
/// Null in three cases, and each one is a figure this page refuses to invent:
///
///  * `lastActivity <= 0` is qB's "never seen it move" sentinel: printing the
///    epoch difference would claim the torrent stalled in 1970;
///  * a timestamp in the future is a clock skew between phone and server, and
///    a negative age rendered as "stalled -3 min" is worse than silence;
///  * under a minute is not an idle period, it is the gap between two polls.
///
/// Whole minutes up to an hour, then whole hours, then days: the same ladder
/// [formatRelativeDateTime] walks, without its "ago", because this is a
/// duration and not a point in time.
String? qbittorrentIdleLabel(int lastActivity, {required DateTime now}) {
  if (lastActivity <= 0) return null;
  final since = DateTime.fromMillisecondsSinceEpoch(
    lastActivity * 1000,
  ).toLocal();
  final delta = now.toLocal().difference(since);
  if (delta.isNegative || delta < const Duration(minutes: 1)) return null;
  if (delta < const Duration(hours: 1)) {
    return withUnit(delta.inMinutes, 'min');
  }
  if (delta < const Duration(days: 1)) return withUnit(delta.inHours, 'h');
  final days = delta.inDays;
  return days == 1 ? '1 day' : '$days days';
}

/// `92%`: the progress fraction as whole percent.
///
/// Whole percent rather than [Torrent.progressFormatted]'s `92.0%`: the tenth
/// is noise beside a name that is already being ellipsised, and it is the
/// spelling the board draws.
///
/// The shared rule of `percent_format.dart`: nearest, and a torrent at 99.6%
/// does not read `100%` while it is still copying. `100%` is a claim the user
/// acts on.
String qbittorrentPercentLabel(double progress) {
  final clamped = progress.clamp(0.0, 1.0);
  return formatPercent(clamped * 100);
}

/// Which faults a torrent is in, or null when it is not in one.
QbittorrentFaultKind? qbittorrentFaultKindOf(Torrent torrent) {
  // The raw state string, not `parsedState`: the model folds `error` and
  // `missingFiles` into one [TorrentState.error], and those two send the user
  // to two different places.
  if (torrent.state == 'missingFiles') return QbittorrentFaultKind.missingFiles;
  if (torrent.parsedState == TorrentState.error) {
    return QbittorrentFaultKind.errored;
  }
  if (torrent.parsedState == TorrentState.stalled) {
    return QbittorrentFaultKind.stalled;
  }
  return null;
}

/// The faults in the torrent list, worst-evidence first, capped at [limit].
///
/// Ordered errored → missing files → stalled, and within a kind by how long the
/// thing has been wrong: a torrent that died an hour ago has had longer to
/// matter than one that died during this poll.
///
/// A deliberately stopped torrent never appears here at any position: see
/// [QbittorrentFaultKind].
List<QbittorrentAttentionItem> qbittorrentFaultRows(
  List<Torrent> torrents, {
  required DateTime now,
  int limit = qbittorrentAttentionLimit,
}) {
  final faults = <(QbittorrentFaultKind, Torrent)>[];
  for (final torrent in torrents) {
    final kind = qbittorrentFaultKindOf(torrent);
    if (kind != null) faults.add((kind, torrent));
  }

  faults.sort((a, b) {
    final byKind = a.$1.index.compareTo(b.$1.index);
    if (byKind != 0) return byKind;
    // Oldest activity first. A `0` sentinel sorts as "never moved", which is
    // the most stale thing there is, so it leads its kind.
    final aSeen = a.$2.lastActivity <= 0 ? 0 : a.$2.lastActivity;
    final bSeen = b.$2.lastActivity <= 0 ? 0 : b.$2.lastActivity;
    final bySeen = aSeen.compareTo(bSeen);
    return bySeen != 0 ? bySeen : a.$2.name.compareTo(b.$2.name);
  });

  return List.unmodifiable(
    faults.take(limit).map((entry) {
      final (kind, torrent) = entry;
      final idle = qbittorrentIdleLabel(torrent.lastActivity, now: now);
      return QbittorrentAttentionItem(
        kind: kind,
        headline: switch (kind) {
          QbittorrentFaultKind.stalled =>
            '${StateWord.stuck.label} · ${torrent.name}',
          QbittorrentFaultKind.missingFiles =>
            'Missing files · ${torrent.name}',
          QbittorrentFaultKind.errored => 'Errored · ${torrent.name}',
        },
        detail: switch (kind) {
          // A stalled transfer's evidence is how far it got, how long it has
          // been still, and whether anyone is left to talk to.
          QbittorrentFaultKind.stalled => joinDisplayParts([
            qbittorrentPercentLabel(torrent.progress),
            idle == null ? null : 'idle $idle',
            torrent.seeders > 0
                ? '${torrent.seeders} ${torrent.seeders == 1 ? 'seed' : 'seeds'}'
                // Zero seeds is the *reason* it is stalled and a genuinely
                // fetched figure, so it is stated rather than dropped.
                : 'no seeds',
          ]),
          // For the other two the transfer is beside the point: what the user
          // needs is which torrent and where its data was meant to be.
          QbittorrentFaultKind.missingFiles => joinDisplayParts([
            'qBittorrent cannot find the files',
            torrent.category.isEmpty ? null : torrent.category,
          ]),
          QbittorrentFaultKind.errored => joinDisplayParts([
            qbittorrentPercentLabel(torrent.progress),
            torrent.category.isEmpty ? null : torrent.category,
            idle == null ? null : 'idle $idle',
          ]),
        },
      );
    }),
  );
}

// ─── Queue ──────────────────────────────────────────────────────────────────

/// One row of the Queue preview: a transfer that is actually moving.
@immutable
class QbittorrentTransferRow {
  const QbittorrentTransferRow({
    required this.name,
    required this.percent,
    required this.detail,
    required this.isSeeding,
  });

  final String name;

  /// `92%`, already rendered: it is the row's trailing figure.
  final String percent;

  /// Category, size, rate and (downloading only) what is left.
  final String detail;

  /// Seeding rows are *complete*, which is the success arm of the tone rule;
  /// downloading rows are in flight, which is the informational one.
  final bool isSeeding;

  /// Green for a finished thing still giving back, blue for one in flight.
  /// Neither is amber: nothing on this row is wrong.
  StatusTone get tone => isSeeding ? StatusTone.success : StatusTone.info;

  String get spoken =>
      joinSpokenParts([name, percent, spokenFromDotted(detail)]);
}

/// The transfers worth a row, downloading before seeding, capped at [limit].
///
/// Downloading first and by progress descending, which is the board's order and
/// also the useful one: the thing about to land is the thing worth looking at.
/// Seeding follows, ordered by upload rate: a seed nobody is pulling from is
/// the least interesting row on the page.
///
/// Faults are **absent by construction**: `stalledDL`, `error` and
/// `missingFiles` all fail the active test, so nothing appears both here and in
/// Needs attention above. Paused and queued torrents are absent too; they are
/// backlog, they are reported as counts, and a queue preview is a list of what
/// is happening rather than of what exists.
List<QbittorrentTransferRow> qbittorrentTransferRows(
  List<Torrent> torrents, {
  int limit = qbittorrentTransferPreviewLimit,
}) {
  final active = torrents
      .where((t) => t.parsedState.isActive)
      .toList(growable: false);

  int rank(Torrent t) => t.parsedState == TorrentState.seeding ? 1 : 0;
  final sorted = [...active]
    ..sort((a, b) {
      final byRank = rank(a).compareTo(rank(b));
      if (byRank != 0) return byRank;
      if (rank(a) == 1) {
        final bySpeed = b.upSpeed.compareTo(a.upSpeed);
        if (bySpeed != 0) return bySpeed;
      } else {
        final byProgress = b.progress.compareTo(a.progress);
        if (byProgress != 0) return byProgress;
      }
      return a.name.compareTo(b.name);
    });

  return List.unmodifiable(
    sorted.take(limit).map((torrent) {
      final seeding = torrent.parsedState == TorrentState.seeding;
      // `etaFormatted` renders qB's "practically never" sentinel as `∞`, which
      // a screen reader calls "infinity" in the middle of a sentence about a
      // download. The glyph is dropped and the clause with it: an unknowable
      // ETA is better left unsaid than rendered as a symbol.
      final eta = torrent.etaFormatted;
      return QbittorrentTransferRow(
        name: torrent.name,
        percent: qbittorrentPercentLabel(torrent.progress),
        isSeeding: seeding,
        detail: joinDisplayParts([
          torrent.category.isEmpty ? null : torrent.category,
          // `formatSize` answers `—` for qB's `0` size, which is what a magnet
          // with no metadata yet reports. That is the em-dash rule, not a bug.
          formatSize(torrent.size),
          seeding
              ? (torrent.upSpeed > 0
                    ? '${formatSpeed(torrent.upSpeed)} up'
                    : null)
              : (torrent.dlSpeed > 0
                    ? '${formatSpeed(torrent.dlSpeed)} down'
                    : null),
          seeding
              ? 'ratio ${torrent.ratio.toStringAsFixed(2)}'
              : (eta.isEmpty || eta == '∞' ? null : '$eta left'),
        ]),
      );
    }),
  );
}

/// The shape of the queue, as counts.
///
/// Each field is a plain census of the list qB answered with; none of them is a
/// fallback for a fetch that failed. When the list itself did not arrive the
/// section prints `—` rather than constructing one of these full of zeroes:
/// `0 torrents` and "we could not ask" are opposite readings and the user acts
/// differently on each.
@immutable
class QbittorrentQueueCounts {
  const QbittorrentQueueCounts({
    required this.total,
    required this.downloading,
    required this.seeding,
    required this.paused,
    required this.stalled,
    required this.errored,
  });

  final int total;
  final int downloading;
  final int seeding;

  /// Deliberately stopped. **Backlog, not a fault**: see
  /// [QbittorrentFaultKind].
  final int paused;

  final int stalled;

  /// `error` and `missingFiles` together: both are "this one is broken", and
  /// the header is counting, not triaging.
  final int errored;

  int get active => downloading + seeding;
  int get faults => stalled + errored;
}

/// Folds the torrent list into its census.
QbittorrentQueueCounts qbittorrentQueueCounts(List<Torrent> torrents) {
  var downloading = 0;
  var seeding = 0;
  var paused = 0;
  var stalled = 0;
  var errored = 0;

  for (final torrent in torrents) {
    switch (torrent.parsedState) {
      case TorrentState.downloading:
      case TorrentState.metaDownloading:
        downloading++;
      case TorrentState.seeding:
        seeding++;
      case TorrentState.paused:
        paused++;
      case TorrentState.stalled:
        stalled++;
      case TorrentState.error:
        errored++;
      case TorrentState.checking:
      case TorrentState.queuedUp:
      case TorrentState.queuedDl:
      case TorrentState.unknown:
        break;
    }
  }

  return QbittorrentQueueCounts(
    total: torrents.length,
    downloading: downloading,
    seeding: seeding,
    paused: paused,
    stalled: stalled,
    errored: errored,
  );
}

// ─── Categories ─────────────────────────────────────────────────────────────

/// One category, with how much of the library sits under it.
@immutable
class QbittorrentCategoryRow {
  const QbittorrentCategoryRow({
    required this.name,
    required this.count,
    required this.bytes,
  });

  final String name;
  final int count;

  /// Summed `size`, so `formatSize`'s `—` sentinel applies to the total too:
  /// a category made entirely of metadata-less magnets sums to zero, and zero
  /// bytes is "not known yet" in this API, not "empty".
  final int bytes;

  String get sizeLabel => formatSize(bytes);

  String get countLabel => count == 1 ? '1 torrent' : '$count torrents';

  String get spoken => joinSpokenParts([name, countLabel, sizeLabel]);
}

/// The categories present in the torrent list, largest first.
///
/// Derived from `/torrents/info` rather than fetched from
/// `/api/v2/torrents/categories`: the categories endpoint answers with the
/// *configured* categories and their save paths, and this section is about
/// where the library actually sits: a configured category holding nothing has
/// nothing to say on an Overview. The count and the size therefore always agree
/// with the Queue tab, because they are the same list folded twice.
///
/// Uncategorised torrents are collected under [qbittorrentNoCategoryLabel] and
/// pinned **last** whatever their size, because it is not a category: it is
/// the absence of one, and sorting it to the top would make the section look
/// like the user had named a category after the thing they had not done.
List<QbittorrentCategoryRow> qbittorrentCategoryRows(
  List<Torrent> torrents, {
  int limit = qbittorrentCategoryLimit,
}) {
  final counts = <String, int>{};
  final bytes = <String, int>{};
  for (final torrent in torrents) {
    final key = torrent.category.trim().isEmpty
        ? qbittorrentNoCategoryLabel
        : torrent.category.trim();
    counts[key] = (counts[key] ?? 0) + 1;
    // Guard the sentinel before summing: a `-1` or `0` size added into a total
    // would drag the whole category's figure the wrong way.
    bytes[key] = (bytes[key] ?? 0) + (torrent.size > 0 ? torrent.size : 0);
  }

  final rows =
      counts.entries
          .map(
            (entry) => QbittorrentCategoryRow(
              name: entry.key,
              count: entry.value,
              bytes: bytes[entry.key] ?? 0,
            ),
          )
          .toList()
        ..sort((a, b) {
          final aUncategorised = a.name == qbittorrentNoCategoryLabel;
          final bUncategorised = b.name == qbittorrentNoCategoryLabel;
          if (aUncategorised != bUncategorised) return aUncategorised ? 1 : -1;
          final bySize = b.bytes.compareTo(a.bytes);
          if (bySize != 0) return bySize;
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
        });

  return List.unmodifiable(rows.take(limit));
}

// ─── Session ────────────────────────────────────────────────────────────────

/// One label/value pair in the Session section.
@immutable
class QbittorrentSessionFact {
  const QbittorrentSessionFact({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;

  /// Already rendered, `—` included: the decision about whether a figure is
  /// knowable belongs to the function that had the sentinel in its hand, not to
  /// the widget three layers up that only has a string.
  final String value;

  final IconData icon;

  String get spoken => joinSpokenParts([label, value]);
}

/// The global rate limit, in qB's **global** sentinel vocabulary.
///
/// `0` means *no limit* for `/transfer/info`'s `dl_rate_limit` /
/// `up_rate_limit` and for `/transfer/setDownloadLimit`, which is the exact
/// inverse of the per-torrent `dl_limit` / `up_limit` that [formatLimit]
/// renders: there `0` is a cleared limit and `-1` is unlimited. Passing a
/// global limit through `formatLimit` prints a bare `0` on an uncapped link,
/// which reads as "throttled to nothing": the most misleading single character
/// this screen could draw. Negatives are folded in defensively; no qB version
/// is known to send one here.
String qbittorrentGlobalLimitLabel(int bytesPerSecond) =>
    bytesPerSecond <= 0 ? 'no limit' : formatSpeed(bytesPerSecond);

/// A session byte counter, where `0` is an answer.
///
/// **Not [formatSize].** That helper is qB's *torrent-size* sentinel wrapper:
/// `bytes <= 0 ? '—'`, and it is right there, because a magnet with no
/// metadata reports size `0` and "zero bytes" is not a size any torrent has.
/// `dl_info_data` / `up_info_data` are counters on `/transfer/info`: a daemon
/// restarted ten minutes ago that has not moved anything reports `0` and means
/// it. Rendering that as `—` would say `/transfer/info` had not answered while
/// five rows beside it prove it did: the page inverting its own rule, refusing
/// to print `0` for an unanswered question and then printing "unanswered" for a
/// genuine zero.
///
/// Negatives are folded to zero defensively; no qB version is known to send one
/// on these fields, and a counter that went backwards is still not an em dash.
String qbittorrentSessionTotalLabel(int bytes) =>
    formatBytes(bytes < 0 ? 0 : bytes);

/// `1.83`, or `—` when the ratio is not a number yet.
///
/// Undefined rather than zero when nothing has been downloaded this session:
/// dividing by zero gives `Infinity`, and rounding it to `0.00` would claim a
/// session that has uploaded 8 TB gave nothing back. `—` is the honest answer
/// to "what is x over nothing".
String qbittorrentSessionRatioLabel({
  required int downloaded,
  required int uploaded,
}) {
  if (downloaded <= 0) return '—';
  return (uploaded / downloaded).toStringAsFixed(2);
}

/// What `/transfer/info` can honestly say about the session.
///
/// Six facts and no more. The board's Session panel also asks for DHT nodes, the
/// listen port's reachability and free disk space; none of the three is on any
/// endpoint this client calls, so they are **absent rather than zeroed**: see
/// the screen's own doc for which call would be needed.
///
/// The two limits are the *effective* ones: when alternative limits are on, qB
/// reports the alternative figures in these fields, which is why the alt row
/// sits directly beneath them rather than somewhere else in the list.
List<QbittorrentSessionFact> qbittorrentSessionFacts(TransferInfo info) {
  return List.unmodifiable([
    QbittorrentSessionFact(
      label: 'Downloaded this session',
      value: qbittorrentSessionTotalLabel(info.dlInfoData),
      icon: Icons.south_rounded,
    ),
    QbittorrentSessionFact(
      label: 'Uploaded this session',
      value: qbittorrentSessionTotalLabel(info.upInfoData),
      icon: Icons.north_rounded,
    ),
    QbittorrentSessionFact(
      label: 'Session ratio',
      value: qbittorrentSessionRatioLabel(
        downloaded: info.dlInfoData,
        uploaded: info.upInfoData,
      ),
      icon: Icons.balance_rounded,
    ),
    QbittorrentSessionFact(
      label: 'Download limit',
      value: qbittorrentGlobalLimitLabel(info.dlRateLimit),
      icon: Icons.speed_rounded,
    ),
    QbittorrentSessionFact(
      label: 'Upload limit',
      value: qbittorrentGlobalLimitLabel(info.upRateLimit),
      icon: Icons.speed_rounded,
    ),
    QbittorrentSessionFact(
      label: 'Alternative limits',
      // A bool that arrived is a bool: on or off, never `—`. The whole object
      // is missing when `/transfer/info` did not answer, and the section says
      // so once for all six rows.
      value: info.altSpeedEnabled ? 'on' : 'off',
      icon: Icons.schedule_rounded,
    ),
  ]);
}

// ─── Providers ──────────────────────────────────────────────────────────────
//
// Every one of these derives from [allTorrentsProvider] or
// [transferInfoProvider], which fail on the first attempt; each carries
// `retry: noProviderRetry` too, or the derivation would quietly re-run the
// backoff the source refused and hold the section on its skeleton.

/// The faults, from the list the Queue tab and the KPI rail already hold.
///
/// Derived from [allTorrentsProvider] rather than fetching: `/torrents/info` is
/// one of the largest bodies this app pulls, and the Overview asking for its own
/// copy would double it on every refresh for a list it would fold identically.
final qbittorrentOverviewAttentionProvider =
    FutureProvider.autoDispose<List<QbittorrentAttentionItem>>((ref) async {
      final torrents = await ref.watch(allTorrentsProvider.future);
      return qbittorrentFaultRows(torrents, now: DateTime.now());
    }, retry: noProviderRetry);

/// The Queue preview.
final qbittorrentOverviewTransfersProvider =
    FutureProvider.autoDispose<List<QbittorrentTransferRow>>((ref) async {
      final torrents = await ref.watch(allTorrentsProvider.future);
      return qbittorrentTransferRows(torrents);
    }, retry: noProviderRetry);

/// The queue census behind the Queue header's subtitle.
final qbittorrentOverviewCountsProvider =
    FutureProvider.autoDispose<QbittorrentQueueCounts>((ref) async {
      final torrents = await ref.watch(allTorrentsProvider.future);
      return qbittorrentQueueCounts(torrents);
    }, retry: noProviderRetry);

/// The categories, largest first.
final qbittorrentOverviewCategoriesProvider =
    FutureProvider.autoDispose<List<QbittorrentCategoryRow>>((ref) async {
      final torrents = await ref.watch(allTorrentsProvider.future);
      return qbittorrentCategoryRows(torrents);
    }, retry: noProviderRetry);

/// How many distinct categories the library actually uses.
///
/// Counted over the *whole* list rather than over the capped rows, so a library
/// spread across nine categories says nine in its header while showing five.
final qbittorrentOverviewCategoryCountProvider =
    FutureProvider.autoDispose<int>((ref) async {
      final torrents = await ref.watch(allTorrentsProvider.future);
      return qbittorrentCategoryRows(
        torrents,
        limit: torrents.length + 1,
      ).length;
    }, retry: noProviderRetry);

/// The session facts, from `/transfer/info`.
final qbittorrentOverviewSessionProvider =
    FutureProvider.autoDispose<List<QbittorrentSessionFact>>((ref) async {
      final info = await ref.watch(transferInfoProvider.future);
      return qbittorrentSessionFacts(info);
    }, retry: noProviderRetry);
