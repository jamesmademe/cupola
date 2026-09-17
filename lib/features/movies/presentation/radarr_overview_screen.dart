import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:go_router/go_router.dart';

import 'package:cupola/core/app_animation.dart';

import 'package:cupola/core/app_spacing.dart';

import 'package:cupola/core/text_scale.dart';

import 'package:cupola/core/theme.dart';

import 'package:cupola/core/utils/arr_activity_display.dart';

import 'package:cupola/core/utils/image_utils.dart';

import 'package:cupola/core/utils/service_routes.dart';

import 'package:cupola/core/widgets/widgets.dart';

import 'package:cupola/features/movies/domain/models/radarr_movie.dart';

import 'package:cupola/features/movies/presentation/movies_provider.dart';
import 'package:cupola/features/movies/presentation/radarr_overview_provider.dart';

import 'package:cupola/features/services/domain/service_tab.dart';

import 'package:cupola/features/services/domain/services_semantics.dart';

import 'package:cupola/features/services/presentation/service_kpi_provider.dart';

import 'package:cupola/features/services/presentation/services_provider.dart';

import 'package:cupola/features/settings/data/settings_provider.dart';

import 'package:cupola/features/settings/domain/service_key.dart';

/// The first tab of Radarr's service home.
///
/// Overview alone carries the identity block and the readouts — every other tab
/// is a view of one kind of record — and then five sections in the order the
/// board draws them: what is coming, what needs a decision, what arrived, what
/// happened today. Each section ends in a link named exactly like the tab it
/// jumps to.
///
/// **It draws neither the app bar nor the tab bar.** `ServiceHomeScreen` owns
/// the first and `ServiceTabScaffold` the second, both as glass bands floated
/// above this page so the ambient gradient reads continuously behind them; this
/// screen reserves the room with [topPadding] instead.
///
/// Sections load independently and fail independently. That is the design's
/// SECTION failure level: a Radarr that answers the library and not the queue
/// still draws four regions, and the one that could not load says so in its own
/// slot rather than taking the page with it.
class RadarrOverviewScreen extends ConsumerWidget {
  const RadarrOverviewScreen({super.key, this.topPadding = _hostedTopPadding});

  /// The room the two glass bands above this page occupy.
  ///
  /// Composed from the same two constants the router composes its own from, so
  /// a screen built outside the router — a test, a preview — reserves the right
  /// space instead of tucking its first region under the tab bar.
  static const double _hostedTopPadding = kToolbarHeight + ServiceTabBar.height;

  /// Height of the chrome the host draws above this page.
  final double topPadding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final configured = ref.watch(
      currentSettingsProvider.select(
        (settings) => settings.isServiceConfigured(ServiceKey.radarr),
      ),
    );

    return AmbientScaffold(
      accent: ServiceKey.radarr.accent,
      body: SafeArea(
        child: configured
            ? _OverviewBody(topPadding: topPadding)
            // `.forService`, never the generic form: this is a service
            // dashboard, so the door goes to Radarr's own connection form
            // rather than to the settings index. Resolved once here rather than
            // five times inside five sections, which is what a page made only
            // of `AsyncValueWidget`s would print on a server that was never set
            // up.
            : NotConfiguredPlaceholder.forService(ServiceKey.radarr),
      ),
    );
  }
}

class _OverviewBody extends ConsumerWidget {
  const _OverviewBody({required this.topPadding});

  final double topPadding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(serviceSummaryProvider(ServiceKey.radarr));
        ref.invalidate(serviceKpiProvider(ServiceKey.radarr));
        // The library itself, not only the three readings of it. Coming up,
        // Recently added and all four figures on the rail fall out of
        // `moviesProvider`, which is a plain `FutureProvider` fetched once for
        // the life of the app — so invalidating only the derived trio re-ran
        // the window functions against the same cached list with a new clock
        // and re-read the rail off the same cached list again. A pull that
        // refetched nothing: a film that landed, one that was added or a
        // release date that moved never appeared.
        ref.invalidate(moviesProvider);
        // And the rail's own non-swallowing read of it. See
        // `radarrKpiLibraryProvider`.
        ref.invalidate(radarrKpiLibraryProvider);
        // And the queue snapshot behind the rail's fourth figure, for the same
        // reason: `serviceKpiProvider` is autoDispose, this one is not, so
        // Queued stayed frozen for the life of the scope while the three
        // figures beside it moved.
        //
        // The **family**, not `radarrQueueSnapshotProvider`: that one only
        // resolves the lens and re-watches `radarrQueueSnapshotForProvider`,
        // so invalidating it re-reads the member's cached future and fetches
        // nothing. Invalidating the family is what reaches the request, and it
        // takes the lens-resolving provider and the queued-id set down with it
        // as dependents.
        ref.invalidate(radarrQueueSnapshotForProvider);
        ref.invalidate(radarrComingUpProvider);
        ref.invalidate(radarrNeedsAttentionProvider);
        ref.invalidate(radarrQueueRecordsProvider);
        ref.invalidate(radarrCutoffUnmetCountProvider);
        ref.invalidate(radarrRecentlyAddedProvider);
        ref.invalidate(radarrHistoryTodayProvider);
        await Future<void>.delayed(AppAnimation.durationMd);
      },
      // One scroll view for the whole page: the regions are one column of
      // reading, not five independently scrolling panes.
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.only(
          bottom: FloatingNavBarMetrics.getScrollViewBottomPadding(context),
        ),
        children: [
          if (topPadding > 0) SizedBox(height: topPadding),
          const ServiceOverviewIdentity(service: ServiceKey.radarr),
          ServiceKpiPeek(
            kpis: ref.watch(serviceKpiProvider(ServiceKey.radarr)),
            accent: ServiceKey.radarr.accent,
          ),
          const _ComingUpSection(),
          const _NeedsAttentionSection(),
          const _RecentlyAddedSection(),
          const _HistoryTodaySection(),
        ],
      ),
    );
  }
}

// ─── 2. Coming up ───────────────────────────────────────────────────────────

class _ComingUpSection extends ConsumerWidget {
  const _ComingUpSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final releases = ref.watch(radarrComingUpProvider);
    // `hasValue`, never `asData`: `asData` is null on an `AsyncError` even when
    // Riverpod retained the value it had, while `AsyncValueWidget` under this
    // header draws exactly that retained list at full ink beneath the
    // unreachable band. Read through `asData` the header printed "—" over rows
    // it was still showing. A source that never answered has no retained value
    // and still reads "—".
    final count = releases.hasValue ? releases.requireValue.length : null;

    return ServiceOverviewSection(
      service: ServiceKey.radarr,
      title: 'Coming up',
      // "—" while the library is loading or after it failed: a "0 releases"
      // printed over an unanswered question is a claim nobody made.
      subtitle:
          'next $radarrComingUpDays days · '
          '${count == null ? '—' : '$count ${count == 1 ? 'release' : 'releases'}'}',
      destination: ServiceTab.calendar,
      child: AsyncValueWidget<List<RadarrUpcomingRelease>>(
        value: releases,
        serviceName: 'Radarr',
        loadingLabel: 'Loading what is coming up',
        onRetry: () => ref.invalidate(radarrComingUpProvider),
        skeleton: const ServiceOverviewRowsSkeleton(rows: 2),
        isEmpty: (items) => items.isEmpty,
        emptyBuilder: const ServiceOverviewEmpty(
          icon: Icons.event_available_rounded,
          label: 'Nothing releasing this week',
        ),
        data: (items) => Column(
          children: [
            for (final release in items.take(radarrComingUpPreviewLimit))
              _ComingUpRow(release: release),
          ],
        ),
      ),
    );
  }
}

class _ComingUpRow extends StatelessWidget {
  const _ComingUpRow({required this.release});

  final RadarrUpcomingRelease release;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final day = _dayLabel(release.date, DateTime.now());
    final movie = release.movie;
    // Monitored is the fact that decides whether Radarr will actually do
    // anything on that date, which is the whole reason the row is worth a line.
    final qualifier = joinDisplayParts([
      release.kind.label,
      movie.monitored ? 'monitored' : 'unmonitored',
    ]);

    return ServiceOverviewRow(
      spoken: joinSpokenParts([day, movie.title, spokenFromDotted(qualifier)]),
      leading: SizedBox(
        width: 58,
        child: Text(
          day,
          maxLines: 2,
          style: AppTheme.chrome(
            context,
            size: 11,
            weight: FontWeight.w700,
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      ),
      title: movie.title,
      detail: qualifier,
    );
  }
}

// ─── 3. Needs attention ─────────────────────────────────────────────────────

class _NeedsAttentionSection extends ConsumerWidget {
  const _NeedsAttentionSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(radarrNeedsAttentionProvider);
    // `hasValue`, never `asData`: `asData` is null on an `AsyncError` even when
    // Riverpod retained the value it had, while `AsyncValueWidget` under this
    // header draws exactly that retained list at full ink beneath the
    // unreachable band. Read through `asData` the header printed "—" over rows
    // it was still showing. A source that never answered has no retained value
    // and still reads "—".
    final count = items.hasValue ? items.requireValue.length : null;

    return ServiceOverviewSection(
      service: ServiceKey.radarr,
      title: 'Needs attention',
      subtitle: count == null ? '—' : '$count',
      // No link: every row here belongs to a different tab, and a single
      // destination would have to lie about four of them.
      child: AsyncValueWidget<List<RadarrAttentionItem>>(
        value: items,
        serviceName: 'Radarr',
        loadingLabel: 'Loading what needs attention',
        onRetry: () => ref.invalidate(radarrNeedsAttentionProvider),
        skeleton: const ServiceOverviewRowsSkeleton(rows: 2),
        isEmpty: (data) => data.isEmpty,
        // A resting state wears no alarm chrome: nothing is wrong, and saying
        // so is not an error state.
        emptyBuilder: const ServiceOverviewEmpty(
          icon: Icons.check_circle_outline_rounded,
          label: 'Nothing needs you',
        ),
        data: (data) => Column(
          children: [for (final item in data) _AttentionRow(item: item)],
        ),
      ),
    );
  }
}

class _AttentionRow extends StatelessWidget {
  const _AttentionRow({required this.item});

  final RadarrAttentionItem item;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    // Through the tone rule, never a raw `AppColors.*`: amber is a fault, and
    // a backlog row — films below the cutoff — is neutral by construction.
    final tone = statusToneColor(
      colorScheme,
      item.tone,
      surface: colorScheme.surfaceContainerLow,
    );

    return ServiceOverviewRow(
      spoken: item.spoken,
      leading: Icon(item.icon, size: 18, color: tone),
      title: item.headline,
      titleColor: tone,
      detail: item.detail,
    );
  }
}

// ─── 4. Recently added ──────────────────────────────────────────────────────

class _RecentlyAddedSection extends ConsumerWidget {
  const _RecentlyAddedSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final movies = ref.watch(radarrRecentlyAddedProvider);

    return ServiceOverviewSection.bleed(
      service: ServiceKey.radarr,
      title: 'Recently added',
      destination: ServiceTab.library,
      child: AsyncValueWidget<List<RadarrMovie>>(
        value: movies,
        serviceName: 'Radarr',
        loadingLabel: 'Loading recently added films',
        onRetry: () => ref.invalidate(radarrRecentlyAddedProvider),
        skeleton: AppSkeleton.posterRow(height: 138),
        isEmpty: (items) => items.isEmpty,
        emptyBuilder: const Padding(
          padding: EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: ServiceOverviewEmpty(
            icon: Icons.movie_outlined,
            label: 'Nothing added yet',
          ),
        ),
        data: (items) => _PosterRail(movies: items),
      ),
    );
  }
}

class _PosterRail extends ConsumerWidget {
  const _PosterRail({required this.movies});

  final List<RadarrMovie> movies;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final instance = ref.watch(activeInstanceProvider(ServiceKey.radarr));

    return SizedBox(
      // 138pt poster, the gap, and two label lines — grown by the reading size
      // so the captions are not clipped at an accessibility text size.
      height: TextScaleMetrics.boxHeight(context, base: 176, textHeight: 34),
      // The box grew by the *clamped* scale, so the text has to be laid out at
      // the same clamp: unclamped, the rail is sized for 1.6x and painted at
      // 3.0x, which is an overflow stripe.
      child: MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaleMetrics.clampedScalerOf(context)),
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          itemCount: movies.length,
          separatorBuilder: (_, _) =>
              const SizedBox(width: AppSpacing.carouselGap),
          itemBuilder: (context, index) => _PosterTile(
            movie: movies[index],
            baseUrl: instance?.url ?? '',
            apiKey: instance?.credential ?? '',
          ),
        ),
      ),
    );
  }
}

class _PosterTile extends StatelessWidget {
  const _PosterTile({
    required this.movie,
    required this.baseUrl,
    required this.apiKey,
  });

  final RadarrMovie movie;
  final String baseUrl;
  final String apiKey;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final poster = ImageUtils.extractPosterUrl(
      movie.images,
      baseUrl: baseUrl,
      apiKey: apiKey,
    );
    // Its own namespace: the Library tab's grid is alive in a sibling branch
    // and tags a poster of the same film, and two live Heroes sharing a tag is
    // an assertion, not a flight.
    final heroTag = 'radarr_overview_recent_${movie.id}';
    final caption = movie.year > 0 ? '${movie.year}' : '';

    return SizedBox(
      width: 96,
      child: PressableScale(
        onTap: () => context.push(
          ServiceRoutes.radarrMovie(movie.id, heroTag: heroTag),
          extra: movie,
        ),
        // A poster is an image with no name of its own; the tile announces the
        // film and its year as one button.
        semanticLabel: movie.title,
        semanticValue: caption.isEmpty ? null : caption,
        excludeChildSemantics: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 96,
              height: 138,
              child: MediaPosterCard(
                heroTag: heroTag,
                imageUrl: poster.url,
                imageHeaders: poster.headers,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              movie.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall
                  ?.weight(FontWeight.w600)
                  .copyWith(color: colorScheme.onSurface),
            ),
            if (caption.isNotEmpty)
              Text(
                caption,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ─── 5. History today ───────────────────────────────────────────────────────

class _HistoryTodaySection extends ConsumerWidget {
  const _HistoryTodaySection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = ref.watch(radarrHistoryTodayProvider);

    return ServiceOverviewSection(
      service: ServiceKey.radarr,
      title: 'History',
      subtitle: 'today',
      destination: ServiceTab.history,
      child: AsyncValueWidget<List<RadarrHistoryEntry>>(
        value: entries,
        serviceName: 'Radarr',
        loadingLabel: "Loading today's history",
        onRetry: () => ref.invalidate(radarrHistoryTodayProvider),
        skeleton: const ServiceOverviewRowsSkeleton(rows: 2),
        isEmpty: (items) => items.isEmpty,
        emptyBuilder: const ServiceOverviewEmpty(
          icon: Icons.history_rounded,
          label: 'Nothing yet today',
        ),
        data: (items) => Column(
          children: [for (final entry in items) _HistoryRow(entry: entry)],
        ),
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.entry});

  final RadarrHistoryEntry entry;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final tone = statusToneColor(
      colorScheme,
      entry.tone,
      surface: colorScheme.surfaceContainerLow,
    );

    return ServiceOverviewRow(
      spoken: entry.spoken,
      leading: Container(
        width: 8,
        height: 8,
        margin: const EdgeInsets.only(top: 5),
        decoration: BoxDecoration(color: tone, shape: BoxShape.circle),
      ),
      title: '${entry.title} · ${entry.event.toLowerCase()}',
      detail: entry.detail,
    );
  }
}

const List<String> _weekdayNames = [
  'Mon',
  'Tue',
  'Wed',
  'Thu',
  'Fri',
  'Sat',
  'Sun',
];

/// `Today`, `Tomorrow`, then `Wed 3`.
///
/// English weekday names are hard-coded for the same reason the month names in
/// `string_utils.dart` are: English-only is a decision here, not debt, and there
/// is no `intl` dependency to reach for.
String _dayLabel(DateTime date, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(date.year, date.month, date.day);
  final difference = day.difference(today).inDays;
  if (difference == 0) return 'Today';
  if (difference == 1) return 'Tomorrow';
  return '${_weekdayNames[day.weekday - 1]} ${day.day}';
}
