import 'package:flutter/material.dart';

import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/date_format.dart';
import 'package:cupola/core/widgets/status_badge.dart';
import 'package:cupola/features/discover/domain/library_calendar.dart';

/// The calendar's thirty days as weeks, Monday to Sunday, on a window wide
/// enough to lay them side by side: each day its date and its things, a
/// line or two each, in its tone.
///
/// A day is one target that selects it; what it holds is read beside the
/// grid, so the things in it are a picture to the screen reader and a tip
/// under the pointer. Days before today are dimmed; the days of the last
/// week past the thirty are hatched, and the first of them says so.
class CalendarMonthGrid extends StatelessWidget {
  const CalendarMonthGrid({
    super.key,
    required this.weeks,
    required this.now,
    required this.window,
    required this.byDay,
    required this.selected,
    required this.onSelect,
  });

  /// The Mondays of the weeks to draw, as `calendarWeeks` gives them.
  final List<DateTime> weeks;
  final DateTime now;
  final CalendarWindow window;

  /// Each day's things, in the agenda's order.
  final Map<DateTime, List<CalendarEvent>> byDay;

  final DateTime selected;
  final ValueChanged<DateTime> onSelect;

  /// Past this many a day counts the rest: a week of one busy day should not
  /// push the next week off the window.
  static const _shown = 3;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    final today = DateTime(now.year, now.month, now.day);
    // The first hatched day says why, once.
    final beyond = weeks
        .expand(calendarWeekDays)
        .where((day) => day.isAfter(window.end))
        .firstOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ExcludeSemantics(
          child: Row(
            children: [
              for (final name in shortWeekdayNames)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.sm,
                      0,
                      AppSpacing.xs,
                      AppSpacing.sm,
                    ),
                    child: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.clip,
                      style: AppType.caption.copyWith(color: room.inkTertiary),
                    ),
                  ),
                ),
            ],
          ),
        ),
        for (final (index, monday) in weeks.indexed) ...[
          if (index > 0) const SizedBox(height: AppSpacing.sm),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (column, day) in calendarWeekDays(
                  monday,
                ).indexed) ...[
                  if (column > 0) const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: _Day(
                      day: day,
                      now: now,
                      today: today,
                      events: byDay[day] ?? const [],
                      inWindow: window.contains(day),
                      saysBeyond: day == beyond,
                      selected: day == selected,
                      onSelect: () => onSelect(day),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _Day extends StatelessWidget {
  const _Day({
    required this.day,
    required this.now,
    required this.today,
    required this.events,
    required this.inWindow,
    required this.saysBeyond,
    required this.selected,
    required this.onSelect,
  });

  final DateTime day;
  final DateTime now;
  final DateTime today;
  final List<CalendarEvent> events;
  final bool inWindow;
  final bool saysBeyond;
  final bool selected;
  final VoidCallback onSelect;

  /// Tall enough for two things at the reading size; a busier day grows
  /// its week.
  static const double _minHeight = 100;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    final before = day.isBefore(today);
    final isToday = day == today;
    final dim = before || !inWindow;
    final shown = events.length > CalendarMonthGrid._shown
        ? events.take(CalendarMonthGrid._shown - 1).toList()
        : events;
    final rest = events.length - shown.length;
    // The first of a month names it, `1 Oct`, never with a year: the grid
    // is thirty days long.
    final number = day.day == 1 ? formatDayMonthNoYear(day) : '${day.day}';

    final cell = Container(
      constraints: const BoxConstraints(minHeight: _minHeight),
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: dim ? null : room.slab,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: room.hair),
      ),
      // The ring over the border rather than in it, so a selected day's
      // things do not move.
      foregroundDecoration: selected
          ? BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: room.ink, width: 2),
            )
          : inWindow || before
          ? null
          : _Hatch(color: room.hair, radius: AppRadius.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: isToday
                    ? const EdgeInsets.symmetric(
                        horizontal: AppSpacing.xs + 1,
                        vertical: 1,
                      )
                    : EdgeInsets.zero,
                decoration: isToday
                    ? BoxDecoration(
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                        border: Border.all(color: room.ink, width: 1.5),
                      )
                    : null,
                child: Text(
                  number,
                  maxLines: 1,
                  style: AppType.label.copyWith(
                    color: dim ? room.inkDisabled : room.ink,
                  ),
                ),
              ),
              if (isToday) ...[
                const SizedBox(width: AppSpacing.xs),
                Flexible(
                  child: Text(
                    'Today',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.caption.copyWith(color: room.inkSecondary),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          if (inWindow) ...[
            for (final event in shown)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xs),
                child: _Thing(event: event, now: now),
              ),
            if (rest > 0)
              Padding(
                padding: const EdgeInsets.only(
                  top: AppSpacing.xs,
                  left: AppSpacing.xs,
                ),
                child: Text(
                  '$rest more',
                  style: AppType.caption.copyWith(color: room.inkSecondary),
                ),
              ),
          ] else if (saysBeyond) ...[
            const Spacer(),
            // Its own two lines, scaled down rather than broken inside a word
            // at a large reading size.
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.bottomLeft,
              child: Text(
                'Beyond the\n${CalendarWindow.days} days',
                style: AppType.caption.copyWith(color: room.inkTertiary),
              ),
            ),
          ],
        ],
      ),
    );

    final spoken = spokenDay(day, now);
    if (dim) {
      return Semantics(
        label:
            '$spoken, ${before ? 'before today' : 'beyond the ${CalendarWindow.days} days'}',
        child: ExcludeSemantics(child: cell),
      );
    }
    return Semantics(
      container: true,
      button: true,
      selected: selected,
      label:
          '$spoken, ${switch (events.length) {
            0 => 'nothing',
            1 => '1 thing',
            final count => '$count things',
          }}',
      onTap: onSelect,
      child: ExcludeSemantics(
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onSelect,
            child: cell,
          ),
        ),
      ),
    );
  }
}

/// One thing in a day: what kind of moment and its code over the title,
/// with its tone's dot, ringed while it has not come.
class _Thing extends StatelessWidget {
  const _Thing({required this.event, required this.now});

  final CalendarEvent event;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    final scheme = Theme.of(context).colorScheme;
    final state = event.state;
    final tone = statusToneColor(scheme, state.tone, surface: room.slab);
    final toned = state.stand == CalendarStand.inFlight;
    return Tooltip(
      message: calendarEventTip(event, now),
      waitDuration: const Duration(milliseconds: 400),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.xs + 2,
          AppSpacing.xs,
          AppSpacing.xs,
          AppSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: room.fillQuiet,
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: state.hollow ? null : tone,
                    border: state.hollow
                        ? Border.all(color: room.inkSecondary, width: 1.2)
                        : null,
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    calendarGridLead(event),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.micro.copyWith(
                      color: toned ? tone : room.inkSecondary,
                    ),
                  ),
                ),
              ],
            ),
            Text(
              event.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppType.caption
                  .weight(FontWeight.w600)
                  .copyWith(color: room.ink),
            ),
          ],
        ),
      ),
    );
  }
}

/// The diagonal hatch over a day past the thirty.
class _Hatch extends Decoration {
  const _Hatch({required this.color, required this.radius});

  final Color color;
  final double radius;

  @override
  BoxPainter createBoxPainter([VoidCallback? onChanged]) =>
      _HatchPainter(color, radius);
}

class _HatchPainter extends BoxPainter {
  _HatchPainter(this.color, this.radius);

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Offset offset, ImageConfiguration configuration) {
    final size = configuration.size;
    if (size == null) return;
    final rect = offset & size;
    canvas.save();
    canvas.clipRRect(RRect.fromRectAndRadius(rect, Radius.circular(radius)));
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    const gap = 10.0;
    for (var x = -size.height; x < size.width; x += gap) {
      canvas.drawLine(
        Offset(rect.left + x, rect.bottom),
        Offset(rect.left + x + size.height, rect.top),
        paint,
      );
    }
    canvas.restore();
  }
}
