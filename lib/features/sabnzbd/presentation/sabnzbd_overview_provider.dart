/// What the SABnzbd Overview reads, and the pure functions that shape it.
///
/// SABnzbd answers one endpoint per question and this page asks only two of
/// them: `mode=queue`, shared with the readout band through
/// [sabnzbdQueueProvider] so the rail and the rows cannot disagree about the
/// same queue, and `mode=history` through [sabnzbdOverviewHistoryPageProvider],
/// which this page asks for itself.
///
/// The history page is its own request, and deliberately not
/// [sabnzbdHistoryProvider]'s: that one takes the client's default twenty
/// records, and this section states counts *for the day*. Twenty records is
/// half a lunchtime on a busy usenet box, and a count taken inside a page that
/// short is the size of the page wearing the name of the day. See
/// [sabnzbdHistoryPageSize].
///
/// Four rules govern the whole file, and they are the reason it exists as
/// functions rather than as expressions inside `build`:
///
///  * **The tone rule, on SABnzbd's own status words.** A *paused* job is the
///    user's decision and therefore neutral; a *failed* one is a fault and
///    therefore amber; *repairing* is par2 working, which is the same
///    post-processing run as unpacking and therefore blue. Collapsing them,
///    which the previous dashboard did with a single `slot.status` string,
///    puts "you pressed pause" in the same colour as "this download broke".
///  * **A count states its own window, or wears a `+`.** A figure computed
///    inside a page is a floor, not a total, and the header says which it is.
///  * **A figure nobody could compute reads an em dash, never `0`.** SABnzbd
///    keeps reporting `timeleft: 0:00:00` on a paused or idle queue; printed as
///    an ETA that is the single most misleading number this page could carry,
///    because `0 min` means "about to finish" and the truth is "there is no
///    estimate". [ServiceKpi.unavailable] exists for exactly that.
///  * **Every window takes an explicit `now`.** "Today" is a local calendar
///    day, and a boundary that can only be exercised by waiting for midnight is
///    a boundary nobody tests.
///
/// **What the board asks for and this client cannot answer** is absent rather
/// than stubbed, because a section that invents its rows is worse than a
/// section that is not there:
///
///  * **Servers**: needs `mode=status`, which carries the per-server
///    connection counts and the SSL flag. [SabnzbdClient] never calls it.
///  * **Warnings** ("Disk space low on /incomplete"): needs `mode=warnings`,
///    and the disk figures beside it need `diskspace1`/`diskspacetotal1`, which
///    `mode=queue` does return but [SabnzbdQueue] does not parse.
///  * **The speed limit under the speed readout** ("limit 60 · 80%"): needs
///    `speedlimit`/`speedlimit_abs` off the same unparsed queue payload.
///  * **Retry / Delete on a failed history row**: needs `mode=retry` and
///    `mode=history&name=delete`. The client has neither, and a button that
///    cannot do the thing it names is worse than no button.
///  * **"drag to reorder"**: needs a position write (`mode=switch`). The
///    client has none, so the promise is deleted rather than drawn dead.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/providers/provider_retry.dart';
import 'package:cupola/core/models/service_kpi.dart';
import 'package:cupola/core/status/lexicon.dart';
import 'package:cupola/core/status/media_status.dart';
import 'package:cupola/core/utils/arr_activity_display.dart';
import 'package:cupola/core/utils/byte_format.dart';
import 'package:cupola/core/utils/date_format.dart' show formatRelativeDateTime;
import 'package:cupola/core/utils/duration_format.dart';
import 'package:cupola/core/utils/percent_format.dart';
import 'package:cupola/core/utils/unit_space.dart';
import 'package:cupola/features/sabnzbd/domain/models/sabnzbd_models.dart';
import 'package:cupola/features/sabnzbd/presentation/sabnzbd_provider.dart';
import 'package:cupola/features/services/domain/services_semantics.dart';

/// Queue rows the section draws before the header's count is the only place
/// the rest are reported.
const int sabnzbdQueuePreviewLimit = 4;

/// History rows the section draws.
///
/// Four, one more than the \*arr Overviews take, because this section sorts
/// **failed first**: three rows on a day with two failures would leave room for
/// exactly one of the twelve things that went right.
const int sabnzbdHistoryTodayLimit = 4;

/// History records this page asks SABnzbd for.
///
/// A hundred, not the client's default twenty, because this section counts *a
/// day* and a count is only as true as the window it was taken in. Twenty
/// records is one season pack plus a film; past that the page stops covering
/// today and the counts become a floor, which the header then says with a `+`
/// rather than pretending otherwise (see [sabnzbdHistoryToday]).
///
/// A hundred is one request of a few tens of kilobytes and covers every day
/// this client will realistically see, and where it does not, the page says so
/// instead of quietly under-reporting.
const int sabnzbdHistoryPageSize = 100;

// ─── SABnzbd's status vocabulary, toned ─────────────────────────────────────

/// The five-arm tone rule applied to a SABnzbd status word.
///
/// SABnzbd uses one vocabulary for a queue slot and a history slot, so one
/// function serves both and the two sections cannot disagree about what
/// `Repairing` means.
///
///  * **amber: a fault.** `Failed`, the download giving up, and nothing else.
///    `Repairing` is **not** here: par2 rebuilding articles that arrived broken
///    is the recovery working, one stage of the same post-processing run as
///    `Verifying` and `Extracting`, and it ends in a completed download far
///    more often than not. Nothing has failed, stalled or stopped, and nobody
///    has to do anything, which is the definition of blue three lines down.
///    The tone is not cosmetic: [sabnzbdHistoryToday] counts every amber row as
///    a failure, so an amber `Repairing` invents a failure in the header and
///    pushes the real one down the list on the day there is one.
///  * **neutral: deliberate.** `Paused` is the user's own decision, and
///    `Deleted` is their decision one step further. Neither is damage, and
///    painting them amber is the single most common way the tone rule is
///    broken.
///  * **blue: in flight.** `Queued`, `Downloading`, `Fetching`, `Grabbing`,
///    and the post-processing run (`Repairing`, `Extracting`, `Verifying`,
///    `Moving`, `Running`, `Propagating`, `Checking`) are all informational:
///    work is happening and nobody has to do anything.
///  * **green: complete.** `Completed`, and nothing else.
///
/// Red is deliberately unreachable from here. Red means the *service* did not
/// answer, which is the unreachable band's job for the page as a whole; never
/// a row's.
StatusTone sabnzbdStatusTone(String status) {
  return switch (status.trim().toLowerCase()) {
    'failed' => StatusTone.warning,
    'paused' => StatusTone.neutral,
    'deleted' => StatusTone.neutral,
    'completed' => StatusTone.success,
    'queued' ||
    'grabbing' ||
    'fetching' ||
    'downloading' ||
    'repairing' ||
    'extracting' ||
    'verifying' ||
    'moving' ||
    'running' ||
    'propagating' ||
    'checking' => StatusTone.info,
    // An unknown word is reported as-is and left uncoloured: SABnzbd adds
    // states between releases, and guessing a tone for one is how a benign new
    // state arrives painted as a fault.
    _ => StatusTone.neutral,
  };
}

/// The status word as the page prints it: lower case, or `unknown` when
/// SABnzbd sent none.
///
/// Lower case because it sits in a dotted detail line beside other lower-case
/// facts (`downloading · 15.2 GB left · movies`), and a stray `Downloading`
/// there reads as the start of a new sentence. SABnzbd's `Paused` is the app's
/// `stopped`, as NZBGet's is: someone stopped the job on purpose.
String sabnzbdStatusLabel(String status) {
  final word = status.trim().toLowerCase();
  if (word.isEmpty) return 'unknown';
  return word == 'paused' ? StateWord.stopped.inline : word;
}

// ─── The ETA ────────────────────────────────────────────────────────────────

/// SABnzbd's `timeleft` as a [Duration], or null when there is no estimate.
///
/// The wire format is colon-separated and grows from the right: `12:30` is
/// twelve minutes, `0:12:30` twelve and a half, `1:04:00:00` a day and four
/// hours. Parsed from the right for that reason, rather than by assuming three
/// fields: a queue with more than a day left is precisely the one whose ETA
/// the user wants, and the three-field assumption reads it as 1 hour 4 minutes.
///
/// Null, not [Duration.zero], for `0:00:00`: SABnzbd reports that both for "a
/// second left" and for "nothing is downloading", and only the second is true
/// often enough to matter. A zero-length estimate is no estimate.
Duration? sabnzbdParseTimeLeft(String? raw) {
  final value = raw?.trim();
  if (value == null || value.isEmpty) return null;

  final parts = value.split(':');
  if (parts.length > 4) return null;

  var seconds = 0;
  var unit = 1;
  const units = [1, 60, 3600, 86400];
  for (var i = parts.length - 1; i >= 0; i--) {
    final part = int.tryParse(parts[i].trim());
    // One unparseable field poisons the whole string: a partially read duration
    // is a wrong number wearing the authority of a right one.
    if (part == null || part < 0) return null;
    seconds += part * units[unit - 1];
    unit++;
  }

  return seconds <= 0 ? null : Duration(seconds: seconds);
}

/// `< 1 min`, `7 min`, `2 h 5 min`, `1 d 4 h`. Null in, null out.
///
/// Two units at most, and never a bare `0`: an estimate is read at a glance to
/// decide whether to wait, and the seconds under an hour-long download are
/// noise that changes on every poll.
String? sabnzbdEtaLabel(Duration? remaining) {
  if (remaining == null || remaining <= Duration.zero) return null;

  if (remaining < const Duration(minutes: 1)) {
    return '< ${withUnit(1, 'min')}';
  }
  return formatTimeSpan(remaining);
}

/// The ETA readout, and the one figure on this page that is routinely absent.
///
/// Returns [ServiceKpi.unavailable] (an em dash) whenever SABnzbd cannot
/// stand behind an estimate, and names which of the three reasons it is:
///
///  * the queue is **paused**, so `timeleft` freezes at whatever it last was;
///  * **nothing is downloading**, so there is no rate to divide by;
///  * SABnzbd sent a zero or unreadable `timeleft`.
///
/// Never `0 min`. That would read as "about to finish" on a queue that is not
/// moving at all, which is the opposite of the truth and the exact reading the
/// user would act on.
ServiceKpi sabnzbdEtaKpi(SabnzbdQueue queue) {
  final label = sabnzbdEtaLabel(sabnzbdParseTimeLeft(queue.timeLeft));
  if (label != null && !queue.paused && queue.kbPerSec > 0) {
    return ServiceKpi(label: 'ETA', value: label, icon: Icons.schedule_rounded);
  }

  return ServiceKpi.unavailable(
    label: 'ETA',
    icon: Icons.schedule_rounded,
    note: queue.paused
        ? 'queue ${StateWord.stopped.inline}'
        : queue.slots.isEmpty
        ? 'nothing queued'
        : 'nothing downloading',
  );
}

/// The readout band: Speed, Queue, Left, ETA.
///
/// Four figures, like the board, but not the board's four. It draws **Disk
/// free** in the fourth slot, and the client never asks for it (see the library
/// note), so the slot carries the size still to fetch instead of a fabricated
/// terabyte count. `Left` is a figure SABnzbd actually answers, sits in the
/// same identity line on the board (`18.6 GB left`), and is what the fourth
/// tile was there to support: how much is still coming.
///
/// This page builds its own list rather than taking `serviceKpiProvider`'s,
/// which for SABnzbd is Down/Queue/Remaining/Status/Total. It has no ETA,
/// the readout the board gives the most prominent slot on the phone, and
/// adding one there means editing a file thirteen other services share. Folding
/// the two back together is worth doing once this batch lands; see the report.
///
/// A zero **is** printed for speed and for the queue size: the server answered
/// those, and `0 B/s` on a paused queue is a fact. The em-dash rule is about
/// figures nobody could compute, not about small ones.
List<ServiceKpi> sabnzbdOverviewReadouts(SabnzbdQueue queue) {
  return List.unmodifiable([
    ServiceKpi(
      label: 'Speed',
      value: queue.speedLabel,
      icon: Icons.south_rounded,
      // Blue, and only while bytes are moving: activity is informational, and
      // a rate that is simply a rate wants no colour at all.
      tone: queue.kbPerSec > 0 ? StatusTone.info : null,
    ),
    ServiceKpi(
      label: 'Queue',
      // [SabnzbdQueue.jobCount], never the length of the page: the client asks
      // for fifty slots and a deeper queue would read as fifty jobs for as long
      // as it stayed deep.
      value: '${queue.jobCount}',
      icon: Icons.list_rounded,
      // Untoned on purpose, paused or not: a paused queue is the client obeying
      // an instruction, and the Queue section's own subtitle says so in words.
    ),
    ServiceKpi(
      label: 'Left',
      value: queue.sizeLeftLabel,
      icon: Icons.download_rounded,
    ),
    sabnzbdEtaKpi(queue),
  ]);
}

// ─── The queue ──────────────────────────────────────────────────────────────

/// One row of the Queue section: what is downloading, how far in, and in what
/// state.
@immutable
class SabnzbdQueueRow {
  const SabnzbdQueueRow({
    required this.name,
    required this.detail,
    required this.tone,
    required this.percentLabel,
  });

  /// The release, as SABnzbd names it.
  final String name;

  /// `downloading · 15.2 GB left of 40.1 GB · 2 min · movies`.
  final String detail;

  final StatusTone tone;

  /// `72%`. A percentage SABnzbd answered, so `0%` is printed as `0%`: it
  /// means "not started", which is exactly what a queued job is.
  final String percentLabel;

  /// Whether this row is a fault: failed, and only failed.
  ///
  /// Exposed here rather than compared against [StatusTone] at the call site,
  /// for the same reason [SabnzbdHistoryEntry.failed] is: the judgement of what
  /// counts as a fault is this file's, and a widget re-deriving it is a second
  /// place for the tone rule to drift.
  bool get isFault => tone == StatusTone.warning;

  /// The row as one sentence, with the layout's `·` turned back into commas.
  ///
  /// The percentage leads, because it is the thing a screen-reader user is
  /// scanning the section for, and it is the part the eye reads from the
  /// right-hand column without being told it is a percentage at all.
  String get spoken => joinSpokenParts([
    name,
    '$percentLabel downloaded',
    spokenFromDotted(detail),
  ]);
}

/// The Queue section: its rows, and the facts its header states.
typedef SabnzbdQueueSection = ({
  List<SabnzbdQueueRow> rows,
  int total,
  String sizeLeftLabel,
  bool paused,
});

/// The queue, in the order SABnzbd keeps it.
///
/// Not re-sorted. That order *is* the priority order the user set, so a preview
/// that sorted by progress or by state would show the top of a queue that does
/// not exist.
SabnzbdQueueSection sabnzbdQueuePreview(
  SabnzbdQueue queue, {
  int limit = sabnzbdQueuePreviewLimit,
}) {
  final rows = <SabnzbdQueueRow>[];
  for (final slot in queue.slots.take(limit)) {
    final eta = sabnzbdEtaLabel(sabnzbdParseTimeLeft(slot.timeLeft));
    rows.add(
      SabnzbdQueueRow(
        name: slot.filename,
        detail: joinDisplayParts([
          sabnzbdStatusLabel(slot.status),
          // `1.2 GB left of 3.4 GB`: the remainder *and* the job's own size,
          // because the remainder alone is the same sentence a third of the
          // way in as it is at the end. The total is dropped rather than
          // dashed when `mode=queue` sent none, for the reason the ETA below
          // is dropped: this section prints what the server stood behind.
          slot.sizeProgressLabel,
          // Absent rather than `—` when SABnzbd has no per-job estimate: a
          // queued job has no ETA to report and never claimed one, and a dash
          // in a dotted line reads as a value that failed to load.
          eta,
          slot.category.trim().isEmpty ? null : slot.category.trim(),
        ]),
        tone: sabnzbdStatusTone(slot.status),
        percentLabel: formatPercent(slot.percentage),
      ),
    );
  }

  return (
    rows: List.unmodifiable(rows),
    // The queue's own depth, which `mode=queue` states in `noofslots_total` and
    // [SabnzbdQueue.jobCount] reads: the header says "62 jobs" over four rows.
    // [sabnzbdQueueProvider] asks for the whole queue, so the page and the
    // queue are the same size today; reading the server's figure rather than
    // `slots.length` keeps the header honest for any caller that pages.
    total: queue.jobCount,
    sizeLeftLabel: queue.sizeLeftLabel,
    paused: queue.paused,
  );
}

/// The queue, shaped for the Overview.
///
/// Derived from [sabnzbdQueueProvider] rather than fetching again: the readout
/// band watches the same provider, and two calls to `mode=queue` a second apart
/// would let the rail and the rows disagree about the same queue.
final sabnzbdOverviewQueueProvider =
    FutureProvider.autoDispose<SabnzbdQueueSection>((ref) async {
      final queue = await ref.watch(sabnzbdQueueProvider.future);
      return sabnzbdQueuePreview(queue);
    }, retry: noProviderRetry);

// ─── History today ──────────────────────────────────────────────────────────

/// One finished job, resolved into the two lines the row draws.
@immutable
class SabnzbdHistoryEntry {
  const SabnzbdHistoryEntry({
    required this.name,
    required this.event,
    required this.tone,
    required this.detail,
    required this.completed,
  });

  /// The release.
  final String name;

  /// What became of it, in SABnzbd's own word: `completed`, `failed`,
  /// `extracting`.
  final String event;

  final StatusTone tone;

  /// `missing 14 articles · 1 hour ago`, or `1.4 GB · 2 h ago · tv`.
  final String detail;

  final DateTime completed;

  /// Whether this is one of the rows the section lifts to the top.
  bool get failed => tone == StatusTone.warning;

  String get spoken => joinSpokenParts([name, event, spokenFromDotted(detail)]);
}

/// The History section: its rows, the counts its header states, and whether
/// those counts are the day or only a floor under it.
typedef SabnzbdHistorySection = ({
  List<SabnzbdHistoryEntry> rows,
  int completed,
  int failed,
  bool dayCovered,
});

/// Today's finished jobs, **failed first**, then newest first within each
/// group.
///
/// Failed first is the mobile board's instruction, and it is the whole reason
/// the section is worth its space: twelve successful imports are a log, and the
/// one that failed is a decision. Within a group the order is newest first,
/// because two failures are read as "what just broke" and "what broke before
/// that".
///
/// "Today" is the local calendar day of [now]. A job that finished at 23:50
/// yesterday is out even though it is twenty minutes old. The header says
/// `today`, and a heading is a promise. [completed] and [failed] count every
/// record in the window, not just the [limit] the section draws, so the header
/// can say `12 completed · 1 failed` over four rows without contradicting
/// itself.
///
/// **[dayCovered] is what makes those counts honest.** `mode=history` answers a
/// *page*, and a count taken inside a page is the day only when the page is
/// long enough to reach yesterday. Two things prove it did, and either is
/// enough:
///
///  * the server returned fewer records than [pageSize]: it had no more to
///    give, so everything that ever finished is in hand; or
///  * at least one record is older than today: the page crossed midnight, so
///    every one of today's is above it.
///
/// When neither holds, the counts are a **floor**: there are at least this many
/// completions today and possibly a failure that fell off the end of the page,
/// which matters more here than anywhere else because this section sorts failed
/// first and a failure it never received cannot be lifted. The header then
/// prints `100+ completed` rather than a total it cannot stand behind, and the
/// honest answer to seeing that every day is a larger [pageSize].
///
/// A slot whose `completed` timestamp is missing or unreadable is dropped
/// rather than assumed to be recent: the section claims to be about today, and
/// a record with no time cannot honour that claim in either direction. Such a
/// slot proves nothing about the window either: it is counted against
/// [pageSize] and never as a record from before today.
SabnzbdHistorySection sabnzbdHistoryToday(
  List<SabnzbdHistorySlot> slots, {
  required DateTime now,
  int limit = sabnzbdHistoryTodayLimit,
  int pageSize = sabnzbdHistoryPageSize,
}) {
  final local = now.toLocal();
  final startOfDay = DateTime(local.year, local.month, local.day);
  final entries = <SabnzbdHistoryEntry>[];
  var completed = 0;
  var failed = 0;
  // Set by the first record from before today: proof that the page reached back
  // past midnight and therefore holds every one of today's.
  var reachedYesterday = false;

  for (final slot in slots) {
    final when = slot.completed?.toLocal();
    if (when == null) continue;
    if (when.isBefore(startOfDay)) {
      reachedYesterday = true;
      continue;
    }
    if (when.year != local.year ||
        when.month != local.month ||
        when.day != local.day) {
      // Later than today: a clock skew, not a window boundary, and it proves
      // nothing about how far back the page goes.
      continue;
    }

    final tone = sabnzbdStatusTone(slot.status);
    final isFailure = tone == StatusTone.warning;
    if (isFailure) {
      failed++;
    } else {
      // Everything that is not a fault counts as work that got done: a job
      // still unpacking at the moment of the poll is on its way to completed,
      // and a second count for "in post-processing" would be a third number in
      // a header that has room for two.
      completed++;
    }

    entries.add(
      SabnzbdHistoryEntry(
        name: slot.name,
        event: sabnzbdStatusLabel(slot.status),
        tone: tone,
        detail: joinDisplayParts([
          // The server's own reason, where it gave one. It is the most useful
          // string on a failed row and the board leads with it.
          slot.failMessage?.trim(),
          slot.bytes > 0 ? formatBytes(slot.bytes) : null,
          formatRelativeDateTime(when, now: now),
          slot.category.trim().isEmpty ? null : slot.category.trim(),
        ]),
        completed: when,
      ),
    );
  }

  entries.sort((a, b) {
    // Faults above everything, then newest first inside each group.
    if (a.failed != b.failed) return a.failed ? -1 : 1;
    return b.completed.compareTo(a.completed);
  });

  return (
    rows: List.unmodifiable(entries.take(limit)),
    completed: completed,
    failed: failed,
    dayCovered: reachedYesterday || slots.length < pageSize,
  );
}

/// The history page this section counts over.
///
/// Its own request, at [sabnzbdHistoryPageSize] rather than the twenty
/// [sabnzbdHistoryProvider] takes, because this section states counts for a day
/// and a day does not fit in twenty records. Neither provider declares a
/// `noProviderRetry`, and the derivation below carries it too.
final sabnzbdOverviewHistoryPageProvider =
    FutureProvider.autoDispose<List<SabnzbdHistorySlot>>((ref) async {
      return ref
          .watch(sabnzbdClientProvider)
          .getHistory(limit: sabnzbdHistoryPageSize);
    }, retry: noProviderRetry);

/// Today's history, and whether that page was long enough to be the day.
final sabnzbdOverviewHistoryProvider =
    FutureProvider.autoDispose<SabnzbdHistorySection>((ref) async {
      final slots = await ref.watch(sabnzbdOverviewHistoryPageProvider.future);
      return sabnzbdHistoryToday(
        slots,
        now: DateTime.now(),
        // The size actually asked for, so the window rule reasons about the
        // request that happened rather than about a default it assumed.
        pageSize: sabnzbdHistoryPageSize,
      );
    }, retry: noProviderRetry);
