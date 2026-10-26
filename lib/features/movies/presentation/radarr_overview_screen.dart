import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:go_router/go_router.dart';

import 'package:cupola/core/app_spacing.dart';

import 'package:cupola/core/title_light.dart';

import 'package:cupola/core/utils/arr_activity_display.dart';

import 'package:cupola/core/utils/date_format.dart';

import 'package:cupola/core/utils/service_routes.dart';

import 'package:cupola/core/widgets/widgets.dart';

import 'package:cupola/features/movies/domain/models/radarr_movie.dart';

import 'package:cupola/features/movies/presentation/movies_provider.dart';
import 'package:cupola/features/movies/presentation/radarr_overview_provider.dart';

import 'package:cupola/features/services/domain/service_tab.dart';

import 'package:cupola/features/services/domain/services_semantics.dart';

import 'package:cupola/features/services/presentation/service_kpi_provider.dart';

import 'package:cupola/features/services/presentation/services_provider.dart';

import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/media/domain/media_key.dart';
import 'package:cupola/features/media/presentation/open_media.dart';
import 'package:cupola/core/utils/arr_model_helpers.dart';

/// The first tab of Radarr's service home.
///
/// Overview alone carries the identity block and the readouts: every other tab
/// is a view of one kind of record, and then five sections in the order the
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
class RadarrOverviewScreen extends StatelessWidget {
  const RadarrOverviewScreen({
    super.key,
    this.topPadding = ServiceOverviewPage.hostedTopPadding,
  });

  /// Height of the chrome the host draws above this page.
  final double topPadding;

  @override
  Widget build(BuildContext context) {
    return ServiceOverviewPage(
      service: ServiceKey.radarr,
      topPadding: topPadding,
      refresh: _refresh,
      sections: (ref) => [
        const _ComingUpSection(),
        ArrNeedsAttentionSection(
          service: ServiceKey.radarr,
          items: radarrNeedsAttentionProvider,
          queueRecords: radarrQueueRecordsProvider,
          retry: [
            radarrNeedsAttentionProvider,
            radarrQueueRecordsProvider,
            radarrCutoffUnmetCountProvider,
          ],
        ),
        const _RecentlyAddedSection(),
        ArrHistoryTodaySection(
          service: ServiceKey.radarr,
          entries: radarrHistoryTodayProvider,
          retry: [radarrHistoryTodayProvider],
        ),
      ],
    );
  }
}

/// What a pull re-reads besides the readout (`ServiceOverviewPage`).
void _refresh(WidgetRef ref) {
  // The library itself, not only the three readings of it. Coming up,
  // Recently added and all four figures on the rail fall out of
  // `moviesProvider`, which is a plain `FutureProvider` fetched once for
  // the life of the app, so invalidating only the derived trio re-ran
  // the window functions against the same cached list with a new clock
  // and re-read the rail off the same cached list again. A pull that
  // refetched nothing: a film that landed, one that was added or a
  // release date that moved never appeared.
  ref.invalidate(moviesProvider);
  // The Overview's own throwing read of it. See
  // `radarrOverviewMoviesProvider`.
  ref.invalidate(radarrOverviewMoviesProvider);
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
    // The slab glows with its first title's light, read from a public
    // picture only, once the row has drawn it.
    final lead = [
      for (final release
          in releases.value?.take(radarrComingUpPreviewLimit) ??
              const <RadarrUpcomingRelease>[])
        ?remotePosterOf(release.movie.images),
    ].firstOrNull;

    return ServiceOverviewSection(
      service: ServiceKey.radarr,
      title: 'Coming up',
      light: lead == null
          ? null
          : ref.watch(titleLightProvider(lead)).value?.art,
      // "—" while the library is loading or after it failed: a "0 releases"
      // printed over an unanswered question is a claim nobody made.
      subtitle:
          'next $radarrComingUpDays days\u00A0· '
          '${count == null ? '—' : '$count ${count == 1 ? 'release' : 'releases'}'}',
      destination: ServiceTab.calendar,
      child: AsyncValueWidget<List<RadarrUpcomingRelease>>.section(
        value: releases,
        service: ServiceKey.radarr,
        consequence: 'what is coming up is not shown',
        loadingLabel: 'Loading what is coming up',
        onRetry: () {
          ref.invalidate(radarrOverviewMoviesProvider);
          ref.invalidate(radarrComingUpProvider);
        },
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
    final now = DateTime.now();
    final day = formatDayLabel(release.date, now);
    final movie = release.movie;
    // Monitored is the fact that decides whether Radarr will actually do
    // anything on that date, which is the whole reason the row is worth a line.
    final qualifier = joinDisplayParts([
      release.kind.label,
      movie.monitored ? 'monitored' : 'unmonitored',
    ]);

    return ServiceOverviewRow(
      spoken: joinSpokenParts([day, movie.title, spokenFromDotted(qualifier)]),
      leading: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ServiceOverviewDay(day: release.date, now: now),
          const SizedBox(width: AppSpacing.sm),
          ServiceOverviewArt(
            posterUrl: remotePosterOf(movie.images),
            title: movie.title,
          ),
        ],
      ),
      title: movie.title,
      detail: qualifier,
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
      child: AsyncValueWidget<List<RadarrMovie>>.bleedSection(
        value: movies,
        service: ServiceKey.radarr,
        consequence: 'the recently added movies are not shown',
        loadingLabel: 'Loading recently added movies',
        onRetry: () {
          ref.invalidate(radarrOverviewMoviesProvider);
          ref.invalidate(radarrRecentlyAddedProvider);
        },
        skeleton: AppSkeleton.posterRow(height: 138),
        isEmpty: (items) => items.isEmpty,
        emptyBuilder: const Padding(
          padding: EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: ServiceOverviewEmpty(
            icon: Icons.movie_outlined,
            label: 'Nothing added yet',
          ),
        ),
        data: (items) => ServicePosterRail<RadarrMovie>(
          service: ServiceKey.radarr,
          items: items,
          idOf: (movie) => movie.id,
          titleOf: (movie) => movie.title,
          imagesOf: (movie) => movie.images,
          captionOf: (movie) => movie.year > 0 ? '${movie.year}' : null,
          onTap: (context, movie, heroTag) => movie.tmdbId <= 0
              ? context.push(
                  ServiceRoutes.radarrMovie(movie.id, heroTag: heroTag),
                )
              : context.openMedia(
                  MediaKey.movie(movie.tmdbId),
                  heroTag: heroTag,
                  posterUrl: remotePosterOf(movie.images),
                ),
        ),
      ),
    );
  }
}
