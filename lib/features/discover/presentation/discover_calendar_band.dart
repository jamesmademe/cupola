import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/features/discover/domain/library_calendar.dart';
import 'package:cupola/features/discover/presentation/library_calendar_provider.dart';
import 'package:cupola/features/discover/presentation/widgets/calendar_band.dart';

/// The atrium's band, over the calendar it opens: there whenever the
/// household has something the calendar can read, whatever Seerr says,
/// since the calendar comes from the arrs.
class DiscoverCalendarBand extends ConsumerWidget {
  const DiscoverCalendarBand({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(hasLibraryCalendarProvider)) return const SizedBox.shrink();
    void open() => context.push(ServiceRoutes.discoverCalendar);
    final now = ref.watch(calendarClockProvider)();
    final calendar = ref.watch(libraryCalendarProvider);
    final value = calendar.value;
    if (value == null) {
      return CalendarBand.loading(
        window: CalendarWindow.from(now),
        now: now,
        onTap: open,
      );
    }
    return CalendarBand(
      events: value.events,
      window: value.window,
      now: now,
      onTap: open,
      silent: [
        for (final silence in value.silent)
          (name: silence.name, error: silence.error, at: value.readAt),
      ],
      silentKinds: value.silentKinds,
    );
  }
}
