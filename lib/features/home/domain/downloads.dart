/// The words of the Home's Downloads module: what is moving, what is stuck,
/// what waits its turn, and how fast, read at a glance from four rows.
///
/// The module draws the transfers that move and the ones that stopped
/// moving, each with its remedy in the row. A finished download the arr will
/// not import is not a download any more: Needs you leads with it, and the
/// module names it once in its footnote.
///
/// No sizes: how much of a file has landed is the client's page's business.
/// A row says how far it got and how long it has left, and the stuck one says
/// where it stopped.
library;

import 'package:cupola/core/status/lexicon.dart';
import 'package:cupola/core/utils/byte_format.dart';
import 'package:cupola/core/utils/date_format.dart';
import 'package:cupola/core/utils/duration_format.dart';
import 'package:cupola/core/utils/percent_format.dart';
import 'package:cupola/features/services/domain/in_flight.dart';
import 'package:cupola/features/services/domain/source_coverage.dart';

/// How many rows the module draws before See all in Activity.
const downloadsRowLimit = 4;

/// The faults a download row carries: the ones whose remedy is another
/// download. A blocked import is downloaded already, and stays in Needs you.
bool isDownloadFault(InFlightFault? fault) =>
    fault == InFlightFault.stalled || fault == InFlightFault.failed;

/// Which of [moving] and [stuck] the module draws, in drawing order: the
/// moving ones as their queue orders them, then the stuck ones.
///
/// The stuck ones are chosen first, because each carries a remedy and a
/// moving download needs nothing; the moving ones fill what is left of
/// [limit].
List<T> downloadRowsOf<T>(
  List<T> moving,
  List<T> stuck, {
  int limit = downloadsRowLimit,
}) {
  final faults = stuck.take(limit).toList(growable: false);
  return [...moving.take(limit - faults.length), ...faults];
}

/// The line under the module's name: `3 moving · 1 stuck · 1 queued ·
/// 40.4 MB/s`.
///
/// What waits its turn ([queued]) is said after what is stuck, and alone when
/// nothing moves or is stuck (`1 queued`): a download that has not started is
/// not moving, and the line no longer counts it so. `Nothing moving` only
/// when all three are zero.
///
/// The counts are over the queues [coverage] read, a floor when a walk
/// stopped short. The speed is the download clients' own rates added up, and
/// only theirs: an arr reports none. It reads `—` while a client that is set
/// up did not answer, since the sum of the others would understate it, and it
/// is left out when no client is set up at all ([clientSetUp]): the module
/// then says where speeds come from.
String downloadsSubtitle({
  required int moving,
  required int stuck,
  required int queued,
  required bool clientSetUp,
  bool clientSilent = false,
  int? rateBytesPerSecond,
  SourceCoverage coverage = SourceCoverage.none,
}) {
  if (moving == 0 && stuck == 0 && queued == 0) return 'Nothing moving';
  final speed = !clientSetUp
      ? null
      : clientSilent
      ? Lexicon.noFigure
      : rateBytesPerSecond == null
      ? null
      : formatBytesPerSecond(rateBytesPerSecond);
  return [
    if (moving > 0) '${coveredFigure(moving, coverage)} moving',
    if (stuck > 0) '${coveredFigure(stuck, coverage)} stuck',
    if (queued > 0) '${coveredFigure(queued, coverage)} queued',
    ?speed,
  ].join(' · ');
}

/// The line under the module's name when the module is a last drawing:
/// `3 moving · 1 queued`, as it counted then.
///
/// No speed (a rate is not drawn from a drawing) and no `stuck` (a fault is
/// judged by the live read; a download that was stuck is a row, not a count).
/// Counts only for a read that was [whole]: over a queue that did not answer,
/// or stopped short, they are not stated. With rows to draw and nothing
/// counted there is no line at all, rather than `Nothing moving` over a row;
/// `Nothing moving` is only for a whole read with nothing in it.
String? downloadsKnownSubtitle({
  required int moving,
  required int queued,
  required bool whole,
  required bool hasRows,
}) {
  if (!whole) return null;
  if (moving == 0 && queued == 0) return hasRows ? null : 'Nothing moving';
  return downloadsSubtitle(
    moving: moving,
    stuck: 0,
    queued: queued,
    clientSetUp: false,
  );
}

/// [downloadsSubtitle] as a screen reader should say it: the dash as an
/// unknown speed, each part on its own pause, a floor as `at least`.
String spokenDownloadsSubtitle(String subtitle) => subtitle
    .split('·')
    .map((part) => part.trim())
    .map(
      (part) =>
          part == Lexicon.noFigure ? 'speed unknown' : spokenCountPhrase(part),
    )
    .join(', ');

/// What a moving row says beside its title: `88% · 1 min`, either half
/// alone when the other is unknown, empty when both are.
String movingValue({int? percent, int? etaSeconds}) => [
  if (percent != null) formatPercent(percent),
  // Zero is no estimate: SABnzbd says `0:00:00` of a job nothing reaches.
  if (etaSeconds != null && etaSeconds > 0)
    formatTimeSpan(Duration(seconds: etaSeconds)),
].join(' · ');

/// What a stuck row says beside its title: where it stopped, `Stuck at
/// 47%`, or that it failed.
String stuckValue(InFlightFault fault, {int? percent}) => switch (fault) {
  InFlightFault.failed => StateWord.failed.label,
  InFlightFault.stalled || InFlightFault.needsImport =>
    percent == null
        ? StateWord.stuck.label
        : '${StateWord.stuck.label} at ${formatPercent(percent)}',
};

/// A row's value as a screen reader should say it: `88 percent, 1 min left`.
String spokenMovingValue({int? percent, int? etaSeconds}) => [
  if (percent != null) '${spokenPercent(percent)} done',
  if (etaSeconds != null && etaSeconds > 0)
    '${formatTimeSpan(Duration(seconds: etaSeconds))} left',
].join(', ');

/// The calm line under `Nothing is downloading`: when the last download
/// arrived in a library, from the imports Arrived reads.
///
/// `The last download finished at 18:52.` today, `yesterday at 18:52`, the
/// weekday within the week; null past a week, and when nothing says.
String? lastFinishedLine(DateTime? at, {required DateTime now}) {
  if (at == null) return null;
  final local = at.toLocal();
  final when = switch (calendarDaysBetween(local, now)) {
    0 => 'at ${formatClockTime(local)}',
    1 => 'yesterday at ${formatClockTime(local)}',
    > 1 && < 7 => 'on ${weekdayName(local)}',
    _ => null,
  };
  if (when == null) return null;
  return 'The last download finished $when.';
}
