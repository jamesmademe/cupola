import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/lifecycle/gated_poll.dart';
import 'package:cupola/core/lifecycle/page_activity.dart';
import 'package:cupola/core/status/read_clock.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// The time as of the last minute, renewed every minute for as long as
/// something listens to it.
///
/// An age is bucketed to the minute (`formatDurationAge`), so a figure that is
/// recomputed any faster repaints a page for an answer that did not change.
/// `autoDispose`, so its timer exists only while a page is printing an age: a
/// healthy page never watches it and never rebuilds on a clock.
///
/// The repeating work goes through `Ref.gatedPoll` because that is the only
/// place the app is allowed to construct it (`test/core/no_ungated_polling_test.dart`);
/// the page decides when it is listening, and [ReadAgeWatch.watchQueueReadAge]
/// listens only while the page is on screen.
///
/// Renewing is an invalidation of this provider itself, which re-reads the
/// time from the [ReadClock], so the clock a test hands the app is the clock
/// the age is measured by.
final minuteNowProvider = Provider.autoDispose<DateTime>((ref) {
  ref.gatedPoll(
    id: 'read_age.minute',
    interval: const Duration(minutes: 1),
    onTick: ref.invalidateSelf,
  );
  return ref.read(readClockProvider).now();
});

extension ReadAgeWatch on WidgetRef {
  /// How old the queue of [service] is, as the page draws it, or null when the
  /// rows are not stale.
  ///
  /// [underBand] is the page's own fact: it is showing the last queue it read
  /// beneath a fault band. Anywhere else the answer is null and the rows print
  /// the figures they were given, so a healthy page costs nothing and watches
  /// nothing here.
  ///
  /// Also null when there is no recorded read for the connection the page is
  /// reading: a row never claims an age nobody measured.
  ///
  /// The page rebuilds once a minute through [minuteNowProvider] while it is
  /// the page on screen; behind another tab or a pushed page it does not, and
  /// reads the time afresh when it comes back, which rebuilds it anyway.
  ///
  /// Must be called from `build`, for the dependencies it registers.
  Duration? watchQueueReadAge(
    BuildContext context,
    ServiceKey service, {
    required bool underBand,
  }) {
    if (!underBand) return null;
    final clock = read(readClockProvider);
    // The connection this page is reading, by the same lens the provider that
    // read it resolved.
    final at = clock.at(
      queueReadKey(service, effectiveInstanceId(this, service, null)),
    );
    if (at == null) return null;
    final now = watchPageActivity(context, this).isLive
        ? watch(minuteNowProvider)
        : clock.now();
    final age = now.difference(at);
    // A read stamped after the page's reading of the time (the two were taken
    // a frame apart) is not a negative age.
    return age.isNegative ? Duration.zero : age;
  }
}
