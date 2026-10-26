import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/readarr/presentation/readarr_overview_provider.dart';
import 'package:cupola/features/readarr/presentation/readarr_provider.dart';
import 'package:cupola/features/services/presentation/service_kpi_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// The first tab of Readarr's service home.
///
/// Overview alone carries the identity block and the readouts: every other tab
/// is a view of one kind of record, and then the regions the client can
/// actually fill, in the order the board draws them.
///
/// **Two of the board's five regions are not here, and their absence is the
/// design.** `Coming up` wants `GET /api/v1/calendar` and `Recently added`
/// wants `GET /api/v1/book`; `ReadarrService` calls neither, and an author
/// carries no release date and no cover, so neither could be derived from what
/// is loaded. Drawing them empty would print `0 releases` and `Nothing added
/// yet` over questions nobody asked the server: a promise the app cannot keep.
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
class ReadarrOverviewScreen extends StatelessWidget {
  const ReadarrOverviewScreen({
    super.key,
    this.topPadding = ServiceOverviewPage.hostedTopPadding,
  });

  /// Height of the chrome the host draws above this page.
  final double topPadding;

  @override
  Widget build(BuildContext context) {
    return ServiceOverviewPage(
      service: ServiceKey.readarr,
      topPadding: topPadding,
      refresh: _refresh,
      sections: (ref) => [
        ArrNeedsAttentionSection(
          service: ServiceKey.readarr,
          items: readarrNeedsAttentionProvider,
          queueRecords: readarrQueueRecordsProvider,
          retry: [
            readarrNeedsAttentionProvider,
            readarrQueueRecordsProvider,
            // The library is plain, not autoDispose: a Retry that re-ran the
            // fold alone read its cached failure straight back.
            readarrAuthorsProvider,
          ],
        ),
        const _RootFolderSection(),
        ArrHistoryTodaySection(
          service: ServiceKey.readarr,
          entries: readarrHistoryTodayProvider,
          retry: [readarrHistoryTodayProvider],
        ),
      ],
    );
  }
}

/// What a pull re-reads besides the readout (`ServiceOverviewPage`).
void _refresh(WidgetRef ref) {
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
  // scope: `Queue` frozen while Authors, Books and Missing moved.
  ref.invalidate(readarrQueueProvider);
  ref.invalidate(readarrQueueRecordsProvider);
  ref.invalidate(readarrBelowCutoffProvider);
  ref.invalidate(readarrNeedsAttentionProvider);
  ref.invalidate(readarrRootFoldersProvider);
  ref.invalidate(readarrHistoryTodayProvider);
}

// ─── Root folder ────────────────────────────────────────────────────────────

/// Where Readarr files books, and how much room is left.
///
/// The board draws a meter here (`160 GB used · 16% of 1 TB`) and this draws
/// only the free figure, because `/rootfolder` carries `freeSpace` and no
/// total. A percentage needs a denominator, and the denominator lives behind
/// `/api/v1/diskspace`, which the client does not call. One true figure rather
/// than a bar whose length would be invented.
///
/// The mobile board drops this region entirely, and it is here anyway: it was
/// dropped for room, competing against Coming up and Recently added; and on
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
    // under it was still drawing: a server that stopped answering took the
    // count with it and left the rows. Same test the widget itself applies.
    final count = folders.hasValue ? folders.requireValue.length : 0;

    return ServiceOverviewSection(
      service: ServiceKey.readarr,
      title: 'Root folder',
      // Silent for the ordinary one-folder server; a count only once it is news
      // that the title's singular does not cover the whole story.
      subtitle: count > 1 ? '$count folders' : null,
      // The board's link is "Manage →", which opens the service's own settings
      // page rather than one of its tabs, and `ServiceTab` has no settings
      // member because settings is not a tab. No link, rather than a link that
      // lands somewhere else.
      child: AsyncValueWidget<List<ReadarrRootFolder>>.section(
        value: folders,
        service: ServiceKey.readarr,
        consequence: 'its root folders are not shown',
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
