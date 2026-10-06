import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/app_animation.dart';
import 'package:cupola/core/app_gradients.dart';
import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/capability/audience.dart';
import 'package:cupola/core/capability/role_gate_provider.dart';
import 'package:cupola/core/models/media_preview.dart';
import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/title_light.dart';
import 'package:cupola/core/utils/arr_model_helpers.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/core/utils/string_utils.dart';
import 'package:cupola/core/widgets/ambient_scaffold.dart';
import 'package:cupola/core/widgets/app_empty_state.dart';
import 'package:cupola/core/widgets/app_skeleton.dart';
import 'package:cupola/core/widgets/brief_failure_line.dart';
import 'package:cupola/core/widgets/failure_remedy.dart';
import 'package:cupola/core/widgets/floating_bottom_nav_bar.dart';
import 'package:cupola/core/widgets/glass_app_bar.dart';
import 'package:cupola/core/widgets/pressable_scale.dart';
import 'package:cupola/core/widgets/selection_pills.dart';
import 'package:cupola/core/widgets/status_badge.dart';
import 'package:cupola/features/discover/domain/library_calendar.dart';
import 'package:cupola/features/discover/presentation/catalog_providers.dart';
import 'package:cupola/features/discover/presentation/discover_provider.dart';
import 'package:cupola/features/discover/presentation/library_calendar_provider.dart';
import 'package:cupola/features/discover/presentation/widgets/calendar_agenda.dart';
import 'package:cupola/features/discover/presentation/widgets/calendar_week_strip.dart';
import 'package:cupola/features/discover/presentation/widgets/discover_carousel.dart';
import 'package:cupola/features/discover/presentation/widgets/seerr_not_set_up.dart';
import 'package:cupola/features/media/presentation/media_facts_sections.dart';
import 'package:cupola/features/media/presentation/media_parts.dart';
import 'package:cupola/features/media/presentation/open_media.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/connection_presentation.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// The calendar of everything the household's arrs date in the next thirty
/// days, at `/discover/calendar`: what this week holds, the week's strip,
/// the kinds as chips, then the agenda day by day.
class CalendarPage extends ConsumerStatefulWidget {
  const CalendarPage({super.key});

  @override
  ConsumerState<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends ConsumerState<CalendarPage> {
  final _scroll = ScrollController();
  final _days = <DateTime, GlobalKey>{};

  /// The chip: one kind, or every kind.
  CalendarKind? _kind;

  /// The strip's page, 0 for the week today is in.
  int _week = 0;

  /// The day the strip has selected; today until another is tapped.
  DateTime? _selected;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _readAgain() {
    ref.invalidate(calendarDayProvider);
    ref.invalidate(calendarSourceProvider);
    ref.invalidate(activeRequestsForProvider);
    ref.invalidate(requesterCalendarProvider);
  }

  bool get _reduceMotion => MediaQuery.disableAnimationsOf(context);

  /// Selects [day], and brings its rows (or the next day's, when it has
  /// none) into view.
  void _select(DateTime day, List<CalendarEvent> events) {
    setState(() => _selected = day);
    final target = events
        .map((event) => event.day)
        .where((d) => !d.isBefore(day))
        .firstOrNull;
    final context = target == null ? null : _days[target]?.currentContext;
    if (context == null) return;
    Scrollable.ensureVisible(
      context,
      alignment: 0.15,
      duration: _reduceMotion ? Duration.zero : AppAnimation.durationMd,
      curve: AppAnimation.standardCurve,
    );
  }

  void _today(CalendarWindow window) {
    setState(() {
      _week = 0;
      _selected = window.start;
    });
    if (!_scroll.hasClients) return;
    if (_reduceMotion) {
      _scroll.jumpTo(0);
    } else {
      _scroll.animateTo(
        0,
        duration: AppAnimation.durationMd,
        curve: AppAnimation.standardCurve,
      );
    }
  }

  void _open(CalendarEvent event) {
    switch (event.target) {
      case CalendarMediaTarget(:final key, :final connectionId):
        context.openMedia(key, focus: connectionId);
      case CalendarShelfTarget(:final service, :final connectionId, :final id):
        // A person's shelf lives under its service's tab, in another branch.
        context.go(switch (service) {
          ServiceKey.readarr => ServiceRoutes.readarrAuthor(
            id,
            instanceId: connectionId,
          ),
          _ => ServiceRoutes.lidarrArtist(id, instanceId: connectionId),
        });
      case null:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    final requester = ref.watch(audienceProvider) == Audience.requester;
    final calendar = ref.watch(calendarProvider);
    final value = calendar.value;
    final now = ref.watch(calendarClockProvider)();
    final window = value?.window ?? CalendarWindow.from(now);
    final top = MediaQuery.paddingOf(context).top;
    final bottom = FloatingNavBarMetrics.getScrollViewBottomPadding(context);

    if (!ref.watch(hasCalendarProvider)) {
      return AmbientScaffold(
        body: ListView(
          padding: EdgeInsets.fromLTRB(
            AppSpacing.lg,
            top + AppSpacing.md,
            AppSpacing.lg,
            bottom,
          ),
          children: [
            const Align(
              alignment: Alignment.centerLeft,
              child: MediaBackPlate(),
            ),
            const SizedBox(height: AppSpacing.xxl),
            AppEmptyState(
              icon: Icons.calendar_month_rounded,
              title: 'Nothing to put on a calendar yet',
              message:
                  'Set up Radarr, Sonarr, Lidarr or Readarr to see what '
                  'comes out and airs in the next ${CalendarWindow.days} '
                  'days.',
              action: FilledButton(
                // `go`: Connections lives in the Settings branch.
                onPressed: () => context.go(ServiceRoutes.settingsConnections),
                child: const Text('Set up a service'),
              ),
            ),
          ],
        ),
      );
    }

    final events = value?.of(_kind) ?? const <CalendarEvent>[];
    final all = value?.events ?? const <CalendarEvent>[];
    final digest = CalendarDigest.of(all, now);
    final art = digest.lead?.poster;
    final light = art == null || art.headers != null || art.url.isEmpty
        ? null
        : ref.watch(titleLightProvider(art.url)).value;
    final selected = _selected ?? window.start;
    final weeks = calendarWeeks(window);
    final week = _week.clamp(0, weeks.length - 1);
    final days = calendarWeekDays(weeks[week]);
    final byDay = <DateTime, List<CalendarEvent>>{};
    for (final event in events) {
      (byDay[event.day] ??= []).add(event);
    }

    final slivers = <Widget>[
      SliverPadding(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.lg,
          top + AppSpacing.md,
          AppSpacing.lg,
          0,
        ),
        sliver: SliverToBoxAdapter(
          child: _Head(
            calendar: value,
            digest: digest,
            loading: calendar.isLoading && value == null,
            requester: requester,
            onToday: () => _today(window),
          ),
        ),
      ),
      if (value != null)
        for (final silence in value.silent)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.sm,
              AppSpacing.lg,
              0,
            ),
            sliver: SliverToBoxAdapter(
              child: _SilentSource(
                silence: silence,
                onRetry: () => ref.invalidate(
                  calendarSourceProvider((
                    service: silence.service,
                    connectionId: silence.connectionId,
                    from: window.start,
                  )),
                ),
              ),
            ),
          ),
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.sm,
            AppSpacing.lg,
            AppSpacing.sm,
            0,
          ),
          child: _WeekPager(
            index: week,
            count: weeks.length,
            monday: weeks[week],
            onPage: (index) => setState(() => _week = index),
          ),
        ),
      ),
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        sliver: SliverToBoxAdapter(
          child: CalendarWeekStrip(
            days: days,
            now: now,
            window: window,
            dots: {
              for (final day in days) day: ?calendarDayDot(byDay[day] ?? []),
            },
            selected: selected,
            onSelect: (day) => _select(day, events),
            countOf: (day) => byDay[day]?.length ?? 0,
          ),
        ),
      ),
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.sm,
          AppSpacing.lg,
          0,
        ),
        sliver: SliverToBoxAdapter(
          child: Semantics(
            liveRegion: true,
            child: Text(
              _selectedLine(selected, byDay, events, now),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppType.meta.copyWith(color: room.inkSecondary),
            ),
          ),
        ),
      ),
      if (value != null)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(top: AppSpacing.lg),
            child: _Kinds(
              calendar: value,
              requester: requester,
              selected: _kind,
              onSelected: (kind) => setState(() => _kind = kind),
            ),
          ),
        ),
      if (value == null && calendar.error != null)
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.xl,
            AppSpacing.lg,
            0,
          ),
          // Only the requester's calendar fails whole: her Seerr is its one
          // source.
          sliver: SliverToBoxAdapter(
            child: BriefFailureLine.line(
              error: calendar.error,
              onRetry: _readAgain,
              service: ServiceKey.seerr,
            ),
          ),
        )
      else if (value == null)
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.xl,
            AppSpacing.lg,
            0,
          ),
          sliver: SliverToBoxAdapter(child: AppSkeleton.listRows(count: 5)),
        )
      else
        for (final entry in calendarAgenda(events, window))
          SliverToBoxAdapter(
            child: switch (entry) {
              AgendaDay(:final day, events: final rows) => CalendarDayGroup(
                key: _days.putIfAbsent(day, GlobalKey.new),
                day: day,
                now: now,
                highlighted: day == selected && _selected != null,
                children: [
                  for (final event in rows)
                    requester
                        ? CalendarRow.requester(
                            event: event,
                            now: now,
                            onTap: event.target == null
                                ? null
                                : () => _open(event),
                          )
                        : CalendarRow(
                            event: event,
                            now: now,
                            onTap: event.target == null
                                ? null
                                : () => _open(event),
                          ),
                ],
              ),
              AgendaGap(:final until) => CalendarQuietLine.until(until),
              AgendaEnd() => const CalendarQuietLine.end(),
            },
          ),
      if (value != null)
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.lg,
            0,
          ),
          sliver: SliverToBoxAdapter(
            child: Text(
              requester
                  ? 'Dates are for ${regionName(ref.watch(regionProvider))}. '
                        'Episodes have a date here, not a time.'
                  : _timesNote(value.kinds),
              style: AppType.meta.copyWith(color: room.inkTertiary),
            ),
          ),
        ),
      if (watchSeerrConfigured(ref))
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xxl),
            child: DiscoverCarousel(
              title: requester
                  ? 'Coming out, not on the server'
                  : 'Coming out, not on your server',
              subtitle: requester
                  ? 'Most popular first. Ask for one and you’ll be told when '
                        'it’s ready.'
                  : 'From Seerr, most popular first.',
              sectionId: 'coming_out',
              // What is on the calendar already is not coming out for you.
              items: ref
                  .watch(comingOutProvider)
                  .whenData(
                    (items) => [
                      for (final item in items)
                        if (!all.any(
                          (event) =>
                              event.tmdbId == item.id &&
                              (event.kind == CalendarKind.movie) ==
                                  (item.mediaType == 'movie'),
                        ))
                          item,
                    ],
                  ),
              onRetry: () => ref.invalidate(comingSoonProvider),
              metaOf: (item) => _comingOut(item, now),
            ),
          ),
        ),
      SliverToBoxAdapter(child: SizedBox(height: bottom + AppSpacing.xl)),
    ];

    return AmbientScaffold(
      accent: light?.light,
      body: Stack(
        children: [
          // The next release lights the head of the page, as it lit the
          // band that opened it.
          if (light != null)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: top + 420,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: AppGradients.serviceGlow(
                      light.light,
                      center: const Alignment(0.6, -1),
                      radius: 1.3,
                      alpha: 0.28,
                    ),
                  ),
                ),
              ),
            ),
          RefreshIndicator(
            edgeOffset: top,
            onRefresh: () async {
              _readAgain();
              await ref.read(calendarProvider.future);
            },
            child: CustomScrollView(
              controller: _scroll,
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: slivers,
            ),
          ),
          const Positioned(top: 0, left: 0, right: 0, child: StatusBarScrim()),
        ],
      ),
    );
  }

  /// What the selected day holds, under the strip: `Fri 2 Oct · Sintel
  /// (Anniversary Edition), album · Cosmos Laundromat S3 E1 at 21:00`; an
  /// empty day names the next one.
  String _selectedLine(
    DateTime day,
    Map<DateTime, List<CalendarEvent>> byDay,
    List<CalendarEvent> events,
    DateTime now,
  ) {
    final name = calendarDayName(day, now) == 'Today'
        ? 'Today'
        : calendarShortDate(day);
    final rows = byDay[day];
    if (rows != null && rows.isNotEmpty) {
      return [
        name,
        for (final event in rows) calendarEventShort(event),
      ].join(' · ');
    }
    final next = events.where((event) => event.day.isAfter(day)).firstOrNull;
    final nothing = name == 'Today' ? 'Nothing today' : 'Nothing on $name';
    return next == null
        ? nothing
        : '$nothing · next on ${calendarShortDate(next.day)}';
  }

  /// When a title of the last shelf comes out: a movie `Out 14 Oct`, a new
  /// series `From 1 Oct`.
  static String? _comingOut(MediaPreview item, DateTime now) {
    final day = arrCalendarDate(item.releaseDate);
    if (day == null) return null;
    final date = calendarDayMonth(day, now);
    return item.mediaType == 'tv' ? 'From $date' : 'Out $date';
  }

  /// When the rows' times are: the note under the agenda.
  static String _timesNote(Set<CalendarKind> kinds) {
    final dated = [
      for (final kind in const [
        CalendarKind.movie,
        CalendarKind.album,
        CalendarKind.book,
      ])
        if (kinds.contains(kind)) kind.plural,
    ];
    final datedWords = dated.isEmpty
        ? null
        : '${_capital(joinWithAnd(dated))} have a date, not a time.';
    return [
      if (kinds.contains(CalendarKind.episode))
        'Episode times are when they air, in your time zone.',
      ?datedWords,
    ].join(' ');
  }

  static String _capital(String words) =>
      words.isEmpty ? words : words[0].toUpperCase() + words.substring(1);
}

/// The way back and to today, the name, what this week holds, and who said
/// so.
class _Head extends StatelessWidget {
  const _Head({
    required this.calendar,
    required this.digest,
    required this.loading,
    required this.requester,
    required this.onToday,
  });

  final LibraryCalendar? calendar;
  final CalendarDigest digest;
  final bool loading;
  final bool requester;
  final VoidCallback onToday;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    final stacked = mediaStacked(context);
    final calendar = this.calendar;
    final answer = digest.answer(
      countKnown: calendar != null && calendar.silent.isEmpty,
      requester: requester,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const MediaBackPlate(),
            const Spacer(),
            _TodayPlate(onTap: onToday),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        Semantics(
          header: true,
          child: Text(
            'Calendar',
            style: (stacked ? AppType.room : AppType.screen).copyWith(
              color: room.ink,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        if (loading)
          AppSkeleton.listRows(count: 1)
        else if (calendar != null) ...[
          Text.rich(
            TextSpan(
              children: [
                if (answer.figure.isNotEmpty)
                  TextSpan(
                    text: '${answer.figure} ',
                    style: AppType.figureSmall.copyWith(color: room.ink),
                  ),
                TextSpan(text: answer.words),
                if (answer.name case final name?) ...[
                  const TextSpan(text: ' '),
                  TextSpan(
                    text: name,
                    style: AppType.body
                        .weight(FontWeight.w600)
                        .copyWith(color: room.ink),
                  ),
                ],
                TextSpan(text: answer.tail),
              ],
            ),
            style: AppType.body.copyWith(color: room.inkSecondary),
          ),
          if (requester || calendar.answered.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              requester
                  ? 'Your requests on their way · checked at '
                        '${formatClockTime(calendar.readAt)}'
                  : 'From ${joinWithAnd(calendar.answered)} at '
                        '${formatClockTime(calendar.readAt)}',
              style: AppType.caption.copyWith(color: room.inkTertiary),
            ),
          ],
        ],
      ],
    );
  }
}

/// `Today`, a plate like the way back: the strip back to this week, the
/// agenda back to its top.
class _TodayPlate extends StatelessWidget {
  const _TodayPlate({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    return Semantics(
      container: true,
      button: true,
      label: 'Today',
      child: ExcludeSemantics(
        child: PressableScale(
          onTap: onTap,
          child: Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: room.fillControl,
              borderRadius: BorderRadius.circular(AppRadius.control),
              border: Border.all(color: room.edge),
            ),
            child: Text(
              'Today',
              style: AppType.label.copyWith(color: room.ink),
            ),
          ),
        ),
      ),
    );
  }
}

/// The week's name and its days, between the arrows that page the strip.
class _WeekPager extends StatelessWidget {
  const _WeekPager({
    required this.index,
    required this.count,
    required this.monday,
    required this.onPage,
  });

  final int index;
  final int count;
  final DateTime monday;
  final ValueChanged<int> onPage;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    Widget arrow(IconData icon, String label, int? to) => IconButton(
      onPressed: to == null ? null : () => onPage(to),
      tooltip: label,
      style: IconButton.styleFrom(visualDensity: VisualDensity.standard),
      icon: Icon(icon, color: to == null ? room.inkDisabled : room.ink),
    );
    return Row(
      children: [
        arrow(
          Icons.chevron_left_rounded,
          'Week before',
          index > 0 ? index - 1 : null,
        ),
        Expanded(
          child: Semantics(
            liveRegion: true,
            child: Column(
              children: [
                Text(
                  calendarWeekName(index),
                  style: AppType.label.copyWith(color: room.ink),
                ),
                Text(
                  calendarWeekRange(monday),
                  style: AppType.caption.copyWith(color: room.inkTertiary),
                ),
              ],
            ),
          ),
        ),
        arrow(
          Icons.chevron_right_rounded,
          'Week after',
          index < count - 1 ? index + 1 : null,
        ),
      ],
    );
  }
}

/// The kinds as chips, a silent kind's with a red dot, and one line for the
/// kinds the household has no service for.
class _Kinds extends StatelessWidget {
  const _Kinds({
    required this.calendar,
    required this.requester,
    required this.selected,
    required this.onSelected,
  });

  final LibraryCalendar calendar;

  /// The requester reads no service's name, so no line about the kinds no
  /// service of hers dates.
  final bool requester;
  final CalendarKind? selected;
  final ValueChanged<CalendarKind?> onSelected;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    final scheme = Theme.of(context).colorScheme;
    final kinds = [
      for (final kind in CalendarKind.values)
        if (calendar.kinds.contains(kind)) kind,
    ];
    final missing = [
      for (final kind in CalendarKind.values)
        if (!calendar.kinds.contains(kind)) kind,
    ];
    final silent = calendar.silentKinds;
    final values = <CalendarKind?>[null, ...kinds];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (kinds.length > 1)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: SelectionPills.gutter,
            child: Row(
              children: [
                for (final kind in values)
                  Padding(
                    padding: const EdgeInsets.only(right: AppSpacing.sm),
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        SelectionPill(
                          label: kind?.chip ?? 'All',
                          selected: kind == selected,
                          onTap: () => onSelected(kind),
                        ),
                        if (silent.contains(kind))
                          Positioned(
                            top: 6,
                            right: 2,
                            child: ExcludeSemantics(
                              child: Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: statusToneColor(
                                    scheme,
                                    StatusTone.error,
                                    surface: room.ground,
                                  ),
                                  border: Border.all(color: room.ground),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        if (!requester &&
            missing.isNotEmpty &&
            missing.length < CalendarKind.values.length)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.xs,
              AppSpacing.lg,
              0,
            ),
            child: Text(
              '${_capital(joinWithAnd([for (final kind in missing) kind.plural]))} '
              'appear here when '
              '${joinWithAnd([for (final kind in missing) kind.service.title])} '
              '${missing.length == 1 ? 'is' : 'are'} set up.',
              style: AppType.meta.copyWith(color: room.inkTertiary),
            ),
          ),
      ],
    );
  }

  static String _capital(String words) =>
      words.isEmpty ? words : words[0].toUpperCase() + words.substring(1);
}

/// A connection whose calendar did not arrive: what may be missing and
/// why, once, with the remedy its cause names and Retry where asking again
/// can help.
class _SilentSource extends ConsumerWidget {
  const _SilentSource({required this.silence, required this.onRetry});

  final CalendarSilence silence;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gate = ref.watch(roleGateOfProvider(silence.connectionId));
    if (!gate.namesService(silence.service)) {
      return BriefFailureLine.line(
        error: silence.error,
        onRetry: onRetry,
        service: silence.service,
        instanceId: silence.connectionId,
      );
    }
    final room = CupolaRoom.of(context);
    final scheme = Theme.of(context).colorScheme;
    final reason = classifyConnectionFailure(silence.error);
    final gateway = accessGatewayOf(silence.error);
    final kind = CalendarKind.of(silence.service);
    final headline = failureHeadline(
      reason,
      subject: silence.name,
      gateway: gateway,
    );
    final remedy = FailureRemedy.forReason(
      silence.service,
      reason,
      instanceId: silence.connectionId,
      gateway: gateway,
    );
    final verbs = failureLineVerbs(
      context,
      remedy: remedy,
      fault: failureTone(reason) == StatusTone.warning,
      onRetry: onRetry,
      subject: silence.name,
    );
    final sentence = Row(
      children: [
        Icon(
          failureIcon(reason),
          size: 18,
          color: statusToneColor(scheme, failureTone(reason)),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            [
              headline,
              if (kind != null) '${kind.plural} may be missing here',
            ].join(' · '),
            style: AppType.meta.copyWith(color: room.inkSecondary),
          ),
        ),
      ],
    );
    return verbs.length == 1 && remedy == null
        ? Row(
            children: [
              Expanded(child: sentence),
              const SizedBox(width: AppSpacing.sm),
              verbs.single,
            ],
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              sentence,
              Wrap(
                alignment: WrapAlignment.end,
                spacing: AppSpacing.xs,
                children: verbs,
              ),
            ],
          );
  }
}
