import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:go_router/go_router.dart';

import 'package:cupola/core/app_spacing.dart';

import 'package:cupola/core/title_light.dart';

import 'package:cupola/core/utils/arr_activity_display.dart';

import 'package:cupola/core/utils/arr_model_helpers.dart';

import 'package:cupola/core/utils/date_format.dart';

import 'package:cupola/core/utils/service_routes.dart';

import 'package:cupola/core/widgets/widgets.dart';

import 'package:cupola/features/media/domain/media_key.dart';

import 'package:cupola/features/media/presentation/open_media.dart';

import 'package:cupola/features/series/presentation/series_provider.dart';

import 'package:cupola/features/series/presentation/sonarr_overview_provider.dart';

import 'package:cupola/features/services/domain/service_tab.dart';

import 'package:cupola/features/services/domain/services_semantics.dart';

import 'package:cupola/features/services/presentation/service_kpi_provider.dart';

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
class SonarrOverviewScreen extends StatelessWidget {
  const SonarrOverviewScreen({
    super.key,
    this.topPadding = ServiceOverviewPage.hostedTopPadding,
  });

  /// Height of the chrome the host draws above this page.
  final double topPadding;

  @override
  Widget build(BuildContext context) {
    return ServiceOverviewPage(
      service: ServiceKey.sonarr,
      topPadding: topPadding,
      refresh: _refresh,
      sections: (ref) => [
        const _AiringSection(),
        ArrNeedsAttentionSection(
          service: ServiceKey.sonarr,
          items: sonarrNeedsAttentionProvider,
          queueRecords: sonarrQueueRecordsProvider,
          retry: [
            sonarrNeedsAttentionProvider,
            sonarrQueueRecordsProvider,
            sonarrBacklogProvider,
          ],
        ),
        const _RecentlyDownloadedSection(),
        ArrHistoryTodaySection(
          service: ServiceKey.sonarr,
          entries: sonarrHistoryTodayProvider,
          retry: [sonarrHistoryTodayProvider, sonarrHistoryPageProvider],
        ),
      ],
    );
  }
}

/// What a pull re-reads besides the readout (`ServiceOverviewPage`).
void _refresh(WidgetRef ref) {
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
    // The slab glows with its first series' light, read from a public picture
    // only.
    final lead = [
      for (final entry
          in data?.entries.take(sonarrAiringPreviewLimit) ??
              const <SonarrAiringEntry>[])
        ?remotePosterOf(entry.series.images),
    ].firstOrNull;

    return ServiceOverviewSection(
      service: ServiceKey.sonarr,
      title: 'Airing this week',
      light: lead == null
          ? null
          : ref.watch(titleLightProvider(lead)).value?.art,
      // Series, never episodes. One `nextAiring` per series is all this window
      // has, so a series airing twice this week is one row here, and calling
      // these episodes would be short by exactly the ones it cannot see.
      subtitle:
          'next $sonarrAiringDays days\u00A0· ${count == null ? '—' : '$count series'}',
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
    final now = DateTime.now();
    final day = formatDayLabel(entry.airsAt, now);
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
      leading: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ServiceOverviewDay(day: entry.airsAt, now: now),
          const SizedBox(width: AppSpacing.sm),
          ServiceOverviewArt(
            posterUrl: remotePosterOf(series.images),
            title: series.title,
          ),
        ],
      ),
      title: series.title,
      detail: qualifier,
    );
  }
}

// ─── 3. Needs attention ─────────────────────────────────────────────────────

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
        data: (items) => ServicePosterRail<SonarrDownloadedEpisode>(
          service: ServiceKey.sonarr,
          items: items,
          idOf: (episode) => episode.seriesId,
          titleOf: (episode) => episode.seriesTitle,
          imagesOf: (episode) => episode.images,
          captionOf: (episode) => episode.caption,
          onTap: (context, episode, heroTag) => switch (episode.tmdbId) {
            final tmdbId? when tmdbId > 0 => context.openMedia(
              MediaKey.tv(tmdbId),
              heroTag: heroTag,
              posterUrl: remotePosterOf(episode.images),
            ),
            _ => context.push(
              ServiceRoutes.sonarrSeries(episode.seriesId, heroTag: heroTag),
            ),
          },
        ),
      ),
    );
  }
}
