import 'package:flutter/material.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/status_badge.dart';
import 'package:cupola/features/discover/domain/library_calendar.dart';

/// A day's dot in the strip: its tone, and a ring while nothing of it has
/// come.
typedef CalendarDot = ({StatusTone tone, bool hollow});

/// A week of the calendar, Monday to Sunday: each day's letter and date,
/// and a dot under every day that has something, in that day's most
/// pressing tone. Days before today and past the thirty days are dimmed.
///
/// On the atrium's band ([CalendarWeekStrip.band]) it is a picture: today
/// ringed, nothing to tap, nothing for a screen reader (the band speaks one
/// sentence). On the calendar's page each day is a toggle that selects it.
class CalendarWeekStrip extends StatelessWidget {
  const CalendarWeekStrip({
    super.key,
    required this.days,
    required this.now,
    required this.window,
    required this.dots,
    required this.selected,
    required this.onSelect,
    required this.countOf,
  }) : _band = false;

  const CalendarWeekStrip.band({
    super.key,
    required this.days,
    required this.now,
    required this.window,
    required this.dots,
  }) : selected = null,
       onSelect = null,
       countOf = null,
       _band = true;

  /// The seven days, Monday first.
  final List<DateTime> days;
  final DateTime now;
  final CalendarWindow window;
  final Map<DateTime, CalendarDot> dots;

  /// The selected day, filled; null on the band.
  final DateTime? selected;
  final ValueChanged<DateTime>? onSelect;

  /// How many things [day] has, for the day's spoken name.
  final int Function(DateTime day)? countOf;

  final bool _band;

  static const _letters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
  static const _names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const double _disc = 34;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    final scheme = Theme.of(context).colorScheme;
    final today = DateTime(now.year, now.month, now.day);
    return Row(
      children: [
        for (final (index, day) in days.indexed)
          Expanded(child: _day(context, room, scheme, index, day, today)),
      ],
    );
  }

  Widget _day(
    BuildContext context,
    CupolaRoom room,
    ColorScheme scheme,
    int index,
    DateTime day,
    DateTime today,
  ) {
    final before = day.isBefore(today);
    final outside = !window.contains(day);
    final isToday = day == today;
    final isSelected = !_band && day == selected;
    final dot = dots[day];
    final dim = before || outside;
    final numberColor = isSelected
        ? room.onInk
        : dim
        ? room.inkDisabled
        : room.ink;
    final cell = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          _band ? _letters[index] : _names[index],
          maxLines: 1,
          style: AppType.caption.copyWith(
            color: dim ? room.inkDisabled : room.inkTertiary,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Container(
          width: _disc,
          height: _disc,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isSelected ? room.ink : null,
            border: isToday && !isSelected
                ? Border.all(color: room.ink, width: 1.5)
                : null,
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              '${day.day}',
              style: AppType.label.copyWith(color: numberColor),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        SizedBox(
          height: 6,
          child: dot == null || dim
              ? null
              : Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: dot.hollow
                        ? null
                        : statusToneColor(scheme, dot.tone, surface: room.slab),
                    border: dot.hollow
                        ? Border.all(color: room.inkSecondary, width: 1.2)
                        : null,
                  ),
                ),
        ),
      ],
    );
    if (_band) return ExcludeSemantics(child: cell);

    final spoken = spokenDay(day, now);
    if (dim) {
      return Semantics(
        label:
            '$spoken, ${before ? 'before today' : 'beyond the ${CalendarWindow.days} days'}',
        child: ExcludeSemantics(child: cell),
      );
    }
    final count = countOf?.call(day) ?? 0;
    return Semantics(
      container: true,
      button: true,
      toggled: isSelected,
      label:
          '$spoken, ${switch (count) {
            0 => 'nothing',
            1 => '1 thing',
            _ => '$count things',
          }}',
      onTap: () => onSelect?.call(day),
      child: ExcludeSemantics(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => onSelect?.call(day),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: cell,
          ),
        ),
      ),
    );
  }
}
