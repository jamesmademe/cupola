import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/app_animation.dart';

import 'package:cupola/core/widgets/widgets.dart';

import 'package:cupola/features/prowlarr/presentation/prowlarr_overview_provider.dart';

import 'package:cupola/features/prowlarr/presentation/prowlarr_provider.dart';

import 'package:cupola/features/services/domain/service_tab.dart';

import 'package:cupola/features/services/presentation/service_kpi_provider.dart';

import 'package:cupola/features/services/presentation/services_provider.dart';

import 'package:cupola/features/settings/data/settings_provider.dart';

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
          const ServiceOverviewIdentity(service: ServiceKey.prowlarr),
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

// ─── 1. Needs attention ─────────────────────────────────────────────────────

/// What needs a decision, before the inventory and before the history.
class _AttentionSection extends ConsumerWidget {
  const _AttentionSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final section = ref.watch(prowlarrOverviewAttentionProvider);
    final total = section.asData?.value.total;

    return ServiceOverviewSection(
      service: ServiceKey.prowlarr,
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
        skeleton: const ServiceOverviewRowsSkeleton(rows: 2),
        isEmpty: (data) => data.rows.isEmpty,
        // A resting state wears no alarm chrome.
        emptyBuilder: const ServiceOverviewEmpty(
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

    return ServiceOverviewSection(
      service: ServiceKey.prowlarr,
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
        skeleton: const ServiceOverviewRowsSkeleton(rows: 3),
        isEmpty: (data) => data.rows.isEmpty,
        emptyBuilder: const ServiceOverviewEmpty(
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

    return ServiceOverviewSection(
      service: ServiceKey.prowlarr,
      title: 'Recent',
      destination: ServiceTab.history,
      child: AsyncValueWidget<List<ProwlarrOverviewRow>>(
        value: rows,
        serviceName: 'Prowlarr',
        loadingLabel: 'Loading recent indexer activity',
        onRetry: () => ref.invalidate(prowlarrRecentHistoryProvider),
        skeleton: const ServiceOverviewRowsSkeleton(rows: 2),
        isEmpty: (items) => items.isEmpty,
        emptyBuilder: const ServiceOverviewEmpty(
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

    return ServiceOverviewRow(
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
