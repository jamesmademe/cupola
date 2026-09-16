import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/app_animation.dart';
import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/service_theme.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/bazarr/presentation/bazarr_overview_provider.dart';
import 'package:cupola/features/bazarr/presentation/bazarr_provider.dart';
import 'package:cupola/features/services/domain/service_tab.dart';
import 'package:cupola/features/services/domain/services_semantics.dart';
import 'package:cupola/features/services/presentation/service_kpi_provider.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/data/service_connection_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/connection_presentation.dart';
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
          const _IdentityBlock(),
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

    final summary = ref.watch(serviceSummaryProvider(ServiceKey.bazarr));
    final instance = ref.watch(activeInstanceProvider(ServiceKey.bazarr));
    final hasLens = ref.watch(hasMultipleInstancesProvider(ServiceKey.bazarr));

    final status = summary.when(
      loading: () => ServiceConnectionStatus.checking,
      error: (_, _) => ServiceConnectionStatus.disconnected,
      data: (value) => value.isOnline
          ? ServiceConnectionStatus.connected
          : ServiceConnectionStatus.disconnected,
    );
    final presentation = describeConnection(ServiceKey.bazarr, status: status);
    final toneColor = statusToneColor(colorScheme, presentation.tone);

    final host = ServiceKey.bazarr.extractHost(instance?.url);
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
          ServiceKey.bazarr.title,
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
          color: _bazarrInk(colorScheme),
        ),
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

    return _OverviewSection(
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
        skeleton: const _RowsSkeleton(rows: 3),
        isEmpty: (data) => data.rows.isEmpty,
        // A resting state wears no alarm chrome, and an empty backlog is the
        // best state Bazarr can be in.
        emptyBuilder: const _SectionEmpty(
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

    return _OverviewSection(
      title: 'History',
      destination: ServiceTab.history,
      child: AsyncValueWidget<List<BazarrOverviewRow>>(
        value: rows,
        serviceName: 'Bazarr',
        loadingLabel: 'Loading recent subtitle activity',
        onRetry: () => ref.invalidate(bazarrDashboardHistoryProvider),
        skeleton: const _RowsSkeleton(rows: 2),
        isEmpty: (items) => items.isEmpty,
        emptyBuilder: const _SectionEmpty(
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
              : _TabLink(label: tab.label, color: _bazarrInk(colorScheme)),
          // The link's "→" sits inside the region the header silences — read
          // out it is "rightwards arrow" — so the destination comes back as a
          // hint instead.
          semanticHint: tab == null
              ? null
              : 'opens the Bazarr ${tab.label} tab',
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

/// Bazarr's accent, walked until it can carry ink.
///
/// Every place the accent becomes *text* rather than a dot goes through
/// [ServiceTheme.onTint]; seven of the seventeen service accents sit under 3:1
/// on paper and resolve to a darker hue than the dark artboards draw.
Color _bazarrInk(ColorScheme colorScheme) => ServiceTheme.onTint(
  ServiceKey.bazarr.accent,
  surface: colorScheme.surface,
  tintAlpha: 0,
);

/// Switches to another of Bazarr's tabs.
///
/// `goBranch`, not `context.go`: it restores that branch's own stack, which is
/// what makes "back returns to the tab you left" true. `maybeOf` rather than
/// `of` because this screen is also legitimately built outside a shell — a
/// widget test, a preview — where there is no branch to switch and the link
/// simply does nothing rather than throwing.
void _goToTab(BuildContext context, ServiceTab tab) {
  final tabs = tabsFor(ServiceKey.bazarr);
  if (tabs == null) return;
  final index = tabs.indexOf(tab);
  if (index < 0) return;
  StatefulNavigationShell.maybeOf(context)?.goBranch(index);
}
