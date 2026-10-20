import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/app_breakpoints.dart';
import 'package:cupola/core/app_elevation.dart';
import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/text_scale.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/date_format.dart' show shortWeekdayName;
import 'package:cupola/core/utils/dot_separator.dart';
import 'package:cupola/core/title_light.dart';
import 'package:cupola/core/widgets/pressable_scale.dart';
import 'package:cupola/core/widgets/shimmer_placeholder.dart';
import 'package:cupola/core/widgets/status_badge.dart';
import 'package:cupola/features/discover/domain/library_calendar.dart';
import 'package:cupola/features/discover/presentation/widgets/calendar_week_strip.dart';
import 'package:cupola/features/settings/domain/connection_presentation.dart';
import 'package:cupola/features/media/presentation/shelf_page.dart';

/// A calendar that did not arrive, as the band says it: [words] in the
/// reader's voice (`Lidarr did not answer at 20:53`, `Can't reach the server
/// since 20:41`), [error] for its tone and glyph.
typedef CalendarBandSilence = ({String words, Object error});

/// The calendar's way in from the top of the Discover atrium: the one live
/// object there. Lit by the next release's artwork, it names the next thing
/// and dots this week; a connection whose calendar did not arrive is named
/// in one line. The whole band is one link, and one sentence.
///
/// [CalendarBand.loading] keeps the band's place while the calendars are
/// read, so the atrium under it does not jump when they arrive.
class CalendarBand extends ConsumerStatefulWidget {
  const CalendarBand({
    super.key,
    required this.events,
    required this.window,
    required this.now,
    required this.onTap,
    this.silent = const [],
    this.silentKinds = const {},
  }) : _loading = false;

  const CalendarBand.loading({
    super.key,
    required this.window,
    required this.now,
    required this.onTap,
  }) : events = const [],
       silent = const [],
       silentKinds = const {},
       _loading = true;

  /// The calendar's rows, sorted, inside [window].
  final List<CalendarEvent> events;
  final CalendarWindow window;
  final DateTime now;
  final VoidCallback onTap;

  /// The connections whose calendars did not arrive.
  final List<CalendarBandSilence> silent;

  /// The kinds they may be missing, for the band's sentence.
  final Set<CalendarKind> silentKinds;

  final bool _loading;

  /// The widest the week is drawn: as the widest phone draws it
  /// ([AppBreakpoints.splitList], less the band's margins and its padding),
  /// about 54 to a day. Wider, the seven days drift apart and stop reading
  /// as one week. (The band's hairline edges keep a phone's two points under
  /// it.)
  static const double weekMeasure =
      AppBreakpoints.splitList - 4 * AppSpacing.lg;

  /// The width inside the band from which the week goes beside the words:
  /// where the words keep at least the week's own measure. That is a band of
  /// about 840 with its margins: a tablet on its side or a desktop window
  /// draws one, no phone and no tablet's list beside a title does.
  static const double besideFrom = 2 * weekMeasure + AppSpacing.xl;

  /// The words' column where the week is drawn in posters.
  static const double postersHead = 220;

  /// The narrowest day of the posters' week: two posters side by side.
  static const double postersDay = 92;

  /// The width inside the band from which the week is seven days with their
  /// posters in them, beside the words (`W-Desk-Discover`): a desktop window,
  /// a tablet on its side. Narrower, the days are dots.
  static const double postersFrom =
      postersHead + AppSpacing.xl + 7 * postersDay + 6 * AppSpacing.sm;

  @override
  ConsumerState<CalendarBand> createState() => _CalendarBandState();
}

class _CalendarBandState extends ConsumerState<CalendarBand> {
  String? _drawn;

  void _posterDrawn(String url) {
    if (_drawn == url) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _drawn = url);
    });
  }

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    final scheme = Theme.of(context).colorScheme;
    final digest = CalendarDigest.of(widget.events, widget.now);
    final lead = digest.lead;
    final art = lead?.poster;
    // The light of artwork the band drew, read from the cache; a picture
    // behind a key is not read again for it.
    final light = _drawn != null && _drawn == art?.url && art?.headers == null
        ? ref.watch(titleLightProvider(_drawn!)).value?.light
        : null;
    final today = DateTime(widget.now.year, widget.now.month, widget.now.day);
    final monday = DateTime(
      today.year,
      today.month,
      today.day - (today.weekday - 1),
    );
    final week = calendarWeekDays(monday);
    final dots = <DateTime, CalendarDot>{
      for (final day in week)
        day: ?calendarDayDot([
          for (final event in widget.events)
            if (event.day == day) event,
        ]),
    };
    final line = digest.bandLine();
    // With no rows and a connection that did not answer, the band says
    // nothing of what is not there: only who did not answer.
    final unknown = lead == null && widget.silent.isNotEmpty;
    final empty = lead == null && !widget._loading && !unknown;

    // What the band says: the next thing, and its poster at the end of the
    // line; where the days carry their posters, the words alone.
    Widget headOf({required bool poster}) => Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      'Calendar',
                      style: AppType.section.copyWith(color: room.ink),
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded, color: scheme.primary),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              if (widget._loading)
                const Padding(
                  padding: EdgeInsets.only(top: 3),
                  child: SizedBox(
                    width: 180,
                    child: ShimmerPlaceholder(height: 12),
                  ),
                )
              else if (!unknown) ...[
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: line.lead,
                        style: AppType.label.copyWith(color: room.ink),
                      ),
                      TextSpan(
                        text: ' ${line.rest}',
                        style: AppType.label
                            .weight(FontWeight.w400)
                            .copyWith(color: room.inkSecondary),
                      ),
                    ],
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (empty)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.xs),
                    child: Text(
                      'See what’s coming out',
                      style: AppType.label.copyWith(color: scheme.primary),
                    ),
                  ),
              ],
            ],
          ),
        ),
        if (poster && art != null) ...[
          const SizedBox(width: AppSpacing.md),
          DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.thumb),
              boxShadow: AppElevation.poster(scheme, light: light),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.thumb),
              child: SizedBox(
                width: 36,
                height: 54,
                child: ShelfArtwork(
                  art: art,
                  box: const Size(36, 54),
                  onDrawn: _posterDrawn,
                  fallback: ColoredBox(color: room.raised),
                ),
              ),
            ),
          ),
        ],
      ],
    );
    final head = headOf(poster: true);
    final wordsHead = headOf(poster: false);
    final silentLines = [
      for (final silence in widget.silent) ...[
        const SizedBox(height: AppSpacing.sm),
        _SilentLine(silence: silence),
      ],
    ];
    final strip = CalendarWeekStrip.band(
      days: week,
      now: widget.now,
      window: widget.window,
      dots: dots,
    );

    final band = Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: room.slab,
        borderRadius: BorderRadius.circular(AppRadius.door),
        border: Border.all(color: room.hair),
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [
            Color.alphaBlend(
              (light ?? room.lamp).withValues(
                alpha: light == null ? 0.10 : 0.22,
              ),
              room.slab,
            ),
            room.slab,
          ],
        ),
      ),
      // The phone's band: the words over the week. Where the words would keep
      // at least the week's own measure beside it, the week goes beside them
      // instead, at the end of the band, and the band is one line tall.
      child: LayoutBuilder(
        builder: (context, box) {
          if (box.maxWidth >= CalendarBand.postersFrom && !widget._loading) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: CalendarBand.postersHead,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [wordsHead, ...silentLines],
                  ),
                ),
                const SizedBox(width: AppSpacing.xl),
                Expanded(
                  child: _PostersWeek(
                    events: widget.events,
                    now: widget.now,
                    window: widget.window,
                  ),
                ),
              ],
            );
          }
          if (box.maxWidth >= CalendarBand.besideFrom) {
            return Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [head, ...silentLines],
                  ),
                ),
                const SizedBox(width: AppSpacing.xl),
                SizedBox(width: CalendarBand.weekMeasure, child: strip),
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              head,
              ...silentLines,
              const SizedBox(height: AppSpacing.md),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: CalendarBand.weekMeasure,
                  ),
                  child: strip,
                ),
              ),
            ],
          );
        },
      ),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      child: PressableScale(
        onTap: widget.onTap,
        semanticLabel: widget._loading
            ? 'Calendar'
            : unknown
            ? [
                'Calendar',
                for (final silence in widget.silent) silence.words,
              ].join('. ')
            : digest.spokenBand(silent: widget.silentKinds),
        excludeChildSemantics: true,
        child: band,
      ),
    );
  }
}

/// A calendar that did not arrive, in the tone of its cause.
class _SilentLine extends StatelessWidget {
  const _SilentLine({required this.silence});

  final CalendarBandSilence silence;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    final scheme = Theme.of(context).colorScheme;
    final reason = classifyConnectionFailure(silence.error);
    return Row(
      children: [
        Icon(
          failureIcon(reason),
          size: 16,
          color: statusToneColor(
            scheme,
            failureTone(reason),
            surface: room.slab,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Flexible(
          child: Text(
            silence.words,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppType.meta.copyWith(color: room.inkSecondary),
          ),
        ),
      ],
    );
  }
}

/// The week where there is room for it: seven days from today, each a cell
/// with its day over the posters of what comes out on it; a day with one
/// thing names it under its poster, a day with more than its cell holds ends
/// on `+2`. Today's cell is lit. A picture, as the band's dots are: the band
/// is the one link and the one sentence.
class _PostersWeek extends StatelessWidget {
  const _PostersWeek({
    required this.events,
    required this.now,
    required this.window,
  });

  final List<CalendarEvent> events;
  final DateTime now;
  final CalendarWindow window;

  static const Size _poster = Size(34, 51);

  /// A day's cell at the default reading size: its day, a poster and two
  /// lines of a title under it. It grows with the words.
  static const double _height = 136;

  /// The cell from which a lone thing's title goes beside its poster.
  static const double _besideFrom = 120;

  @override
  Widget build(BuildContext context) {
    final today = DateTime(now.year, now.month, now.day);
    final days = [
      for (var i = 0; i < 7; i++)
        DateTime(today.year, today.month, today.day + i),
    ];
    return ExcludeSemantics(
      // Seven days cannot reflow: their words follow the reading size to the
      // single-line ceiling, as the week of dots does, and lay out on the
      // same clamp the cells grew by.
      child: MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaleMetrics.clampedScalerOf(
            context,
            maxScaleFactor: TextScaleMetrics.singleLineChromeMaxScaleFactor,
          ),
        ),
        child: SizedBox(
          height: TextScaleMetrics.boxHeight(
            context,
            base: _height,
            textHeight: 52,
            maxScaleFactor: TextScaleMetrics.singleLineChromeMaxScaleFactor,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (index, day) in days.indexed) ...[
                if (index > 0) const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: _DayCell(
                    day: day,
                    today: index == 0,
                    known: window.contains(day),
                    events: [
                      for (final event in events)
                        if (event.day == day) event,
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.today,
    required this.known,
    required this.events,
  });

  final DateTime day;
  final bool today;

  /// Inside the calendar's thirty days: past them nothing was read.
  final bool known;
  final List<CalendarEvent> events;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    final label = today
        ? 'Today$dotSeparator${day.day}'
        : '${shortWeekdayName(day)} ${day.day}';
    final quiet = events.isEmpty || !known;
    return Container(
      key: ValueKey('calendar-band-day-${day.day}'),
      padding: const EdgeInsets.all(AppSpacing.row),
      decoration: BoxDecoration(
        color: today ? room.fillControl : room.fillQuiet,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: today ? Border.all(color: room.edge) : null,
      ),
      // A last line that does not fit is cut at the cell's edge, never
      // drawn past it.
      clipBehavior: Clip.hardEdge,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppType.meta
                .weight(FontWeight.w600)
                .copyWith(color: quiet ? room.inkSecondary : room.ink),
          ),
          if (known && events.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            if (events.length == 1)
              // Its title beside the poster where the cell is wide, under
              // it where it is not: a title squeezed beside a poster broke
              // inside its words.
              LayoutBuilder(
                builder: (context, box) {
                  final beside = box.maxWidth >= _PostersWeek._besideFrom;
                  final style = AppType.meta
                      .weight(FontWeight.w600)
                      .copyWith(color: room.ink);
                  final title = events.single.title;
                  final words = Text(
                    title,
                    maxLines: beside ? 3 : 2,
                    overflow: TextOverflow.ellipsis,
                    textScaler: TextScaleMetrics.wholeWordScaler(
                      MediaQuery.textScalerOf(context),
                      text: title,
                      style: style,
                      width: beside
                          ? box.maxWidth -
                                _PostersWeek._poster.width -
                                AppSpacing.sm
                          : box.maxWidth,
                      maxLines: beside ? 3 : 2,
                    ),
                    style: style,
                  );
                  return beside
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _poster(context, events.single),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(child: words),
                          ],
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _poster(context, events.single),
                            const SizedBox(height: AppSpacing.xs),
                            words,
                          ],
                        );
                },
              )
            else
              LayoutBuilder(
                builder: (context, box) {
                  final step = _PostersWeek._poster.width + AppSpacing.xs;
                  final fits = ((box.maxWidth + AppSpacing.xs) / step)
                      .floor()
                      .clamp(1, events.length);
                  final shown = fits < events.length ? fits - 1 : fits;
                  final more = events.length - shown;
                  return Row(
                    children: [
                      for (final (index, event)
                          in events.take(shown).indexed) ...[
                        if (index > 0) const SizedBox(width: AppSpacing.xs),
                        _poster(context, event),
                      ],
                      if (more > 0) ...[
                        if (shown > 0) const SizedBox(width: AppSpacing.xs),
                        SizedBox.fromSize(
                          size: _PostersWeek._poster,
                          child: Center(
                            child: Text(
                              '+$more',
                              style: AppType.meta
                                  .weight(FontWeight.w600)
                                  .copyWith(color: room.inkSecondary),
                            ),
                          ),
                        ),
                      ],
                    ],
                  );
                },
              ),
          ],
        ],
      ),
    );
  }

  Widget _poster(BuildContext context, CalendarEvent event) {
    final room = CupolaRoom.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.thumb),
      child: SizedBox.fromSize(
        size: _PostersWeek._poster,
        child: ShelfArtwork(
          art: event.poster,
          box: _PostersWeek._poster,
          fallback: ColoredBox(color: room.raised),
        ),
      ),
    );
  }
}
