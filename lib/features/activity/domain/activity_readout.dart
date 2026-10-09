/// The words under Activity's title: what is moving, how fast, and what is
/// stuck, or when the last download finished.
library;

import 'package:cupola/core/status/lexicon.dart';
import 'package:cupola/core/utils/byte_format.dart';
import 'package:cupola/core/utils/string_utils.dart';
import 'package:cupola/features/services/domain/source_coverage.dart';

/// One fact of the readout: a figure, set large, and its words after it.
class ActivityReadoutPart {
  const ActivityReadoutPart(this.figure, this.words, {this.stuck = false});

  /// `4`, `40.4`, `20+`.
  final String figure;

  /// `moving`, `MB/s`, `stuck`.
  final String words;

  /// A fault: the part is amber.
  final bool stuck;

  /// The part as a screen reader says it.
  String get spoken => spokenCountPhrase('$figure $words');

  @override
  bool operator ==(Object other) =>
      other is ActivityReadoutPart &&
      other.figure == figure &&
      other.words == words &&
      other.stuck == stuck;

  @override
  int get hashCode => Object.hash(figure, words, stuck);

  @override
  String toString() => '$figure $words';
}

/// What is moving, how fast and what is stuck: `4 moving · 40.4 MB/s ·
/// 1 stuck`. Empty when nothing moves and nothing is stuck: the page then
/// says [nothingMoving].
///
/// The counts are over the queues [coverage] read, a floor when a walk
/// stopped short. The speed is the download clients' own rates added up,
/// over the clients that answered ([rateBytesPerSecond], null when none
/// measured one): a client that did not answer is named under it, never
/// counted as nothing.
List<ActivityReadoutPart> activityReadoutParts({
  required int moving,
  required int stuck,
  int? rateBytesPerSecond,
  SourceCoverage coverage = SourceCoverage.none,
}) {
  if (moving == 0 && stuck == 0) return const [];
  final speed = rateBytesPerSecond == null || moving == 0
      ? null
      : formatBytesPerSecond(rateBytesPerSecond);
  final space = speed?.indexOf(' ') ?? -1;
  return [
    if (moving > 0)
      ActivityReadoutPart(coveredFigure(moving, coverage), 'moving'),
    if (speed != null && space > 0)
      ActivityReadoutPart(
        speed.substring(0, space),
        speed.substring(space + 1),
      ),
    if (stuck > 0)
      ActivityReadoutPart(
        coveredFigure(stuck, coverage),
        StateWord.stuck.label.toLowerCase(),
        stuck: true,
      ),
  ];
}

/// What the readout says when nothing moves and nothing is stuck.
const String nothingMoving = 'Nothing moving';

/// The calm line under [nothingMoving]: `Last download finished 18:52`
/// today, `yesterday 18:52`, the weekday within the week. Null past a week,
/// and when nothing says.
String? lastDownloadFinished(DateTime? at, {required DateTime now}) {
  if (at == null) return null;
  final local = at.toLocal();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(local.year, local.month, local.day);
  final when = switch (today.difference(day).inDays) {
    0 => formatClockTime(local),
    1 => 'yesterday ${formatClockTime(local)}',
    > 1 && < 7 => '${weekdayName(local)} ${formatClockTime(local)}',
    _ => null,
  };
  return when == null ? null : 'Last download finished $when';
}

/// The readout as one sentence for a screen reader: `4 moving, 40.4
/// megabytes a second, 1 stuck`.
String spokenActivityReadout(List<ActivityReadoutPart> parts) => parts
    .map(
      (part) => part.words.endsWith('/s')
          ? spokenBytesPerSecond('${part.figure} ${part.words}')
          : part.spoken,
    )
    .join(', ');
