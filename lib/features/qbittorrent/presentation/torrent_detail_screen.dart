import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/generated/design_tokens.g.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/core/lifecycle/page_activity.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/route_utils.dart';
import 'package:cupola/core/utils/snack_bar_helper.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/qbittorrent/domain/models/parse_utils.dart';
import 'package:cupola/features/qbittorrent/domain/models/torrent.dart';
import 'package:cupola/features/qbittorrent/domain/models/torrent_file.dart';
import 'package:cupola/features/qbittorrent/domain/models/torrent_properties.dart';
import 'package:cupola/features/qbittorrent/domain/models/torrent_tracker.dart';
import 'package:cupola/features/qbittorrent/domain/tracker_tone.dart';
import 'package:cupola/features/qbittorrent/presentation/qbittorrent_actions.dart';
import 'package:cupola/features/qbittorrent/presentation/qbittorrent_provider.dart';
import 'package:cupola/features/qbittorrent/presentation/widgets/torrent_delete_dialog.dart';
import 'package:cupola/features/qbittorrent/presentation/widgets/torrent_edit_dialogs.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

class TorrentDetailScreen extends ConsumerStatefulWidget {
  final String hash;
  final String? heroTag;

  const TorrentDetailScreen({super.key, required this.hash, this.heroTag});

  @override
  ConsumerState<TorrentDetailScreen> createState() =>
      _TorrentDetailScreenState();
}

class _TorrentDetailScreenState extends ConsumerState<TorrentDetailScreen>
    with TickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // The not-configured gate, before anything is watched, for the reason
    // `QbittorrentScreen` states at length: a provider that throws
    // `qBittorrent not configured` is a provider that failed, and Riverpod
    // retries a failure on a backoff. A connection is configured in Settings or
    // it is not, so the poll and the retry are both spent on a question that
    // cannot change while this page is open. The screen is the same either way
    // — `AsyncValueWidget` was already routing that exception here.
    //
    // It matters more on this page than on the list, because a deep link lands
    // straight on it: `/dashboard/qbittorrent/queue/torrent/<hash>` from a
    // shortcut or a restored session reaches a torrent detail for a server the
    // app has never been told about.
    if (!ref
        .watch(currentSettingsProvider)
        .isServiceConfigured(ServiceKey.qbittorrent)) {
      return Scaffold(
        body: SafeArea(
          child: NotConfiguredPlaceholder.forService(ServiceKey.qbittorrent),
        ),
      );
    }

    // Only while this detail is the page on screen: a sort sheet over it, a
    // switch to another tab, or the app going away all stop the poll.
    ref.watchWhileLive(context, torrentDetailPollingProvider(widget.hash));
    final torrentAsync = ref.watch(qbittorrentTorrentsProvider(widget.hash));

    return AsyncValueWidget<List<Torrent>>(
      value: torrentAsync,
      serviceName: 'qBittorrent',
      onRetry: () {
        clearQbittorrentLoginRefusal(ref);
        ref.invalidate(qbittorrentTorrentsProvider(widget.hash));
      },
      data: (matches) {
        if (matches.isEmpty) {
          return Scaffold(
            appBar: AppBar(title: const Text('Torrent')),
            body: const Center(child: Text('Torrent not found')),
          );
        }
        return _buildContent(matches.first);
      },
    );
  }

  Widget _buildContent(Torrent torrent) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          SliverAppBar(
            floating: true,
            pinned: true,
            leading: IconButton(
              tooltip: MaterialLocalizations.of(context).backButtonTooltip,
              icon: Icon(
                Icons.chevron_left_rounded,
                color: colorScheme.onSurfaceVariant,
              ),
              onPressed: () =>
                  RouteUtils.popOrGo(context, ServiceRoutes.qbittorrentQueue),
            ),
            title: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  // The service's dot, monochrome: which service this is,
                  // the page's own route already says.
                  decoration: BoxDecoration(
                    color: colorScheme.onSurfaceVariant,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    torrent.name,
                    style: Theme.of(context).appBarTheme.titleTextStyle,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            bottom: TabBar(
              controller: _tabController,
              tabs: const [
                Tab(text: 'Info'),
                Tab(text: 'Files'),
                Tab(text: 'Trackers'),
                Tab(text: 'Actions'),
              ],
            ),
          ),
        ],
        body: TabBarView(
          controller: _tabController,
          children: [
            _InfoTab(torrent: torrent, hash: widget.hash),
            _FilesTab(hash: widget.hash),
            _TrackersTab(hash: widget.hash),
            _ActionsTab(torrent: torrent),
          ],
        ),
      ),
    );
  }
}

class _InfoTab extends ConsumerWidget {
  final Torrent torrent;
  final String hash;

  const _InfoTab({required this.torrent, required this.hash});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        _SectionLabel('Transfer'),
        _InfoRow(label: 'Name', value: torrent.name),
        _InfoRow(label: 'Size', value: torrent.sizeFormatted),
        _InfoRow(label: 'Progress', value: torrent.progressFormatted),
        _InfoRow(label: 'State', value: torrent.state),
        _InfoRow(label: 'Download speed', value: torrent.dlSpeedFormatted),
        _InfoRow(label: 'Upload speed', value: torrent.upSpeedFormatted),
        _InfoRow(label: 'ETA', value: torrent.etaFormatted),
        _InfoRow(label: 'Downloaded', value: formatSize(torrent.downloaded)),
        _InfoRow(label: 'Uploaded', value: formatSize(torrent.uploaded)),
        _InfoRow(label: 'Share ratio', value: torrent.ratio.toStringAsFixed(2)),
        const SizedBox(height: AppSpacing.lg),
        _SectionLabel('Organization'),
        _EditableInfoRow(
          label: 'Category',
          value: torrent.category,
          onTap: () => _editCategory(context, ref, torrent),
        ),
        _EditableInfoRow(
          label: 'Tags',
          value: torrent.tags.join(', '),
          onTap: () => _editTags(context, ref, torrent),
        ),
        const SizedBox(height: AppSpacing.lg),
        _SectionLabel('Activity'),
        _PropRow(
          label: 'Time active',
          hash: hash,
          valueOf: (p) => p.timeActiveFormatted,
        ),
        _PropRow(
          label: 'Seeded for',
          hash: hash,
          valueOf: (p) => p.seededForFormatted,
        ),
        _PropRow(
          label: 'Avg download speed',
          hash: hash,
          valueOf: (p) => p.dlSpeedAvgFormatted,
        ),
        _PropRow(
          label: 'Avg upload speed',
          hash: hash,
          valueOf: (p) => p.upSpeedAvgFormatted,
        ),
        _InfoRow(
          label: 'Last activity',
          value: formatEpochDate(torrent.lastActivity),
        ),
        _PropRow(
          label: 'Last seen',
          hash: hash,
          valueOf: (p) => p.lastSeenFormatted,
        ),
        _PropRow(
          label: 'Reannounce in',
          hash: hash,
          valueOf: (p) => p.reannounceFormatted,
        ),
        const SizedBox(height: AppSpacing.lg),
        _SectionLabel('Limits'),
        _PropRow(
          label: 'Download limit',
          hash: hash,
          valueOf: (p) => p.dlLimitFormatted,
        ),
        _PropRow(
          label: 'Upload limit',
          hash: hash,
          valueOf: (p) => p.upLimitFormatted,
        ),
        const SizedBox(height: AppSpacing.lg),
        _SectionLabel('Trackers & peers'),
        _PropRow(
          label: 'Connections',
          hash: hash,
          valueOf: (p) => p.connectionsFormatted,
        ),
        _PropRow(label: 'Peers', hash: hash, valueOf: (p) => p.peersFormatted),
        _PropRow(label: 'Seeds', hash: hash, valueOf: (p) => p.seedsFormatted),
        _PropRow(
          label: 'Pieces',
          hash: hash,
          valueOf: (p) => p.piecesFormatted,
        ),
        const SizedBox(height: AppSpacing.lg),
        _SectionLabel('File info'),
        _PropRow(
          label: 'Save path',
          hash: hash,
          valueOf: (p) => p.savePathFormatted,
        ),
        _PropRow(
          label: 'Created by',
          hash: hash,
          valueOf: (p) => p.createdByFormatted,
        ),
        _PropRow(
          label: 'Comment',
          hash: hash,
          valueOf: (p) => p.commentFormatted,
        ),
        _PropRow(
          label: 'Piece size',
          hash: hash,
          valueOf: (p) => p.pieceSizeFormatted,
        ),
        const SizedBox(height: AppSpacing.lg),
        _SectionLabel('Dates'),
        _InfoRow(label: 'Added on', value: formatEpochDate(torrent.addedOn)),
        _PropRow(
          label: 'Completed on',
          hash: hash,
          valueOf: (p) => p.completionDateFormatted,
        ),
        _PropRow(
          label: 'Created on',
          hash: hash,
          valueOf: (p) => p.creationDateFormatted,
        ),
      ],
    );
  }

  Future<void> _editCategory(
    BuildContext context,
    WidgetRef ref,
    Torrent torrent,
  ) async {
    final result = await showEditCategoryDialog(
      context,
      currentCategory: torrent.category,
    );
    if (result == null) return;
    if (result == torrent.category) return;
    if (!context.mounted) return;
    await runTorrentAction(
      context,
      ref,
      action: (service) => service.setCategory([torrent.hash], result),
      successMessage: 'Category set to "${result.trim()}"',
      failureMessage: 'Failed to set category',
      invalidate: [torrentsProvider, allTorrentsProvider],
    );
  }

  Future<void> _editTags(
    BuildContext context,
    WidgetRef ref,
    Torrent torrent,
  ) async {
    final result = await showEditTagsDialog(context, currentTags: torrent.tags);
    if (result == null) return;
    final newSet = result.toSet();
    final oldSet = torrent.tags.toSet();
    if (newSet.length == oldSet.length && newSet.containsAll(oldSet)) return;
    if (!context.mounted) return;
    final toAdd = newSet.difference(oldSet).toList();
    final toRemove = oldSet.difference(newSet).toList();
    await runTorrentAction(
      context,
      ref,
      action: (service) async {
        if (toAdd.isNotEmpty) await service.addTags([torrent.hash], toAdd);
        if (toRemove.isNotEmpty) {
          await service.removeTags([torrent.hash], toRemove);
        }
      },
      successMessage: 'Tags updated',
      failureMessage: 'Failed to update tags',
      invalidate: [torrentsProvider, allTorrentsProvider],
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value.isEmpty ? '—' : value,
              style: Theme.of(context).textTheme.bodySmall!.tabular,
            ),
          ),
        ],
      ),
    );
  }
}

class _EditableInfoRow extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback onTap;

  const _EditableInfoRow({
    required this.label,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(DesignTokens.radiusXs2),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          vertical: AppSpacing.xs,
          horizontal: AppSpacing.xs,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 120,
              child: Text(
                label,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            Expanded(
              child: Text(
                value.isEmpty ? '—' : value,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            Icon(
              Icons.edit_outlined,
              size: 14,
              color: colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

class _PropRow extends ConsumerWidget {
  final String label;
  final String hash;
  final String Function(TorrentProperties) valueOf;

  const _PropRow({
    required this.label,
    required this.hash,
    required this.valueOf,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final props = ref.watch(torrentPropertiesProvider(hash));
    return props.maybeWhen(
      data: (p) => _InfoRow(label: label, value: valueOf(p)),
      orElse: () => _InfoRow(label: label, value: '—'),
    );
  }
}

class _FilesTab extends ConsumerWidget {
  final String hash;

  const _FilesTab({required this.hash});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filesAsync = ref.watch(torrentFilesProvider(hash));

    return AsyncValueWidget<List<TorrentFile>>(
      value: filesAsync,
      serviceName: 'qBittorrent',
      onRetry: () {
        clearQbittorrentLoginRefusal(ref);
        ref.invalidate(torrentFilesProvider(hash));
      },
      data: (files) {
        if (files.isEmpty) {
          return const Center(child: Text('No files'));
        }
        return ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          itemCount: files.length,
          itemBuilder: (context, index) =>
              _FileRow(file: files[index], index: index, hash: hash),
        );
      },
    );
  }
}

class _FileRow extends ConsumerWidget {
  final TorrentFile file;
  final int index;
  final String hash;

  const _FileRow({required this.file, required this.index, required this.hash});

  static const _priorityLabels = <int, String>{
    0: 'Do not download',
    1: 'Normal',
    2: 'High',
    6: 'Maximum',
    7: 'Mixed',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;

    return ListTile(
      dense: true,
      onTap: () => _showPriorityMenu(context, ref),
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(2),
        child: SizedBox(
          // The progress bar's own geometry, not a layout gap: these stay
          // literals rather than borrowing the AppSpacing vocabulary.
          width: 4,
          height: 32,
          child: LinearProgressIndicator(
            value: file.progress,
            backgroundColor: colorScheme.outline,
          ),
        ),
      ),
      title: Text(
        file.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.bodySmall,
      ),
      subtitle: Text(
        file.priorityLabel,
        style: Theme.of(
          context,
        ).textTheme.labelSmall?.copyWith(color: colorScheme.onSurfaceVariant),
      ),
      trailing: Text(
        '${file.sizeFormatted} · ${file.progressFormatted}',
        style: Theme.of(context).textTheme.labelSmall!.tabular.copyWith(
          color: colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  Future<void> _showPriorityMenu(BuildContext context, WidgetRef ref) async {
    final picked = await AppBottomSheet.show<int>(
      context: context,
      title: 'Priority',
      icon: Icons.low_priority_rounded,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: _priorityLabels.entries
            .map(
              (e) => ListTile(
                dense: true,
                title: Text(e.value),
                trailing: file.priority == e.key
                    ? Icon(
                        Icons.check_rounded,
                        color: Theme.of(ctx).colorScheme.onSurface,
                        size: 18,
                      )
                    : null,
                onTap: () => Navigator.of(ctx).pop(e.key),
              ),
            )
            .toList(growable: false),
      ),
    );
    if (picked == null) return;
    if (picked == file.priority) return;
    if (!context.mounted) return;

    await runTorrentAction(
      context,
      ref,
      action: (service) =>
          service.filePrio(hash: hash, fileIndexes: [index], priority: picked),
      successMessage: 'Priority set to ${_priorityLabels[picked]}',
      failureMessage: 'Failed to set priority',
      invalidate: [torrentFilesProvider(hash)],
    );
  }
}

class _TrackersTab extends ConsumerWidget {
  final String hash;

  const _TrackersTab({required this.hash});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trackersAsync = ref.watch(torrentTrackersProvider(hash));

    return AsyncValueWidget<List<TorrentTracker>>(
      value: trackersAsync,
      serviceName: 'qBittorrent',
      onRetry: () {
        clearQbittorrentLoginRefusal(ref);
        ref.invalidate(torrentTrackersProvider(hash));
      },
      data: (trackers) {
        if (trackers.isEmpty) {
          return const Center(child: Text('No trackers'));
        }
        return ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          itemCount: trackers.length,
          itemBuilder: (context, index) =>
              _TrackerRow(tracker: trackers[index]),
        );
      },
    );
  }
}

class _TrackerRow extends StatelessWidget {
  final TorrentTracker tracker;

  const _TrackerRow({required this.tracker});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return ListTile(
      dense: true,
      title: Text(
        tracker.url,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.bodySmall!.tabular,
      ),
      subtitle: Row(
        children: [
          _StatusDot(status: tracker.status),
          const SizedBox(width: 6),
          Text(
            tracker.statusLabel,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
      trailing: Text(
        'Peers: ${tracker.numPeers}',
        style: Theme.of(context).textTheme.labelSmall!.tabular.copyWith(
          color: colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _StatusDot extends StatelessWidget {
  final int status;

  const _StatusDot({required this.status});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    // Through the tone rule, never the raw palette: the walk resolves the tone
    // against the surface this dot actually lands on, and at 6pt a mark that
    // carries the whole meaning of the row cannot afford to be the one thing
    // that misses contrast.
    final color = statusToneColor(
      colorScheme,
      trackerStatusTone(status),
      surface: colorScheme.surface,
    );

    return Container(
      width: 6,
      height: 6,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;

  const _SectionLabel(this.label);

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Text(
      label,
      style: Theme.of(context).textTheme.labelSmall!
          .weight(FontWeight.w600)
          .copyWith(color: colorScheme.onSurfaceVariant),
    );
  }
}

class _ActionsTab extends ConsumerWidget {
  final Torrent torrent;

  const _ActionsTab({required this.torrent});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        FilledButton.icon(
          onPressed: () => runTorrentAction(
            context,
            ref,
            action: (service) => service.resumeTorrents([torrent.hash]),
            successMessage: 'Resumed',
            failureMessage: 'Failed to resume',
            invalidate: [torrentsProvider, allTorrentsProvider],
          ),
          icon: const Icon(Icons.play_arrow_rounded, size: 18),
          label: const Text('Resume'),
        ),
        const SizedBox(height: AppSpacing.sm),
        FilledButton.icon(
          onPressed: () => runTorrentAction(
            context,
            ref,
            action: (service) => service.setForceStart([torrent.hash], true),
            successMessage: 'Force started',
            failureMessage: 'Failed',
            invalidate: [torrentsProvider, allTorrentsProvider],
          ),
          icon: const Icon(Icons.flash_on_rounded, size: 18),
          label: const Text('Force resume'),
        ),
        const SizedBox(height: AppSpacing.sm),
        // Pause is an action the user chooses, not a state the client reports,
        // so it wears no status tone at all — amber here said "something is
        // wrong" about a button, and hardcoded its ink black to survive it.
        FilledButton.icon(
          onPressed: () => runTorrentAction(
            context,
            ref,
            action: (service) => service.pauseTorrents([torrent.hash]),
            successMessage: 'Paused',
            failureMessage: 'Failed to pause',
            invalidate: [torrentsProvider, allTorrentsProvider],
          ),
          icon: const Icon(Icons.pause_rounded, size: 18),
          label: const Text('Pause'),
        ),
        const SizedBox(height: AppSpacing.sm),
        // The theme's own fill, like Pause above it: red means unreachable
        // and nothing else, and the confirmation says what Delete will do.
        FilledButton.icon(
          onPressed: () => _confirmDeleteSingle(context, ref, torrent),
          icon: const Icon(Icons.delete_outline_rounded, size: 18),
          label: const Text('Delete'),
        ),
        const SizedBox(height: AppSpacing.lg),
        OutlinedButton.icon(
          onPressed: () {
            Clipboard.setData(ClipboardData(text: torrent.hash));
            SnackBarHelper.info(context, 'Hash copied to clipboard');
          },
          icon: const Icon(Icons.copy_rounded, size: 16),
          label: const Text('Copy hash'),
        ),
        const SizedBox(height: AppSpacing.sm),
        OutlinedButton.icon(
          onPressed: () {
            Clipboard.setData(ClipboardData(text: torrent.name));
            SnackBarHelper.info(context, 'Name copied to clipboard');
          },
          icon: const Icon(Icons.copy_rounded, size: 16),
          label: const Text('Copy name'),
        ),
        const SizedBox(height: AppSpacing.xl),
        const Divider(),
        const SizedBox(height: AppSpacing.sm),
        _SectionLabel('Speed limits (this torrent)'),
        const SizedBox(height: AppSpacing.sm),
        OutlinedButton.icon(
          onPressed: () => _setLimit(context, ref, torrent, isDownload: true),
          icon: const Icon(Icons.south_rounded, size: 16),
          label: const Text('Download limit'),
        ),
        const SizedBox(height: AppSpacing.sm),
        OutlinedButton.icon(
          onPressed: () => _setLimit(context, ref, torrent, isDownload: false),
          icon: const Icon(Icons.north_rounded, size: 16),
          label: const Text('Upload limit'),
        ),
        const SizedBox(height: AppSpacing.xl),
        _SectionLabel('Global'),
        const SizedBox(height: AppSpacing.sm),
        OutlinedButton.icon(
          onPressed: () => _toggleAltSpeed(context, ref),
          icon: const Icon(Icons.shield_moon_outlined, size: 16),
          label: const Text('Toggle alternative speed limits'),
        ),
        const SizedBox(height: AppSpacing.xl),
        _SectionLabel('Maintenance'),
        const SizedBox(height: AppSpacing.sm),
        OutlinedButton.icon(
          onPressed: () => _recheck(context, ref, torrent),
          icon: const Icon(Icons.refresh_rounded, size: 16),
          label: const Text('Force recheck'),
        ),
        const SizedBox(height: AppSpacing.sm),
        OutlinedButton.icon(
          onPressed: () => _reannounce(context, ref, torrent),
          icon: const Icon(Icons.campaign_rounded, size: 16),
          label: const Text('Reannounce to trackers'),
        ),
      ],
    );
  }

  Future<void> _recheck(BuildContext context, WidgetRef ref, Torrent torrent) {
    return runTorrentAction(
      context,
      ref,
      action: (service) => service.recheck(torrent.hash),
      successMessage: 'Recheck started',
      failureMessage: 'Failed to recheck',
    );
  }

  Future<void> _reannounce(
    BuildContext context,
    WidgetRef ref,
    Torrent torrent,
  ) {
    return runTorrentAction(
      context,
      ref,
      action: (service) => service.reannounce([torrent.hash]),
      successMessage: 'Reannounced to trackers',
      failureMessage: 'Failed to reannounce',
    );
  }

  Future<void> _setLimit(
    BuildContext context,
    WidgetRef ref,
    Torrent torrent, {
    required bool isDownload,
  }) async {
    // qB doesn't expose per-torrent current limits directly; we use 0 as a
    // best-effort starting point (the user can re-type the actual value).
    final result = await showSpeedLimitDialog(
      context,
      title: isDownload ? 'Download limit' : 'Upload limit',
      currentLimitBytes: 0,
    );
    if (result == null) return;
    if (!context.mounted) return;
    final bytes = result.bytesPerSecond!;
    final label = bytes == 0
        ? 'cleared'
        : '${(bytes / 1024).toStringAsFixed(0)} KB/s';
    await runTorrentAction(
      context,
      ref,
      action: (service) => isDownload
          ? service.setDownloadLimit([torrent.hash], bytes)
          : service.setUploadLimit([torrent.hash], bytes),
      successMessage: isDownload
          ? 'Download limit set to $label'
          : 'Upload limit set to $label',
      failureMessage: 'Failed to set limit',
      invalidate: [torrentsProvider, allTorrentsProvider],
    );
  }

  Future<void> _toggleAltSpeed(BuildContext context, WidgetRef ref) {
    return runTorrentAction(
      context,
      ref,
      action: (service) => service.toggleAlternativeSpeedLimits(),
      successMessage: 'Alternative speed limits toggled',
      failureMessage: 'Failed to toggle',
      invalidate: [transferInfoProvider],
    );
  }

  void _confirmDeleteSingle(
    BuildContext context,
    WidgetRef ref,
    Torrent torrent,
  ) {
    showTorrentDeleteDialog(
      context: context,
      title: 'Delete torrent?',
      message: '"${torrent.name}" leaves qBittorrent.',
    ).then((result) async {
      if (!result.confirmed) return;
      if (!context.mounted) return;
      final ok = await runTorrentAction(
        context,
        ref,
        action: (service) => service.deleteTorrents([
          torrent.hash,
        ], deleteFiles: result.deleteFiles),
        successMessage: result.deleteFiles
            ? 'Deleted torrent and files'
            : 'Deleted torrent',
        failureMessage: 'Failed to delete',
        invalidate: [torrentsProvider, allTorrentsProvider],
      );
      if (ok && context.mounted) context.pop();
    });
  }
}
