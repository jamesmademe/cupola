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
import 'package:cupola/features/home/data/home_last_known.dart';
import 'package:cupola/features/home/data/last_known/coming_up_last_known.dart';
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

    // The live answer, or until it comes the last drawing (a cold start).
    final read = ref.watchOrLastKnown(
      libraryCalendarProvider,
      comingUpLastKnown,
    );
    final live = read.live;
    final calendar = read.value;
    final known = read.asOf;

    /// Each connection that did not answer a read, in the words of why.
    SourceCoverage silenceOf(LibraryCalendar read) => SourceCoverage.merge([
      for (final source in read.silent)
        SourceCoverage.failure(
          source.service,
          source.error,
          instanceId: source.connectionId,
          name: settings.connectionName(source.connectionId),
        ),
    ]);

    // The live read failed, or answered with no connection answering (a
    // drawing then stands over it, in the live read's words).
    final liveFailed = live.hasError || read.silent;

    /// The whole read failed: every connection named, in the words of why.
    SourceCoverage failed() => read.silent
        ? silenceOf(live.value!)
        : SourceCoverage.merge([
            for (final instance in ref.watch(calendarConnectionsProvider))
              SourceCoverage.failure(
                instance.service,
                live.error,
                instanceId: instance.id,
                name: settings.connectionName(instance.id),
              ),
          ]);
    Widget unanswered() => liveFailed
        ? HomeModuleFrame.silent(
            title: _title,
            coverage: failed(),
            onRetry: () => _retry(ref),
          )
        : const HomeModuleFrame.loading(title: _title);

    if (calendar == null) return unanswered();

    final silent = silenceOf(calendar);
    if (calendar.answered.isEmpty && calendar.silent.isNotEmpty) {
      return HomeModuleFrame.silent(
        title: _title,
        coverage: silent,
        onRetry: () => _retry(ref),
      );
    }

    // A drawing is drawn at the time it is drawn, never at the time it was
    // read: "Today" and "airs at 21:00" are said against now.
    final now = known == null
        ? calendar.readAt
        : ref.watch(calendarClockProvider)();
    final rows = known == null
        ? comingUpOf(calendar.events, now)
        : comingUpAsDrawn(calendar.events, now);
    // A drawing with nothing left to draw once its window is cut again says
    // nothing, not "nothing comes out": the live answer decides that.
    if (known != null && rows.isEmpty) return unanswered();

    final shown = rows.take(comingUpRowLimit).toList(growable: false);
    final note = calendar.silent.isEmpty
        ? null
        : coverageFailureSentence(silent);
    List<Widget> rowsOf() => [
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
    ];

    // The last drawing whose live read failed: the rows it knew, at full ink,
    // over the failure in its own words.
    if (known != null && liveFailed) {
      return LastKnownMark(
        asOf: known,
        checking: false,
        child: HomeModuleFrame.silent(
          title: _title,
          coverage: failed(),
          onRetry: () => _retry(ref),
          child: Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: rowsOf(),
            ),
          ),
        ),
      );
    }

    return LastKnownMark(
      asOf: known,
      checking: true,
      child: HomeModuleFrame(
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
            if (shown.isEmpty) _NothingComingUp(now: now) else ...rowsOf(),
          ],
        ),
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
