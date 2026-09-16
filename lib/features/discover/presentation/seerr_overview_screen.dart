import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:go_router/go_router.dart';

import 'package:cupola/core/app_animation.dart';

import 'package:cupola/core/app_spacing.dart';

import 'package:cupola/core/models/media_preview.dart';

import 'package:cupola/core/text_scale.dart';

import 'package:cupola/core/theme.dart';

import 'package:cupola/core/utils/image_utils.dart';

import 'package:cupola/core/utils/service_routes.dart';

import 'package:cupola/core/widgets/widgets.dart';

import 'package:cupola/features/discover/presentation/discover_provider.dart';

import 'package:cupola/features/discover/presentation/seerr_overview_provider.dart';

import 'package:cupola/features/services/domain/service_tab.dart';

import 'package:cupola/features/services/presentation/service_kpi_provider.dart';

import 'package:cupola/features/services/presentation/services_provider.dart';

import 'package:cupola/features/settings/data/settings_provider.dart';

import 'package:cupola/features/settings/domain/service_key.dart';

/// The first tab of Seerr's service home.
///
/// **Seerr is the exception among the media services.** Every other home leads
/// with what is arriving or what is on disk; this one leads with the decisions,
/// then the work already accepted, and the discover rails move *down* — because
/// approving is what the phone opens Seerr for, and the rails are the reason
/// the service exists rather than the reason the page is opened.
///
/// Overview alone carries the identity block and the readouts; every other tab
/// is a view of one kind of record. Each section ends in a link named exactly
/// like the tab it jumps to.
///
/// **It draws neither the app bar nor the tab bar.** The host owns both as
/// glass bands floated above this page, and this screen reserves the room with
/// [topPadding] instead.
///
/// Sections load and fail independently: a Seerr that answers its requests and
/// not TMDB still draws its decisions.
class SeerrOverviewScreen extends ConsumerWidget {
  const SeerrOverviewScreen({super.key, this.topPadding = _hostedTopPadding});

  static const double _hostedTopPadding = kToolbarHeight + ServiceTabBar.height;

  /// Height of the chrome the host draws above this page.
  final double topPadding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final configured = ref.watch(
      currentSettingsProvider.select(
        (settings) => settings.isServiceConfigured(ServiceKey.seerr),
      ),
    );

    return AmbientScaffold(
      accent: ServiceKey.seerr.accent,
      body: SafeArea(
        child: configured
            ? _OverviewBody(topPadding: topPadding)
            // `.forService`: this is a service dashboard, so the door goes to
            // Seerr's own connection form rather than to the settings index.
            : NotConfiguredPlaceholder.forService(ServiceKey.seerr),
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
        ref.invalidate(serviceSummaryProvider(ServiceKey.seerr));
        ref.invalidate(serviceKpiProvider(ServiceKey.seerr));
        ref.invalidate(requestsProvider);
        ref.invalidate(seerrOverviewDecisionsProvider);
        ref.invalidate(seerrOverviewProcessingProvider);
        ref.invalidate(discoverTrendingProvider);
        ref.invalidate(seerrOverviewTrendingProvider);
        await Future<void>.delayed(AppAnimation.durationMd);
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.only(
          bottom: FloatingNavBarMetrics.getScrollViewBottomPadding(context),
        ),
        children: [
          if (topPadding > 0) SizedBox(height: topPadding),
          const ServiceOverviewIdentity(service: ServiceKey.seerr),
          ServiceKpiPeek(
            kpis: ref.watch(serviceKpiProvider(ServiceKey.seerr)),
            accent: ServiceKey.seerr.accent,
          ),
          const _DecisionsSection(),
          const _ProcessingSection(),
          const _TrendingSection(),
        ],
      ),
    );
  }
}

// ─── 1. Needs a decision ────────────────────────────────────────────────────

/// The region the whole page is ordered around.
///
/// It stays on screen with its empty state when nothing is waiting, unlike the
/// dashboard's `SeerrDecisionsSection` which vanishes: this is a *tab*, and a
/// tab whose first region disappears leaves the user unable to tell a working
/// auto-approve rule from a page that failed to load.
class _DecisionsSection extends ConsumerWidget {
  const _DecisionsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final section = ref.watch(seerrOverviewDecisionsProvider);
    final total = section.asData?.value.total;

    return ServiceOverviewSection(
      service: ServiceKey.seerr,
      title: 'Needs a decision',
      // "—" while the list is loading or after it failed: a "0 waiting" printed
      // over an unanswered question is a claim nobody made.
      subtitle: total == null
          ? '—'
          : '$total ${total == 1 ? 'request' : 'requests'} waiting',
      destination: ServiceTab.requests,
      child: AsyncValueWidget<SeerrOverviewSection>(
        value: section,
        serviceName: 'Seerr',
        loadingLabel: 'Loading what needs a decision',
        onRetry: () => ref.invalidate(requestsProvider),
        skeleton: const ServiceOverviewRowsSkeleton(rows: 3),
        isEmpty: (data) => data.rows.isEmpty,
        // A resting state wears no alarm chrome: an auto-approving Seerr with
        // nothing waiting is working exactly as configured.
        emptyBuilder: const ServiceOverviewEmpty(
          icon: Icons.check_circle_outline_rounded,
          label: 'Nothing waiting on you',
        ),
        data: (data) => Column(
          children: [for (final row in data.rows) _RequestRow(row: row)],
        ),
      ),
    );
  }
}

// ─── 2. Processing ──────────────────────────────────────────────────────────

/// What Seerr has already accepted and is still working on.
class _ProcessingSection extends ConsumerWidget {
  const _ProcessingSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final section = ref.watch(seerrOverviewProcessingProvider);
    final total = section.asData?.value.total;

    return ServiceOverviewSection(
      service: ServiceKey.seerr,
      title: 'Processing',
      subtitle: total == null ? '—' : '$total',
      destination: ServiceTab.requests,
      child: AsyncValueWidget<SeerrOverviewSection>(
        value: section,
        serviceName: 'Seerr',
        loadingLabel: 'Loading what is processing',
        onRetry: () => ref.invalidate(requestsProvider),
        skeleton: const ServiceOverviewRowsSkeleton(rows: 2),
        isEmpty: (data) => data.rows.isEmpty,
        emptyBuilder: const ServiceOverviewEmpty(
          icon: Icons.inbox_rounded,
          label: 'Nothing in flight',
        ),
        data: (data) => Column(
          children: [for (final row in data.rows) _RequestRow(row: row)],
        ),
      ),
    );
  }
}

class _RequestRow extends StatelessWidget {
  const _RequestRow({required this.row});

  final SeerrOverviewRow row;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    // Through the tone rule, never a raw `AppColors.*`. A pending request is
    // neutral here by construction — see [SeerrOverviewRow.tone].
    final tone = statusToneColor(
      colorScheme,
      row.tone,
      surface: colorScheme.surfaceContainerLow,
    );

    return ServiceOverviewRow(
      spoken: row.spoken,
      leading: Container(
        width: 8,
        height: 8,
        margin: const EdgeInsets.only(top: 5),
        decoration: BoxDecoration(color: tone, shape: BoxShape.circle),
      ),
      title: row.headline,
      detail: row.detail,
    );
  }
}

// ─── 3. Trending ────────────────────────────────────────────────────────────

/// The discover rail, which on this service is deliberately last.
class _TrendingSection extends ConsumerWidget {
  const _TrendingSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trending = ref.watch(seerrOverviewTrendingProvider);

    return ServiceOverviewSection.bleed(
      service: ServiceKey.seerr,
      title: 'Trending',
      // Seerr's `/discover/trending` proxies TMDB's *weekly* list, so the label
      // and the window agree.
      subtitle: 'this week',
      destination: ServiceTab.discover,
      child: AsyncValueWidget<List<MediaPreview>>(
        value: trending,
        serviceName: 'Seerr',
        loadingLabel: 'Loading what is trending',
        onRetry: () => ref.invalidate(discoverTrendingProvider),
        skeleton: AppSkeleton.posterRow(height: 138),
        isEmpty: (items) => items.isEmpty,
        emptyBuilder: const Padding(
          padding: EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: ServiceOverviewEmpty(
            icon: Icons.local_fire_department_outlined,
            label: 'Nothing trending right now',
          ),
        ),
        data: (items) => _PosterRail(items: items),
      ),
    );
  }
}

class _PosterRail extends StatelessWidget {
  const _PosterRail({required this.items});

  final List<MediaPreview> items;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      // 138pt poster, the gap, and two label lines — grown by the reading size
      // so the captions are not clipped at an accessibility text size.
      height: TextScaleMetrics.boxHeight(context, base: 176, textHeight: 34),
      // The box grew by the *clamped* scale, so the text has to be laid out at
      // the same clamp.
      child: MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaleMetrics.clampedScalerOf(context)),
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          itemCount: items.length,
          separatorBuilder: (_, _) =>
              const SizedBox(width: AppSpacing.carouselGap),
          itemBuilder: (context, index) => _PosterTile(item: items[index]),
        ),
      ),
    );
  }
}

class _PosterTile extends StatelessWidget {
  const _PosterTile({required this.item});

  final MediaPreview item;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final imageUrl = ImageUtils.buildTmdbPosterUrl(item.posterPath);
    // Its own namespace: the Discover tab's own carousels are alive in a
    // sibling branch and tag a poster of the same title, and two live Heroes
    // sharing a tag is an assertion, not a flight.
    final heroTag = 'seerr_overview_trending_${item.id}';
    final caption = item.mediaType == 'tv' ? 'TV' : 'Movie';

    return SizedBox(
      width: 96,
      child: PressableScale(
        onTap: () => context.push(
          ServiceRoutes.seerrDetail(
            mediaType: item.mediaType,
            id: item.id,
            heroTag: heroTag,
            posterUrl: imageUrl,
          ),
        ),
        // A poster is an image with no name of its own; the tile announces the
        // title and its kind as one button.
        semanticLabel: item.title,
        semanticValue: caption,
        excludeChildSemantics: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 96,
              height: 138,
              child: MediaPosterCard(heroTag: heroTag, imageUrl: imageUrl),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              item.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall
                  ?.weight(FontWeight.w600)
                  .copyWith(color: colorScheme.onSurface),
            ),
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
