import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/app_animation.dart';

import 'package:cupola/core/widgets/widgets.dart';

import 'package:cupola/features/bazarr/presentation/bazarr_overview_provider.dart';

import 'package:cupola/features/bazarr/presentation/bazarr_provider.dart';

import 'package:cupola/features/services/domain/service_tab.dart';

import 'package:cupola/features/services/presentation/service_kpi_provider.dart';

import 'package:cupola/features/services/presentation/services_provider.dart';

import 'package:cupola/features/settings/data/settings_provider.dart';

import 'package:cupola/features/settings/domain/service_key.dart';

/// The first tab of Bazarr's service home.
///
/// Bazarr's work is the **wanted subtitles**, and the backlog is drawn neutral
/// throughout: a wanted count is not a fault, and the amber it used to wear
/// made a perfectly healthy stack with a long tail look broken.
///
/// Overview alone carries the identity block and the readouts; every other tab
/// is a view of one kind of record. Each section ends in a link named exactly
/// like the tab it jumps to.
///
/// **It draws neither the app bar nor the tab bar.** The host owns both as
/// glass bands floated above this page, and this screen reserves the room with
/// [topPadding] instead.
///
/// The Providers region the board draws is **absent rather than stubbed**: the
/// client has no `GET /api/providers`, so it can report neither the throttle
/// state nor the per-provider quota that region is made of, and a section that
/// renders a lie is worse than one that is missing.
class BazarrOverviewScreen extends ConsumerWidget {
  const BazarrOverviewScreen({super.key, this.topPadding = _hostedTopPadding});

  static const double _hostedTopPadding = kToolbarHeight + ServiceTabBar.height;

  /// Height of the chrome the host draws above this page.
  final double topPadding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final configured = ref.watch(
      currentSettingsProvider.select(
        (settings) => settings.isServiceConfigured(ServiceKey.bazarr),
      ),
    );

    return AmbientScaffold(
      accent: ServiceKey.bazarr.accent,
      body: SafeArea(
        child: configured
            ? _OverviewBody(topPadding: topPadding)
            // `.forService`: this is a service dashboard, so the door goes to
            // Bazarr's own connection form rather than to the settings index.
            : NotConfiguredPlaceholder.forService(ServiceKey.bazarr),
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
        ref.invalidate(serviceSummaryProvider(ServiceKey.bazarr));
        ref.invalidate(serviceKpiProvider(ServiceKey.bazarr));
        ref.invalidate(bazarrBadgesProvider);
        ref.invalidate(bazarrDashboardWantedProvider);
        ref.invalidate(bazarrDashboardHistoryProvider);
        ref.invalidate(bazarrOverviewWantedProvider);
        ref.invalidate(bazarrOverviewHistoryProvider);
        await Future<void>.delayed(AppAnimation.durationMd);
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.only(
          bottom: FloatingNavBarMetrics.getScrollViewBottomPadding(context),
        ),
        children: [
          if (topPadding > 0) SizedBox(height: topPadding),
          const ServiceOverviewIdentity(service: ServiceKey.bazarr),
          ServiceKpiPeek(
            kpis: ref.watch(serviceKpiProvider(ServiceKey.bazarr)),
            accent: ServiceKey.bazarr.accent,
          ),
          const _WantedSection(),
          const _HistorySection(),
        ],
      ),
    );
  }
}

// ─── 1. Wanted subtitles ────────────────────────────────────────────────────

/// The service's own work, and the page's reason to exist.
class _WantedSection extends ConsumerWidget {
  const _WantedSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final section = ref.watch(bazarrOverviewWantedProvider);
    final total = section.asData?.value.total;

    return ServiceOverviewSection(
      service: ServiceKey.bazarr,
      title: 'Wanted subtitles',
      // "—" while it loads or after it failed: a "0 wanted" printed over an
      // unanswered question is a claim nobody made. No age clause either —
      // Bazarr's wanted rows carry no date, so "oldest 8 days" cannot be said.
      subtitle: total == null ? '—' : '$total',
      destination: ServiceTab.wanted,
      child: AsyncValueWidget<BazarrOverviewSection>(
        value: section,
        serviceName: 'Bazarr',
        loadingLabel: 'Loading wanted subtitles',
        onRetry: () => ref.invalidate(bazarrDashboardWantedProvider),
        skeleton: const ServiceOverviewRowsSkeleton(rows: 3),
        isEmpty: (data) => data.rows.isEmpty,
        // A resting state wears no alarm chrome, and an empty backlog is the
        // best state Bazarr can be in.
        emptyBuilder: const ServiceOverviewEmpty(
          icon: Icons.subtitles_rounded,
          label: 'Nothing wanted',
        ),
        data: (data) => Column(
          children: [for (final row in data.rows) _BazarrRow(row: row)],
        ),
      ),
    );
  }
}

// ─── 2. History ─────────────────────────────────────────────────────────────

/// What Bazarr did recently.
///
/// Headed `History` with **no window**: Bazarr serves its timestamps as a
/// pre-rendered relative string and a locale-formatted `%x %X`, neither of
/// which the app can turn back into an instant, so a "today" heading would be a
/// promise this page cannot keep. Each row quotes Bazarr's own words for when.
class _HistorySection extends ConsumerWidget {
  const _HistorySection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rows = ref.watch(bazarrOverviewHistoryProvider);

    return ServiceOverviewSection(
      service: ServiceKey.bazarr,
      title: 'History',
      destination: ServiceTab.history,
      child: AsyncValueWidget<List<BazarrOverviewRow>>(
        value: rows,
        serviceName: 'Bazarr',
        loadingLabel: 'Loading recent subtitle activity',
        onRetry: () => ref.invalidate(bazarrDashboardHistoryProvider),
        skeleton: const ServiceOverviewRowsSkeleton(rows: 2),
        isEmpty: (items) => items.isEmpty,
        emptyBuilder: const ServiceOverviewEmpty(
          icon: Icons.history_rounded,
          label: 'Nothing yet',
        ),
        data: (items) =>
            Column(children: [for (final row in items) _BazarrRow(row: row)]),
      ),
    );
  }
}

class _BazarrRow extends StatelessWidget {
  const _BazarrRow({required this.row});

  final BazarrOverviewRow row;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    // Through the tone rule, never a raw `AppColors.*`. Backlog is neutral by
    // construction, and a blacklisted entry is neutral too — blacklisting is a
    // choice, not a fault.
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
