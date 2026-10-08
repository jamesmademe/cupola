import 'package:flutter/material.dart';

import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/string_utils.dart';
import 'package:cupola/core/widgets/pressable_scale.dart';
import 'package:cupola/core/widgets/status_badge.dart';
import 'package:cupola/features/discover/domain/library_calendar.dart';
import 'package:cupola/features/media/presentation/shelf_page.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// Past this reading size the lead column cannot hold its time beside the
/// row: it takes a line of its own above it.
const double _stackedScale = 1.4;

/// One dated thing of the calendar: when (an episode's time, or what kind
/// of day it is), its artwork, its name, where it stands, and who holds it.
/// The whole row is one target and speaks one sentence.
///
/// The operator's row names the connections that hold the thing; the
/// requester's ([CalendarRow.requester]) has no lead column and no service
/// names, a larger poster and its own note in their place. The Home's
/// ([CalendarRow.home]) leads with the day, carries an episode's time in its
/// status and stops at two lines.
class CalendarRow extends StatelessWidget {
  const CalendarRow({
    super.key,
    required this.event,
    required this.now,
    this.onTap,
  }) : _for = _RowFor.operator;

  /// The requester's row: a date and no time, no service names, the poster
  /// larger and the event's own note (`You asked for season 3 on Sat 26
  /// Sep`) in the sources' place.
  const CalendarRow.requester({
    super.key,
    required this.event,
    required this.now,
    this.onTap,
  }) : _for = _RowFor.requester;

  /// Coming up's row on the Home: the day in the lead column (`Today` over
  /// `29 Sep`), an episode's time at the head of its status (`21:00 · S3 E1
  /// · premiere · not aired`), and nothing under it: no sources, no bar, the
  /// figure of a download already in the status.
  const CalendarRow.home({
    super.key,
    required this.event,
    required this.now,
    this.onTap,
  }) : _for = _RowFor.home;

  final CalendarEvent event;

  /// The clock the row reads `out today` and `not aired` against.
  final DateTime now;

  final VoidCallback? onTap;

  final _RowFor _for;

  bool get _requester => _for == _RowFor.requester;
  bool get _home => _for == _RowFor.home;

  static const Size _poster = Size(36, 54);

  /// The lead column: an episode's `22:00`, or `Digital` over `all day`.
  static const double _leadWidth = 54;
  static const Size _posterLarge = Size(44, 66);

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    final scheme = Theme.of(context).colorScheme;
    final state = event.state;
    final toned = state.stand == CalendarStand.inFlight;
    final tone = statusToneColor(scheme, state.tone, surface: room.slab);
    final progress = !_home && state.queue?.showsProgress == true
        ? state.queue?.progress
        : null;
    final stacked = MediaQuery.textScalerOf(context).scale(1) > _stackedScale;
    final lead = _home
        ? (
            lead: calendarDayName(event.day, now),
            under: calendarDayMonth(event.day, now),
          )
        : event.lead();
    final leadWords = lead.under == null
        ? lead.lead
        : '${lead.lead} · ${lead.under}';

    // The dot sits on the first line of the status, however many it takes.
    final firstLine =
        MediaQuery.textScalerOf(context).scale(AppType.meta.fontSize ?? 13) *
        (AppType.meta.height ?? 1.4);
    final status = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(top: (firstLine - 7) / 2),
          child: _Dot(
            color: state.hollow || state.stand == CalendarStand.out
                ? room.inkSecondary
                : tone,
            hollow: state.hollow,
          ),
        ),
        const SizedBox(width: AppSpacing.s),
        Flexible(
          child: Text(
            _home && event.airsAt != null
                ? '${formatClockTime(event.airsAt!)} · ${event.statusLine(now)}'
                : event.statusLine(now),
            maxLines: stacked ? 3 : 2,
            overflow: TextOverflow.ellipsis,
            style: (toned ? AppType.meta.weight(FontWeight.w600) : AppType.meta)
                .copyWith(color: toned ? tone : room.inkSecondary),
          ),
        ),
      ],
    );
    final third = _home
        ? null
        : _requester || event.sources.isEmpty
        ? (event.note == null
              ? null
              : Text(
                  event.note!,
                  maxLines: stacked ? 3 : 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.meta.copyWith(color: room.inkSecondary),
                ))
        : Row(
            children: [
              Icon(event.kind.service.icon, size: 14, color: room.inkTertiary),
              const SizedBox(width: AppSpacing.xs),
              Flexible(
                child: Text(
                  event.sources.join(' · '),
                  maxLines: stacked ? 3 : 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.meta.copyWith(color: room.inkTertiary),
                ),
              ),
            ],
          );
    final words = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          event.title,
          maxLines: stacked ? 3 : 1,
          overflow: TextOverflow.ellipsis,
          style: AppType.row.copyWith(color: room.ink),
        ),
        const SizedBox(height: 3),
        status,
        if (third != null) ...[const SizedBox(height: 3), third],
        if (progress != null) ...[
          const SizedBox(height: AppSpacing.sm),
          // The time keeps at most 70% of the line, so a narrow row or a
          // large reading size cuts it rather than overflowing.
          LayoutBuilder(
            builder: (context, box) => Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(1.5),
                    child: LinearProgressIndicator(
                      value: progress.clamp(0, 1).toDouble(),
                      minHeight: 3,
                      backgroundColor: room.fillTrack,
                      valueColor: AlwaysStoppedAnimation(tone),
                    ),
                  ),
                ),
                if (state.finishesAt case final at?) ...[
                  const SizedBox(width: AppSpacing.md),
                  ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: box.maxWidth * 0.7),
                    child: Text(
                      '${_requester ? 'ready around' : 'around'} '
                      '${formatClockTime(at)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.caption
                          .weight(FontWeight.w600)
                          .copyWith(color: room.inkSecondary),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
    final size = _requester ? _posterLarge : _poster;
    final poster = ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.thumb),
      child: SizedBox.fromSize(
        size: event.kind == CalendarKind.album ? Size.square(size.width) : size,
        child: ShelfArtwork(
          art: event.poster,
          box: size,
          fallback: _Initials(title: event.title),
        ),
      ),
    );

    final Widget body;
    if (_requester) {
      body = Row(
        children: [
          poster,
          const SizedBox(width: AppSpacing.md),
          Expanded(child: words),
        ],
      );
    } else if (stacked) {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(leadWords, style: AppType.label.copyWith(color: room.ink)),
          const SizedBox(height: AppSpacing.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              poster,
              const SizedBox(width: AppSpacing.md),
              Expanded(child: words),
            ],
          ),
        ],
      );
    } else {
      body = Row(
        children: [
          SizedBox(
            width: _leadWidth,
            child: lead.under == null
                ? Text(
                    lead.lead,
                    maxLines: 1,
                    style: AppType.figureSmall.copyWith(color: room.ink),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // `Cinemas` is the longest word: it scales down
                      // rather than lose a letter.
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          lead.lead,
                          maxLines: 1,
                          style: AppType.label.copyWith(color: room.ink),
                        ),
                      ),
                      Text(
                        lead.under!,
                        maxLines: 1,
                        style: AppType.caption.copyWith(
                          color: room.inkTertiary,
                        ),
                      ),
                    ],
                  ),
          ),
          const SizedBox(width: AppSpacing.md),
          SizedBox(width: 40, child: Center(child: poster)),
          const SizedBox(width: AppSpacing.md),
          Expanded(child: words),
        ],
      );
    }

    return PressableScale(
      onTap: onTap,
      semanticLabel: event.spoken(now),
      excludeChildSemantics: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: Padding(
          // The Home's slab has its own margin; the row does not add one.
          padding: EdgeInsets.symmetric(
            horizontal: _home ? 0 : AppSpacing.md + 2,
            vertical: AppSpacing.md,
          ),
          child: body,
        ),
      ),
    );
  }
}

/// A day of the agenda: its name and date over the slab of its rows.
/// [highlighted] rings the slab, the day the strip has selected.
class CalendarDayGroup extends StatelessWidget {
  const CalendarDayGroup({
    super.key,
    required this.day,
    required this.now,
    required this.children,
    this.highlighted = false,
  });

  final DateTime day;
  final DateTime now;
  final List<Widget> children;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.xl,
            AppSpacing.lg,
            AppSpacing.sm,
          ),
          child: Semantics(
            header: true,
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.end,
              spacing: AppSpacing.sm,
              children: [
                Text(
                  calendarDayName(day, now),
                  style: AppType.figureSmall.copyWith(color: room.ink),
                ),
                Text(
                  calendarDayDate(day, now),
                  style: AppType.meta.copyWith(color: room.inkTertiary),
                ),
              ],
            ),
          ),
        ),
        AnimatedContainer(
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic,
          margin: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: room.slab,
            borderRadius: BorderRadius.circular(AppRadius.group),
            border: Border.all(
              color: highlighted ? room.inkSecondary : room.hair,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (index, child) in children.indexed) ...[
                if (index > 0) Divider(height: 1, color: room.hair),
                child,
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// A quiet line between days, `Nothing until Wed 21 Oct`, or at the end of
/// the thirty days: dashes either side of the words.
class CalendarQuietLine extends StatelessWidget {
  const CalendarQuietLine({super.key, required this.words});

  /// `Nothing until Wed 21 Oct` for a gap of [AgendaGap.until].
  CalendarQuietLine.until(DateTime day, {super.key})
    : words = 'Nothing until ${calendarShortDate(day)}';

  /// The end of the window.
  const CalendarQuietLine.end({super.key})
    : words = 'Nothing more in the next ${CalendarWindow.days} days';

  final String words;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    Widget dash(double width) => SizedBox(
      width: width,
      child: CustomPaint(painter: _Dashes(room.hair)),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.xl,
        AppSpacing.lg,
        0,
      ),
      child: Row(
        children: [
          dash(18),
          const SizedBox(width: AppSpacing.sm),
          // The words take what they need, the dashes what is left.
          Flexible(
            flex: 4,
            child: Text(
              words,
              style: AppType.meta.copyWith(color: room.inkTertiary),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: SizedBox(
              height: 1,
              child: CustomPaint(painter: _Dashes(room.hair)),
            ),
          ),
        ],
      ),
    );
  }
}

class _Dashes extends CustomPainter {
  _Dashes(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    final y = size.height / 2;
    for (var x = 0.0; x < size.width; x += 7) {
      canvas.drawLine(Offset(x, y), Offset(x + 4, y), paint);
    }
  }

  @override
  bool shouldRepaint(_Dashes old) => old.color != color;
}

/// A day's or a row's dot: filled in its tone, or a ring for a day that has
/// not come.
class _Dot extends StatelessWidget {
  const _Dot({required this.color, required this.hollow});

  final Color color;
  final bool hollow;

  @override
  Widget build(BuildContext context) => Container(
    width: 7,
    height: 7,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: hollow ? null : color,
      border: hollow ? Border.all(color: color, width: 1.5) : null,
    ),
  );
}

/// The initials of a thing with no artwork, on the plate.
class _Initials extends StatelessWidget {
  const _Initials({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    final initials = title
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty && RegExp(r'\w').hasMatch(word[0]))
        .take(2)
        .map((word) => word[0].toUpperCase())
        .join();
    return DecoratedBox(
      decoration: BoxDecoration(
        color: room.raised,
        border: Border.all(color: room.hair),
        borderRadius: BorderRadius.circular(AppRadius.thumb),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xs),
        child: Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              initials,
              maxLines: 1,
              style: AppType.label.copyWith(color: room.inkSecondary),
            ),
          ),
        ),
      ),
    );
  }
}

/// Which of [CalendarRow]'s three rows this is.
enum _RowFor { operator, requester, home }
