/// Dates and clock times as the app writes them: the weekday and month names,
/// the date voices and the clock, in one file.
///
/// Each voice answers a different question and they are kept apart on purpose
/// (the sortable `2026-09-20` of a dense row, the `Jul 17, 2026` of a detail
/// grid, the `Tue 29 Sep` of a day in the week), but they share their pieces:
/// one list of weekday names, one list of month names, one clock. A screen that
/// needs one of them calls it from here instead of spelling the names again.
///
/// Every function is pure and top-level, so it can run inside `compute` and
/// `Isolate.run`. English names are hard-coded: English-only is a decision, not
/// debt, so there is no `intl` dependency to reach for.
library;

import 'package:cupola/core/utils/sample_age.dart';
import 'package:cupola/core/utils/unit_space.dart';

/// Formats an ISO-8601 date string to `YYYY-MM-DD`.
///
/// Returns the original string if parsing fails.
///
/// This is the *dense-row* date voice: the activity feed pairs it with a clock
/// time and sorts by it, where a fixed-width sortable form reads better than a
/// prose one. It is deliberately **not** the detail-page voice; see
/// [formatMediumDate].
String formatIsoDate(String isoDate) {
  try {
    return formatIsoDay(DateTime.parse(isoDate));
  } catch (_) {
    return isoDate;
  }
}

/// `2026-09-02`: the sortable form of a day that is already a [DateTime], the
/// components as they stand and each padded to a fixed width.
String formatIsoDay(DateTime day) =>
    '${day.year}-${day.month.toString().padLeft(2, '0')}-'
    '${day.day.toString().padLeft(2, '0')}';

/// Formats an ISO-8601 date as `Jul 17, 2026`: the one date voice every media
/// detail page speaks.
///
/// The drift this exists to end was visible two taps apart: a Radarr movie
/// printed `2019-05-22` in its Details grid while the Seerr page for the same
/// film printed `May 22, 2019`. Both are correct and neither is wrong on its
/// own, which is exactly why the choice has to live in one place instead of
/// being re-made per screen. Prose form wins on a detail page because nothing
/// there is sorted or compared column-wise; [formatIsoDate] keeps the sortable
/// form for the rows that are.
///
/// Returns the input unchanged when it cannot be parsed, so a service that
/// answers with something unexpected still shows what it actually said rather
/// than an empty cell. English month names are hard-coded on purpose:
/// English-only is a decision here, not debt, so there is no `intl` dependency
/// to reach for.
String formatMediumDate(String isoDate) {
  final trimmed = isoDate.trim();
  if (trimmed.isEmpty) return trimmed;

  final parsed = DateTime.tryParse(trimmed);
  if (parsed == null) return isoDate;

  return '${_shortMonthNames[parsed.month - 1]} ${parsed.day}, ${parsed.year}';
}

/// Formats an ISO-8601 date as `Tue 29 Sep`, and as `Tue 29 Sep 2025` when it
/// is not in [now]'s year: the brand book's date, a year only when it is
/// another year.
///
/// A row that says *when* a thing is due or was released speaks this voice. It
/// sits beside [formatIsoDate], the sortable `YYYY-MM-DD` of the dense feed
/// rows that pair a date with a clock time, and [formatMediumDate], the
/// `Jul 17, 2026` of the detail grids; it answers the question the other two
/// do not, which is where in the week a date falls.
///
/// The day is the one the string states: the components of the parsed value,
/// with no shift into the reader's timezone, so a release dated the 29th reads
/// the 29th everywhere. [now] is for tests; it defaults to the clock. Returns
/// the input unchanged when it cannot be parsed, like its siblings. English
/// names are hard-coded for the reason [formatMediumDate] gives.
String formatShortDate(String isoDate, {DateTime? now}) {
  final parsed = DateTime.tryParse(isoDate.trim());
  if (parsed == null) return isoDate;

  return formatShortDay(parsed, now: now);
}

/// [formatShortDate] for a day that is already a [DateTime]: `Tue 29 Sep`, and
/// `Tue 29 Sep 2025` when it is not in [now]'s year.
///
/// The components of [day] as they stand, with no shift into the reader's
/// timezone, so a caller that has shifted (or chosen not to) is not second
/// guessed.
String formatShortDay(DateTime day, {DateTime? now}) {
  final words = formatWeekdayDayMonth(day);
  return day.year == (now ?? DateTime.now()).year
      ? words
      : '$words ${day.year}';
}

/// `Wed 21 Oct`: the weekday, the day and the month, and never a year. The
/// piece [formatShortDay] adds its year to.
String formatWeekdayDayMonth(DateTime day) =>
    '${shortWeekdayName(day)} ${formatDayMonthNoYear(day)}';

/// [day] as a day and a month, `12 Sep`, with the year only when it is not
/// [now]'s: `12 Sep 2025`. For a day that is past and named with no weekday,
/// as `On the server since 12 Sep`.
String formatDayMonth(DateTime day, {DateTime? now}) {
  final words = formatDayMonthNoYear(day);
  return day.year == (now ?? DateTime.now()).year
      ? words
      : '$words ${day.year}';
}

/// `12 Sep`: the day and the month, and never a year. For a cell of a calendar
/// or a window of a few weeks, where the year would only be noise.
String formatDayMonthNoYear(DateTime day) =>
    '${day.day} ${_shortMonthNames[day.month - 1]}';

/// The weekday of [day] in full: `Thursday`. For the Home's date and for
/// what a screen reader says of a day, where `Thu` would be read as letters.
String weekdayName(DateTime day) => _weekdayNames[day.weekday - 1];

/// The month of [day] in full: `October`.
String monthName(DateTime day) => _monthNames[day.month - 1];

/// The weekday of [day] as the brand book abbreviates it: `Thu`.
String shortWeekdayName(DateTime day) => shortWeekdayNames[day.weekday - 1];

/// The seven weekdays, Monday first, abbreviated: `Mon` to `Sun`. For a header
/// row that names the columns of a week; a single day asks [shortWeekdayName].
final List<String> shortWeekdayNames = _shortened(_weekdayNames);

// The one list of weekday names and the one list of month names. The short
// forms are their first three letters, which is how the brand book writes both
// (`Tue`, `Sep`), so there is nothing else to keep in step.
const List<String> _weekdayNames = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

const List<String> _monthNames = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

final List<String> _shortMonthNames = _shortened(_monthNames);

List<String> _shortened(List<String> names) =>
    List.unmodifiable([for (final name in names) name.substring(0, 3)]);

/// `Today`, `Tomorrow`, then the weekday and the day of the month, `Wed 3`:
/// the day a thing airs or comes out, in a list of what the next days hold.
///
/// A windowing rule, so it takes an explicit [now]: which day a timestamp
/// belongs to is a calendar day on the device, and the one boundary worth a
/// test is that 23:59 today and 00:01 tomorrow are different words.
String formatDayLabel(DateTime date, DateTime now) {
  final difference = calendarDaysBetween(now, date);
  if (difference == 0) return 'Today';
  if (difference == 1) return 'Tomorrow';
  return '${shortWeekdayName(date)} ${date.day}';
}

/// Whole calendar days from [from] to [to]: `1` from any time on Monday to any
/// time on Tuesday, `0` within a day, negative when [to] is the earlier day.
///
/// Counts the days on the calendar, not the hours between two instants. On the
/// night the clocks go forward a day is 23 h long, so two local midnights a day
/// apart are 23 h apart and `Duration.inDays` calls it `0`: tomorrow reads
/// `Today`, and a week of such days reads six. Comparing the two dates as UTC
/// days removes the clock change from the sum.
///
/// The components of both values as they stand, so a caller that means the
/// device's day passes values already on the device's clock (`toLocal()`). For
/// a span that is *elapsed* time (a certificate's days left, how long a
/// download has idled) the difference of the instants is the right measure and
/// this is the wrong one.
int calendarDaysBetween(DateTime from, DateTime to) => DateTime.utc(
  to.year,
  to.month,
  to.day,
).difference(DateTime.utc(from.year, from.month, from.day)).inDays;

/// A time of day as the brand book writes one: 24 h, `20:41`, on this
/// device's clock.
///
/// Zero-padded, so a column of them stays a column, and 24 h unconditionally:
/// the app has no locale layer to ask, so a 12 h form would be a guess wearing
/// the authority of a formatted time.
String formatClockTime(DateTime time) {
  final local = time.toLocal();
  return '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}';
}

/// `2026-09-20 14:03`: a timestamp on this device's clock, the sortable day and
/// the 24 h clock, or `—` when there is none.
///
/// The dense-row stamp of a feed row or a detail grid. Written twice verbatim
/// (NZBGet and SABnzbd), then a third time for qBittorrent's epoch dates, which
/// is the point at which it belongs here instead: a clock that disagrees with
/// the rest of the app by one surface reads as a different kind of timestamp
/// rather than as a bug.
String formatDateTimeStamp(DateTime? value) {
  if (value == null) return '—';
  final local = value.toLocal();
  return '${formatIsoDay(local)} ${formatClockTime(local)}';
}

/// Relative label for an already-parsed timestamp: `just now`, `20 min ago`,
/// `3 h ago`, `2 days ago`, then the day beyond a week (`Tue 29 Sep`).
///
/// A timestamp ahead of [now] reads the same ladder the other way round
/// (`in 20 min`, `in 2 days`). [now] is for tests; it defaults to the clock.
String formatRelativeDateTime(DateTime date, {DateTime? now}) {
  final local = date.toLocal();
  final reference = (now ?? DateTime.now()).toLocal();
  final difference = reference.difference(local);
  final isFuture = difference.isNegative;
  final delta = isFuture ? local.difference(reference) : difference;

  if (delta < const Duration(minutes: 1)) {
    return isFuture ? 'in < ${withUnit(1, 'min')}' : 'just now';
  }
  if (delta < const Duration(hours: 1)) {
    final minutes = delta.inMinutes;
    final age = withUnit(minutes, 'min');
    return isFuture ? 'in $age' : '$age ago';
  }
  if (delta < const Duration(days: 1)) {
    final hours = delta.inHours;
    final age = withUnit(hours, 'h');
    return isFuture ? 'in $age' : '$age ago';
  }
  if (delta < const Duration(days: 7)) {
    final days = delta.inDays;
    final unit = days == 1 ? 'day' : 'days';
    return isFuture ? 'in $days $unit' : '$days $unit ago';
  }

  // The app's date, `Tue 29 Sep`, with the year only when it is another.
  return formatShortDay(local, now: reference);
}

/// A day that is already past, in words, counted in calendar days: `yesterday`,
/// the weekday within the week (`Wednesday`), then the date as the app says
/// dates (`Tue 29 Sep`, with the year only in another year). Null for today and
/// for a day ahead, which each row says in its own words.
///
/// The voice of the rows about people and requests (who asked, since when it
/// is on the server), where the day is what matters and the hours are noise. A
/// feed or a live list that reads like a log speaks [formatRelativeDateTime]
/// instead: `4 days ago`, counted in elapsed time. Both values are read on this
/// device's clock.
String? formatPastDay(DateTime at, {required DateTime now}) {
  final local = at.toLocal();
  final reference = now.toLocal();
  final days = calendarDaysBetween(local, reference);
  if (days <= 0) return null;
  if (days == 1) return 'yesterday';
  if (days < 7) return weekdayName(local);
  return formatShortDay(local, now: reference);
}

/// [formatPastDay] as a clause of a sentence: `yesterday`, `on Wednesday`, `on
/// Tue 29 Sep`. Null for today and for a day ahead.
String? formatPastDayOn(DateTime at, {required DateTime now}) {
  final words = formatPastDay(at, now: now);
  if (words == null) return null;
  return calendarDaysBetween(at.toLocal(), now.toLocal()) == 1
      ? words
      : 'on $words';
}

/// When a person did something, as a row says it: `2 h ago` through the day
/// (and through the half day before it, so a request made at 23:00 does not
/// read `yesterday` at 07:00), then [formatPastDay]: `yesterday`, `Wednesday`,
/// `Tue 29 Sep`.
///
/// One voice for who asked and when it came, so the same request reads the same
/// on the Home, in My requests and on the Seerr Overview. A time ahead of [now]
/// (two clocks that disagree) reads `just now`.
String formatDayWords(DateTime at, {required DateTime now}) {
  final local = at.toLocal();
  final past = formatPastDay(local, now: now);
  if (past == null || now.difference(local) < const Duration(hours: 12)) {
    return formatSampleAge(local, now: now);
  }
  return past;
}

/// [formatMediumDate] for a nullable field, answering null rather than echoing
/// something unparseable back.
///
/// A dense child row states its facts in a dot-separated line built from a
/// `List<String>`: there is no cell to leave blank, so a date the service did
/// not send (or sent in a shape no one can read) has to disappear from the
/// line entirely rather than print raw JSON at the user. The prose form itself
/// is [formatMediumDate]'s, so a row and the Details grid above it cannot
/// disagree about what a date looks like.
String? formatMediumDateOrNull(String? isoDate) {
  final raw = isoDate?.trim();
  if (raw == null || raw.isEmpty) return null;
  if (DateTime.tryParse(raw) == null) return null;
  return formatMediumDate(raw);
}
