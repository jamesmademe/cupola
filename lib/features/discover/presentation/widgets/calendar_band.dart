import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/app_elevation.dart';
import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/title_light.dart';
import 'package:cupola/core/utils/string_utils.dart';
import 'package:cupola/core/widgets/pressable_scale.dart';
import 'package:cupola/core/widgets/shimmer_placeholder.dart';
import 'package:cupola/core/widgets/status_badge.dart';
import 'package:cupola/features/discover/domain/library_calendar.dart';
import 'package:cupola/features/discover/presentation/widgets/calendar_week_strip.dart';
import 'package:cupola/features/settings/domain/connection_presentation.dart';
import 'package:cupola/features/media/presentation/shelf_page.dart';

/// A connection the band names because its calendar did not arrive: its
/// name in a sentence, the failure, and when.
typedef CalendarBandSilence = ({String name, Object error, DateTime at});

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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
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
                        Icon(
                          Icons.chevron_right_rounded,
                          color: scheme.primary,
                        ),
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
                            style: AppType.label.copyWith(
                              color: scheme.primary,
                            ),
                          ),
                        ),
                    ],
                  ],
                ),
              ),
              if (art != null) ...[
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
          ),
          for (final silence in widget.silent) ...[
            const SizedBox(height: AppSpacing.sm),
            _SilentLine(silence: silence),
          ],
          const SizedBox(height: AppSpacing.md),
          CalendarWeekStrip.band(
            days: week,
            now: widget.now,
            window: widget.window,
            dots: dots,
          ),
        ],
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
                for (final silence in widget.silent)
                  failureHeadline(
                    classifyConnectionFailure(silence.error),
                    subject: silence.name,
                    gateway: accessGatewayOf(silence.error),
                  ),
              ].join('. ')
            : digest.spokenBand(silent: widget.silentKinds),
        excludeChildSemantics: true,
        child: band,
      ),
    );
  }
}

/// `Lidarr did not answer at 20:53`, in the tone of its cause.
class _SilentLine extends StatelessWidget {
  const _SilentLine({required this.silence});

  final CalendarBandSilence silence;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    final scheme = Theme.of(context).colorScheme;
    final reason = classifyConnectionFailure(silence.error);
    final words = failureHeadline(
      reason,
      subject: silence.name,
      gateway: accessGatewayOf(silence.error),
    );
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
            failureDidNotAnswer(reason)
                ? '$words at ${formatClockTime(silence.at)}'
                : words,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppType.meta.copyWith(color: room.inkSecondary),
          ),
        ),
      ],
    );
  }
}
