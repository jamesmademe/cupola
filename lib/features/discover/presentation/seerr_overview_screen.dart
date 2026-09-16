import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/app_animation.dart';
import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/models/media_preview.dart';
import 'package:cupola/core/service_theme.dart';
import 'package:cupola/core/text_scale.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/image_utils.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/discover/presentation/discover_provider.dart';
import 'package:cupola/features/discover/presentation/seerr_overview_provider.dart';
import 'package:cupola/features/services/domain/service_tab.dart';
import 'package:cupola/features/services/domain/services_semantics.dart';
import 'package:cupola/features/services/presentation/service_kpi_provider.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/data/service_connection_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/connection_presentation.dart';
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
          const _IdentityBlock(),
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

// ─── 0. Identity ────────────────────────────────────────────────────────────

/// Host, version, whether it is answering, and which connection you are
/// reading.
///
/// The status word comes from [describeConnection], not from
/// `ServiceSummary.statusLabel`: that one says "Online"/"Offline", which is off
/// the app's lexicon — everything else in Cupola says *Answering*, *Not set
/// up*, *Unreachable*.
class _IdentityBlock extends ConsumerWidget {
  const _IdentityBlock();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;

    final summary = ref.watch(serviceSummaryProvider(ServiceKey.seerr));
    final instance = ref.watch(activeInstanceProvider(ServiceKey.seerr));
    final hasLens = ref.watch(hasMultipleInstancesProvider(ServiceKey.seerr));

    final status = summary.when(
      loading: () => ServiceConnectionStatus.checking,
      error: (_, _) => ServiceConnectionStatus.disconnected,
      data: (value) => value.isOnline
          ? ServiceConnectionStatus.connected
          : ServiceConnectionStatus.disconnected,
    );
    final presentation = describeConnection(ServiceKey.seerr, status: status);
    final toneColor = statusToneColor(colorScheme, presentation.tone);

    final host = ServiceKey.seerr.extractHost(instance?.url);
    // A figure whose source did not answer reads "—", never a fallback dressed
    // up as an answer.
    final summaryData = summary.asData?.value;
    final version = summaryData != null && summaryData.isOnline
        ? summaryData.versionLabel
        : null;
    final lens = hasLens ? instance?.label.trim() : null;

    final facts = <String>[
      host == null || host.isEmpty ? '—' : host,
      version == null || version.isEmpty ? '—' : version,
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.md,
      ),
      child: Semantics(
        container: true,
        // One sentence rather than four stops: the host alone, read out on its
        // own, does not say what it is the host of.
        label: joinSpokenParts([
          ServiceKey.seerr.title,
          ...facts,
          presentation.label,
          if (lens != null && lens.isNotEmpty) lens,
        ]),
        excludeSemantics: true,
        child: Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.xs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              facts.join(' · '),
              style: AppTheme.chrome(
                context,
                size: 12,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            // Tone and glyph both, because colour is not information: the word
            // is the channel that always works.
            _StatusWord(
              icon: presentation.icon,
              label: presentation.label,
              color: toneColor,
            ),
            if (lens != null && lens.isNotEmpty) _LensChip(label: lens),
          ],
        ),
      ),
    );
  }
}

class _StatusWord extends StatelessWidget {
  const _StatusWord({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: AppSpacing.xs),
        Text(
          label,
          style: AppTheme.chrome(
            context,
            size: 12,
            weight: FontWeight.w700,
            color: color,
          ),
        ),
      ],
    );
  }
}

/// Which connection the page is reading, when there is more than one.
class _LensChip extends StatelessWidget {
  const _LensChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        borderRadius: AppRadius.borderRadiusSm,
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Text(
        label,
        style: AppTheme.chrome(
          context,
          size: 11,
          weight: FontWeight.w700,
          color: _seerrInk(colorScheme),
        ),
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

    return _OverviewSection(
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
        skeleton: const _RowsSkeleton(rows: 3),
        isEmpty: (data) => data.rows.isEmpty,
        // A resting state wears no alarm chrome: an auto-approving Seerr with
        // nothing waiting is working exactly as configured.
        emptyBuilder: const _SectionEmpty(
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

    return _OverviewSection(
      title: 'Processing',
      subtitle: total == null ? '—' : '$total',
      destination: ServiceTab.requests,
      child: AsyncValueWidget<SeerrOverviewSection>(
        value: section,
        serviceName: 'Seerr',
        loadingLabel: 'Loading what is processing',
        onRetry: () => ref.invalidate(requestsProvider),
        skeleton: const _RowsSkeleton(rows: 2),
        isEmpty: (data) => data.rows.isEmpty,
        emptyBuilder: const _SectionEmpty(
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

    return _OverviewRow(
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

    return _OverviewSection(
      title: 'Trending',
      // Seerr's `/discover/trending` proxies TMDB's *weekly* list, so the label
      // and the window agree.
      subtitle: 'this week',
      destination: ServiceTab.discover,
      padBody: false,
      child: AsyncValueWidget<List<MediaPreview>>(
        value: trending,
        serviceName: 'Seerr',
        loadingLabel: 'Loading what is trending',
        onRetry: () => ref.invalidate(discoverTrendingProvider),
        skeleton: AppSkeleton.posterRow(height: 138),
        isEmpty: (items) => items.isEmpty,
        emptyBuilder: const Padding(
          padding: EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: _SectionEmpty(
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

// ─── The shared shell ───────────────────────────────────────────────────────

/// One region of the Overview: a heading, an optional link to the tab that owns
/// the full list, and the body.
///
/// The link is named exactly like its tab — the design's rule, and the reason
/// it takes a [ServiceTab] and not a string: a label and a destination that can
/// drift apart eventually do.
class _OverviewSection extends StatelessWidget {
  const _OverviewSection({
    required this.title,
    required this.child,
    this.subtitle,
    this.destination,
    this.padBody = true,
  });

  final String title;
  final String? subtitle;

  /// The tab this region's "see the rest" link opens, or null for a region
  /// whose rows belong to several tabs at once.
  final ServiceTab? destination;

  final Widget child;

  /// False for a body that bleeds to the window edge — a poster rail, whose
  /// first tile aligns to the column while the row itself runs off it.
  final bool padBody;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final tab = destination;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: title,
          subtitle: subtitle,
          showChevron: false,
          trailing: tab == null
              ? null
              : _TabLink(label: tab.label, color: _seerrInk(colorScheme)),
          // The link's "→" sits inside the region the header silences — read
          // out it is "rightwards arrow" — so the destination comes back as a
          // hint instead.
          semanticHint: tab == null ? null : 'opens the Seerr ${tab.label} tab',
          onTap: tab == null ? null : () => _goToTab(context, tab),
        ),
        const SizedBox(height: AppSpacing.sm),
        if (padBody)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: child,
          )
        else
          child,
        const SizedBox(height: AppSpacing.lg),
      ],
    );
  }
}

class _TabLink extends StatelessWidget {
  const _TabLink({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Text(
      '$label →',
      // One line, always: the arrow belongs to the word before it, and stranded
      // on a line of its own it reads as a second control.
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(
        context,
      ).textTheme.labelMedium?.weight(FontWeight.w700).copyWith(color: color),
    );
  }
}

/// Two lines and a leading mark: the one row shape every section here uses.
class _OverviewRow extends StatelessWidget {
  const _OverviewRow({
    required this.spoken,
    required this.leading,
    required this.title,
    required this.detail,
  });

  /// The whole row as one sentence, with the layout's `·` turned back into
  /// commas.
  final String spoken;

  final Widget leading;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;

    return Semantics(
      container: true,
      label: spoken,
      // Nothing in this row is interactive, so the parts are safe to silence —
      // read separately they are three fragments of one fact.
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            leading,
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AppTheme.data(
                      brightness,
                    ).copyWith(color: colorScheme.onSurface),
                  ),
                  if (detail.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      detail,
                      style: AppTheme.chrome(
                        context,
                        size: 11,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The "nothing here" note for a region at rest.
class _SectionEmpty extends StatelessWidget {
  const _SectionEmpty({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return AppEmptyState.inline(icon: icon, title: label);
  }
}

class _RowsSkeleton extends StatelessWidget {
  const _RowsSkeleton({required this.rows});

  final int rows;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < rows; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ShimmerPlaceholder.text(width: 180, height: 14),
                const SizedBox(height: AppSpacing.xs),
                ShimmerPlaceholder.text(width: 120, height: 10),
              ],
            ),
          ),
      ],
    );
  }
}

// ─── Shared bits ────────────────────────────────────────────────────────────

/// Seerr's accent, walked until it can carry ink.
///
/// Every place the accent becomes *text* rather than a dot goes through
/// [ServiceTheme.onTint]; seven of the seventeen service accents sit under 3:1
/// on paper and resolve to a darker hue than the dark artboards draw.
Color _seerrInk(ColorScheme colorScheme) => ServiceTheme.onTint(
  ServiceKey.seerr.accent,
  surface: colorScheme.surface,
  tintAlpha: 0,
);

/// Switches to another of Seerr's tabs.
///
/// `goBranch`, not `context.go`: it restores that branch's own stack, which is
/// what makes "back returns to the tab you left" true. `maybeOf` rather than
/// `of` because this screen is also legitimately built outside a shell — a
/// widget test, a preview — where there is no branch to switch and the link
/// simply does nothing rather than throwing.
void _goToTab(BuildContext context, ServiceTab tab) {
  final tabs = tabsFor(ServiceKey.seerr);
  if (tabs == null) return;
  final index = tabs.indexOf(tab);
  if (index < 0) return;
  StatefulNavigationShell.maybeOf(context)?.goBranch(index);
}
