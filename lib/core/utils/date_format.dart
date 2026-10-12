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
    final date = DateTime.parse(isoDate);
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  } catch (_) {
    return isoDate;
  }
}

const List<String> _shortMonthNames = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

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

const List<String> _weekdayNames = [
  'Mon',
  'Tue',
  'Wed',
  'Thu',
  'Fri',
  'Sat',
  'Sun',
];

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

  final weekday = _weekdayNames[parsed.weekday - 1];
  final month = _shortMonthNames[parsed.month - 1];
  final day = '$weekday ${parsed.day} $month';
  return parsed.year == (now ?? DateTime.now()).year
      ? day
      : '$day ${parsed.year}';
}

/// [day] as a day and a month, `12 Sep`, with the year only when it is not
/// [now]'s: `12 Sep 2025`. For a day that is past and named with no weekday,
/// as `On the server since 12 Sep`.
String formatDayMonth(DateTime day, {DateTime? now}) {
  final words = '${day.day} ${_shortMonthNames[day.month - 1]}';
  return day.year == (now ?? DateTime.now()).year
      ? words
      : '$words ${day.year}';
}

/// The weekday of [day] in full: `Thursday`. For the Home's date and for
/// what a screen reader says of a day, where `Thu` would be read as letters.
String weekdayName(DateTime day) => _fullWeekdayNames[day.weekday - 1];

/// The month of [day] in full: `October`.
String monthName(DateTime day) => _fullMonthNames[day.month - 1];

const List<String> _fullWeekdayNames = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

const List<String> _fullMonthNames = [
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

/// A time of day as the brand book writes one: 24 h, `20:41`, on this
/// device's clock.
String formatClockTime(DateTime time) {
  final local = time.toLocal();
  return '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}';
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
