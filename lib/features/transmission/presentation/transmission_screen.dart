import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderOrFamily;

import 'package:cupola/core/app_animation.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/snack_bar_helper.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/services/presentation/service_kpi_provider.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/transmission/domain/models/transmission_models.dart';
import 'package:cupola/features/transmission/presentation/transmission_actions.dart';
import 'package:cupola/features/transmission/presentation/transmission_provider.dart';
import 'package:cupola/features/transmission/presentation/widgets/transmission_torrent_tile.dart';

/// Transmission dashboard: the live queue, what is seeding, and the controls
/// that act on both.
class TransmissionScreen extends ConsumerWidget {
  const TransmissionScreen({
    super.key,
    this.showAppBar = true,
    this.topPadding = 0,
  });

  final bool showAppBar;
  final double topPadding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(currentSettingsProvider);
    final isConfigured = settings.isServiceConfigured(ServiceKey.transmission);

    return AmbientScaffold(
      accent: AppColors.transmission,
      appBar: showAppBar
          ? const GlassAppBar(title: Text('Transmission'))
          : null,
      body: SafeArea(
        child: isConfigured
            ? _TransmissionDashboard(topPadding: topPadding)
            : NotConfiguredPlaceholder.forService(ServiceKey.transmission),
      ),
    );
  }
}

final _invalidateAfterAction = <ProviderOrFamily>[
  transmissionTorrentsProvider,
  transmissionStatsProvider,
  transmissionSessionProvider,
];

void _invalidateAll(WidgetRef ref) {
  ref.invalidate(transmissionTorrentsProvider);
  ref.invalidate(transmissionStatsProvider);
  ref.invalidate(transmissionSessionProvider);
  ref.invalidate(serviceKpiProvider(ServiceKey.transmission));
  ref.invalidate(serviceSummaryProvider(ServiceKey.transmission));
}

class _TransmissionDashboard extends ConsumerWidget {
  const _TransmissionDashboard({required this.topPadding});

  final double topPadding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final torrentsAsync = ref.watch(transmissionTorrentsProvider);
    final summaryAsync = ref.watch(
      serviceSummaryProvider(ServiceKey.transmission),
    );
    final isOffline = summaryAsync.maybeWhen(
      data: (summary) => !summary.isOnline,
      orElse: () => false,
    );

    if (isOffline) {
      return ServiceOfflineState(
        serviceName: ServiceKey.transmission.title,
        accent: AppColors.transmission,
        onRetry: () => _invalidateAll(ref),
      );
    }

    return RefreshIndicator(
      onRefresh: () async {
        _invalidateAll(ref);
        await Future<void>.delayed(AppAnimation.durationMd);
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.only(
          bottom: FloatingNavBarMetrics.getScrollViewBottomPadding(context),
        ),
        children: [
          if (topPadding > 0) SizedBox(height: topPadding),
          ServiceKpiPeek(
            kpis: ref.watch(serviceKpiProvider(ServiceKey.transmission)),
            accent: AppColors.transmission,
          ),
          const SizedBox(height: AppSpacing.sm),
          const _TransmissionActionsBar(),
          const SizedBox(height: AppSpacing.sm),
          const SectionHeader(title: 'Transferring', showChevron: false),
          const SizedBox(height: 2),
          _TorrentList(
            torrentsAsync: torrentsAsync,
            filter: (t) => t.status.isIncoming,
            emptyLabel: 'Nothing is downloading.',
          ),
          const SizedBox(height: AppSpacing.sm),
          const SectionHeader(title: 'Seeding and idle', showChevron: false),
          const SizedBox(height: 2),
          _TorrentList(
            torrentsAsync: torrentsAsync,
            filter: (t) => !t.status.isIncoming,
            emptyLabel: 'Nothing is seeding.',
            limit: 10,
          ),
        ],
      ),
    );
  }
}

/// Global controls: add a torrent, and the turtle toggle.
///
/// Turtle rather than a "pause all": Transmission has no global pause, and
/// faking one by stopping every torrent would be a lie with a bad recovery —
/// "resume all" could not know which ones the user had stopped deliberately.
/// The alternative speed limit is the real control the daemon offers for
/// "quieten down without losing my state", so that is what is here.
class _TransmissionActionsBar extends ConsumerWidget {
  const _TransmissionActionsBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final turtle =
        ref.watch(transmissionSessionProvider).asData?.value.altSpeedEnabled ??
        false;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => _showAddTorrentDialog(context, ref),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Add torrent'),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: FilledButton.tonalIcon(
              onPressed: () {
                HapticFeedback.selectionClick();
                runTransmissionAction(
                  context,
                  ref,
                  action: (c) => c.setAltSpeedEnabled(!turtle),
                  successMessage: turtle
                      ? 'Speed limits off'
                      : 'Alternative speed limits on',
                  failureMessage: turtle
                      ? 'Failed to turn speed limits off'
                      : 'Failed to turn speed limits on',
                  invalidate: _invalidateAfterAction,
                );
              },
              icon: Icon(
                turtle ? Icons.speed_rounded : Icons.hourglass_bottom_rounded,
                size: 18,
              ),
              label: Text(turtle ? 'Full speed' : 'Slow mode'),
            ),
          ),
        ],
      ),
    );
  }
}

/// Prompts for a magnet link or `.torrent` URL and hands it to the daemon.
Future<void> _showAddTorrentDialog(BuildContext context, WidgetRef ref) async {
  final controller = TextEditingController();
  final submitted = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Add torrent'),
      content: TextField(
        controller: controller,
        autofocus: true,
        keyboardType: TextInputType.url,
        decoration: const InputDecoration(
          labelText: 'Magnet link or .torrent URL',
          hintText: 'magnet:?xt=urn:btih:…',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Add'),
        ),
      ],
    ),
  );

  if (submitted != true) {
    controller.dispose();
    return;
  }
  final value = controller.text.trim();
  controller.dispose();
  if (value.isEmpty || !context.mounted) return;

  // The duplicate case is reported honestly rather than as a success:
  // Transmission answers `result: "success"` with a `torrent-duplicate` key for
  // a torrent it already had, and telling the user it was added would be wrong.
  var wasDuplicate = false;
  await runTransmissionAction(
    context,
    ref,
    action: (c) async {
      final outcome = await c.addTorrent(value);
      wasDuplicate = outcome.isDuplicate;
    },
    successMessage: null,
    failureMessage: 'Failed to add the torrent',
    invalidate: _invalidateAfterAction,
  );
  if (context.mounted) {
    SnackBarHelper.success(
      context,
      wasDuplicate ? 'Already in Transmission' : 'Torrent added',
    );
  }
}

/// Per-torrent overflow menu.
class _TorrentMenu extends ConsumerWidget {
  const _TorrentMenu({required this.torrent});

  final TransmissionTorrent torrent;

  bool get _stopped => torrent.status == TransmissionStatus.stopped;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ids = [torrent.rpcId];
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert_rounded, size: 18),
      tooltip: 'Torrent actions',
      onSelected: (value) {
        switch (value) {
          case 'start':
            runTransmissionAction(
              context,
              ref,
              action: (c) => c.start(ids),
              successMessage: 'Started',
              failureMessage: 'Failed to start the torrent',
              invalidate: _invalidateAfterAction,
            );
          case 'stop':
            runTransmissionAction(
              context,
              ref,
              action: (c) => c.stop(ids),
              successMessage: 'Stopped',
              failureMessage: 'Failed to stop the torrent',
              invalidate: _invalidateAfterAction,
            );
          case 'verify':
            runTransmissionAction(
              context,
              ref,
              action: (c) => c.verify(ids),
              // Deliberately not "Verified": `torrent-verify` returns as soon
              // as the daemon accepts the job, while the re-check itself runs
              // for minutes or hours. Claiming completion here would be false.
              successMessage: 'Verifying — this runs in the background',
              failureMessage: 'Failed to start verification',
              invalidate: _invalidateAfterAction,
            );
          case 'reannounce':
            runTransmissionAction(
              context,
              ref,
              action: (c) => c.reannounce(ids),
              successMessage: 'Asked the trackers for more peers',
              failureMessage: 'Failed to reannounce',
              invalidate: _invalidateAfterAction,
            );
          case 'top':
            runTransmissionAction(
              context,
              ref,
              action: (c) => c.queueMove(ids, TransmissionQueueMove.top),
              successMessage: 'Moved to the top of the queue',
              failureMessage: 'Failed to move the torrent',
              invalidate: _invalidateAfterAction,
            );
          case 'remove':
            _confirmRemove(context, ref, torrent);
        }
      },
      itemBuilder: (context) => [
        if (_stopped)
          const PopupMenuItem(value: 'start', child: Text('Start'))
        else
          const PopupMenuItem(value: 'stop', child: Text('Stop')),
        const PopupMenuItem(value: 'verify', child: Text('Verify local data')),
        const PopupMenuItem(value: 'reannounce', child: Text('Reannounce')),
        const PopupMenuItem(value: 'top', child: Text('Move to top')),
        const PopupMenuItem(value: 'remove', child: Text('Remove…')),
      ],
    );
  }
}

/// Confirms a removal, with deleting the downloaded files as a separate,
/// off-by-default choice.
///
/// Two decisions, not one. Removing a torrent from the daemon is recoverable —
/// re-add it and it re-checks. Deleting its data is not: Transmission unlinks
/// the files and nothing goes to a trash. Folding them into a single "Delete"
/// button is how people lose a library, so the destructive half is a checkbox
/// the user has to reach for, and the dialog escalates to its danger styling
/// only once they do.
Future<void> _confirmRemove(
  BuildContext context,
  WidgetRef ref,
  TransmissionTorrent torrent,
) async {
  final result = await showAppConfirmDialog(
    context: context,
    icon: Icons.delete_outline_rounded,
    title: 'Remove ${torrent.name}?',
    message:
        'It stops downloading and leaves the list. The files it has already '
        'written stay on disk unless you also tick the box below.',
    confirmLabel: 'Remove',
    destructive: true,
    dangerNote: 'Deleting the downloaded files cannot be undone.',
    options: const [
      AppConfirmOption(
        key: 'deleteData',
        label: 'Also delete the downloaded files',
        subtitle: 'Removes the data from the Transmission host permanently.',
        danger: true,
      ),
    ],
  );

  if (!result.confirmed || !context.mounted) return;

  final deleteData = result.option('deleteData');
  await runTransmissionAction(
    context,
    ref,
    action: (c) =>
        c.removeTorrents([torrent.rpcId], deleteLocalData: deleteData),
    successMessage: deleteData ? 'Removed and files deleted' : 'Removed',
    failureMessage: 'Failed to remove the torrent',
    invalidate: _invalidateAfterAction,
  );
}

class _TorrentList extends ConsumerWidget {
  const _TorrentList({
    required this.torrentsAsync,
    required this.filter,
    required this.emptyLabel,
    this.limit = 5,
  });

  final AsyncValue<List<TransmissionTorrent>> torrentsAsync;
  final bool Function(TransmissionTorrent torrent) filter;
  final String emptyLabel;
  final int limit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return torrentsAsync.when(
      data: (torrents) {
        final matching = torrents.where(filter).toList(growable: false);
        if (matching.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.md,
            ),
            child: Text(emptyLabel),
          );
        }
        return Column(
          children: matching
              .take(limit)
              .map(
                (torrent) => TransmissionTorrentTile(
                  torrent: torrent,
                  // The menu is built here rather than inside the tile: it
                  // dispatches through this screen's `ref`, and a plate that
                  // reached for a provider would stop being a plate.
                  actions: _TorrentMenu(torrent: torrent),
                ),
              )
              .toList(),
        );
      },
      loading: () => const ListRowsShimmer(),
      error: (error, _) => InlineErrorRetry(
        message: 'Failed to load torrents',
        onRetry: () => ref.invalidate(transmissionTorrentsProvider),
      ),
    );
  }
}
