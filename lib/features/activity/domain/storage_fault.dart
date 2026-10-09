/// The words of a TrueNAS alert about a disk, on its card in Needs you: what
/// the errors mean for the disk's pool, the pool's evidence, and the scrub
/// that repairs it.
library;

import 'package:cupola/core/utils/duration_format.dart';
import 'package:cupola/core/utils/percent_format.dart';
import 'package:cupola/core/utils/string_utils.dart';
import 'package:cupola/features/truenas/domain/models/pool.dart';

/// What [disk]'s errors mean: `sdd could not read some data by itself. The
/// pool is still healthy: a scrub reads every block and repairs it from the
/// other disks.`, or that its pool is not healthy either.
String diskErrorsExplanation(String disk, TrueNasPool pool) => pool.healthy
    ? '$disk could not read some data by itself. The pool is still healthy: '
          'a scrub reads every block and repairs it from the other disks.'
    : '$disk could not read some data by itself, and pool ${pool.name} is '
          '${pool.status.toLowerCase()}.';

/// The pool's evidence, a line each: `Pool tank · Healthy · 72%`, `Disk sdd
/// · 8 errors`.
List<String> poolEvidence(String disk, TrueNasPool pool) {
  final used = pool.usedFraction;
  final member = pool.memberNamed(disk);
  final errors = member?.errors;
  return [
    [
      'Pool ${pool.name}',
      pool.healthy ? 'Healthy' : capitalizeFirst(pool.status.toLowerCase()),
      if (used != null) formatPercent(wholePercent(used * 100)),
    ].join(' · '),
    if (member != null)
      [
        'Disk $disk',
        if (errors != null && errors > 0)
          errors == 1 ? '1 error' : '$errors errors'
        else
          capitalizeFirst(member.status.toLowerCase()),
      ].join(' · '),
  ];
}

/// The scrub's button: `Scrub tank`.
String scrubLabel(TrueNasPool pool) => 'Scrub ${pool.name}';

/// The scan that runs, under the card: `Scrubbing tank · 2% · about 9 h
/// left`, `Resilvering tank · 40%`.
String scanningLine(TrueNasPool pool) {
  final verb = pool.scanFunction?.toUpperCase() == 'RESILVER'
      ? 'Resilvering'
      : 'Scrubbing';
  final percent = pool.scanPercentage;
  final left = pool.scanSecondsLeft;
  return [
    '$verb ${pool.name}',
    if (percent != null) formatPercent(percent.floor()),
    if (left != null && left > 0)
      'about ${formatTimeSpan(Duration(seconds: left))} left',
  ].join(' · ');
}

/// The confirmation a scrub asks: it reads the whole pool, for hours.
typedef ScrubConfirmation = ({String title, String message, String confirm});

ScrubConfirmation scrubConfirmation(TrueNasPool pool) => (
  title: 'Scrub ${pool.name}?',
  message:
      'A scrub reads every block of ${pool.name} and repairs what it can from '
      'the other disks. It can take hours and adds disk load, but is safe to '
      'run.',
  confirm: 'Scrub ${pool.name}',
);
