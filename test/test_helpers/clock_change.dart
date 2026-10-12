/// The days on which this machine's zone changes its clocks, found rather than
/// assumed, so a test about a day that is 23 h or 25 h long does not depend on
/// the zone being any one place.
///
/// A zone that never changes its clocks (UTC, most CI machines) has none: the
/// helpers answer null and the test that needs one skips itself, with the
/// reason. Run the suite with `TZ=Europe/Rome` (or any zone that does) to
/// exercise them.
library;

/// The local midnight that opens the day the clocks go forward, when that day
/// is 23 h long; null in a zone that has no such day in 2025 to 2028.
DateTime? springForwardDay() => _dayLasting(23);

/// The local midnight that opens the day the clocks go back, when that day is
/// 25 h long; null in a zone that has no such day in 2025 to 2028.
DateTime? fallBackDay() => _dayLasting(25);

/// Why a test that needs [springForwardDay] or [fallBackDay] was skipped.
const String noClockChange =
    'This zone does not change its clocks; run with TZ=Europe/Rome';

/// The local day [offset] days from [day], at [hour]:[minute].
DateTime dayAfter(DateTime day, int offset, {int hour = 0, int minute = 0}) =>
    DateTime(day.year, day.month, day.day + offset, hour, minute);

DateTime? _dayLasting(int hours) {
  for (var year = 2025; year <= 2028; year++) {
    for (var month = 1; month <= 12; month++) {
      for (var day = 1; day <= 31; day++) {
        final start = DateTime(year, month, day);
        if (start.month != month) break;
        final next = DateTime(year, month, day + 1);
        if (next.difference(start).inHours == hours) return start;
      }
    }
  }
  return null;
}
