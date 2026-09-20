import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/app_animation.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/nzbget/presentation/nzbget_overview_provider.dart';
import 'package:cupola/features/nzbget/presentation/nzbget_provider.dart';
import 'package:cupola/features/services/domain/service_tab.dart';
import 'package:cupola/features/services/presentation/service_kpi_provider.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// The first tab of NZBGet's service home.
///
/// Overview alone carries the identity block and the readouts — every other tab
/// is a view of one kind of record — and then the two regions this client can
/// actually fill: History first, Queue second.
///
/// **That is a deliberate deviation from both NZBGet artboards**, which draw
/// Queue above History (`HomeNzbgetMobile.dc.html` stacks `Queue / 1
/// downloading · 1 post-processing` over `History / failed first`, and the
/// desktop board does the same). The reason is the rule that outranks the
/// board's stacking order here: a failed download is the only thing on an
/// NZBGet page that needs a person, and a queue that is 56% of the way through
/// needs nobody. What needs a decision comes before what is merely outstanding
/// — the same rule the \*arr Overviews follow when they put Needs attention
/// above Recently added, and the same call the SABnzbd twin makes. The board's
/// own "failed first" instruction inside the History region is that rule one
/// level down; this applies it one level up.
///
/// Feeds and Messages now have dedicated tab screens backed by the client.
/// They are intentionally not duplicated in this Overview, which stays a
/// compact queue/history summary. The Servers readout and Disk free figure
/// remain unavailable where the current NZBGet contract does not provide a
/// trustworthy value; the UI uses an em dash rather than manufacturing zero.
///
/// **It draws neither the app bar nor the tab bar.** The host owns both as
/// glass bands floated above this page so the ambient gradient reads
/// continuously behind them; this screen reserves the room with [topPadding]
/// instead.
///
/// Sections load independently and fail independently: an NZBGet that answers
/// `listgroups` and not `history` still draws its queue, and the region that
/// could not load says so in its own slot rather than taking the page with it.
class NzbgetOverviewScreen extends ConsumerWidget {
  const NzbgetOverviewScreen({super.key, this.topPadding = _hostedTopPadding});

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
    // Checked **before** any NZBGet provider is watched. `nzbgetClientProvider`
    // throws "NZBGet not configured", and a `FutureProvider` that throws is a
    // failed provider: Riverpod schedules a retry with backoff for a condition
    // that no amount of waiting changes, and the test that navigates here fails
    // on a pending timer rather than on anything it meant to assert.
    final configured = ref.watch(
      currentSettingsProvider.select(
        (settings) => settings.isServiceConfigured(ServiceKey.nzbget),
      ),
    );

    return AmbientScaffold(
      accent: ServiceKey.nzbget.accent,
      body: SafeArea(
        child: configured
            ? _OverviewBody(topPadding: topPadding)
            // `.forService`, never the generic form: this is a service
            // dashboard, so the door goes to NZBGet's own connection form
            // rather than to the settings index.
            : NotConfiguredPlaceholder.forService(ServiceKey.nzbget),
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
        // The three source calls, then the two derived regions. Invalidating
        // the sources alone would be enough — the derived providers watch them
        // — but naming all five keeps a pull-to-refresh honest if one of them
        // is ever given its own fetch.
        ref.invalidate(serviceSummaryProvider(ServiceKey.nzbget));
        ref.invalidate(serviceKpiProvider(ServiceKey.nzbget));
        ref.invalidate(nzbgetStatusProvider);
        ref.invalidate(nzbgetQueueProvider);
        ref.invalidate(nzbgetHistoryProvider);
        ref.invalidate(nzbgetOverviewHistoryProvider);
        ref.invalidate(nzbgetOverviewQueueProvider);
        await Future<void>.delayed(AppAnimation.durationMd);
      },
      // One scroll view for the whole page: the regions are one column of
      // reading, not two independently scrolling panes.
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.only(
          bottom: FloatingNavBarMetrics.getScrollViewBottomPadding(context),
        ),
        children: [
          if (topPadding > 0) SizedBox(height: topPadding),
          const ServiceOverviewIdentity(service: ServiceKey.nzbget),
          // The shared rail, not a private one: Speed, Queue, Remaining and
          // Status are the same four figures the stack matrix shows for this
          // service, and a second copy computed here would be free to drift.
          // The board's fifth and sixth tiles — Disk free, and "no limit" under
          // Speed — are the two figures `NzbgetStatus` does not parse.
          ServiceKpiPeek(
            kpis: ref.watch(serviceKpiProvider(ServiceKey.nzbget)),
            accent: ServiceKey.nzbget.accent,
          ),
          const _HistorySection(),
          const _QueueSection(),
        ],
      ),
    );
  }
}

// ─── 1. History ─────────────────────────────────────────────────────────────

/// What finished today, faults first.
class _HistorySection extends ConsumerWidget {
  const _HistorySection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final section = ref.watch(nzbgetOverviewHistoryProvider);
    // `AsyncValue.value`, never `asData?.value`: `asData` is null for an
    // `AsyncError` and for an `AsyncLoading` that is still carrying the
    // previous data, while `AsyncValueWidget` draws that retained readout at
    // full ink under the unreachable band. With `asData` the header would print
    // "today · —" over three rows stating the very figures it claims not to
    // know — on every pull-to-refresh, and for as long as the box stays off the
    // network. (`value` is riverpod 3's spelling of riverpod 2's `valueOrNull`;
    // the four earlier Overviews still use `asData?.value` and inherit the bug.)
    final data = section.value;

    return ServiceOverviewSection(
      service: ServiceKey.nzbget,
      title: 'History',
      // "today · —" while it loads or after it failed. A "0 completed" printed
      // over an unanswered question is a claim nobody made — and on this
      // section it would be the *reassuring* claim, which is the worse of the
      // two mistakes.
      subtitle: data == null ? 'today · —' : data.subtitle,
      destination: ServiceTab.history,
      child: AsyncValueWidget<NzbgetHistorySection>(
        value: section,
        serviceName: 'NZBGet',
        loadingLabel: "Loading today's downloads",
        onRetry: () => ref.invalidate(nzbgetHistoryProvider),
        skeleton: const ServiceOverviewRowsSkeleton(rows: 2),
        isEmpty: (value) => value.rows.isEmpty,
        // A resting state wears no alarm chrome: a day with nothing finished on
        // it is not an error.
        emptyBuilder: const ServiceOverviewEmpty(
          icon: Icons.history_rounded,
          label: 'Nothing finished today',
        ),
        data: (value) => Column(
          children: [for (final entry in value.rows) _HistoryRow(entry: entry)],
        ),
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.entry});

  final NzbgetHistoryEntry entry;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    // Through the tone rule, never a raw `AppColors.*`: amber is a fault, and a
    // job NZBGet deleted on purpose — a dupe, a manual removal — is neutral by
    // construction. The surface is named because this row sits on the page's
    // own container and the walk is measured against what the ink lands on.
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
      title: entry.headline,
      // Only a fault carries its tone into the title. A row that merely
      // succeeded reads in ordinary ink, so a green page has one colour on it
      // and the amber lines are the ones the eye lands on — which is the whole
      // reason this section leads with them.
      titleColor: entry.outcome.isFault ? tone : null,
      detail: entry.detail,
    );
  }
}

// ─── 2. Queue ───────────────────────────────────────────────────────────────

/// What is downloading now.
class _QueueSection extends ConsumerWidget {
  const _QueueSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final section = ref.watch(nzbgetOverviewQueueProvider);
    // `AsyncValue.value` for the reason spelled out on the History section: a
    // retained readout drawn under the fault band must not be contradicted by
    // an em dash in the header above it.
    final data = section.value;

    return ServiceOverviewSection(
      service: ServiceKey.nzbget,
      title: 'Queue',
      subtitle: data == null ? '—' : data.subtitle,
      destination: ServiceTab.queue,
      child: AsyncValueWidget<NzbgetQueueSection>(
        value: section,
        serviceName: 'NZBGet',
        loadingLabel: 'Loading the queue',
        onRetry: () => ref.invalidate(nzbgetQueueProvider),
        skeleton: const ServiceOverviewRowsSkeleton(rows: 2),
        isEmpty: (value) => value.rows.isEmpty,
        emptyBuilder: const ServiceOverviewEmpty(
          icon: Icons.download_done_rounded,
          label: 'Nothing in the queue',
        ),
        data: (value) => Column(
          children: [for (final entry in value.rows) _QueueRow(entry: entry)],
        ),
      ),
    );
  }
}

class _QueueRow extends StatelessWidget {
  const _QueueRow({required this.entry});

  final NzbgetQueueEntry entry;

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
      leading: Icon(entry.icon, size: 18, color: tone),
      title: entry.name,
      detail: entry.detail,
      // The figure on the right, capped by the shared row so an accessibility
      // reading size ellipsises it instead of overflowing. Null — not "0%" —
      // when NZBGet reported no size for the job.
      trailing: entry.percentLabel,
    );
  }
}
