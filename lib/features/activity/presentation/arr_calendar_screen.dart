import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/widgets/app_empty_state.dart';
import 'package:cupola/core/widgets/app_error_state.dart';
import 'package:cupola/core/widgets/app_skeleton.dart';
import 'package:cupola/core/widgets/floating_bottom_nav_bar.dart';
import 'package:cupola/core/widgets/not_configured_placeholder.dart';
import 'package:cupola/features/discover/domain/library_calendar.dart';
import 'package:cupola/features/discover/presentation/calendar_page.dart';
import 'package:cupola/features/discover/presentation/library_calendar_provider.dart';
import 'package:cupola/features/discover/presentation/widgets/calendar_agenda.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// The Calendar tab of Radarr, Sonarr, Lidarr and Readarr: the calendar of
/// Discover filtered to the connection the lens is on. The same rows, the
/// same days and quiet lines, the same thirty days from local midnight; no
/// connection is named on a row, since the room is the connection's.
class ArrCalendarScreen extends ConsumerWidget {
  const ArrCalendarScreen({
    super.key,
    required this.service,
    this.topPadding = 0,
  });

  final ServiceKey service;
  final double topPadding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Before the provider: a calendar of nothing set up can only fail.
    if (!ref.watch(currentSettingsProvider).isServiceConfigured(service)) {
      return NotConfiguredPlaceholder.forService(service);
    }
    final lens = ref.watch(activeInstanceProvider(service));
    if (lens == null) return NotConfiguredPlaceholder.forService(service);
    final now = ref.watch(calendarClockProvider)();
    final key = (
      service: service,
      connectionId: lens.id,
      from: ref.watch(calendarDayProvider),
    );
    final reading = ref.watch(calendarSourceProvider(key));
    final window = CalendarWindow.from(key.from);

    final List<Widget> body;
    switch (reading) {
      case AsyncValue(:final value?):
        // The room is the connection's: no row names it.
        final events = libraryCalendarEvents(
          [
            CalendarReading(
              service: value.service,
              connectionId: value.connectionId,
              label: '',
              records: value.records,
              queue: value.queue,
              poster: value.poster,
            ),
          ],
          window,
          now,
        );
        body = events.isEmpty
            ? [
                const AppEmptyState(
                  icon: Icons.calendar_month_rounded,
                  title: 'Nothing scheduled',
                  message: 'The next 30 days are clear on this service.',
                ),
              ]
            : [
                for (final entry in calendarAgenda(events, window))
                  switch (entry) {
                    AgendaDay(:final day, events: final rows) =>
                      CalendarDayGroup(
                        day: day,
                        now: now,
                        children: [
                          for (final event in rows)
                            CalendarRow(
                              event: event,
                              now: now,
                              onTap: event.target == null
                                  ? null
                                  : () => openCalendarEvent(context, event),
                            ),
                        ],
                      ),
                    AgendaGap(:final until) => CalendarQuietLine.until(until),
                    AgendaEnd() => const CalendarQuietLine.end(),
                  },
              ];
      case AsyncValue(:final error?):
        body = [
          AppErrorState(
            error: error,
            onRetry: () => ref.invalidate(calendarSourceProvider(key)),
            serviceName: service.title,
            service: service,
            instanceId: lens.id,
          ),
        ];
      default:
        body = [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: AppSkeleton.listRows(count: 6),
          ),
        ];
    }

    // The band above the tab bar reaches below the phone's top inset, which
    // the router's constant does not count.
    final top = topPadding + MediaQuery.paddingOf(context).top;
    return RefreshIndicator(
      edgeOffset: top,
      onRefresh: () async {
        ref.invalidate(calendarDayProvider);
        ref.invalidate(calendarSourceProvider(key));
        try {
          await ref.read(calendarSourceProvider(key).future);
        } catch (_) {
          // The failure is drawn in place.
        }
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.only(
          top: top,
          bottom:
              FloatingNavBarMetrics.getScrollViewBottomPadding(context) +
              AppSpacing.xl,
        ),
        children: body,
      ),
    );
  }
}
