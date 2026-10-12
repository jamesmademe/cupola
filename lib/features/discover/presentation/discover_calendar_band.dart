import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/capability/audience.dart';
import 'package:cupola/core/capability/role_gate_provider.dart';
import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/utils/date_format.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/core/widgets/brief_failure_line.dart';
import 'package:cupola/features/discover/domain/library_calendar.dart';
import 'package:cupola/features/discover/presentation/library_calendar_provider.dart';
import 'package:cupola/features/discover/presentation/widgets/calendar_band.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// The atrium's band, over the calendar it opens: the operator's whenever
/// the household has something the calendar can read, whatever Seerr says,
/// since it comes from the arrs; the requester's from her requests.
class DiscoverCalendarBand extends ConsumerWidget {
  const DiscoverCalendarBand({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(hasCalendarProvider)) return const SizedBox.shrink();
    void open() => context.push(ServiceRoutes.discoverCalendar);
    final now = ref.watch(calendarClockProvider)();
    final calendar = ref.watch(calendarProvider);
    final value = calendar.value;
    if (value == null) {
      if (calendar.error case final error?) {
        // Only the requester's calendar fails whole: her Seerr is its one
        // source, and she reads its silence in her own words.
        return CalendarBand(
          events: const [],
          window: CalendarWindow.from(now),
          now: now,
          onTap: open,
          silent: [
            (
              words: BriefFailureLine.wordsFor(
                classifyConnectionFailure(error),
                since: now,
              ).headline,
              error: error,
            ),
          ],
        );
      }
      return CalendarBand.loading(
        window: CalendarWindow.from(now),
        now: now,
        onTap: open,
      );
    }
    final requester = ref.watch(audienceProvider) == Audience.requester;
    return CalendarBand(
      events: value.events,
      window: value.window,
      now: now,
      onTap: open,
      silent: [
        for (final silence in value.silent)
          (
            words: _silentWords(silence, value.readAt, requester: requester),
            error: silence.error,
          ),
      ],
      silentKinds: value.silentKinds,
    );
  }

  /// `Lidarr did not answer at 20:53`, or the requester's line.
  static String _silentWords(
    CalendarSilence silence,
    DateTime at, {
    required bool requester,
  }) {
    final reason = classifyConnectionFailure(silence.error);
    if (requester) {
      return BriefFailureLine.wordsFor(
        reason,
        since: at,
        service: ServiceKey.seerr,
      ).headline;
    }
    final words = failureHeadline(
      reason,
      subject: silence.name,
      gateway: accessGatewayOf(silence.error),
    );
    return failureDidNotAnswer(reason)
        ? '$words at ${formatClockTime(at)}'
        : words;
  }
}
