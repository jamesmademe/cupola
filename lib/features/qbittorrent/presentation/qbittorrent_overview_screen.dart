import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/app_animation.dart';
import 'package:cupola/core/status/lexicon.dart';
import 'package:cupola/core/utils/arr_activity_display.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/qbittorrent/presentation/qbittorrent_actions.dart';
import 'package:cupola/features/qbittorrent/presentation/qbittorrent_overview_provider.dart';
import 'package:cupola/features/qbittorrent/presentation/qbittorrent_provider.dart';
import 'package:cupola/features/services/domain/service_tab.dart';
import 'package:cupola/features/services/presentation/service_kpi_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// The first tab of qBittorrent's service home.
///
/// Overview alone carries the identity block and the readouts: Queue and RSS
/// are each a view of one kind of record, and then four regions: what is
/// broken, what is moving, how the library is filed, and what the session has
/// done. Each region that has a tab to go to ends in a link named exactly like
/// that tab.
///
/// **It draws neither the app bar nor the tab bar.** `ServiceHomeScreen` owns
/// the first and `ServiceTabScaffold` the second, both floated above this page
/// as glass bands so the ambient gradient reads continuously behind them; this
/// screen reserves the room with [topPadding] instead.
///
/// ## Where this departs from the board, and why
///
/// **Needs attention is promoted out of the queue.** The desktop board folds
/// the stalled and errored torrents into the queue table, which works there
/// because that table draws all eighteen rows. An Overview preview draws five,
/// and on a real server the broken torrent is rarely in the first five: it is
/// the one that stopped moving days ago. A fault that a preview can hide is a
/// fault the page failed to report, so the faults get their own region above
/// the queue and the queue preview shows only what is actually moving. Nothing
/// appears in both: `stalledDL`, `error` and `missingFiles` all fail the active
/// test that builds the queue rows.
///
/// **The Overview keeps some board regions out of its compact summary**: RSS
/// is a dedicated endpoint-backed tab; DHT nodes, the listen port and the
/// all-time ratio are in the answer this page reads (`sync/maindata`'s
/// `server_state`) but not drawn yet. An em dash is reserved for a requested
/// figure whose source did not answer, so they are absent rather than `—`.
///  * **Disk free**: the board's fourth readout is the Session list's last
///    row, `Free space`, when the server says it (old versions do not, and the
///    row is then absent).
///  * The *session* ratio is arithmetic on the session's two totals, and is
///    labelled as the session's.
///
/// Sections load and fail independently, each in its own slot, though today
/// they all read one answer and so mostly fail together.
class QbittorrentOverviewScreen extends ConsumerWidget {
  const QbittorrentOverviewScreen({
    super.key,
    this.topPadding = _hostedTopPadding,
  });

  /// The room the two glass bands above this page occupy.
  ///
  /// Composed from the same two constants the router composes its own from, so
  /// a screen built outside the router (a test, a preview) reserves the right
  /// space instead of tucking its first region under the tab bar.
  static const double _hostedTopPadding = kToolbarHeight + ServiceTabBar.height;

  /// Height of the chrome the host draws above this page.
  final double topPadding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Checked **before** any provider is reached. `qbittorrentServiceProvider`
    // throws `qBittorrent not configured`, and letting `AsyncValueWidget` catch
    // that throw would draw the same pixels while leaving four *failed*
    // providers behind it, each scheduling a retry with backoff for a condition
    // no amount of waiting changes, which surfaces in tests as a pending timer
    // and on device as a battery cost.
    final configured = ref.watch(
      currentSettingsProvider.select(
        (settings) => settings.isServiceConfigured(ServiceKey.qbittorrent),
      ),
    );

    return AmbientScaffold(
      accent: ServiceKey.qbittorrent.accent,
      body: SafeArea(
        child: configured
            ? _OverviewBody(topPadding: topPadding)
            // `.forService`, never the generic form: this is a service
            // dashboard, so the door goes to qBittorrent's own connection form
            // rather than the settings index.
            : NotConfiguredPlaceholder.forService(ServiceKey.qbittorrent),
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
        clearQbittorrentLoginRefusal(ref);
        invalidateServiceReadout(ref, ServiceKey.qbittorrent);
        // The two sources every region on this page is folded from. The four
        // derived providers below are invalidated too rather than left to
        // recompute: they are `autoDispose`, so a region the user has scrolled
        // past may already have been collected, and invalidating the source
        // alone would leave it holding the previous fold when it came back.
        ref.invalidate(allTorrentsProvider);
        ref.invalidate(transferInfoProvider);
        ref.invalidate(qbittorrentOverviewAttentionProvider);
        ref.invalidate(qbittorrentOverviewTransfersProvider);
        ref.invalidate(qbittorrentOverviewCountsProvider);
        ref.invalidate(qbittorrentOverviewCategoriesProvider);
        ref.invalidate(qbittorrentOverviewCategoryCountProvider);
        ref.invalidate(qbittorrentOverviewSessionProvider);
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
          const ServiceOverviewIdentity(service: ServiceKey.qbittorrent),
          ...sectionsOrOneLine(ref, ServiceKey.qbittorrent, [
            ServiceKpiPeek(
              kpis: ref.watch(serviceKpiProvider(ServiceKey.qbittorrent)),
              service: ServiceKey.qbittorrent,
            ),
            const _NeedsAttentionSection(),
            const _QueueSection(),
            const _CategoriesSection(),
            const _SessionSection(),
          ]),
        ],
      ),
    );
  }
}

// ─── 1. Needs attention ─────────────────────────────────────────────────────

/// What is broken, before what is working.
class _NeedsAttentionSection extends ConsumerWidget {
  const _NeedsAttentionSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(qbittorrentOverviewAttentionProvider);
    // The **census**, not the length of the list below it. `qbittorrentFaultRows`
    // caps at `qbittorrentAttentionLimit`, so its length is a sample: a server
    // with twelve broken torrents would print "4" over four rows and report the
    // other eight nowhere. `QbittorrentQueueCounts.faults` counts `stalled` and
    // `errored` over the whole list: the same population the rows are drawn
    // from, since `qbittorrentFaultKindOf` answers non-null for exactly those
    // two parsed states, so the header is where the remainder gets reported.
    final counts = ref.watch(qbittorrentOverviewCountsProvider).asData?.value;

    return ServiceOverviewSection(
      service: ServiceKey.qbittorrent,
      title: 'Needs attention',
      // `—` while the list is in flight or after it failed. A `0` printed over
      // an unanswered question is a claim nobody made, and the claim it makes
      // ("nothing is wrong") is the one the user would act on.
      subtitle: counts == null ? '—' : '${counts.faults}',
      // Every fault here is a torrent, and every torrent lives on the Queue
      // tab, so the destination is honest for all of them.
      destination: ServiceTab.queue,
      child: AsyncValueWidget<List<QbittorrentAttentionItem>>.section(
        value: items,
        service: ServiceKey.qbittorrent,
        consequence: 'what needs attention is not shown',
        loadingLabel: 'Loading what needs attention',
        onRetry: () {
          clearQbittorrentLoginRefusal(ref);
          ref.invalidate(qbittorrentOverviewAttentionProvider);
          ref.invalidate(allTorrentsProvider);
        },
        skeleton: const ServiceOverviewRowsSkeleton(rows: 2),
        isEmpty: (data) => data.isEmpty,
        // A resting state wears no alarm chrome: nothing is wrong, and saying
        // so is not an error state.
        emptyBuilder: const ServiceOverviewEmpty(
          icon: Icons.check_circle_outline_rounded,
          label: 'Nothing stuck or errored',
        ),
        data: (data) => Column(
          children: [for (final item in data) _AttentionRow(item: item)],
        ),
      ),
    );
  }
}

/// A row of Needs attention: a fault, and the way to where it is fixed.
///
/// One torrent opens its own page; the several a folded row stands for open
/// the Queue tab, which lists them all. One stalled torrent can be asked for
/// peers again from here, through the action the torrent's page and Needs you
/// already run: an errored torrent or one with missing files has no one-tap
/// remedy (the fix is a disk, or a recheck the page offers), and a torrent
/// somebody stopped is not here at all.
class _AttentionRow extends ConsumerWidget {
  const _AttentionRow({required this.item});

  final QbittorrentAttentionItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    // Through the tone rule, never a raw `AppColors.warning`: the walk resolves
    // amber against the surface this row actually lands on, which on the light
    // theme is a different hue from the one the dark artboards draw.
    final tone = statusToneColor(
      colorScheme,
      item.tone,
      surface: colorScheme.surfaceContainerLow,
    );
    final door = item.door;
    final hash = item.hash;

    return ServiceOverviewRow(
      spoken: item.spoken,
      leading: Icon(item.icon, size: 18, color: tone),
      title: item.headline,
      titleColor: tone,
      detail: item.detail,
      onTap: door == null
          ? null
          : () => openAttentionDoor(context, ServiceKey.qbittorrent, door),
      doorHint: door == null
          ? null
          : attentionDoorHint(ServiceKey.qbittorrent, door),
      action: hash != null && item.kind == QbittorrentFaultKind.stalled
          ? ServiceOverviewRowAction.remedy(
              label: 'Look for peers again',
              hint: 'asks the trackers again for ${item.subject}',
              onPressed: () => runTorrentAction(
                context,
                ref,
                action: (service) => service.reannounce([hash]),
                successMessage: 'Asked the trackers for more peers',
                failureMessage: 'Could not look for peers again',
              ),
            )
          : null,
    );
  }
}

// ─── 2. Queue ───────────────────────────────────────────────────────────────

/// What is actually moving right now.
class _QueueSection extends ConsumerWidget {
  const _QueueSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final transfers = ref.watch(qbittorrentOverviewTransfersProvider);
    final counts = ref.watch(qbittorrentOverviewCountsProvider).asData?.value;

    return ServiceOverviewSection(
      service: ServiceKey.qbittorrent,
      title: 'Queue',
      // The census, in the board's order, plus the paused figure the board does
      // not draw. Paused is stated as a plain count and coloured like every
      // other word here: a torrent the user stopped is **backlog**, and
      // painting it amber beside a genuinely stalled one is how the five-arm
      // tone rule gets broken in a download client.
      subtitle: counts == null
          ? '—'
          : joinDisplayParts([
              counts.total == 1 ? '1 torrent' : '${counts.total} torrents',
              '${counts.downloading} downloading',
              '${counts.seeding} seeding',
              if (counts.paused > 0)
                '${counts.paused} ${StateWord.stopped.inline}',
            ]),
      destination: ServiceTab.queue,
      child: AsyncValueWidget<List<QbittorrentTransferRow>>.section(
        value: transfers,
        service: ServiceKey.qbittorrent,
        consequence: 'its queue is not shown',
        loadingLabel: 'Loading the queue',
        onRetry: () {
          clearQbittorrentLoginRefusal(ref);
          ref.invalidate(qbittorrentOverviewTransfersProvider);
          ref.invalidate(allTorrentsProvider);
        },
        skeleton: const ServiceOverviewRowsSkeleton(rows: 3),
        isEmpty: (data) => data.isEmpty,
        emptyBuilder: const ServiceOverviewEmpty(
          icon: Icons.pause_circle_outline_rounded,
          label: 'Nothing transferring',
        ),
        data: (data) =>
            Column(children: [for (final row in data) _TransferRow(row: row)]),
      ),
    );
  }
}

class _TransferRow extends StatelessWidget {
  const _TransferRow({required this.row});

  final QbittorrentTransferRow row;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final tone = statusToneColor(
      colorScheme,
      row.tone,
      surface: colorScheme.surfaceContainerLow,
    );

    return ServiceOverviewRow(
      spoken: row.spoken,
      // A dot rather than a glyph: downloading and seeding are two states of
      // one healthy thing, and two icons would read as two kinds of event.
      leading: Container(
        width: 8,
        height: 8,
        margin: const EdgeInsets.only(top: 5),
        decoration: BoxDecoration(color: tone, shape: BoxShape.circle),
      ),
      // The name is left in ink rather than tinted: the tone belongs to the
      // dot, and a page where every row's title is coloured has no way left to
      // say that one of them is different.
      title: row.name,
      detail: row.detail,
      trailing: row.percent,
    );
  }
}

// ─── 3. Categories ──────────────────────────────────────────────────────────

/// How the library is filed, and how much sits under each heading.
class _CategoriesSection extends ConsumerWidget {
  const _CategoriesSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rows = ref.watch(qbittorrentOverviewCategoriesProvider);
    final categories = ref
        .watch(qbittorrentOverviewCategoryCountProvider)
        .asData
        ?.value;
    final counts = ref.watch(qbittorrentOverviewCountsProvider).asData?.value;

    return ServiceOverviewSection(
      service: ServiceKey.qbittorrent,
      title: 'Categories',
      subtitle: categories == null || counts == null
          ? '—'
          : joinDisplayParts([
              categories == 1 ? '1 category' : '$categories categories',
              counts.total == 1 ? '1 torrent' : '${counts.total} torrents',
            ]),
      // No link. The board's header carries a "Manage →" that would open a
      // category editor; there is no Categories tab on qBittorrent's bar and no
      // write call behind one, and a link named after a tab that does not exist
      // is a promise the app cannot keep.
      child: AsyncValueWidget<List<QbittorrentCategoryRow>>.section(
        value: rows,
        service: ServiceKey.qbittorrent,
        consequence: 'its categories are not shown',
        loadingLabel: 'Loading categories',
        onRetry: () {
          clearQbittorrentLoginRefusal(ref);
          ref.invalidate(qbittorrentOverviewCategoriesProvider);
          ref.invalidate(allTorrentsProvider);
        },
        skeleton: const ServiceOverviewRowsSkeleton(rows: 3),
        isEmpty: (data) => data.isEmpty,
        emptyBuilder: const ServiceOverviewEmpty(
          icon: Icons.folder_outlined,
          label: 'Nothing to file yet',
        ),
        data: (data) =>
            Column(children: [for (final row in data) _CategoryRow(row: row)]),
      ),
    );
  }
}

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({required this.row});

  final QbittorrentCategoryRow row;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return ServiceOverviewRow(
      spoken: row.spoken,
      // The service's own accent, walked to ink by the shared helper: a
      // category is inventory, not a status, so it takes no tone from the
      // five-arm rule.
      leading: Icon(
        Icons.folder_rounded,
        size: 18,
        color: serviceOverviewInk(ServiceKey.qbittorrent, colorScheme),
      ),
      title: row.name,
      detail: row.countLabel,
      trailing: row.sizeLabel,
    );
  }
}

// ─── 4. Session ─────────────────────────────────────────────────────────────

/// What this run of qBittorrent has moved, and under what limits.
class _SessionSection extends ConsumerWidget {
  const _SessionSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final facts = ref.watch(qbittorrentOverviewSessionProvider);

    return ServiceOverviewSection(
      service: ServiceKey.qbittorrent,
      title: 'Session',
      // Says the window in the header, because every figure below it is scoped
      // to the current run of the daemon and three of them: downloaded,
      // uploaded, and ratio look exactly like all-time totals otherwise.
      subtitle: 'since qBittorrent started',
      // No link: qBittorrent's bar is Overview, Queue and RSS. There is no
      // Session tab to send anyone to.
      child: AsyncValueWidget<List<QbittorrentSessionFact>>.section(
        value: facts,
        service: ServiceKey.qbittorrent,
        consequence: 'its session figures are not shown',
        loadingLabel: 'Loading the session',
        onRetry: () {
          clearQbittorrentLoginRefusal(ref);
          ref.invalidate(qbittorrentOverviewSessionProvider);
          ref.invalidate(transferInfoProvider);
        },
        skeleton: const ServiceOverviewRowsSkeleton(rows: 3),
        // Never empty: `/transfer/info` either answers all six facts or fails,
        // and a failure is the error state rather than an empty one.
        data: (data) => Column(
          children: [for (final fact in data) _SessionRow(fact: fact)],
        ),
      ),
    );
  }
}

class _SessionRow extends StatelessWidget {
  const _SessionRow({required this.fact});

  final QbittorrentSessionFact fact;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return ServiceOverviewRow(
      spoken: fact.spoken,
      leading: Icon(fact.icon, size: 18, color: colorScheme.onSurfaceVariant),
      // The figure in the title slot and its label beneath, the inverse of the
      // other three regions, and deliberately so. There the title is the
      // subject (a torrent, a category) and the trailing figure is secondary,
      // which is the shape `ServiceOverviewRow` was built for. Session has no
      // subject: "Downloaded this session" is chrome and `1.2 TB` is the
      // content, so putting the label in the primary slot would print six
      // captions at 13/w600 with their answers dimmed to 11pt at the right
      // margin, and capped at 132pt, where a long figure ellipsises. The board
      // draws these the other way round (figure large, label small) for the
      // same reason, and `AppTheme.data` sitting above Label is the theme
      // saying it: the thing that needs a human must never be smaller than the
      // word describing it.
      title: fact.value,
      detail: fact.label,
    );
  }
}
