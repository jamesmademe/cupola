/// What the NZBGet Overview reads, and the pure functions that shape it.
///
/// Everything here is derived from the three calls the client already makes:
/// `status`, `listgroups`, `history`, since the KPI rail on the same page
/// loads all three: a second fetch for the same figures would double the
/// traffic to a box that is usually a Raspberry Pi and still answer the same
/// numbers.
///
/// Every windowing and classification rule lives in a top-level pure function
/// taking an explicit `now`, so the boundaries are unit-testable without a
/// clock or a container.
///
/// **What the board asks for and this Overview does not serve**, named here
/// rather than duplicated, because a section that renders a lie is worse than
/// one that is missing:
///
///  * **Disk free**: NZBGet's `status` result carries `FreeDiskSpaceMB` /
///    `FreeDiskSpaceHi` / `FreeDiskSpaceLo`, but [NzbgetStatus] parses only the
///    rate, the remaining size and the paused flag, and `NzbgetClient` exposes
///    no raw accessor to reach past it.
///  * **The speed limit** ("no limit" under the Speed tile): same call, same
///    gap: `DownloadLimit` is dropped by the model. The client can *set* a rate
///    (`rate`) and cannot read the one in force.
///  * **Servers**: rendered on the dedicated Servers tab from the client
///    configuration response, not repeated in this Overview.
///  * **Feeds** and **Messages**: rendered on their dedicated tabs from the
///    corresponding NZBGet configuration/log reads.
///
///  * **Retry / Delete on a failed history row**: NZBGet does those through
///    `editqueue` with the `History*` command family, which `NzbgetClient`
///    never sends; its `editQueue` is public but the three wrappers over it are
///    all group commands. A button that cannot do the thing it names is worse
///    than no button, so the rows are read-only here.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/providers/provider_retry.dart';
import 'package:cupola/core/status/lexicon.dart';
import 'package:cupola/core/status/media_status.dart';
import 'package:cupola/core/utils/arr_activity_display.dart'
    show joinDisplayParts;
import 'package:cupola/core/utils/byte_format.dart';
import 'package:cupola/core/utils/duration_format.dart';
import 'package:cupola/core/utils/percent_format.dart';
import 'package:cupola/features/activity/presentation/widgets/activity_formatters.dart'
    show formatRelativeDateTime;
import 'package:cupola/features/nzbget/domain/models/nzbget_models.dart';
import 'package:cupola/features/nzbget/presentation/nzbget_provider.dart';
import 'package:cupola/features/services/domain/services_semantics.dart';

/// Rows the Queue section draws before the header's counts are the only place
/// the rest are reported.
const int nzbgetQueuePreviewLimit = 3;

/// Rows the History section draws.
const int nzbgetHistoryTodayLimit = 3;

// ─── Queue ──────────────────────────────────────────────────────────────────

/// What a queued NZB is doing, in the five-arm tone vocabulary.
///
/// NZBGet reports a dozen-odd `Status` strings and most of them are stages of
/// post-processing; this collapses them to the five states that differ in
/// *tone*, and [nzbgetGroupStageLabel] keeps the stage word for the eye.
///
/// Nothing here is amber. NZBGet's queue has no fault state; a job that broke
/// leaves the queue and lands in history as `FAILURE/*`, so painting any of
/// these amber would be the backlog mistake in its download-client form.
enum NzbgetGroupState {
  /// Bytes are moving. Blue: activity, not alarm.
  downloading(StatusTone.info, Icons.south_rounded),

  /// NZBGet is fetching the NZB file itself, before any article.
  fetching(StatusTone.info, Icons.cloud_download_rounded),

  /// Par-check, repair, unpack, move, script. Still work in progress.
  postProcessing(StatusTone.info, Icons.build_rounded),

  /// The user paused this job. Deliberate, therefore neutral: pausing is the
  /// client obeying, not a condition to fix.
  paused(StatusTone.neutral, Icons.pause_circle_outline_rounded),

  /// Waiting its turn.
  queued(StatusTone.info, Icons.schedule_rounded),

  /// A status this app has not met. Neutral rather than a guess, and
  /// [nzbgetGroupStageLabel] still prints NZBGet's own word for it.
  unknown(StatusTone.neutral, Icons.inventory_2_outlined);

  const NzbgetGroupState(this.tone, this.icon);

  final StatusTone tone;
  final IconData icon;
}

/// The post-processing stages, as NZBGet spells them in `listgroups`.
const Set<String> _postProcessingStatuses = {
  'PP_QUEUED',
  'LOADING_PARS',
  'VERIFYING_SOURCES',
  'REPAIRING',
  'VERIFYING_REPAIRED',
  'RENAMING',
  'UNPACKING',
  'MOVING',
  'EXECUTING_SCRIPT',
  'PP_FINISHED',
};

/// Which state a `listgroups` `Status` belongs to.
NzbgetGroupState nzbgetGroupState(String rawStatus) {
  final status = rawStatus.trim().toUpperCase();
  if (status.isEmpty) return NzbgetGroupState.queued;
  if (status == 'DOWNLOADING') return NzbgetGroupState.downloading;
  if (status == 'FETCHING') return NzbgetGroupState.fetching;
  if (status == 'PAUSED') return NzbgetGroupState.paused;
  if (status == 'QUEUED') return NzbgetGroupState.queued;
  if (_postProcessingStatuses.contains(status)) {
    return NzbgetGroupState.postProcessing;
  }
  return NzbgetGroupState.unknown;
}

/// NZBGet's own word for what the job is doing, in sentence case.
///
/// The stage is worth keeping because it is the one thing that tells a
/// three-minute repair from a thirty-second unpack, and the board draws it
/// (`par-check … post-processing`). An unrecognised status is humanised rather
/// than replaced: a future NZBGet stage then reads as itself instead of as
/// "working", which would be this app inventing a word for something it did not
/// understand.
String nzbgetGroupStageLabel(String rawStatus) {
  final status = rawStatus.trim().toUpperCase();
  if (status.isEmpty) return 'queued';
  return switch (status) {
    'DOWNLOADING' => 'downloading',
    'FETCHING' => 'fetching the NZB',
    'PAUSED' => StateWord.stopped.inline,
    'QUEUED' => 'queued',
    'PP_QUEUED' || 'PP_FINISHED' => 'post-processing',
    'LOADING_PARS' || 'VERIFYING_SOURCES' => 'par-check',
    'REPAIRING' || 'VERIFYING_REPAIRED' => 'repairing',
    'RENAMING' => 'renaming',
    'UNPACKING' => 'unpacking',
    'MOVING' => 'moving',
    'EXECUTING_SCRIPT' => 'running the post script',
    _ => status.toLowerCase().replaceAll('_', ' '),
  };
}

/// One queue row: what it is, what it is doing, how far it got.
@immutable
class NzbgetQueueEntry {
  const NzbgetQueueEntry({
    required this.name,
    required this.state,
    required this.stage,
    required this.detail,
    required this.percentLabel,
  });

  final String name;
  final NzbgetGroupState state;

  /// NZBGet's word for the stage: `repairing`, `unpacking`.
  final String stage;

  /// Category, stage and total size, as far as the record carried them.
  final String detail;

  /// `56%`, or null when NZBGet reported no file size **or no remaining size**.
  ///
  /// Null and never `0%`: a job whose size the server did not report has no
  /// measurable progress, and `0%` is the one reading a user would act on:
  /// it says "stuck", which nobody established. The remaining half matters for
  /// the opposite reason: a missing remaining size used to compute `100%`,
  /// which says "done".
  final String? percentLabel;

  StatusTone get tone => state.tone;
  IconData get icon => state.icon;

  /// The row as one sentence, with the layout's `·` turned back into commas.
  String get spoken =>
      joinSpokenParts([name, spokenFromDotted(detail), percentLabel]);
}

/// Turns a `listgroups` record into the row the section draws.
NzbgetQueueEntry nzbgetQueueEntry(NzbgetGroup group) {
  final state = nzbgetGroupState(group.status);
  final stage = nzbgetGroupStageLabel(group.status);
  return NzbgetQueueEntry(
    name: group.name,
    state: state,
    stage: stage,
    detail: joinDisplayParts([
      group.category,
      stage,
      // The whole size, not what is left: the board prints the job's size, and
      // "4.8 GB" beside "56%" is a fact the two numbers agree on. A size the
      // record did not carry is dropped rather than printed: see
      // [NzbgetQueueEntry.percentLabel].
      switch (group.fileSizeMb) {
        final int mb when mb > 0 => formatMegabytes(mb),
        _ => null,
      },
    ]),
    percentLabel: switch (group.percentage) {
      final int percent => formatPercent(percent),
      null => null,
    },
  );
}

/// The Queue region: its rows, its counts and its ETA clause.
@immutable
class NzbgetQueueSection {
  const NzbgetQueueSection({
    required this.rows,
    required this.total,
    required this.downloading,
    required this.postProcessing,
    required this.remainingLabel,
    required this.etaLabel,
  });

  /// At most [nzbgetQueuePreviewLimit] rows.
  final List<NzbgetQueueEntry> rows;

  final int total;
  final int downloading;
  final int postProcessing;

  /// `2.1 GB left`, or null when `status` did not answer.
  final String? remainingLabel;

  /// `about 11 min`, or null when nothing is moving or `status` did not answer.
  final String? etaLabel;

  /// `1 downloading · 1 post-processing · 2.1 GB left · about 11 min`, and
  /// `nothing queued` when every clause is silent.
  ///
  /// Every clause is dropped rather than zeroed when its source is silent, so
  /// this line only ever states things that were actually measured. But the
  /// commonest state of a download client is an empty queue, and there every
  /// clause is guarded off at once. An empty string is not a shorter header:
  /// `SectionHeader` treats a non-null subtitle as a subtitle, so it draws the
  /// gap and a blank line under the word Queue and speaks "Queue, " with a
  /// dangling comma. The resting state gets a sentence of its own, the way
  /// History's degrades to plain `today`.
  String get subtitle {
    final measured = joinDisplayParts([
      if (downloading > 0) '$downloading downloading',
      if (postProcessing > 0) '$postProcessing post-processing',
      // A queue that is neither downloading nor post-processing still has a
      // size worth naming; without this the header of a fully paused queue
      // only carries the remaining total.
      if (downloading == 0 && postProcessing == 0 && total > 0)
        total == 1 ? '1 job' : '$total jobs',
      remainingLabel,
      etaLabel,
    ]);
    return measured.isEmpty ? 'nothing queued' : measured;
  }
}

/// How long the rest of the queue will take at the rate NZBGet reports *now*.
///
/// Null rather than a number whenever the arithmetic would be a fiction:
///
///  * no rate (paused, idle, or a `status` that did not answer): dividing by
///    zero gives infinity, and "∞ left" is a decoration, not information;
///  * nothing remaining: there is no wait to describe.
///
/// Deliberately coarse and prefixed "about": it is one instantaneous sample
/// divided into a total, so a minute of precision would be a confidence the
/// figure does not have.
String? nzbgetEtaLabel({
  required int remainingMegabytes,
  required int rateBytesPerSecond,
}) {
  if (rateBytesPerSecond <= 0 || remainingMegabytes <= 0) return null;
  final seconds = (remainingMegabytes * 1024 * 1024) / rateBytesPerSecond;
  if (seconds < 60) return 'about a minute';
  final minutes = (seconds / 60).round();
  final hours = minutes ~/ 60;
  if (hours >= 24) {
    final days = (hours / 24).round();
    return days == 1 ? 'about a day' : 'about $days days';
  }
  return 'about ${formatTimeSpan(Duration(minutes: minutes))}';
}

/// Builds the Queue region from one `listgroups` answer and, when it answered,
/// one `status`.
///
/// [status] is nullable on purpose: the rate and the remaining total are
/// *decoration* on this section, and a `status` call that failed must cost the
/// ETA clause rather than the list of what is downloading.
///
/// Server order is preserved. `listgroups` answers in the order NZBGet will
/// work through the queue, and re-sorting it would tell the user a different
/// story about what runs next than the Queue tab does.
NzbgetQueueSection nzbgetQueueSection(
  List<NzbgetGroup> groups, {
  NzbgetStatus? status,
  int limit = nzbgetQueuePreviewLimit,
}) {
  var downloading = 0;
  var postProcessing = 0;
  for (final group in groups) {
    switch (nzbgetGroupState(group.status)) {
      case NzbgetGroupState.downloading:
      case NzbgetGroupState.fetching:
        downloading++;
      case NzbgetGroupState.postProcessing:
        postProcessing++;
      case NzbgetGroupState.paused:
      case NzbgetGroupState.queued:
      case NzbgetGroupState.unknown:
        break;
    }
  }

  return NzbgetQueueSection(
    rows: List.unmodifiable(groups.take(limit).map(nzbgetQueueEntry)),
    total: groups.length,
    downloading: downloading,
    postProcessing: postProcessing,
    remainingLabel: status == null || status.remainingSizeMb <= 0
        ? null
        : '${status.remainingLabel} left',
    etaLabel: status == null
        ? null
        : nzbgetEtaLabel(
            remainingMegabytes: status.remainingSizeMb,
            rateBytesPerSecond: status.downloadRateBytes,
          ),
  );
}

/// The Queue region, from the queue the KPI rail already loaded.
final nzbgetOverviewQueueProvider =
    FutureProvider.autoDispose<NzbgetQueueSection>((ref) async {
      final groups = await ref.watch(nzbgetQueueProvider.future);
      // Defensive, for the reason [nzbgetQueueSection] documents: the status
      // decorates this section and must not be able to take it down. The same
      // shape the SABnzbd KPI builder uses for its lifetime total.
      NzbgetStatus? status;
      try {
        status = await ref.watch(nzbgetStatusProvider.future);
      } catch (_) {
        status = null;
      }
      return nzbgetQueueSection(groups, status: status);
    }, retry: noProviderRetry);

// ─── History ────────────────────────────────────────────────────────────────

/// How a history record ended, in the five-arm tone vocabulary.
///
/// The interesting arm is [deleted]: `DELETED/DUPE`, `DELETED/MANUAL` and
/// friends are the user or NZBGet's own duplicate rules doing exactly what they
/// were told, so they are **neutral**. Painting them amber is the single most
/// common way the tone rule is broken, and a history list is where it happens,
/// because "deleted" sounds like damage and is not.
enum NzbgetHistoryOutcome {
  succeeded(StatusTone.success, 'success'),

  /// NZBGet gave up on the job. A fault: nobody asked for this.
  failed(StatusTone.warning, 'failed'),

  /// Finished, but damaged, unrepaired, out of space or password-locked. Still
  /// a fault: the file on disk is not what the user asked for.
  warned(StatusTone.warning, 'warning'),

  /// Removed on purpose, by a human or by a dupe rule. Backlog, not damage.
  deleted(StatusTone.neutral, 'deleted'),

  /// A status this app has not met.
  unknown(StatusTone.neutral, 'finished');

  const NzbgetHistoryOutcome(this.tone, this.label);

  final StatusTone tone;

  /// The word the row prints after the job's name.
  final String label;

  /// Whether this record is one the user has to decide something about.
  bool get isFault =>
      this == NzbgetHistoryOutcome.failed ||
      this == NzbgetHistoryOutcome.warned;
}

/// The slash-less statuses NZBGet gives a **URL-kind** history record.
///
/// `history(false)` (the call `NzbgetClient` makes) returns NZB records *and*
/// the URL records left behind by an NZB fetched from a link, and those do not
/// follow the `FAMILY/REASON` shape at all: their whole `Status` is one word.
/// Split on `/`, the word becomes the family, no arm matches and the record
/// lands in [NzbgetHistoryOutcome.unknown]: neutral ink, the word "finished",
/// uncounted in `failed` and unsorted by faults-first. An NZB the daemon could
/// not even fetch would be the one thing on this page that silently reads as
/// fine.
///
/// The reason is spelled out here rather than derived, because there is no
/// `REASON` half to translate.
const Map<String, (NzbgetHistoryOutcome, String?)> _urlOutcomes = {
  // A fault: nobody asked for the fetch to fail.
  'URL_FAILURE': (NzbgetHistoryOutcome.failed, 'could not fetch the NZB'),
  'URL_SCAN_FAILURE': (
    NzbgetHistoryOutcome.failed,
    'the NZB could not be read',
  ),
  // The link was fetched; the scan script chose not to look at it. Not damage,
  // so not amber, and the fetch itself did what it said.
  'URL_SCAN_SKIPPED': (NzbgetHistoryOutcome.succeeded, 'scan skipped'),
  'URL_SUCCESS': (NzbgetHistoryOutcome.succeeded, null),
  // NZBGet's own "I do not know", kept distinct from ours.
  'URL_UNKNOWN': (NzbgetHistoryOutcome.unknown, null),
};

/// NZBGet's history `Status` is `FAMILY/REASON`: `FAILURE/PAR`,
/// `DELETED/DUPE`, except for the URL-kind records of [_urlOutcomes], which
/// carry no slash. This splits it into the outcome and the reason in words.
///
/// The reason is translated rather than printed raw: `PAR` alone means nothing
/// to anyone who has not read the NZBGet manual, and the board's line for the
/// same record is prose ("par2 repair impossible"). An unrecognised reason is
/// lower-cased and passed through, which is honest about a vocabulary that
/// grows.
(NzbgetHistoryOutcome, String?) nzbgetHistoryOutcome(String rawStatus) {
  final status = rawStatus.trim().toUpperCase();
  if (status.isEmpty) return (NzbgetHistoryOutcome.unknown, null);

  final urlOutcome = _urlOutcomes[status];
  if (urlOutcome != null) return urlOutcome;

  final slash = status.indexOf('/');
  final family = slash < 0 ? status : status.substring(0, slash);
  final reason = slash < 0 ? '' : status.substring(slash + 1);

  final outcome = switch (family) {
    'SUCCESS' => NzbgetHistoryOutcome.succeeded,
    'FAILURE' => NzbgetHistoryOutcome.failed,
    'WARNING' => NzbgetHistoryOutcome.warned,
    'DELETED' => NzbgetHistoryOutcome.deleted,
    _ => NzbgetHistoryOutcome.unknown,
  };

  return (outcome, _historyReason(outcome, reason));
}

/// The `REASON` half in words, or null when it adds nothing.
String? _historyReason(NzbgetHistoryOutcome outcome, String reason) {
  if (reason.isEmpty) return null;
  // `SUCCESS/ALL` and `SUCCESS/GOOD` are "it worked", which the outcome word
  // already said. Repeating it as a second clause is noise on the row that
  // needs the least attention.
  if (outcome == NzbgetHistoryOutcome.succeeded &&
      (reason == 'ALL' || reason == 'GOOD')) {
    return null;
  }
  return switch (reason) {
    'PAR' => 'par repair',
    'UNPACK' => 'unpack',
    'MOVE' => 'could not be moved',
    'BAD' => 'rejected by the post script',
    'HEALTH' => 'health check',
    'SCAN' => 'could not be read',
    'DAMAGED' => 'damaged',
    'REPAIRABLE' => 'repairable, not repaired',
    'SPACE' => 'out of disk space',
    'PASSWORD' => 'password required',
    'SCRIPT' => 'post script',
    'TERM' => 'stopped',
    'MANUAL' => 'removed by hand',
    'DUPE' => 'duplicate',
    'COPY' => 'already downloaded',
    _ => reason.toLowerCase().replaceAll('_', ' '),
  };
}

/// One history row: the job, how it ended, and when.
@immutable
class NzbgetHistoryEntry {
  const NzbgetHistoryEntry({
    required this.name,
    required this.outcome,
    required this.detail,
    required this.time,
  });

  final String name;
  final NzbgetHistoryOutcome outcome;

  /// The reason, the category and how long ago, as far as the record carried
  /// them.
  final String detail;

  final DateTime time;

  StatusTone get tone => outcome.tone;

  /// `Sugar.S02E01 · failed`.
  String get headline => '$name · ${outcome.label}';

  String get spoken =>
      joinSpokenParts([name, outcome.label, spokenFromDotted(detail)]);
}

/// The History region: its rows and the counts its header states.
@immutable
class NzbgetHistorySection {
  const NzbgetHistorySection({
    required this.rows,
    required this.completed,
    required this.failed,
    required this.warned,
  });

  /// At most [nzbgetHistoryTodayLimit] rows, faults first.
  final List<NzbgetHistoryEntry> rows;

  final int completed;
  final int failed;
  final int warned;

  /// `today · 6 completed · 1 failed`.
  ///
  /// Deliberate removals are counted in neither clause: a dupe NZBGet threw
  /// away on purpose is not news, and listing it beside the failures would
  /// inflate the one number on this page that should make someone look.
  String get subtitle => joinDisplayParts([
    'today',
    if (completed > 0) '$completed completed',
    if (failed > 0) '$failed failed',
    if (warned > 0) warned == 1 ? '1 warning' : '$warned warnings',
  ]);
}

/// Today's history, faults first, capped at [limit].
///
/// **"Today" is the local calendar day of [now]**, not "the last 24 hours": the
/// section is headed `today`, and a heading is a promise. A record from 23:50
/// yesterday is out even though it is twenty minutes old.
///
/// A record with no `HistoryTime` is dropped rather than sorted to one end: it
/// cannot be placed inside or outside the window, and guessing either way is
/// how a list ordered by time stops being ordered by time.
///
/// Faults first is the mobile board's own instruction ("History failed first").
/// Within each group, newest first.
NzbgetHistorySection nzbgetHistoryToday(
  List<NzbgetHistoryItem> items, {
  required DateTime now,
  int limit = nzbgetHistoryTodayLimit,
}) {
  final local = now.toLocal();
  final entries = <NzbgetHistoryEntry>[];
  var completed = 0;
  var failed = 0;
  var warned = 0;

  for (final item in items) {
    final time = item.time?.toLocal();
    if (time == null) continue;
    if (time.year != local.year ||
        time.month != local.month ||
        time.day != local.day) {
      continue;
    }

    final (outcome, reason) = nzbgetHistoryOutcome(item.status);
    switch (outcome) {
      case NzbgetHistoryOutcome.succeeded:
        completed++;
      case NzbgetHistoryOutcome.failed:
        failed++;
      case NzbgetHistoryOutcome.warned:
        warned++;
      case NzbgetHistoryOutcome.deleted:
      case NzbgetHistoryOutcome.unknown:
        break;
    }

    entries.add(
      NzbgetHistoryEntry(
        name: item.name,
        outcome: outcome,
        detail: joinDisplayParts([
          reason,
          item.category,
          formatRelativeDateTime(time, now: now),
        ]),
        time: time,
      ),
    );
  }

  entries.sort((a, b) {
    // Two booleans compared as ints: a fault sorts before a non-fault, and the
    // tie-break is the clock.
    final byFault = (a.outcome.isFault ? 0 : 1).compareTo(
      b.outcome.isFault ? 0 : 1,
    );
    return byFault != 0 ? byFault : b.time.compareTo(a.time);
  });

  return NzbgetHistorySection(
    rows: List.unmodifiable(entries.take(limit)),
    completed: completed,
    failed: failed,
    warned: warned,
  );
}

/// Today's history, from the single `history` answer the client makes.
///
/// NZBGet answers the whole history in one call: there is no page parameter on
/// the method the client sends, so the windowing is all client-side and costs
/// nothing extra.
final nzbgetOverviewHistoryProvider =
    FutureProvider.autoDispose<NzbgetHistorySection>((ref) async {
      final items = await ref.watch(nzbgetHistoryProvider.future);
      return nzbgetHistoryToday(items, now: DateTime.now());
    }, retry: noProviderRetry);
