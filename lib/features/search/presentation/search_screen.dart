import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// ignore: implementation_imports
import 'package:flutter_riverpod/legacy.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/app_breakpoints.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/providers/navigation_refresh_provider.dart';
import 'package:cupola/core/reel_motion.dart';
import 'package:cupola/core/service_theme.dart';
import 'package:cupola/core/status/lexicon.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/core/widgets/ambient_scaffold.dart';
import 'package:cupola/core/widgets/app_card.dart';
import 'package:cupola/core/widgets/app_empty_state.dart';
import 'package:cupola/core/widgets/content_card.dart';
import 'package:cupola/core/widgets/failure_remedy.dart';
import 'package:cupola/core/widgets/floating_bottom_nav_bar.dart';
import 'package:cupola/core/widgets/inline_error_retry.dart';
import 'package:cupola/core/widgets/glass_app_bar.dart';
import 'package:cupola/core/widgets/media_poster_card.dart';
import 'package:cupola/core/widgets/pressable_scale.dart';
import 'package:cupola/core/widgets/reel_line.dart';
import 'package:cupola/core/widgets/search_bar_header.dart';
import 'package:cupola/core/widgets/shimmer_placeholder.dart';
import 'package:cupola/core/widgets/status_badge.dart';
import 'package:cupola/features/search/domain/global_search_result.dart';
import 'package:cupola/features/search/presentation/arr_add_form_provider.dart';
import 'package:cupola/features/search/presentation/arr_add_sheet.dart';
import 'package:cupola/features/search/presentation/global_search_provider.dart';
import 'package:cupola/features/search/presentation/recent_searches_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/connection_presentation.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

class SearchScreen extends ConsumerWidget {
  const SearchScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = ref.watch(globalSearchQueryProvider);
    final selectedService = ref.watch(_selectedSearchServiceProvider);
    // Every lane as it stands right now, not one future over all of them: the
    // page below draws a Radarr that has answered beside a Bazarr still
    // shimmering, and nothing on it waits.
    final lanes = ref.watch(globalSearchLanesProvider);
    final resetVersion = ref.watch(_globalSearchResetVersionProvider);
    final bottomPadding = FloatingNavBarMetrics.getScrollViewBottomPadding(
      context,
    );

    ref.listen<int>(navigationRefreshProvider(NavigationSection.search), (
      previous,
      next,
    ) {
      ref.read(globalSearchQueryProvider.notifier).state = '';
      // The filter goes with it. Re-tapping Search means "give me a clean
      // field", and a one-service filter that survives the clear silently
      // applies to the next query — and, on a service whose connection has
      // since gone, to a screen with nothing on it at all.
      ref.read(_selectedSearchServiceProvider.notifier).state = null;
      ref.read(_globalSearchResetVersionProvider.notifier).state++;
    });

    // ⌘R's own channel. It is the opposite command to the tab re-tap above —
    // run this query again, rather than throw it away — so it must not arrive
    // on the same wire.
    ref.listen<int>(globalSearchRerunProvider, (previous, next) {
      rerunGlobalSearch(ref);
    });

    // Record queries that returned results as recent searches.
    ref.listen<List<GlobalSearchServiceResults>>(globalSearchLanesProvider, (
      previous,
      next,
    ) {
      final q = ref.read(globalSearchQueryProvider).trim();
      if (q.isNotEmpty && next.any((lane) => lane.results.isNotEmpty)) {
        ref.read(recentSearchesProvider.notifier).add(q);
      }
    });

    final width = MediaQuery.sizeOf(context).width;
    // The readout is a desktop luxury: it is a census of seven lanes, and the
    // phone has no line long enough to print one without wrapping into the
    // field. The compact window gets the heading alone, as drawn.
    final showsReadout =
        AppBreakpoints.isDesktopShell(context) &&
        width >= AppBreakpoints.desktopCompact;
    final stacked = !AppBreakpoints.isDesktopShell(context);

    return AmbientScaffold(
      appBar: GlassAppBar(
        toolbarHeight: _SearchHeading.toolbarHeight(
          context,
          showsReadout: showsReadout,
          stacked: stacked,
        ),
        title: _SearchHeading(
          lanes: lanes,
          showsReadout: showsReadout,
          stacked: stacked,
        ),
      ),
      body: Column(
        children: [
          SearchBarHeader(
            key: ValueKey(resetVersion),
            initialQuery: query,
            hintText: 'Movies, shows, artists...',
            onQueryChanged: (value) {
              ref.read(globalSearchQueryProvider.notifier).state = value;
            },
          ),
          _ServiceFilterChips(
            selectedService: selectedService,
            onSelected: (service) {
              ref.read(_selectedSearchServiceProvider.notifier).state = service;
            },
          ),
          Divider(
            height: 1,
            indent: AppSpacing.lg,
            endIndent: AppSpacing.lg,
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
          Expanded(
            child: query.trim().isEmpty
                ? const _SearchEmptyState()
                : _SearchResultsList(
                    lanes: lanes,
                    selectedService: selectedService,
                    bottomPadding: bottomPadding,
                  ),
          ),
        ],
      ),
    );
  }
}

final _globalSearchResetVersionProvider = StateProvider<int>((ref) => 0);

final _selectedSearchServiceProvider = StateProvider<ServiceKey?>(
  (ref) => null,
);

/// The h1, and — where there is room for it — the census of the fan-out.
///
/// The heading lives in the app bar rather than above the field because the bar
/// is where the window already reserves the room for it; drawing a second
/// "Search" under one that says the same word is the failure mode this avoids.
class _SearchHeading extends StatelessWidget {
  final List<GlobalSearchServiceResults> lanes;
  final bool showsReadout;
  final bool stacked;

  const _SearchHeading({
    required this.lanes,
    required this.showsReadout,
    required this.stacked,
  });

  /// How much bar this heading needs.
  ///
  /// Measured rather than a constant, because the constant is what breaks
  /// Dynamic Type: a bar fixed at 68 clips the second line at an accessibility
  /// reading size, and the second line is the one that says what the field
  /// searches. Each term is a role's own size times its own leading — 32/1.15
  /// for the headline, 22/1.25 and 12/1.4 for the stacked pair — so the bar
  /// grows exactly as fast as the type in it.
  static double toolbarHeight(
    BuildContext context, {
    required bool showsReadout,
    required bool stacked,
  }) {
    final scaler = MediaQuery.textScalerOf(context);
    final needed = stacked
        ? scaler.scale(22) * 1.25 + scaler.scale(12) * 1.4 + AppSpacing.xl
        : showsReadout
        ? scaler.scale(32) * 1.15 + AppSpacing.xl
        : kToolbarHeight;
    return needed < kToolbarHeight ? kToolbarHeight : needed;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dim = CupolaThemeColors.of(context).dimText;

    final heading = Text(
      'Search',
      style: showsReadout
          ? theme.textTheme.headlineLarge
          : theme.textTheme.titleLarge,
    );

    if (showsReadout) {
      final readout = searchLaneCensus(lanes);
      if (readout == null) return heading;
      return Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          heading,
          const SizedBox(width: AppSpacing.md),
          Flexible(
            child: Text(
              readout,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(color: dim),
            ),
          ),
        ],
      );
    }

    if (!stacked) return heading;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        heading,
        Text(
          'across every service',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall?.copyWith(color: dim),
        ),
      ],
    );
  }
}

class _ServiceFilterChips extends ConsumerWidget {
  final ServiceKey? selectedService;
  final ValueChanged<ServiceKey?> onSelected;

  const _ServiceFilterChips({
    required this.selectedService,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(currentSettingsProvider);
    // Only the services that can actually produce a lane. The strip used to
    // list every searchable service configured or not, and selecting one of the
    // unconfigured ones left the page with no lanes, no results and no
    // empty-state — a literally blank screen. `globalSearchServices` is the
    // same list the fan-out walks, so the strip cannot offer a filter the
    // provider never fills.
    final services = globalSearchServices
        .where(settings.isServiceConfigured)
        .toList(growable: false);

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.md,
      ),
      child: Row(
        children: [
          _FilterChip(
            label: 'All services',
            selected: selectedService == null,
            onTap: () => onSelected(null),
          ),
          for (final service in services)
            _FilterChip(
              label: service.title,
              selected: selectedService == service,
              onTap: () => onSelected(service),
            ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.onTap,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    // The brand book's chip, the same for every service: selected is the ink fill with the
    // on-ink label, the rest an ink wash with the primary ink. A service's
    // colour per chip made the strip a legend of hues with nothing to decode —
    // the chip names the service in words.
    final effectiveColor = Theme.of(context).colorScheme.primary;
    // The radius *is* the selection: 12 at rest, the pill at 20 when chosen.
    // Both were hardcoded to 20, which spent the one shape reserved for a
    // selected affordance on every chip in the strip and left selection to be
    // carried by fill alone.
    final radius = selected
        ? AppRadius.borderRadiusPill
        : AppRadius.borderRadiusMd;
    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.sm),
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        onTap: onTap,
        child: ExcludeSemantics(
          child: InkWell(
            onTap: onTap,
            borderRadius: radius,
            child: Container(
              decoration: BoxDecoration(
                color: selected
                    ? effectiveColor
                    : effectiveColor.withValues(alpha: 0.12),
                borderRadius: radius,
              ),
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              child: Text(
                label,
                style: Theme.of(context).textTheme.labelMedium
                    ?.weight(FontWeight.w600)
                    .copyWith(
                      // Measured against the fill, and against the wash over
                      // the page when unselected.
                      color: selected
                          ? ServiceTheme.foregroundOn(effectiveColor)
                          : ServiceTheme.onTint(
                              effectiveColor,
                              surface: Theme.of(context).colorScheme.surface,
                              tintAlpha: 0.12,
                            ),
                    ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SearchResultsList extends ConsumerWidget {
  final List<GlobalSearchServiceResults> lanes;
  final ServiceKey? selectedService;
  final double bottomPadding;

  const _SearchResultsList({
    required this.lanes,
    required this.selectedService,
    required this.bottomPadding,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final visibleLanes = lanes
        .where(
          (lane) => selectedService == null || lane.service == selectedService,
        )
        .toList(growable: false);
    final hasAnyResult = visibleLanes.any((lane) => lane.results.isNotEmpty);
    final allAnswered = visibleLanes.every(
      (lane) => lane.state == SearchLaneState.answered,
    );

    // The third of the three empties: nothing anywhere.
    //
    // Gated on every lane having *answered*, because a page that says "no
    // results" while Bazarr is still shimmering is a page that contradicts
    // itself two seconds later, and a lane that faulted has a card of its own
    // to show instead. That is the half this guard was missing.
    //
    // It stays gated on there being no filter, and that is not an oversight:
    // the page-level empty answers a question about the *query*, while a filter
    // makes the question about one library — and "No Seerr results" under the
    // Seerr heading names the library that answered, which "No results found"
    // cannot.
    //
    // `visibleLanes.isEmpty` is the case that had no answer at all. With the
    // filter pinned to a service whose connection has since gone there are no
    // lanes to draw, the `selectedService == null` arm is false, and the page
    // fell through to a scroll view containing nothing but its bottom spacer.
    // A blank screen.
    if (visibleLanes.isEmpty ||
        (selectedService == null && allAnswered && !hasAnyResult)) {
      return const _NoResultsState();
    }

    // One scroll, and one sliver per section rather than one child per section.
    // A service answering with 50 results used to lay out and paint all 50 the
    // moment any part of its section touched the cache extent — 50 poster
    // requests, each with its own repeating shimmer ticker. A
    // `SliverList.builder` per section keeps the laziness *and* lets a section
    // land mid-page.
    final columns = _columnsFor(context, visibleLanes);

    return CustomScrollView(
      slivers: [
        if (columns.length == 1)
          ..._sectionSlivers(context, ref, columns.single)
        else
          SliverCrossAxisGroup(
            slivers: [
              for (final column in columns)
                SliverCrossAxisExpanded(
                  flex: 1,
                  sliver: SliverMainAxisGroup(
                    slivers: _sectionSlivers(context, ref, column),
                  ),
                ),
            ],
          ),
        SliverToBoxAdapter(child: SizedBox(height: bottomPadding)),
      ],
    );
  }

  /// How the sections are spread across the width.
  ///
  /// Two columns at 1440 and one everywhere else — and the split is *by
  /// section*, never within one. A section is a service's answer, arriving on
  /// its own clock; cutting one down the middle would put half of Radarr's
  /// results in a column that is still empty because Sonarr has not replied.
  ///
  /// Balanced greedily by result count rather than dealt alternately, so a
  /// service with fifty hits does not leave the other column three rows long.
  static List<List<GlobalSearchServiceResults>> _columnsFor(
    BuildContext context,
    List<GlobalSearchServiceResults> lanes,
  ) {
    final width = MediaQuery.sizeOf(context).width;
    if (!AppBreakpoints.isDesktopShell(context) ||
        width < AppBreakpoints.desktopCompact ||
        lanes.length < 2) {
      return [lanes];
    }

    final left = <GlobalSearchServiceResults>[];
    final right = <GlobalSearchServiceResults>[];
    var leftWeight = 0;
    var rightWeight = 0;
    for (final lane in lanes) {
      // A lane with no rows is still a heading and a leaf under it — two
      // shimmer plates, a fault card or an empty line — so it weighs something.
      // Otherwise every silent service piles into one column.
      final weight = lane.results.isEmpty ? 2 : lane.results.length + 1;
      if (leftWeight <= rightWeight) {
        left.add(lane);
        leftWeight += weight;
      } else {
        right.add(lane);
        rightWeight += weight;
      }
    }
    return [left, right];
  }

  /// One column's sections, as real slivers.
  List<Widget> _sectionSlivers(
    BuildContext context,
    WidgetRef ref,
    List<GlobalSearchServiceResults> lanes,
  ) {
    return [
      for (final lane in lanes) ...[
        SliverToBoxAdapter(child: _SearchSectionHeader(lane: lane)),
        // Rows, or the one leaf that stands in for them. Never both: results
        // only ever arrive on an answered lane, and an answered lane with rows
        // has nothing left to explain.
        if (lane.results.isEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: _LaneBody(
                lane: lane,
                // Retry is a per-leg invalidate and never a whole-screen one:
                // the six lanes that answered stay exactly where they are.
                onRetry: () =>
                    ref.invalidate(globalSearchLegProvider(lane.leg)),
              ),
            ),
          )
        else
          SliverList.builder(
            itemCount: lane.results.length,
            itemBuilder: (context, index) => Padding(
              // The section's horizontal inset used to live on the wrapper
              // around the cards' `Column`; folded together with the per-card
              // bottom gap it is the same box.
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                0,
                AppSpacing.lg,
                AppSpacing.sm,
              ),
              child: _SearchResultCard(result: lane.results[index]),
            ),
          ),
      ],
    ];
  }
}

/// What a lane with no rows draws instead: two shimmer plates while it is
/// still out, a fault card with its own Retry once it has stopped, and the
/// "this library does not have it" line once it has answered.
class _LaneBody extends StatelessWidget {
  final GlobalSearchServiceResults lane;
  final VoidCallback onRetry;

  const _LaneBody({required this.lane, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    if (lane.hasFault) {
      return _SearchLaneFault(lane: lane, onRetry: onRetry);
    }
    if (lane.state == SearchLaneState.searching) {
      // Two plates at the drawn 46pt, not the whole page's skeleton: the point
      // of the lane model is that only the lane that is waiting looks like it
      // is waiting.
      return Column(
        children: [
          ShimmerPlaceholder(
            height: 46,
            borderRadius: AppRadius.borderRadiusMd,
          ),
          const SizedBox(height: AppSpacing.sm),
          ShimmerPlaceholder(
            height: 46,
            borderRadius: AppRadius.borderRadiusMd,
          ),
        ],
      );
    }
    // The second of the three empties: this library answered and does not have
    // it. It reads as a fact about the library precisely because a server that
    // did not answer never reaches this branch.
    return _SearchSectionMessage(
      icon: Icons.search_off_rounded,
      text: 'No ${lane.laneTitle} results',
      color: colorScheme.onSurfaceVariant,
    );
  }
}

class _SearchSectionHeader extends StatelessWidget {
  final GlobalSearchServiceResults lane;

  const _SearchSectionHeader({required this.lane});

  @override
  Widget build(BuildContext context) {
    final service = lane.service;
    final chipless = lane.laneTitle == lane.instanceLabel;
    // The mark and the connection badge are both the accent on its own 14%
    // wash over the page, so one walked ink serves both.
    final ink = ServiceTheme.onTint(
      service.accent,
      surface: Theme.of(context).colorScheme.surface,
      tintAlpha: 0.14,
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      child: Row(
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: service.accent.withValues(alpha: 0.14),
              borderRadius: AppRadius.borderRadiusSm,
            ),
            child: Icon(service.icon, size: 14, color: ink),
          ),
          const SizedBox(width: AppSpacing.sm),
          Flexible(
            child: Text(
              // `Radarr 2` for a connection nobody named, whose name already
              // says the service: the heading is the name, with no chip
              // repeating it.
              chipless ? lane.laneTitle : service.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.labelLarge?.weight(FontWeight.w600),
            ),
          ),
          // Which connection answered. On the heading rather than on the rows:
          // one leg queries one server, so every result below came from this
          // one and a chip repeated down forty rows would say it forty times.
          // Absent entirely while the service has a single connection.
          if (lane.instanceLabel.isNotEmpty && !chipless) ...[
            const SizedBox(width: AppSpacing.xs),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: service.accent.withValues(alpha: 0.14),
                borderRadius: AppRadius.borderRadiusXs,
                border: Border.all(
                  color: service.accent.withValues(alpha: 0.34),
                ),
              ),
              child: Text(
                lane.instanceLabel,
                style: AppTheme.chrome(context, color: ink),
              ),
            ),
          ],
          const SizedBox(width: AppSpacing.xs),
          Flexible(child: _LaneStateReadout(lane: lane)),
        ],
      ),
    );
  }
}

/// The lane's own word, and the pip that gives it a tone. A lane that stopped
/// keeps the pip and leaves the words to its fault card.
///
/// The whole vocabulary this replaced was one string, `'offline'`, painted
/// `colorScheme.error` for every kind of failure — so a Bazarr taking nine
/// seconds and a Bazarr that is unplugged read identically, in the ink reserved
/// for the second one.
class _LaneStateReadout extends StatelessWidget {
  final GlobalSearchServiceResults lane;

  const _LaneStateReadout({required this.lane});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final tone = statusToneColor(colorScheme, lane.state.tone);
    final style = Theme.of(
      context,
    ).textTheme.labelSmall?.tabular.copyWith(color: tone);

    final word = lane.stateWord;
    if (!lane.state.showsPip && word != null) {
      // A global search fans out to every configured service and they answer at
      // their own pace, so this count genuinely arrives — it is not a number
      // that was always there. Rolling it is the section reporting in.
      // `.tabular` still does the anti-jitter work; the roll is what marks the
      // arrival.
      return ReelLine(
        word,
        options: ReelMotion.figure,
        style: style,
        fallbackMaxLines: 1,
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Decorative: the word beside it, or the fault card under a lane that
        // stopped, says the same thing, and a screen reader announcing
        // "circle" before every heading is noise.
        ExcludeSemantics(
          child: Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: tone, shape: BoxShape.circle),
          ),
        ),
        // No word once the lane stopped: the card under the heading states
        // the cause, once, beside its remedy.
        if (word != null) ...[
          const SizedBox(width: AppSpacing.xs),
          Flexible(
            child: Text(
              word,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: style,
            ),
          ),
        ],
      ],
    );
  }
}

/// A lane that stopped: what happened, and the verbs its cause allows.
///
/// Drawn as a dashed outline rather than a filled card because there is nothing
/// inside it — the dash is what says "this slot is empty" at a glance, against
/// the solid cards the answered lanes fill their slots with.
///
/// The verbs are a failure line's ([failureLineVerbs], the policy
/// [InlineErrorRetry] draws): the remedy the cause names in the amber fill
/// (`Add a service token`, `Paste the key again`), opening this lane's own
/// connection form; `Retry` only where the same request can still succeed,
/// in the amber fill when retrying is a fault's remedy (a search that timed
/// out) and as text in ink beside a red lane. Each names its server for a
/// screen reader, since up to seven of these share one screen.
class _SearchLaneFault extends StatelessWidget {
  final GlobalSearchServiceResults lane;
  final VoidCallback onRetry;

  const _SearchLaneFault({required this.lane, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final tone = statusToneColor(colorScheme, lane.state.tone);
    final remedy = lane.reason == null
        ? null
        : FailureRemedy.forReason(
            lane.service,
            lane.reason!,
            instanceId: lane.instanceId,
            gateway: lane.gateway,
          );
    final verbs = failureLineVerbs(
      context,
      remedy: remedy,
      fault: lane.state.tone == StatusTone.warning,
      onRetry: onRetry,
      subject: lane.laneTitle,
    );
    final glyph = Icon(_glyph, size: 18, color: tone);
    final sentence = Text(
      lane.faultSentence,
      style: Theme.of(
        context,
      ).textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
    );
    return CustomPaint(
      painter: _DashedBorderPainter(
        color: tone.withValues(alpha: 0.55),
        radius: AppRadius.lg,
      ),
      child: Padding(
        // The drawn card is 46pt. The verbs inside it are controls, and a
        // control keeps its 44pt target whatever the card measures — so the
        // vertical inset is the smallest token rather than the card being
        // squeezed down onto the button.
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.xs,
        ),
        // A lone Retry is one short word and sits beside the sentence. A
        // remedy is a phrase (`Add a service token`): beside the sentence it
        // would squeeze it into a third of a phone's line, so it takes the row
        // under it, at the trailing edge, as `InlineErrorRetry` sets it, and so
        // does a remedy with Retry.
        child: verbs.length == 1 && remedy == null
            ? Row(
                children: [
                  glyph,
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(child: sentence),
                  const SizedBox(width: AppSpacing.sm),
                  verbs.single,
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.sm),
                    child: Row(
                      children: [
                        glyph,
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(child: sentence),
                      ],
                    ),
                  ),
                  Wrap(
                    alignment: WrapAlignment.end,
                    spacing: AppSpacing.xs,
                    children: verbs,
                  ),
                ],
              ),
      ),
    );
  }

  /// The same glyph the settings rows use for the same reason, so one failure
  /// does not get two pictures in one app.
  IconData get _glyph => switch (lane.state) {
    SearchLaneState.timedOut => Icons.timer_off_rounded,
    SearchLaneState.unreachable => Icons.cloud_off_rounded,
    _ => failureIcon(lane.reason ?? ServiceFailureReason.unknown),
  };
}

/// A 1px dashed rounded outline.
///
/// Hand-painted because Flutter's `Border` has no dash: the alternative is a
/// solid outline, which is what a card with content in it wears, and the whole
/// job of this one is to look like a slot nothing filled.
class _DashedBorderPainter extends CustomPainter {
  const _DashedBorderPainter({required this.color, required this.radius});

  final Color color;
  final double radius;

  /// 5 on, 4 off — long enough to read as a line at a glance, short enough that
  /// the corners of a 12–16pt radius still get two dashes each.
  static const double _dash = 5;
  static const double _gap = 4;

  @override
  void paint(Canvas canvas, Size size) {
    final outline = Path()
      ..addRRect(
        RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius)),
      );
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = color;
    for (final metric in outline.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final end = math.min(distance + _dash, metric.length);
        canvas.drawPath(metric.extractPath(distance, end), paint);
        distance = end + _gap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.radius != radius;
}

class _SearchResultCard extends ConsumerWidget {
  final GlobalSearchResult result;

  const _SearchResultCard({required this.result});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final service = result.service;
    final addRequest = result.addRequest;
    // Held by the server that listed it — either when the lookup said so, or
    // because this session put it there. `select` so an add repaints the one
    // row it concerns rather than every card on screen.
    final owned =
        result.inLibrary ||
        (addRequest != null &&
            ref.watch(
              libraryAdditionsProvider.select(
                (keys) => keys.contains(addRequest.libraryKey),
              ),
            ));

    return AppCard.outlined(
      onTap: () => context.push(result.route, extra: result.routeExtra),
      backgroundColor: colorScheme.surfaceContainer,
      borderColor: colorScheme.outlineVariant,
      borderRadius: AppRadius.borderRadiusMd,
      // 12 rather than the 11 that was here: the ladder is 4/8/12/16/24/32/48
      // and anything off it is a bug. With the 50x75 poster the row measures
      // 99pt, comfortably over the 68pt floor a poster that size needs.
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 50, height: 75, child: _ResultPoster(result: result)),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  result.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.weight(FontWeight.w600),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  result.subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final tag in result.tags.take(3))
                      _ResultTag(label: tag, color: service.accent),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          _ResultAction(
            result: result,
            owned: owned,
            // A plus only where there is a real add behind it. Every other row
            // gets the glyph without the tap target: it is a state marker, and
            // a marker that responds to a finger is a promise.
            onAdd: owned || addRequest == null
                ? null
                : () => showArrAddSheet(context, ref, addRequest),
          ),
        ],
      ),
    );
  }
}

/// The row's trailing state glyph, and — where an add is genuinely possible —
/// the control that starts one.
///
/// Green tick for a title the server already holds, the service's own accent
/// and a plus for one it does not. It reads [owned] rather than sniffing the
/// tags for the substring `available`: that tied the affordance to a label's
/// wording, and to a field (`hasFile`) the lookup endpoints never populate — so
/// the tick never appeared and every row invited an add, including the ones
/// already sitting on the server.
class _ResultAction extends StatelessWidget {
  final GlobalSearchResult result;
  final bool owned;
  final VoidCallback? onAdd;

  const _ResultAction({
    required this.result,
    required this.owned,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    // Through the tone vocabulary, not the raw palette constant: the card under
    // this disc is `surfaceContainer`, and raw success measures 2.07:1 against
    // paper — a green nobody can find in daylight.
    final fill = owned
        ? statusToneColor(
            colorScheme,
            StatusTone.success,
            surface: colorScheme.surfaceContainer,
          )
        // The ink disc: adding is the row's primary action, not a service's.
        : colorScheme.primary;
    final glyph = SizedBox.square(
      dimension: 32,
      child: DecoratedBox(
        decoration: BoxDecoration(color: fill, shape: BoxShape.circle),
        // Seventeen possible fills, seven of them under 3:1 on paper: white was
        // the right ink for some of them and never for all.
        child: Icon(
          owned ? Icons.check_rounded : Icons.add_rounded,
          size: 15,
          color: ServiceTheme.foregroundOn(fill),
        ),
      ),
    );

    if (onAdd == null) return glyph;

    // 44 wide around a 32 circle: the glyph's own size is below the touch
    // target floor, and this is now a control rather than a badge.
    return PressableScale(
      onTap: onAdd,
      semanticLabel: 'Add ${result.title}',
      excludeChildSemantics: true,
      child: SizedBox(width: 44, height: 44, child: Center(child: glyph)),
    );
  }
}

/// A result's poster, flying into its detail page as a shared element.
///
/// The Hero is skipped where the service has no artwork (Bazarr), matching the
/// Recently Added rail: an empty grey box flying into a fallback glyph is
/// motion with nothing to follow.
class _ResultPoster extends StatelessWidget {
  final GlobalSearchResult result;

  const _ResultPoster({required this.result});

  @override
  Widget build(BuildContext context) {
    final card = ContentCard(
      imageUrl: result.imageUrl,
      httpHeaders: result.imageHeaders,
      badge: Align(
        alignment: Alignment.bottomLeft,
        child: Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: result.service.accent,
            shape: BoxShape.circle,
          ),
        ),
      ),
    );

    if (!result.canFlyPoster) return card;

    return Hero(
      tag: result.heroTag,
      transitionOnUserGestures: MediaPosterCard.flightOnUserGestures,
      child: card,
    );
  }
}

class _ResultTag extends StatelessWidget {
  final String label;
  final Color color;

  const _ResultTag({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    // Result rows are `surfaceContainer` cards; the label is measured against
    // its 12% wash over that.
    final ink = ServiceTheme.onTint(
      color,
      surface: Theme.of(context).colorScheme.surfaceContainer,
      tintAlpha: 0.12,
    );
    return Container(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: AppRadius.borderRadiusSm,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      child: Text(
        label,
        style: Theme.of(
          context,
        ).textTheme.labelSmall?.weight(FontWeight.w600).copyWith(color: ink),
      ),
    );
  }
}

class _SearchSectionMessage extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;

  const _SearchSectionMessage({
    required this.icon,
    required this.text,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        border: Border.all(color: colorScheme.outlineVariant),
        borderRadius: AppRadius.borderRadiusLg,
      ),
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NoResultsState extends StatelessWidget {
  const _NoResultsState();

  @override
  Widget build(BuildContext context) {
    return const AppEmptyState(
      icon: Icons.search_off_rounded,
      title: 'No results',
      message: 'Try a different title or spelling.',
    );
  }
}

/// "Radarr", "Radarr and Sonarr", "Seerr, Radarr and Sonarr"; with
/// [conjunction] `or`, "Seerr, Radarr or Sonarr", for a list where any one will
/// do.
String _serviceList(List<ServiceKey> services, {String conjunction = 'and'}) {
  final titles = services.map((s) => s.title).toList(growable: false);
  if (titles.length == 1) return titles.single;
  return '${titles.sublist(0, titles.length - 1).join(', ')} $conjunction '
      '${titles.last}';
}

class _SearchEmptyState extends ConsumerWidget {
  const _SearchEmptyState();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final recents = ref.watch(recentSearchesProvider);
    final settings = ref.watch(currentSettingsProvider);

    // Name the services that will actually be queried. The copy used to list
    // "Seerr, Radarr, Sonarr, Lidarr, and Bazarr" unconditionally, so a user with
    // only Radarr connected was promised four searches that could not happen.
    final searchable = globalSearchServices
        .where(settings.isServiceConfigured)
        .toList(growable: false);
    final hasAny = searchable.isNotEmpty;
    final notSetUp = globalSearchServices
        .where((service) => !settings.isServiceConfigured(service))
        .toList(growable: false);

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      children: [
        const SizedBox(height: AppSpacing.xl),
        Icon(
          hasAny ? Icons.search_rounded : Icons.link_off_rounded,
          size: 48,
          color: colorScheme.onSurfaceVariant,
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          hasAny
              ? 'Search across every service'
              : 'No searchable service is set up',
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.weight(FontWeight.w600),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          hasAny
              ? 'Enter a title, show, or artist to query '
                    '${_serviceList(searchable)}.'
              // "or": any one of them is enough to search from here. It said
              // "and", which asked for the whole list before the first search.
              : '${Lexicon.setUp(_serviceList(notSetUp, conjunction: 'or'))} '
                    'to search your libraries from here.',
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
        ),
        if (!hasAny) ...[
          const SizedBox(height: AppSpacing.lg),
          // One way in, as Home has with nothing set up: Connections, where
          // every service's form hangs off. Not a `Set up X`, because nothing
          // is chosen yet, and not one per service either: seven buttons are a
          // wall where one sentence already names them. "Open Settings"
          // landed on the Settings root and left the user to find the list.
          Center(
            child: FilledButton(
              // `go`, not `push`: a push keeps the *origin* branch's
              // navigator, so Connections would render inside the Search tab
              // while the bar stayed lit on Search. `go` switches to the
              // Settings branch, where it lives.
              onPressed: () => context.go(ServiceRoutes.settingsConnections),
              child: const Text('Set up a service'),
            ),
          ),
        ],
        if (recents.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xxl),
          Row(
            children: [
              Text(
                'Recent',
                semanticsLabel: 'Recent',
                style: AppTheme.chrome(
                  context,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              // TextButton rather than a bare GestureDetector on 11pt text: it
              // brings a 44pt hit area, a button role for screen readers and a
              // press state for free.
              TextButton(
                onPressed: () =>
                    ref.read(recentSearchesProvider.notifier).clear(),
                style: TextButton.styleFrom(
                  minimumSize: const Size(44, 44),
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                  ),
                ),
                child: Text(
                  'Clear',
                  style: Theme.of(context).textTheme.labelSmall
                      ?.weight(FontWeight.w600)
                      .copyWith(color: colorScheme.primary),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (final query in recents)
                _RecentChip(
                  label: query,
                  onTap: () {
                    ref.read(globalSearchQueryProvider.notifier).state = query;
                    ref
                        .read(_globalSearchResetVersionProvider.notifier)
                        .state++;
                  },
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _RecentChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _RecentChip({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      // Md, not the pill: a recent query is never in a selected state, and the
      // pill radius is reserved for the shape that says "chosen".
      borderRadius: AppRadius.borderRadiusMd,
      child: Container(
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHigh,
          borderRadius: AppRadius.borderRadiusMd,
          border: Border.all(color: colorScheme.outlineVariant),
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.history_rounded,
              size: 14,
              color: colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: AppSpacing.xs),
            Text(
              label,
              style: Theme.of(
                context,
              ).textTheme.labelMedium?.copyWith(color: colorScheme.onSurface),
            ),
          ],
        ),
      ),
    );
  }
}
