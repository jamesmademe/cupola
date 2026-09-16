import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/app_animation.dart';
import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/service_theme.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/prowlarr/presentation/prowlarr_overview_provider.dart';
import 'package:cupola/features/prowlarr/presentation/prowlarr_provider.dart';
import 'package:cupola/features/services/domain/service_tab.dart';
import 'package:cupola/features/services/domain/services_semantics.dart';
import 'package:cupola/features/services/presentation/service_kpi_provider.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/data/service_connection_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/connection_presentation.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// The first tab of Prowlarr's service home.
///
/// Prowlarr is the odd one among the download services: its work is the
/// **indexer table** — who answers, how fast, and who is failing — rather than
/// a queue. Two rules hold over the whole page:
///
///  * **faults are amber, not red.** Red stays for a Prowlarr that does not
///    answer, which the unreachable band says once for the page.
///  * **every figure carries its window.** The stats behind the readouts and
///    the query counts are scoped to the last twenty-four hours, and the
///    section that draws them says so rather than letting an all-time-looking
///    figure sit under a day's label.
///
/// **It draws neither the app bar nor the tab bar.** The host owns both as
/// glass bands floated above this page, and this screen reserves the room with
/// [topPadding] instead.
///
/// The Apps region the desktop board draws is **absent rather than stubbed**:
/// its rows are per-application sync state — "synced 12 min ago", "sync failed
/// · API key rejected" — and `GET /api/v1/applications` carries no sync
/// timestamp and no per-app failure, so those rows could only be invented.
class ProwlarrOverviewScreen extends ConsumerWidget {
  const ProwlarrOverviewScreen({
    super.key,
    this.topPadding = _hostedTopPadding,
  });

  static const double _hostedTopPadding = kToolbarHeight + ServiceTabBar.height;

  /// Height of the chrome the host draws above this page.
  final double topPadding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final configured = ref.watch(
      currentSettingsProvider.select(
        (settings) => settings.isServiceConfigured(ServiceKey.prowlarr),
      ),
    );

    return AmbientScaffold(
      accent: ServiceKey.prowlarr.accent,
      body: SafeArea(
        child: configured
            ? _OverviewBody(topPadding: topPadding)
            // `.forService`: this is a service dashboard, so the door goes to
            // Prowlarr's own connection form rather than the settings index.
            : NotConfiguredPlaceholder.forService(ServiceKey.prowlarr),
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
        ref.invalidate(serviceSummaryProvider(ServiceKey.prowlarr));
        ref.invalidate(serviceKpiProvider(ServiceKey.prowlarr));
        ref.invalidate(prowlarrIndexersProvider);
        ref.invalidate(prowlarrIndexerStatsProvider);
        ref.invalidate(prowlarrIndexerStatusProvider);
        ref.invalidate(prowlarrHealthProvider);
        ref.invalidate(prowlarrRecentHistoryProvider);
        ref.invalidate(prowlarrOverviewAttentionProvider);
        ref.invalidate(prowlarrOverviewIndexersProvider);
        ref.invalidate(prowlarrOverviewRecentProvider);
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
            kpis: ref.watch(serviceKpiProvider(ServiceKey.prowlarr)),
            accent: ServiceKey.prowlarr.accent,
          ),
          const _AttentionSection(),
          const _IndexersSection(),
          const _RecentSection(),
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

    final summary = ref.watch(serviceSummaryProvider(ServiceKey.prowlarr));
    final instance = ref.watch(activeInstanceProvider(ServiceKey.prowlarr));
    final hasLens = ref.watch(
      hasMultipleInstancesProvider(ServiceKey.prowlarr),
    );

    final status = summary.when(
      loading: () => ServiceConnectionStatus.checking,
      error: (_, _) => ServiceConnectionStatus.disconnected,
      data: (value) => value.isOnline
          ? ServiceConnectionStatus.connected
          : ServiceConnectionStatus.disconnected,
    );
    final presentation = describeConnection(
      ServiceKey.prowlarr,
      status: status,
    );
    final toneColor = statusToneColor(colorScheme, presentation.tone);

    final host = ServiceKey.prowlarr.extractHost(instance?.url);
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
          ServiceKey.prowlarr.title,
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
          color: _prowlarrInk(colorScheme),
        ),
      ),
    );
  }
}

// ─── 1. Needs attention ─────────────────────────────────────────────────────

/// What needs a decision, before the inventory and before the history.
class _AttentionSection extends ConsumerWidget {
  const _AttentionSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final section = ref.watch(prowlarrOverviewAttentionProvider);
    final total = section.asData?.value.total;

    return _OverviewSection(
      title: 'Needs attention',
      // "—" while it loads or after it failed: a "0" printed over an
      // unanswered question is a claim nobody made.
      subtitle: total == null ? '—' : '$total',
      // No link: a failing indexer belongs to Indexers and a health check
      // belongs to nowhere on the bar, so one destination would lie about half
      // the rows.
      child: AsyncValueWidget<ProwlarrOverviewSection>(
        value: section,
        serviceName: 'Prowlarr',
        loadingLabel: 'Loading what needs attention',
        onRetry: () => ref.invalidate(prowlarrIndexerStatusProvider),
        skeleton: const _RowsSkeleton(rows: 2),
        isEmpty: (data) => data.rows.isEmpty,
        // A resting state wears no alarm chrome.
        emptyBuilder: const _SectionEmpty(
          icon: Icons.check_circle_outline_rounded,
          label: 'Every indexer is answering',
        ),
        data: (data) => Column(
          children: [
            for (final row in data.rows)
              _ProwlarrRow(row: row, icon: Icons.error_outline_rounded),
          ],
        ),
      ),
    );
  }
}

// ─── 2. The indexer table ───────────────────────────────────────────────────

/// Prowlarr's own work.
class _IndexersSection extends ConsumerWidget {
  const _IndexersSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final section = ref.watch(prowlarrOverviewIndexersProvider);
    final total = section.asData?.value.total;

    return _OverviewSection(
      title: 'Indexers',
      // The window belongs in the label, because the figures on the rows are a
      // day's queries and nothing else on the row says so.
      subtitle: total == null
          ? '—'
          : '$total · by queries, last ${prowlarrStatsWindow.inHours} h',
      destination: ServiceTab.indexers,
      child: AsyncValueWidget<ProwlarrOverviewSection>(
        value: section,
        serviceName: 'Prowlarr',
        loadingLabel: 'Loading indexers',
        onRetry: () => ref.invalidate(prowlarrIndexersProvider),
        skeleton: const _RowsSkeleton(rows: 3),
        isEmpty: (data) => data.rows.isEmpty,
        emptyBuilder: const _SectionEmpty(
          icon: Icons.travel_explore_rounded,
          label: 'No indexers yet',
        ),
        data: (data) => Column(
          children: [for (final row in data.rows) _ProwlarrRow(row: row)],
        ),
      ),
    );
  }
}

// ─── 3. Recent ──────────────────────────────────────────────────────────────

class _RecentSection extends ConsumerWidget {
  const _RecentSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rows = ref.watch(prowlarrOverviewRecentProvider);

    return _OverviewSection(
      title: 'Recent',
      destination: ServiceTab.history,
      child: AsyncValueWidget<List<ProwlarrOverviewRow>>(
        value: rows,
        serviceName: 'Prowlarr',
        loadingLabel: 'Loading recent indexer activity',
        onRetry: () => ref.invalidate(prowlarrRecentHistoryProvider),
        skeleton: const _RowsSkeleton(rows: 2),
        isEmpty: (items) => items.isEmpty,
        emptyBuilder: const _SectionEmpty(
          icon: Icons.history_rounded,
          label: 'Nothing yet',
        ),
        data: (items) =>
            Column(children: [for (final row in items) _ProwlarrRow(row: row)]),
      ),
    );
  }
}

class _ProwlarrRow extends StatelessWidget {
  const _ProwlarrRow({required this.row, this.icon});

  final ProwlarrOverviewRow row;

  /// A glyph instead of the dot, for the section where every row is a fault.
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    // Through the tone rule, never a raw `AppColors.*`: a failing indexer is
    // amber, and red is kept for a Prowlarr that did not answer at all.
    final tone = statusToneColor(
      colorScheme,
      row.tone,
      surface: colorScheme.surfaceContainerLow,
    );
    final glyph = icon;

    return _OverviewRow(
      spoken: row.spoken,
      leading: glyph == null
          ? Container(
              width: 8,
              height: 8,
              margin: const EdgeInsets.only(top: 5),
              decoration: BoxDecoration(color: tone, shape: BoxShape.circle),
            )
          : Icon(glyph, size: 18, color: tone),
      title: row.headline,
      detail: row.detail,
      trailing: row.trailing,
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
  });

  final String title;
  final String? subtitle;

  /// The tab this region's "see the rest" link opens, or null for a region
  /// whose rows belong to several tabs at once.
  final ServiceTab? destination;

  final Widget child;

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
              : _TabLink(label: tab.label, color: _prowlarrInk(colorScheme)),
          // The link's "→" sits inside the region the header silences — read
          // out it is "rightwards arrow" — so the destination comes back as a
          // hint instead.
          semanticHint: tab == null
              ? null
              : 'opens the Prowlarr ${tab.label} tab',
          onTap: tab == null ? null : () => _goToTab(context, tab),
        ),
        const SizedBox(height: AppSpacing.sm),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: child,
        ),
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
    this.trailing,
  });

  /// The whole row as one sentence, with the layout's `·` turned back into
  /// commas.
  final String spoken;

  final Widget leading;
  final String title;
  final String detail;

  /// The right-hand figure, e.g. `298 queries`. Already folded into [spoken],
  /// which is why the row can silence its own subtree.
  final String? trailing;

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
            if (trailing != null) ...[
              const SizedBox(width: AppSpacing.sm),
              // Capped rather than free: at an accessibility reading size an
              // unconstrained figure next to an `Expanded` title is a
              // right-edge overflow, and a row that throws is worse than a
              // figure that ellipsises — the whole value is still in the
              // sentence a screen reader hears.
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 132),
                child: Text(
                  trailing!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: AppTheme.chrome(
                    context,
                    size: 11,
                    weight: FontWeight.w700,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
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

/// Prowlarr's accent, walked until it can carry ink.
///
/// Every place the accent becomes *text* rather than a dot goes through
/// [ServiceTheme.onTint]; seven of the seventeen service accents sit under 3:1
/// on paper and resolve to a darker hue than the dark artboards draw.
Color _prowlarrInk(ColorScheme colorScheme) => ServiceTheme.onTint(
  ServiceKey.prowlarr.accent,
  surface: colorScheme.surface,
  tintAlpha: 0,
);

/// Switches to another of Prowlarr's tabs.
///
/// `goBranch`, not `context.go`: it restores that branch's own stack, which is
/// what makes "back returns to the tab you left" true. `maybeOf` rather than
/// `of` because this screen is also legitimately built outside a shell — a
/// widget test, a preview — where there is no branch to switch and the link
/// simply does nothing rather than throwing.
void _goToTab(BuildContext context, ServiceTab tab) {
  final tabs = tabsFor(ServiceKey.prowlarr);
  if (tabs == null) return;
  final index = tabs.indexOf(tab);
  if (index < 0) return;
  StatefulNavigationShell.maybeOf(context)?.goBranch(index);
}
