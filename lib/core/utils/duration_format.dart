/// Formatting for elapsed durations that are shown to the user and updated in
/// place — a release search's clock today, and the background job cards that will
/// read the same value later.
///
/// Two forms rather than one, because a screen reader cannot read `1:12`: the
/// glyph form is for the eye and carries `.tabular` at the call site so it does
/// not jitter as it counts, and the spoken form is for `Semantics(label:)`.
///
/// A span that is *read* (a time left, an estimate, a runtime) is [formatTimeSpan]:
/// the brand book's units, one formatter for every screen.
library;

import 'package:cupola/core/utils/unit_space.dart';

/// Formats [elapsed] as `m:ss` — `0:07`, `1:12`, `12:04`.
///
/// Minutes are not zero-padded: this is a stopwatch, not a timestamp, and a
/// leading zero on the minutes reads as a clock time.
String formatElapsed(Duration elapsed) {
  final seconds = elapsed.inSeconds % 60;
  return '${elapsed.inMinutes}:${seconds.toString().padLeft(2, '0')}';
}

/// Spells [elapsed] out for a screen reader: `7 seconds`, `1 minute 12 seconds`,
/// `2 minutes`.
String formatElapsedForSpeech(Duration elapsed) {
  final minutes = elapsed.inMinutes;
  final seconds = elapsed.inSeconds % 60;
  final spokenSeconds = '$seconds second${seconds == 1 ? '' : 's'}';
  if (minutes == 0) return spokenSeconds;
  final spokenMinutes = '$minutes minute${minutes == 1 ? '' : 's'}';
  return seconds == 0 ? spokenMinutes : '$spokenMinutes $spokenSeconds';
}

/// A span as the brand book writes it: `48 s`, `12 min`, `2 h 30 min`, `3 d`,
/// `3 d 4 h`. Every figure joins its unit with a no-break space (`withUnit`).
///
/// The one formatter for a time left, an estimate, a runtime, a task's length:
/// qBittorrent's `1h 5m`, the Activity table's `12m left` and a runtime's `2h 7m`
/// were each a private spelling, so one cell could read `4.4 GB · 12m left`.
///
///  * **Two units at most, the larger first, and the smaller dropped when it is
///    zero**: `2 h` and not `2 h 0 min`, `3 d` and not `3 d 0 h`.
///  * **Truncated, not rounded**: 59 minutes 59 seconds is `59 min`, never
///    `60 min`; a caller that rounds (an estimate that says "about") rounds
///    before it calls.
///  * **Seconds only under a minute** (`48 s`), or under an hour when
///    [seconds] is true (`4 min 30 s`), for a countdown that is read to the
///    second. Above an hour they are noise and never shown.
///  * **Never negative and never bare**: a span below zero reads `0 s`, and
///    there is always a unit.
String formatTimeSpan(Duration span, {bool seconds = false}) {
  final total = span.isNegative ? 0 : span.inSeconds;
  final days = total ~/ 86400;
  final hours = (total % 86400) ~/ 3600;
  final minutes = (total % 3600) ~/ 60;
  final rest = total % 60;

  String join(int major, String majorUnit, int minor, String minorUnit) =>
      minor == 0
      ? withUnit(major, majorUnit)
      : '${withUnit(major, majorUnit)} ${withUnit(minor, minorUnit)}';

  if (days > 0) return join(days, 'd', hours, 'h');
  if (hours > 0) return join(hours, 'h', minutes, 'min');
  if (minutes > 0) {
    return seconds ? join(minutes, 'min', rest, 's') : withUnit(minutes, 'min');
  }
  return withUnit(rest, 's');
}

/// Formats a remaining window: `29 min`, `4 min 30 s`, `0 s`.
///
/// Always carries a unit, at every magnitude. A bare `4:30` in the same slot as
/// an elapsed clock is indistinguishable from one — and these two numbers mean
/// opposite things, so the unit is what keeps them apart. Seconds show under ten
/// minutes, where the countdown is read to the second.
String formatWindowRemaining(Duration remaining) =>
    formatTimeSpan(remaining, seconds: remaining.inMinutes < 10);

/// Spells the same window out for a screen reader, which cannot read `4 min 30 s`.
String formatWindowForSpeech(Duration remaining) {
  final minutes = remaining.inMinutes;
  final seconds = remaining.inSeconds % 60;
  if (minutes == 0) return '$seconds second${seconds == 1 ? '' : 's'}';
  final spokenMinutes = '$minutes minute${minutes == 1 ? '' : 's'}';
  if (remaining.inMinutes >= 10 || seconds == 0) return spokenMinutes;
  return '$spokenMinutes $seconds second${seconds == 1 ? '' : 's'}';
}
