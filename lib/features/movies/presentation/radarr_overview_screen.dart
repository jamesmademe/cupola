import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/app_animation.dart';
import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/service_theme.dart';
import 'package:cupola/core/text_scale.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/arr_activity_display.dart';
import 'package:cupola/core/utils/image_utils.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/movies/domain/models/radarr_movie.dart';
import 'package:cupola/features/movies/presentation/radarr_overview_provider.dart';
import 'package:cupola/features/services/domain/service_tab.dart';
import 'package:cupola/features/services/domain/services_semantics.dart';
import 'package:cupola/features/services/presentation/service_kpi_provider.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/data/service_connection_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/connection_presentation.dart';
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
          const _IdentityBlock(),
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

// ─── 0. Identity ────────────────────────────────────────────────────────────

/// Host, version, whether it is answering, and which connection you are
/// reading.
///
/// The status word comes from [describeConnection] and not from
/// `ServiceSummary.statusLabel`: that one says "Online"/"Offline", which is off
/// the app's lexicon — everything else in Cupola says *Answering*, *Not set
/// up*, *Unreachable* — and has no other call site.
class _IdentityBlock extends ConsumerWidget {
  const _IdentityBlock();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final summary = ref.watch(serviceSummaryProvider(ServiceKey.radarr));
    final instance = ref.watch(activeInstanceProvider(ServiceKey.radarr));
    final hasLens = ref.watch(hasMultipleInstancesProvider(ServiceKey.radarr));

    // The probe reduced to the connection vocabulary. A summary still in flight
    // is `checking` rather than a guess, and one that threw is the same fact a
    // failed probe reports: we could not confirm it, and we cannot say why.
    final status = summary.when(
      loading: () => ServiceConnectionStatus.checking,
      error: (_, _) => ServiceConnectionStatus.disconnected,
      data: (value) => value.isOnline
          ? ServiceConnectionStatus.connected
          : ServiceConnectionStatus.disconnected,
    );
    final presentation = describeConnection(ServiceKey.radarr, status: status);
    final toneColor = statusToneColor(colorScheme, presentation.tone);

    final host = ServiceKey.radarr.extractHost(instance?.url);
    // A figure whose source did not answer reads "—", never a fallback dressed
    // up as an answer: `ServiceSummary.versionLabel` degrades to "v3 API" when
    // the service named no version, which is honest for a server that replied
    // and a fabrication for one that never did.
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
          ServiceKey.radarr.title,
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
    final ink = _radarrInk(colorScheme);

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
          color: ink,
        ),
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
    final count = releases.asData?.value.length;

    return _OverviewSection(
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
        skeleton: const _RowsSkeleton(rows: 2),
        isEmpty: (items) => items.isEmpty,
        emptyBuilder: const _SectionEmpty(
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

    return _OverviewRow(
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
    final count = items.asData?.value.length;

    return _OverviewSection(
      title: 'Needs attention',
      subtitle: count == null ? '—' : '$count',
      // No link: every row here belongs to a different tab, and a single
      // destination would have to lie about four of them.
      child: AsyncValueWidget<List<RadarrAttentionItem>>(
        value: items,
        serviceName: 'Radarr',
        loadingLabel: 'Loading what needs attention',
        onRetry: () => ref.invalidate(radarrNeedsAttentionProvider),
        skeleton: const _RowsSkeleton(rows: 2),
        isEmpty: (data) => data.isEmpty,
        // A resting state wears no alarm chrome: nothing is wrong, and saying
        // so is not an error state.
        emptyBuilder: const _SectionEmpty(
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

    return _OverviewRow(
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

    return _OverviewSection(
      title: 'Recently added',
      destination: ServiceTab.library,
      padBody: false,
      child: AsyncValueWidget<List<RadarrMovie>>(
        value: movies,
        serviceName: 'Radarr',
        loadingLabel: 'Loading recently added films',
        onRetry: () => ref.invalidate(radarrRecentlyAddedProvider),
        skeleton: AppSkeleton.posterRow(height: 138),
        isEmpty: (items) => items.isEmpty,
        emptyBuilder: const Padding(
          padding: EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: _SectionEmpty(
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

    return _OverviewSection(
      title: 'History',
      subtitle: 'today',
      destination: ServiceTab.history,
      child: AsyncValueWidget<List<RadarrHistoryEntry>>(
        value: entries,
        serviceName: 'Radarr',
        loadingLabel: "Loading today's history",
        onRetry: () => ref.invalidate(radarrHistoryTodayProvider),
        skeleton: const _RowsSkeleton(rows: 2),
        isEmpty: (items) => items.isEmpty,
        emptyBuilder: const _SectionEmpty(
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

    return _OverviewRow(
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
              : _TabLink(label: tab.label, color: _radarrInk(colorScheme)),
          // The link's "→" sits inside the region the header silences — read
          // out it is "rightwards arrow" — so the destination comes back as a
          // hint instead.
          semanticHint: tab == null
              ? null
              : 'opens the Radarr ${tab.label} tab',
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
    this.titleColor,
  });

  /// The whole row as one sentence, with the layout's `·` turned back into
  /// commas.
  final String spoken;

  final Widget leading;
  final String title;
  final String detail;
  final Color? titleColor;

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
                    ).copyWith(color: titleColor ?? colorScheme.onSurface),
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
///
/// [AppEmptyState.inline] and not the 72dp well: nothing failed and nothing is
/// missing, so the absence costs a row rather than a screenful of ceremony.
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

/// Radarr's accent, walked until it can carry ink.
///
/// Radarr is one of the seven service accents under 3:1 on paper, so every
/// place the accent becomes *text* rather than a dot goes through
/// [ServiceTheme.onTint] — on a light theme it resolves to a darker hue than
/// the dark artboards draw.
Color _radarrInk(ColorScheme colorScheme) => ServiceTheme.onTint(
  ServiceKey.radarr.accent,
  surface: colorScheme.surface,
  tintAlpha: 0,
);

/// Switches to another of Radarr's tabs.
///
/// `goBranch`, not `context.go`: it restores that branch's own stack, which is
/// what makes "back returns to the tab you left" true. `maybeOf` rather than
/// `of` because this screen is also legitimately built outside a shell — a
/// widget test, a preview — where there is no branch to switch and the link
/// simply does nothing rather than throwing.
void _goToTab(BuildContext context, ServiceTab tab) {
  final tabs = tabsFor(ServiceKey.radarr);
  if (tabs == null) return;
  final index = tabs.indexOf(tab);
  if (index < 0) return;
  StatefulNavigationShell.maybeOf(context)?.goBranch(index);
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
