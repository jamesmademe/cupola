/// Coming up: what comes out or airs from today to three days on.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/features/discover/presentation/calendar_page.dart'
    show openCalendarEvent;
import 'package:cupola/features/discover/presentation/library_calendar_provider.dart';
import 'package:cupola/features/discover/presentation/widgets/calendar_agenda.dart';
import 'package:cupola/features/home/domain/coming_up.dart';
import 'package:cupola/features/home/presentation/widgets/home_module_frame.dart';
import 'package:cupola/features/home/presentation/widgets/home_module_parts.dart';
import 'package:cupola/features/services/domain/services_semantics.dart';
import 'package:cupola/features/services/domain/source_coverage.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';

/// Coming up: three rows of the calendar, today to three days on, then the
/// way to the Calendar.
///
/// Absent only without an arr that dates things; nothing in the window is a
/// calm line, not an absence. A connection that did not answer is named over
/// the rows: what it dates is missing here.
class HomeComingUpModule extends ConsumerWidget {
  const HomeComingUpModule({super.key});

  static const _title = 'Coming up';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(hasLibraryCalendarProvider)) return const SizedBox.shrink();
    final settings = ref.watch(currentSettingsProvider);
    final action = HomeModuleAction(
      'Calendar',
      () => context.go(ServiceRoutes.discoverCalendar),
    );

    final read = ref.watch(libraryCalendarProvider);
    final calendar = read.value;
    if (calendar == null) {
      if (read.hasError) {
        return HomeModuleFrame.silent(
          title: _title,
          coverage: SourceCoverage.merge([
            for (final instance in ref.watch(calendarConnectionsProvider))
              SourceCoverage.failure(
                instance.service,
                read.error,
                instanceId: instance.id,
                name: settings.connectionName(instance.id),
              ),
          ]),
          onRetry: () => _retry(ref),
        );
      }
      return const HomeModuleFrame.loading(title: _title);
    }

    final silent = SourceCoverage.merge([
      for (final source in calendar.silent)
        SourceCoverage.failure(
          source.service,
          source.error,
          instanceId: source.connectionId,
          name: settings.connectionName(source.connectionId),
        ),
    ]);
    if (calendar.answered.isEmpty && calendar.silent.isNotEmpty) {
      return HomeModuleFrame.silent(
        title: _title,
        coverage: silent,
        onRetry: () => _retry(ref),
      );
    }

    final now = calendar.readAt;
    final rows = comingUpOf(calendar.events, now);
    final shown = rows.take(comingUpRowLimit).toList(growable: false);
    final note = calendar.silent.isEmpty
        ? null
        : coverageFailureSentence(silent);

    return HomeModuleFrame(
      title: _title,
      action: action,
      semanticLabel: joinSpokenParts([
        _title,
        if (rows.isEmpty) comingUpCalmLine(now),
        ?note,
      ]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (note != null) HomeCoverageNote(note: note, coverage: silent),
          if (shown.isEmpty)
            _NothingComingUp(now: now)
          else
            for (final (index, event) in shown.indexed)
              _Divided(
                divided: index > 0,
                child: CalendarRow.home(
                  key: ValueKey(event.identity),
                  event: event,
                  now: now,
                  onTap: () => openCalendarEvent(context, event),
                ),
              ),
        ],
      ),
    );
  }

  static void _retry(WidgetRef ref) {
    ref.invalidate(calendarSourceProvider);
    ref.invalidate(libraryCalendarProvider);
  }
}

/// A hairline over every row but the first.
class _Divided extends StatelessWidget {
  const _Divided({required this.divided, required this.child});

  final bool divided;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!divided) return child;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: CupolaRoom.of(context).hair)),
      ),
      child: child,
    );
  }
}

/// Nothing in the window: said calmly, with where the rest is.
class _NothingComingUp extends StatelessWidget {
  const _NothingComingUp({required this.now});

  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    return ExcludeSemantics(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              comingUpCalmLine(now),
              style: AppType.row
                  .weight(FontWeight.w600)
                  .copyWith(color: room.ink),
            ),
            const SizedBox(height: 2),
            Text(
              'The calendar has the rest of the month.',
              style: AppType.meta.copyWith(color: room.inkSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
