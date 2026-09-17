import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/app_animation.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/services/domain/service_tab.dart';
import 'package:cupola/features/services/presentation/service_kpi_provider.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/transmission/domain/models/transmission_models.dart';
import 'package:cupola/features/transmission/presentation/transmission_overview_provider.dart';
import 'package:cupola/features/transmission/presentation/transmission_provider.dart';
import 'package:cupola/features/transmission/presentation/widgets/transmission_torrent_tile.dart';

/// The first tab of Transmission's service home.
///
/// Overview alone carries the identity block and the readouts — Queue, Labels
/// and Session are each a view of one kind of record — and then four regions in
/// the order the board draws them: what is moving, how it is filed, how the
/// daemon is configured, what landed today.
///
/// **It draws neither the app bar nor the tab bar.** `ServiceHomeScreen` owns
/// the first and `ServiceTabScaffold` the second, both floated above this page
/// as glass bands so the ambient gradient reads continuously behind them; this
/// screen reserves the room with [topPadding] instead.
///
/// Regions load and fail independently, which is the design's SECTION failure
/// level. Here that independence is nearly free: three of the four regions are
/// projections of the same `torrent-get`, so they succeed and fail together by
/// construction, and only Session — the one built on `session-get` plus
/// `free-space` — can be the odd one out. That is the shape worth having: a
/// daemon that lists its torrents but will not report its own free space still
/// draws three full regions.
class TransmissionOverviewScreen extends ConsumerWidget {
  const TransmissionOverviewScreen({
    super.key,
    this.topPadding = _hostedTopPadding,
  });

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
    // Asked **before** any provider is watched, and that ordering is the whole
    // point: `transmissionClientProvider` throws "Transmission not configured",
    // so letting a section's `AsyncValueWidget` catch it would paint the same
    // pixels while leaving four *failed* providers behind — each scheduling a
    // retry with backoff for a condition no amount of waiting changes, and each
    // surfacing in a widget test as a pending timer.
    final configured = ref.watch(
      currentSettingsProvider.select(
        (settings) => settings.isServiceConfigured(ServiceKey.transmission),
      ),
    );

    return AmbientScaffold(
      accent: ServiceKey.transmission.accent,
      body: SafeArea(
        child: configured
            ? _OverviewBody(topPadding: topPadding)
            // `.forService`, never the generic form: this is a service
            // dashboard, so the door goes to Transmission's own connection form
            // rather than to the settings index.
            : NotConfiguredPlaceholder.forService(ServiceKey.transmission),
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
        // The two sources first, then everything derived from them. Invalidating
        // only the derived providers would refresh nothing: they would rebuild
        // off the same cached `torrent-get` and print the figures the user just
        // pulled to replace.
        ref.invalidate(transmissionTorrentsProvider);
        ref.invalidate(transmissionSessionProvider);
        ref.invalidate(transmissionStatsProvider);
        ref.invalidate(serviceSummaryProvider(ServiceKey.transmission));
        ref.invalidate(serviceKpiProvider(ServiceKey.transmission));
        ref.invalidate(transmissionTransferringProvider);
        ref.invalidate(transmissionLabelsProvider);
        ref.invalidate(transmissionFreeSpaceProvider);
        ref.invalidate(transmissionSessionFactsProvider);
        ref.invalidate(transmissionFinishedTodayProvider);
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
          const ServiceOverviewIdentity(service: ServiceKey.transmission),
          ServiceKpiPeek(
            kpis: ref.watch(serviceKpiProvider(ServiceKey.transmission)),
            accent: ServiceKey.transmission.accent,
          ),
          const _TransferringSection(),
          const _LabelsSection(),
          const _SessionSection(),
          const _FinishedTodaySection(),
        ],
      ),
    );
  }
}

// ─── 1. Transferring ────────────────────────────────────────────────────────

class _TransferringSection extends ConsumerWidget {
  const _TransferringSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rows = ref.watch(transmissionTransferringProvider);
    // The subtitle counts the **whole** queue, not the five rows below it, so
    // it is read off the source list rather than off the sample. `asData` and
    // not `valueOrNull`: while the list is in flight there is no count to
    // print, and the subtitle says so with an em dash.
    final all = ref.watch(transmissionTorrentsProvider).asData?.value;

    return ServiceOverviewSection.bleed(
      service: ServiceKey.transmission,
      title: 'Transferring',
      subtitle: transmissionTransferringSubtitle(all),
      destination: ServiceTab.queue,
      // `.bleed()`, because `DownloadQueueTile` carries its own `AppSpacing.lg`
      // gutter: inside the padded body it would sit at double the page inset
      // and every other region would be out of alignment with it.
      //
      // The board draws the queue's filter pills — All / Active / Seeding /
      // Stopped / Errored — inside this region. They are not here on purpose:
      // filtering belongs to the Queue tab, and a pill on a five-row sample
      // either filters five rows (useless) or silently means something
      // different from the same pill one tab over (worse). The link goes there.
      child: AsyncValueWidget<List<TransmissionTorrent>>(
        value: rows,
        serviceName: 'Transmission',
        loadingLabel: 'Loading what Transmission is transferring',
        onRetry: () => ref.invalidate(transmissionTorrentsProvider),
        skeleton: const Padding(
          padding: EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: ServiceOverviewRowsSkeleton(rows: 3),
        ),
        isEmpty: (items) => items.isEmpty,
        emptyBuilder: const Padding(
          padding: EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: ServiceOverviewEmpty(
            icon: Icons.inbox_outlined,
            label: 'No torrents on this daemon',
          ),
        ),
        data: (items) => Column(
          children: [
            for (final torrent in items)
              // The app's one queue plate, reached through the thin adapter
              // that turns a `TransmissionTorrent` into it. No `actions`: the
              // per-torrent command menu lives on the Queue tab, and a second
              // copy of it here would be a second place to get the destructive
              // one — remove-with-data — wrong.
              TransmissionTorrentTile(torrent: torrent),
          ],
        ),
      ),
    );
  }
}

// ─── 2. Labels ──────────────────────────────────────────────────────────────

class _LabelsSection extends ConsumerWidget {
  const _LabelsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final labels = ref.watch(transmissionLabelsProvider);
    final count = labels.asData?.value.length;

    return ServiceOverviewSection(
      service: ServiceKey.transmission,
      title: 'Labels',
      subtitle: count == null ? '—' : '$count',
      destination: ServiceTab.labels,
      child: AsyncValueWidget<List<TransmissionLabelTally>>(
        value: labels,
        serviceName: 'Transmission',
        loadingLabel: 'Loading Transmission labels',
        onRetry: () => ref.invalidate(transmissionTorrentsProvider),
        skeleton: const ServiceOverviewRowsSkeleton(rows: 2),
        isEmpty: (items) => items.isEmpty,
        // Nothing is wrong with a daemon whose owner never filed anything, so
        // the absence costs a line rather than an alarm.
        emptyBuilder: const ServiceOverviewEmpty(
          icon: Icons.label_off_outlined,
          label: 'Nothing is labelled',
        ),
        data: (items) => Column(
          children: [
            for (final tally in items.take(transmissionLabelsPreviewLimit))
              _LabelRow(tally: tally),
          ],
        ),
      ),
    );
  }
}

class _LabelRow extends StatelessWidget {
  const _LabelRow({required this.tally});

  final TransmissionLabelTally tally;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return ServiceOverviewRow(
      spoken: tally.spoken,
      leading: Icon(
        Icons.sell_outlined,
        size: 18,
        // The service accent walked until it can carry ink. A label is not a
        // state, so it takes the service's own colour rather than a tone —
        // painting it through the tone rule would have to pick an arm, and
        // "movies" is not any of the five.
        color: serviceOverviewInk(ServiceKey.transmission, colorScheme),
      ),
      title: tally.label,
      detail: '',
      trailing: '${tally.count}',
    );
  }
}

// ─── 3. Session ─────────────────────────────────────────────────────────────

class _SessionSection extends ConsumerWidget {
  const _SessionSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final facts = ref.watch(transmissionSessionFactsProvider);

    return ServiceOverviewSection(
      service: ServiceKey.transmission,
      title: 'Session',
      // No count and no summary line. The board's subtitle here was the port
      // test's result, which this app cannot run — see the library comment on
      // `transmission_overview_provider.dart` for the three rows that went with
      // it.
      destination: ServiceTab.session,
      child: AsyncValueWidget<List<TransmissionSessionFact>>(
        value: facts,
        serviceName: 'Transmission',
        loadingLabel: 'Loading Transmission session settings',
        onRetry: () {
          ref.invalidate(transmissionSessionProvider);
          ref.invalidate(transmissionFreeSpaceProvider);
        },
        skeleton: const ServiceOverviewRowsSkeleton(rows: 3),
        // No empty state: `session-get` either answers or throws, and a daemon
        // that answered always has these four settings. An `isEmpty` here would
        // be a branch nothing can reach.
        data: (items) => Column(
          children: [for (final fact in items) _SessionRow(fact: fact)],
        ),
      ),
    );
  }
}

class _SessionRow extends StatelessWidget {
  const _SessionRow({required this.fact});

  final TransmissionSessionFact fact;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    // Through the tone rule, never a raw `AppColors.*`, and walked against the
    // surface these rows actually land on rather than against the scaffold's.
    final tone = statusToneColor(
      colorScheme,
      fact.tone,
      surface: colorScheme.surfaceContainerLow,
    );

    return ServiceOverviewRow(
      spoken: fact.spoken,
      leading: Icon(fact.icon, size: 18, color: tone),
      // The value rides the title line and the trailing slot stays empty. That
      // slot is 132pt wide, one line, ellipsised — shaped for a figure like
      // `298 queries` — and these values are sentences: at 3× reading size it
      // would hold about seven characters of `Not limited`, and the value is
      // the whole row. On the title line it wraps instead, which is also the
      // shape the board draws this region in.
      title: fact.titleLine,
      detail: fact.detail,
    );
  }
}

// ─── 4. Finished today ──────────────────────────────────────────────────────

class _FinishedTodaySection extends ConsumerWidget {
  const _FinishedTodaySection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final finished = ref.watch(transmissionFinishedTodayProvider);
    final count = finished.asData?.value.length;

    return ServiceOverviewSection(
      service: ServiceKey.transmission,
      title: 'Finished today',
      subtitle: count == null ? '—' : '$count',
      // No link, deliberately. The board labels this region's link `History`,
      // and Transmission's bar has no History tab — the daemon keeps no history
      // of its own, only the torrents it still holds, which is exactly why this
      // region is derived from `doneDate` rather than fetched. A link naming a
      // tab that does not exist is a promise the app cannot keep.
      child: AsyncValueWidget<List<TransmissionFinishedItem>>(
        value: finished,
        serviceName: 'Transmission',
        loadingLabel: 'Loading what finished today',
        onRetry: () => ref.invalidate(transmissionTorrentsProvider),
        skeleton: const ServiceOverviewRowsSkeleton(rows: 2),
        isEmpty: (items) => items.isEmpty,
        emptyBuilder: const ServiceOverviewEmpty(
          icon: Icons.done_all_rounded,
          label: 'Nothing finished today',
        ),
        data: (items) => Column(
          children: [for (final item in items) _FinishedRow(item: item)],
        ),
      ),
    );
  }
}

class _FinishedRow extends StatelessWidget {
  const _FinishedRow({required this.item});

  final TransmissionFinishedItem item;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final tone = statusToneColor(
      colorScheme,
      item.tone,
      surface: colorScheme.surfaceContainerLow,
    );

    return ServiceOverviewRow(
      spoken: item.spoken,
      // A dot and not a glyph: the row's state is already a word in its detail
      // line, so the mark's only job is to let the eye group the rows by tone.
      leading: Container(
        width: 8,
        height: 8,
        margin: const EdgeInsets.only(top: 5),
        decoration: BoxDecoration(color: tone, shape: BoxShape.circle),
      ),
      title: item.name,
      detail: item.detail,
      trailing: item.ratioLabel,
    );
  }
}
