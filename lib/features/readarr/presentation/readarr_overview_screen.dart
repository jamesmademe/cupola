import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/app_animation.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/readarr/presentation/readarr_overview_provider.dart';
import 'package:cupola/features/readarr/presentation/readarr_provider.dart';
import 'package:cupola/features/services/domain/service_tab.dart';
import 'package:cupola/features/services/presentation/service_kpi_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// The first tab of Readarr's service home.
///
/// Overview alone carries the identity block and the readouts — every other tab
/// is a view of one kind of record — and then the regions the client can
/// actually fill, in the order the board draws them.
///
/// **Two of the board's five regions are not here, and their absence is the
/// design.** `Coming up` wants `GET /api/v1/calendar` and `Recently added`
/// wants `GET /api/v1/book`; `ReadarrService` calls neither, and an author
/// carries no release date and no cover, so neither could be derived from what
/// is loaded. Drawing them empty would print `0 releases` and `Nothing added
/// yet` over questions nobody asked the server — a promise the app cannot keep.
/// `readarr_overview_provider.dart` carries the long form of the reasoning.
///
/// What is left is real: the queue's faults, the library's backlog, where the
/// books are filed, and what happened today.
///
/// **It draws neither the app bar nor the tab bar.** `ServiceHomeScreen` owns
/// the first and `ServiceTabScaffold` the second, both as glass bands floated
/// above this page so the ambient gradient reads continuously behind them; this
/// screen reserves the room with [topPadding] instead.
///
/// Sections load independently and fail independently. That is the design's
/// SECTION failure level: a Readarr that answers the library and not the queue
/// still draws its other regions, and the one that could not load says so in
/// its own slot rather than taking the page with it.
class ReadarrOverviewScreen extends ConsumerWidget {
  const ReadarrOverviewScreen({super.key, this.topPadding = _hostedTopPadding});

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
    // Before any provider, never after: `readarrServiceProvider` throws for a
    // Readarr that was never set up, and a `FutureProvider` that throws is a
    // *failed* provider — Riverpod schedules a retry with backoff for a
    // condition no amount of waiting changes, which surfaces in tests as a
    // pending timer and on device as a request loop against nothing.
    final configured = ref.watch(
      currentSettingsProvider.select(
        (settings) => settings.isServiceConfigured(ServiceKey.readarr),
      ),
    );

    return AmbientScaffold(
      accent: ServiceKey.readarr.accent,
      body: SafeArea(
        child: configured
            ? _OverviewBody(topPadding: topPadding)
            // `.forService`, never the generic form: this is a service
            // dashboard, so the door goes to Readarr's own connection form
            // rather than to the settings index. Resolved once here rather than
            // three times inside three sections, which is what a page made only
            // of `AsyncValueWidget`s would print on a server that was never set
            // up.
            : NotConfiguredPlaceholder.forService(ServiceKey.readarr),
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
        invalidateServiceReadout(ref, ServiceKey.readarr);
        // The authors list feeds both the rail and the backlog row, so a pull
        // that refreshed only the derived provider would redraw the same
        // cached figure and look broken.
        ref.invalidate(readarrAuthorsProvider);
        // And the rail's own non-swallowing read of it. See
        // `readarrKpiLibraryProvider`.
        ref.invalidate(readarrKpiLibraryProvider);
        // And the queue behind the rail's fourth figure. `serviceKpiProvider`
        // is autoDispose; `readarrQueueProvider` is not, so invalidating only
        // the derived provider redrew the same cached count for the life of the
        // scope — `Queue` frozen while Authors, Books and Missing moved.
        ref.invalidate(readarrQueueProvider);
        ref.invalidate(readarrQueueRecordsProvider);
        ref.invalidate(readarrBelowCutoffProvider);
        ref.invalidate(readarrNeedsAttentionProvider);
        ref.invalidate(readarrRootFoldersProvider);
        ref.invalidate(readarrHistoryTodayProvider);
        await Future<void>.delayed(AppAnimation.durationMd);
      },
      // One scroll view for the whole page: the regions are one column of
      // reading, not three independently scrolling panes.
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.only(
          bottom: FloatingNavBarMetrics.getScrollViewBottomPadding(context),
        ),
        children: [
          if (topPadding > 0) SizedBox(height: topPadding),
          const ServiceOverviewIdentity(service: ServiceKey.readarr),
          ServiceKpiPeek(
            kpis: ref.watch(serviceKpiProvider(ServiceKey.readarr)),
            accent: ServiceKey.readarr.accent,
          ),
          const _NeedsAttentionSection(),
          const _RootFolderSection(),
          const _HistoryTodaySection(),
        ],
      ),
    );
  }
}

// ─── Needs attention ────────────────────────────────────────────────────────

class _NeedsAttentionSection extends ConsumerWidget {
  const _NeedsAttentionSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(readarrNeedsAttentionProvider);
    // `hasValue`, never `asData`: `asData` is null on an `AsyncError` even when
    // Riverpod retained the value it had, while `AsyncValueWidget` under this
    // header draws exactly that retained list at full ink beneath the
    // unreachable band. Read through `asData` the header printed "—" over rows
    // it was still showing. A source that never answered has no retained value
    // and still reads "—".
    final count = items.hasValue ? items.requireValue.length : null;

    return ServiceOverviewSection(
      service: ServiceKey.readarr,
      title: 'Needs attention',
      // "—" while the queue and the library are loading or after either failed:
      // a "0" printed over an unanswered question is a claim nobody made.
      subtitle: count == null ? '—' : '$count',
      // No link: these rows belong to different tabs — Queue for a stalled
      // import, Wanted for the backlog — and a single destination would have to
      // lie about one of the two.
      child: AsyncValueWidget<List<ReadarrAttentionItem>>(
        value: items,
        serviceName: 'Readarr',
        loadingLabel: 'Loading what needs attention',
        onRetry: () {
          ref.invalidate(readarrNeedsAttentionProvider);
          ref.invalidate(readarrQueueRecordsProvider);
        },
        skeleton: const ServiceOverviewRowsSkeleton(rows: 2),
        isEmpty: (data) => data.isEmpty,
        // The resting case, and it has to be reachable: every row here is
        // derived from a condition that can clear, so a Readarr with a quiet
        // queue and a complete library says so rather than badging a standing
        // 1. A resting state wears no alarm chrome — nothing is wrong, and
        // saying so is not an error state.
        emptyBuilder: const ServiceOverviewEmpty(
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

  final ReadarrAttentionItem item;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    // Through the tone rule, never a raw `AppColors.*`: amber is a fault and
    // the two backlog rows are neutral by construction.
    final tone = statusToneColor(
      colorScheme,
      item.tone,
      surface: colorScheme.surfaceContainerLow,
    );

    return ServiceOverviewRow(
      spoken: item.spoken,
      leading: Icon(item.icon, size: 18, color: tone),
      title: item.headline,
      titleColor: tone,
      detail: item.detail,
    );
  }
}

// ─── Root folder ────────────────────────────────────────────────────────────

/// Where Readarr files books, and how much room is left.
///
/// The board draws a meter here — `160 GB used · 16% of 1 TB` — and this draws
/// only the free figure, because `/rootfolder` carries `freeSpace` and no
/// total. A percentage needs a denominator, and the denominator lives behind
/// `/api/v1/diskspace`, which the client does not call. One true figure rather
/// than a bar whose length would be invented.
///
/// The mobile board drops this region entirely, and it is here anyway: it was
/// dropped for room, competing against Coming up and Recently added — and on
/// this screen neither of those exists to compete with.
class _RootFolderSection extends ConsumerWidget {
  const _RootFolderSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final folders = ref.watch(readarrRootFoldersProvider);
    // `hasValue`, never `asData`: `asData` is null on an `AsyncError` even when
    // Riverpod retained the value it had, and `AsyncValueWidget` below draws
    // exactly that retained list at full ink under the unreachable band. Read
    // through `asData` the header went silent about the folders the section
    // under it was still drawing — a server that stopped answering took the
    // count with it and left the rows. Same test the widget itself applies.
    final count = folders.hasValue ? folders.requireValue.length : 0;

    return ServiceOverviewSection(
      service: ServiceKey.readarr,
      title: 'Root folder',
      // Silent for the ordinary one-folder server; a count only once it is news
      // that the title's singular does not cover the whole story.
      subtitle: count > 1 ? '$count folders' : null,
      // The board's link is "Manage →", which opens the service's own settings
      // page rather than one of its tabs — and `ServiceTab` has no settings
      // member because settings is not a tab. No link, rather than a link that
      // lands somewhere else.
      child: AsyncValueWidget<List<ReadarrRootFolder>>(
        value: folders,
        serviceName: 'Readarr',
        loadingLabel: 'Loading root folders',
        onRetry: () => ref.invalidate(readarrRootFoldersProvider),
        skeleton: const ServiceOverviewRowsSkeleton(rows: 1),
        isEmpty: (items) => items.isEmpty,
        // A server that answered with no root folder has said something
        // specific and actionable: it has nowhere to put a book.
        emptyBuilder: const ServiceOverviewEmpty(
          icon: Icons.folder_off_outlined,
          label: 'No root folder configured',
        ),
        data: (items) => Column(
          children: [
            for (final folder in items) _RootFolderRow(folder: folder),
          ],
        ),
      ),
    );
  }
}

class _RootFolderRow extends StatelessWidget {
  const _RootFolderRow({required this.folder});

  final ReadarrRootFolder folder;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return ServiceOverviewRow(
      spoken: folder.spoken,
      leading: Icon(
        Icons.folder_outlined,
        size: 18,
        color: colorScheme.onSurfaceVariant,
      ),
      title: folder.path,
      // Nothing to add under the path: the figure is the row's other half and
      // it belongs on the right, where the eye scans a column of sizes.
      detail: '',
      trailing: folder.freeLabel,
    );
  }
}

// ─── History today ──────────────────────────────────────────────────────────

class _HistoryTodaySection extends ConsumerWidget {
  const _HistoryTodaySection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = ref.watch(readarrHistoryTodayProvider);

    return ServiceOverviewSection(
      service: ServiceKey.readarr,
      title: 'History',
      subtitle: 'today',
      destination: ServiceTab.history,
      child: AsyncValueWidget<List<ReadarrHistoryEntry>>(
        value: entries,
        serviceName: 'Readarr',
        loadingLabel: "Loading today's history",
        onRetry: () => ref.invalidate(readarrHistoryTodayProvider),
        skeleton: const ServiceOverviewRowsSkeleton(rows: 2),
        isEmpty: (items) => items.isEmpty,
        emptyBuilder: const ServiceOverviewEmpty(
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

  final ReadarrHistoryEntry entry;

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
