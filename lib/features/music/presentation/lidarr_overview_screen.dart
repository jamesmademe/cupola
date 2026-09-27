import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:go_router/go_router.dart';

import 'package:cupola/core/app_animation.dart';

import 'package:cupola/core/app_spacing.dart';

import 'package:cupola/core/text_scale.dart';

import 'package:cupola/core/theme.dart';

import 'package:cupola/core/utils/image_utils.dart';

import 'package:cupola/core/utils/service_routes.dart';

import 'package:cupola/core/widgets/widgets.dart';

import 'package:cupola/features/music/domain/models/lidarr_artist.dart';

import 'package:cupola/features/music/presentation/lidarr_overview_provider.dart';

import 'package:cupola/features/music/presentation/music_provider.dart';

import 'package:cupola/features/services/domain/service_tab.dart';

import 'package:cupola/features/services/domain/services_semantics.dart';

import 'package:cupola/features/services/presentation/service_kpi_provider.dart';

import 'package:cupola/features/settings/data/settings_provider.dart';

import 'package:cupola/features/settings/domain/service_key.dart';

/// The first tab of Lidarr's service home.
///
/// Overview alone carries the identity block and the readouts — every other tab
/// is a view of one kind of record — and then the sections in the order the
/// narrow board draws them: what needs a decision, what arrived, what happened
/// today, and where it all lands. Each section that belongs to exactly one tab
/// ends in a link named exactly like that tab.
///
/// **It draws neither the app bar nor the tab bar.** `ServiceHomeScreen` owns
/// the first and `ServiceTabScaffold` the second, both as glass bands floated
/// above this page so the ambient gradient reads continuously behind them; this
/// screen reserves the room with [topPadding] instead.
///
/// **The board's first region is missing, and that is the design.** `HomeLidarr`
/// opens on a seven-day calendar of upcoming releases. A Lidarr artist carries
/// no release dates — the date belongs to the album — and this client's only
/// album call is artist-scoped, so the window would need `GET /api/v1/calendar`,
/// which it does not make. Radarr can draw the same region because a film's
/// dates ride on the library row it already has; Lidarr cannot, and a window
/// the server was never asked about is a window that mostly reports on the
/// quality of the guess behind it.
///
/// Sections load independently and fail independently. That is the design's
/// SECTION failure level: a Lidarr that answers the library and not the queue
/// still draws three regions, and the one that could not load says so in its
/// own slot rather than taking the page with it.
class LidarrOverviewScreen extends ConsumerWidget {
  const LidarrOverviewScreen({super.key, this.topPadding = _hostedTopPadding});

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
        (settings) => settings.isServiceConfigured(ServiceKey.lidarr),
      ),
    );

    return AmbientScaffold(
      accent: ServiceKey.lidarr.accent,
      body: SafeArea(
        // Checked **before** anything reaches a provider, not after: a fetch on
        // an unconfigured service throws "Lidarr not configured", and a
        // FutureProvider that throws is a failed provider — Riverpod schedules
        // a backoff retry for a condition no amount of waiting changes, which
        // surfaces in tests as a pending timer and on device as four doomed
        // requests per section.
        child: configured
            ? _OverviewBody(topPadding: topPadding)
            // `.forService`, never the generic form: this is a service
            // dashboard, so the door goes to Lidarr's own connection form
            // rather than to the settings index.
            : NotConfiguredPlaceholder.forService(ServiceKey.lidarr),
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
        invalidateServiceReadout(ref, ServiceKey.lidarr);
        // The artist list itself, and not only the two things derived from it.
        // `lidarrRecentlyAddedProvider` re-runs on invalidation but re-reads a
        // library that is still holding the answer it already had, so without
        // these a pull-to-refresh re-sorts the same six artists and reports
        // itself finished. Both reads: the grid's degrading one and this
        // screen's own — see `lidarrOverviewArtistsProvider`.
        ref.invalidate(musicProvider);
        ref.invalidate(lidarrOverviewArtistsProvider);
        // And the rail's own non-swallowing read of it. See
        // `sonarrKpiLibraryProvider`.
        ref.invalidate(lidarrKpiLibraryProvider);
        ref.invalidate(lidarrRecentlyAddedProvider);
        ref.invalidate(lidarrQueueRecordsProvider);
        ref.invalidate(lidarrMissingPageProvider);
        ref.invalidate(lidarrNeedsAttentionProvider);
        ref.invalidate(lidarrHistoryTodayProvider);
        ref.invalidate(lidarrRootFoldersProvider);
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
          const ServiceOverviewIdentity(service: ServiceKey.lidarr),
          ServiceKpiPeek(
            kpis: ref.watch(serviceKpiProvider(ServiceKey.lidarr)),
            accent: ServiceKey.lidarr.accent,
          ),
          const _NeedsAttentionSection(),
          const _RecentlyAddedSection(),
          const _HistoryTodaySection(),
          const _RootFoldersSection(),
        ],
      ),
    );
  }
}

// ─── 1. Needs attention ─────────────────────────────────────────────────────

class _NeedsAttentionSection extends ConsumerWidget {
  const _NeedsAttentionSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(lidarrNeedsAttentionProvider);
    final count = items.asData?.value.length;

    return ServiceOverviewSection(
      service: ServiceKey.lidarr,
      title: 'Needs attention',
      // "—" while the queue and the wishlist are loading or after either
      // failed: a "0" printed over an unanswered question is a claim nobody
      // made, and it is the reassuring direction of wrong.
      subtitle: count == null ? '—' : '$count',
      // No link: the fault rows belong to Queue and the backlog row to Wanted,
      // and a single destination would have to lie about one of them.
      child: AsyncValueWidget<List<LidarrAttentionItem>>(
        value: items,
        serviceName: 'Lidarr',
        loadingLabel: 'Loading what needs attention',
        onRetry: () {
          ref.invalidate(lidarrNeedsAttentionProvider);
          ref.invalidate(lidarrQueueRecordsProvider);
          ref.invalidate(lidarrMissingPageProvider);
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

  final LidarrAttentionItem item;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    // Through the tone rule, never a raw `AppColors.*`: amber is a fault, and
    // the backlog row — monitored albums with no files — is neutral by
    // construction. Walking it against the surface it actually lands on is the
    // other half: the accent-tinted section ground is not `surface`.
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

// ─── 2. Recently added ──────────────────────────────────────────────────────

class _RecentlyAddedSection extends ConsumerWidget {
  const _RecentlyAddedSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final artists = ref.watch(lidarrRecentlyAddedProvider);

    return ServiceOverviewSection.bleed(
      service: ServiceKey.lidarr,
      title: 'Recently added',
      // Says "artists" out loud, because the board says albums: the rail is
      // one granularity coarser than it was drawn, and the subtitle is where
      // that is admitted rather than hoped nobody notices.
      //
      // The word and **no figure**. The rail is the newest
      // [lidarrRecentlyAddedLimit] artists, so its length is the cap for any
      // library that has added that many — a count of the sample printed in the
      // place a section subtitle counts the set. Radarr's sibling rail, which
      // is capped the same way, states no figure at all for the same reason.
      subtitle: 'artists',
      destination: ServiceTab.library,
      child: AsyncValueWidget<List<LidarrArtist>>(
        value: artists,
        serviceName: 'Lidarr',
        loadingLabel: 'Loading recently added artists',
        onRetry: () {
          ref.invalidate(lidarrOverviewArtistsProvider);
          ref.invalidate(lidarrRecentlyAddedProvider);
        },
        skeleton: AppSkeleton.posterRow(height: 138),
        isEmpty: (items) => items.isEmpty,
        emptyBuilder: const Padding(
          padding: EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: ServiceOverviewEmpty(
            icon: Icons.library_music_outlined,
            label: 'Nothing added yet',
          ),
        ),
        data: (items) => _PosterRail(artists: items),
      ),
    );
  }
}

class _PosterRail extends ConsumerWidget {
  const _PosterRail({required this.artists});

  final List<LidarrArtist> artists;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final instance = ref.watch(activeInstanceProvider(ServiceKey.lidarr));

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
          itemCount: artists.length,
          separatorBuilder: (_, _) =>
              const SizedBox(width: AppSpacing.carouselGap),
          itemBuilder: (context, index) => _PosterTile(
            artist: artists[index],
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
    required this.artist,
    required this.baseUrl,
    required this.apiKey,
  });

  final LidarrArtist artist;
  final String baseUrl;
  final String apiKey;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final poster = ImageUtils.extractPosterUrl(
      artist.images,
      baseUrl: baseUrl,
      apiKey: apiKey,
    );
    // Its own namespace: the Library tab's grid is alive in a sibling branch
    // and tags a poster of the same artist, and two live Heroes sharing a tag
    // is an assertion, not a flight.
    final heroTag = 'lidarr_overview_recent_${artist.id}';
    // Albums, never tracks. The two are different counts of different things —
    // an artist with four albums has some hundreds of tracks — and the model
    // carries both, which is exactly how they get swapped.
    //
    // Zero is silence, not a caption. `albumCount` reads `statistics`, which is
    // nullable on the model and absent from any artist record the server sent
    // without it — so a plain `'${artist.albumCount} albums'` captions the tile
    // "0 albums" and says it to a screen reader too, which is a fact about the
    // payload wearing the clothes of a fact about the artist, in the reassuring
    // direction. The same guard `global_search_provider.dart` puts on the same
    // getter for the same reason.
    final caption = switch (artist.albumCount) {
      0 => null,
      1 => '1 album',
      final count => '$count albums',
    };

    return SizedBox(
      width: 96,
      child: PressableScale(
        onTap: () => context.push(
          ServiceRoutes.lidarrArtist(artist.id, heroTag: heroTag),
          extra: artist,
        ),
        // A poster is an image with no name of its own; the tile announces the
        // artist and the size of their discography as one button.
        semanticLabel: artist.artistName,
        semanticValue: caption,
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
              artist.artistName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall
                  ?.weight(FontWeight.w600)
                  .copyWith(color: colorScheme.onSurface),
            ),
            if (caption != null)
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

// ─── 3. History today ───────────────────────────────────────────────────────

class _HistoryTodaySection extends ConsumerWidget {
  const _HistoryTodaySection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = ref.watch(lidarrHistoryTodayProvider);

    return ServiceOverviewSection(
      service: ServiceKey.lidarr,
      title: 'History',
      subtitle: 'today',
      destination: ServiceTab.history,
      child: AsyncValueWidget<List<LidarrHistoryEntry>>(
        value: entries,
        serviceName: 'Lidarr',
        loadingLabel: "Loading today's history",
        onRetry: () => ref.invalidate(lidarrHistoryTodayProvider),
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

  final LidarrHistoryEntry entry;

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

// ─── 4. Root folders ────────────────────────────────────────────────────────

/// Where this Lidarr files music, and how much room is left.
///
/// The board's version of this region carries a capacity bar — `2.2 TB used ·
/// 55% of 4 TB`. A root folder record reports free space and nothing else, so
/// the bar has no denominator that is not invented; it is absent, and the one
/// figure the server really sends is stated plainly beside the path. The narrow
/// board drops this region entirely for room, which is why it sits last: it is
/// the region a phone can scroll past.
class _RootFoldersSection extends ConsumerWidget {
  const _RootFoldersSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final folders = ref.watch(lidarrRootFoldersProvider);

    return ServiceOverviewSection(
      service: ServiceKey.lidarr,
      title: 'Root folders',
      subtitle: lidarrCountLabel(folders.asData?.value.length, noun: 'folder'),
      // No link: the board's "Manage" is a settings surface, and Lidarr's bar
      // has no tab that leads there. A link to the nearest tab would be a
      // different promise wearing the right word.
      child: AsyncValueWidget<List<LidarrRootFolder>>(
        value: folders,
        serviceName: 'Lidarr',
        loadingLabel: 'Loading root folders',
        onRetry: () => ref.invalidate(lidarrRootFoldersProvider),
        skeleton: const ServiceOverviewRowsSkeleton(rows: 1),
        isEmpty: (items) => items.isEmpty,
        emptyBuilder: const ServiceOverviewEmpty(
          icon: Icons.folder_off_outlined,
          label: 'No root folder configured',
        ),
        data: (items) => Column(
          children: [
            for (final folder in items) _RootFolderRow(folder: folder),
          ],
        ),
      ),
    );
  }
}

class _RootFolderRow extends StatelessWidget {
  const _RootFolderRow({required this.folder});

  final LidarrRootFolder folder;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return ServiceOverviewRow(
      // One sentence: the path and its free space are one fact about one
      // folder, and read as two nodes the figure has lost its subject.
      spoken: joinSpokenParts([
        folder.path,
        folder.freeSpace == null ? 'free space unavailable' : folder.freeLabel,
      ]),
      leading: Icon(
        Icons.folder_outlined,
        size: 18,
        // Neutral ink, deliberately: a path is not a status, and disk pressure
        // is a figure this section cannot compute without a capacity.
        color: colorScheme.onSurfaceVariant,
      ),
      title: folder.path,
      detail: '',
      trailing: folder.freeLabel,
    );
  }
}
