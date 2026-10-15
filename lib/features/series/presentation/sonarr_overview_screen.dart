import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:go_router/go_router.dart';

import 'package:cupola/core/app_animation.dart';

import 'package:cupola/core/app_spacing.dart';

import 'package:cupola/core/text_scale.dart';

import 'package:cupola/core/theme.dart';

import 'package:cupola/core/utils/arr_activity_display.dart';

import 'package:cupola/core/utils/arr_model_helpers.dart';

import 'package:cupola/core/utils/date_format.dart';

import 'package:cupola/core/utils/image_utils.dart';

import 'package:cupola/core/utils/service_routes.dart';

import 'package:cupola/core/widgets/widgets.dart';

import 'package:cupola/features/media/domain/media_key.dart';

import 'package:cupola/features/media/presentation/open_media.dart';

import 'package:cupola/features/series/presentation/series_provider.dart';

import 'package:cupola/features/series/presentation/sonarr_overview_provider.dart';

import 'package:cupola/features/services/domain/service_tab.dart';

import 'package:cupola/features/services/domain/services_semantics.dart';

import 'package:cupola/features/services/presentation/service_kpi_provider.dart';

import 'package:cupola/features/settings/data/connection_reach_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';

import 'package:cupola/core/status/lexicon.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// The first tab of Sonarr's service home.
///
/// Overview alone carries the identity block and the readouts: every other tab
/// is a view of one kind of record, and then four sections in the order the
/// **mobile** board draws them, which is the order that survives a narrow
/// window: what is airing, what needs a decision, what arrived, what happened
/// today. Each section ends in a link named exactly like the tab it jumps to.
///
/// **Sonarr reads as Radarr's sibling on purpose.** The two share a bar, so a
/// user who has learned one has learned the other; `RadarrOverviewScreen` is
/// the model and every departure here is forced by the record rather than
/// chosen. The record is an episode inside a season inside a series, so a row
/// names the slot as well as the series, and the week window counts *series*
/// rather than episodes because that is all its source can honestly support:
/// see `sonarr_overview_provider.dart`.
///
/// **Two regions of the board are not drawn.** The desktop board's `Root
/// folder` panel ("2.3 TB free · 81% of 12 TB") needs `GET /api/v3/diskspace`
/// for the capacity: `rootfolder` carries free space and no total, and the
/// mobile board drops the panel entirely, which is the board itself saying it
/// is desktop furniture rather than a promise. The per-row actions (`Manual
/// import`, `Search all`) need a bridge this app does not have. Both are
/// deleted rather than stubbed: better no control than one that fails.
///
/// **It draws neither the app bar nor the tab bar.** `ServiceHomeScreen` owns
/// the first and `ServiceTabScaffold` the second, both as glass bands floated
/// above this page so the ambient gradient reads continuously behind them; this
/// screen reserves the room with [topPadding] instead.
///
/// Sections load independently and fail independently. That is the design's
/// SECTION failure level: a Sonarr that answers the library and not the queue
/// still draws three regions, and the one that could not load says so in its
/// own slot rather than taking the page with it.
class SonarrOverviewScreen extends ConsumerWidget {
  const SonarrOverviewScreen({super.key, this.topPadding = _hostedTopPadding});

  /// The room the two glass bands above this page occupy.
  ///
  /// Composed from the same two constants the router composes its own from, so
  /// a screen built outside the router (a test, a preview) reserves the right
  /// space instead of tucking its first region under the tab bar.
  static const double _hostedTopPadding = kToolbarHeight + ServiceTabBar.height;

  /// Height of the chrome the host draws above this page.
  final double topPadding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final configured = ref.watch(
      currentSettingsProvider.select(
        (settings) => settings.isServiceConfigured(ServiceKey.sonarr),
      ),
    );

    return AmbientScaffold(
      accent: ServiceKey.sonarr.accent,
      body: SafeArea(
        child: configured
            // Checked BEFORE anything reaches a provider: a `FutureProvider`
            // that throws "Sonarr not configured" is a *failed* provider, and
            // Riverpod schedules a backoff retry for a condition no waiting
            // changes, which surfaces in a widget test as a pending timer.
            //
            // `.forService`, never the generic form: this is a service
            // dashboard, so the door goes to Sonarr's own connection form
            // rather than to the settings index. Resolved once here rather than
            // four times inside four sections.
            ? _OverviewBody(topPadding: topPadding)
            : NotConfiguredPlaceholder.forService(ServiceKey.sonarr),
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
        invalidateServiceReadout(ref, ServiceKey.sonarr);
        // The two libraries, not only the readings of them. Both are plain
        // `FutureProvider`s cached for the session, so invalidating just the
        // derived pair re-ran `sonarrAiringWeek` against the same cached list
        // with a new clock, and re-read the KPI rail off the same cached list
        // again, a pull-to-refresh that refetched nothing. An episode that
        // aired, a series added, a show that ended: none of it appeared.
        // One read of the library, which the rail and the week share
        // (`sonarrKpiLibraryProvider` and `sonarrOverviewSeriesProvider` are
        // names for it): invalidating it moves all three.
        ref.invalidate(seriesProvider);
        ref.invalidate(sonarrKpiLibraryProvider);
        ref.invalidate(sonarrOverviewSeriesProvider);
        ref.invalidate(sonarrAiringWeekProvider);
        ref.invalidate(sonarrNeedsAttentionProvider);
        ref.invalidate(sonarrQueueRecordsProvider);
        ref.invalidate(sonarrBacklogProvider);
        // The page, not the two readings of it: invalidating only the derived
        // pair would re-read a cached page and call a pull-to-refresh a
        // refresh.
        ref.invalidate(sonarrHistoryPageProvider);
        ref.invalidate(sonarrRecentlyDownloadedProvider);
        ref.invalidate(sonarrHistoryTodayProvider);
        await Future<void>.delayed(AppAnimation.durationMd);
      },
      // One scroll view for the whole page: the regions are one column of
      // reading, not four independently scrolling panes.
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.only(
          bottom: FloatingNavBarMetrics.getScrollViewBottomPadding(context),
        ),
        children: [
          if (topPadding > 0) SizedBox(height: topPadding),
          const ServiceOverviewIdentity(service: ServiceKey.sonarr),
          ...sectionsOrOneLine(ref, ServiceKey.sonarr, [
            ServiceKpiPeek(
              kpis: ref.watch(serviceKpiProvider(ServiceKey.sonarr)),
              accent: ServiceKey.sonarr.accent,
            ),
            const _AiringSection(),
            const _NeedsAttentionSection(),
            const _RecentlyDownloadedSection(),
            const _HistoryTodaySection(),
          ]),
        ],
      ),
    );
  }
}

// ─── 2. Airing this week ────────────────────────────────────────────────────

class _AiringSection extends ConsumerWidget {
  const _AiringSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final week = ref.watch(sonarrAiringWeekProvider);
    final data = week.asData?.value;
    // "—" while the library is loading, after it failed, **and** when Sonarr
    // never sent a next-airing date at all: a "0 series" printed over an
    // unanswered question is a claim nobody made. This is the one figure on
    // this page whose source can answer and still say nothing.
    final count = data == null || !data.canReport ? null : data.entries.length;

    return ServiceOverviewSection(
      service: ServiceKey.sonarr,
      title: 'Airing this week',
      // Series, never episodes. One `nextAiring` per series is all this window
      // has, so a series airing twice this week is one row here, and calling
      // these episodes would be short by exactly the ones it cannot see.
      subtitle:
          'next $sonarrAiringDays days · ${count == null ? '—' : '$count series'}',
      destination: ServiceTab.calendar,
      child: AsyncValueWidget<SonarrAiringWeek>.section(
        value: week,
        service: ServiceKey.sonarr,
        consequence: 'what is airing this week is not shown',
        loadingLabel: 'Loading what is airing this week',
        onRetry: () {
          ref.invalidate(sonarrAiringWeekProvider);
          ref.invalidate(sonarrOverviewSeriesProvider);
        },
        skeleton: const ServiceOverviewRowsSkeleton(rows: 2),
        // Only the answerable emptiness is "empty"; the other one is a
        // different sentence and is drawn below, because the empty slot takes a
        // widget rather than a function of the value.
        isEmpty: (value) => value.entries.isEmpty && value.canReport,
        emptyBuilder: const ServiceOverviewEmpty(
          icon: Icons.event_available_rounded,
          label: 'Nothing airing this week',
        ),
        data: (value) {
          if (value.entries.isEmpty) {
            return const ServiceOverviewEmpty(
              icon: Icons.help_outline_rounded,
              label: 'Sonarr did not say when anything next airs',
            );
          }
          return Column(
            children: [
              for (final entry in value.entries.take(sonarrAiringPreviewLimit))
                _AiringRow(entry: entry),
            ],
          );
        },
      ),
    );
  }
}

class _AiringRow extends StatelessWidget {
  const _AiringRow({required this.entry});

  final SonarrAiringEntry entry;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final day = formatDayLabel(entry.airsAt, DateTime.now());
    final series = entry.series;
    // Monitored is the fact that decides whether Sonarr will actually do
    // anything when the episode drops, which is the whole reason the row is
    // worth a line. Neutral ink either way: an unmonitored series is a choice
    // somebody made, not a fault.
    final qualifier = joinDisplayParts([
      formatClockTime(entry.airsAt),
      series.monitored ? 'monitored' : 'unmonitored',
    ]);

    return ServiceOverviewRow(
      spoken: joinSpokenParts([day, series.title, spokenFromDotted(qualifier)]),
      leading: SizedBox(
        width: 58,
        child: Text(
          day,
          maxLines: 2,
          style: AppTheme.chrome(
            context,
            size: 11,
            weight: FontWeight.w600,
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      ),
      title: series.title,
      detail: qualifier,
    );
  }
}

// ─── 3. Needs attention ─────────────────────────────────────────────────────

class _NeedsAttentionSection extends ConsumerWidget {
  const _NeedsAttentionSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(sonarrNeedsAttentionProvider);
    final count = items.asData?.value.length;
    // A queue walk that stopped short: see the Radarr home's twin.
    final floor =
        ref.watch(sonarrQueueRecordsProvider).value?.cutShort ?? false;

    return ServiceOverviewSection(
      service: ServiceKey.sonarr,
      title: 'Needs attention',
      subtitle: count == null ? '—' : (floor ? Lexicon.floor(count) : '$count'),
      // No link: every row here belongs to a different tab: a stalled download
      // to Queue, a backlog to Wanted, and a single destination would have to
      // lie about the rest.
      child: AsyncValueWidget<List<SonarrAttentionItem>>.section(
        value: items,
        service: ServiceKey.sonarr,
        consequence: 'what needs attention is not shown',
        loadingLabel: 'Loading what needs attention',
        onRetry: () {
          ref.invalidate(sonarrNeedsAttentionProvider);
          ref.invalidate(sonarrQueueRecordsProvider);
          ref.invalidate(sonarrBacklogProvider);
        },
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

  final SonarrAttentionItem item;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    // Through the tone rule, never a raw `AppColors.*`: amber is a fault, and
    // the backlog rows (missing episodes, episodes below the cutoff) are
    // neutral by construction. `surface:` is the container this row actually
    // lands on, which is what the walk needs to guarantee contrast.
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

// ─── 4. Recently downloaded ─────────────────────────────────────────────────

class _RecentlyDownloadedSection extends ConsumerWidget {
  const _RecentlyDownloadedSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final episodes = ref.watch(sonarrRecentlyDownloadedProvider);

    return ServiceOverviewSection.bleed(
      service: ServiceKey.sonarr,
      title: 'Recently downloaded',
      // "latest imports" and not the board's "9 episodes this week": one page
      // of history need not reach back a week, so a count taken from it would
      // be the number of rows that happened to fit rather than the number of
      // episodes that arrived.
      subtitle: 'latest imports',
      destination: ServiceTab.library,
      child: AsyncValueWidget<List<SonarrDownloadedEpisode>>.bleedSection(
        value: episodes,
        service: ServiceKey.sonarr,
        consequence: 'the recently downloaded episodes are not shown',
        loadingLabel: 'Loading recently downloaded episodes',
        onRetry: () {
          ref.invalidate(sonarrRecentlyDownloadedProvider);
          ref.invalidate(sonarrHistoryPageProvider);
        },
        skeleton: AppSkeleton.posterRow(height: 138),
        isEmpty: (items) => items.isEmpty,
        emptyBuilder: const Padding(
          padding: EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: ServiceOverviewEmpty(
            icon: Icons.tv_outlined,
            label: 'Nothing downloaded recently',
          ),
        ),
        data: (items) => _PosterRail(episodes: items),
      ),
    );
  }
}

class _PosterRail extends ConsumerWidget {
  const _PosterRail({required this.episodes});

  final List<SonarrDownloadedEpisode> episodes;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final instance = ref.watch(activeInstanceProvider(ServiceKey.sonarr));
    // The posters at the address the lens's connection is reached at now.
    final reachedAt = instance == null
        ? ''
        : ref.watch(connectionReachProvider(instance.id))?.url ?? '';

    return SizedBox(
      // 138pt poster, the gap, and two label lines, grown by the reading size
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
          itemCount: episodes.length,
          separatorBuilder: (_, _) =>
              const SizedBox(width: AppSpacing.carouselGap),
          itemBuilder: (context, index) => _PosterTile(
            episode: episodes[index],
            baseUrl: reachedAt,
            apiKey: instance?.credential ?? '',
          ),
        ),
      ),
    );
  }
}

class _PosterTile extends StatelessWidget {
  const _PosterTile({
    required this.episode,
    required this.baseUrl,
    required this.apiKey,
  });

  final SonarrDownloadedEpisode episode;
  final String baseUrl;
  final String apiKey;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final poster = ImageUtils.extractPosterUrl(
      episode.images,
      baseUrl: baseUrl,
      apiKey: apiKey,
    );
    // Its own namespace: the Library tab's grid is alive in a sibling branch
    // and tags a poster of the same series, and two live Heroes sharing a tag
    // is an assertion, not a flight.
    final heroTag = 'sonarr_overview_recent_${episode.seriesId}';
    final caption = episode.caption;

    return SizedBox(
      width: 96,
      child: PressableScale(
        // The tile links to the *series*, not to the episode: the series'
        // own page, under this tab, by the TMDB id the record embeds; else
        // the way through its id here.
        onTap: () => switch (episode.tmdbId) {
          final tmdbId? when tmdbId > 0 => context.openMedia(
            MediaKey.tv(tmdbId),
            heroTag: heroTag,
            posterUrl: remotePosterOf(episode.images),
          ),
          _ => context.push(
            ServiceRoutes.sonarrSeries(episode.seriesId, heroTag: heroTag),
          ),
        },
        // A poster is an image with no name of its own; the tile announces the
        // series, the slot and the age as one button.
        semanticLabel: episode.seriesTitle,
        semanticValue: caption.isEmpty ? null : spokenFromDotted(caption),
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
              episode.seriesTitle,
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
    final entries = ref.watch(sonarrHistoryTodayProvider);

    return ServiceOverviewSection(
      service: ServiceKey.sonarr,
      title: 'History',
      subtitle: 'today',
      destination: ServiceTab.history,
      child: AsyncValueWidget<List<SonarrHistoryEntry>>.section(
        value: entries,
        service: ServiceKey.sonarr,
        consequence: "today's history is not shown",
        loadingLabel: "Loading today's history",
        onRetry: () {
          ref.invalidate(sonarrHistoryTodayProvider);
          ref.invalidate(sonarrHistoryPageProvider);
        },
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

  final SonarrHistoryEntry entry;

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
      title: '${entry.subject} · ${entry.event.toLowerCase()}',
      detail: entry.detail,
    );
  }
}
