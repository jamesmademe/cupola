/// When every source Activity reads last answered: the time the window's
/// chrome and the Needs you page say after `All 12 answered`.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/features/services/presentation/services_provider.dart'
    show dashboardDecisionsProvider, stallClockProvider;

/// The moment the sources Needs you reads (the same the Home's banner counts)
/// last stood with none still out, by the device's clock; null until then.
///
/// Stamped as the reads arrive rather than carried by them: Activity is read
/// again every quarter of a minute while it is on screen, so the time is
/// never older than the page.
class ActivityAnsweredAt extends Notifier<DateTime?> {
  @override
  DateTime? build() {
    ref.listen(dashboardDecisionsProvider, (_, next) {
      if (next.coverage.pending.isEmpty) state = ref.read(stallClockProvider)();
    });
    return ref.read(dashboardDecisionsProvider).coverage.pending.isEmpty
        ? ref.read(stallClockProvider)()
        : null;
  }
}

final activityAnsweredAtProvider =
    NotifierProvider.autoDispose<ActivityAnsweredAt, DateTime?>(
      ActivityAnsweredAt.new,
    );
