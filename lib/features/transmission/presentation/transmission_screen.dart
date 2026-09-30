import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderOrFamily;

import 'package:cupola/core/app_animation.dart';
import 'package:cupola/core/app_spacing.dart';
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
      accent: ServiceKey.transmission.accent,
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
    // A failed probe, in its own words: "did not answer" only when nothing did,
    // the refusal and its remedy when the sign-in was refused.
    final failed = summaryAsync.whenOrNull(
      data: (summary) => summary.isOnline ? null : summary,
    );

    if (failed != null) {
      return ServiceOfflineState.fromSummary(
        summary: failed,
        onRetry: () => _invalidateAll(ref),
      );
    }

    // Split once, through the same `when` the rows draw with, so a header never
    // counts a list its section is not showing: while the list loads or after
    // it failed, both are null and the headers carry no figure at all.
    final torrents = torrentsAsync.whenOrNull(data: (all) => all);
    final incoming = torrents
        ?.where((t) => t.status.isIncoming)
        .toList(growable: false);
    final resting = torrents
        ?.where((t) => !t.status.isIncoming)
        .toList(growable: false);

    return RefreshIndicator(
      onRefresh: () async {
        _invalidateAll(ref);
        await Future<void>.delayed(AppAnimation.durationMd);
      },
      // The whole list, built lazily. This tab used to draw the first five
      // transfers and the first ten seeds with no count and no way to reach
      // the rest, so a daemon with eight downloads read as one with five. The
      // Queue tab *is* the queue: every torrent `torrent-get` returned is a
      // row here, each header states how many there are, and only the rows on
      // screen are built — a seedbox's two thousand seeds included.
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverList.list(
            children: [
              if (topPadding > 0) SizedBox(height: topPadding),
              ServiceKpiPeek(
                kpis: ref.watch(serviceKpiProvider(ServiceKey.transmission)),
                accent: ServiceKey.transmission.accent,
              ),
              const SizedBox(height: AppSpacing.sm),
              const _TransmissionActionsBar(),
              const SizedBox(height: AppSpacing.sm),
              SectionHeader(
                title: 'Transferring',
                subtitle: transmissionTorrentCountLabel(incoming?.length),
                showChevron: false,
              ),
              const SizedBox(height: 2),
            ],
          ),
          _torrentRows(
            ref,
            torrentsAsync: torrentsAsync,
            rows: incoming,
            emptyLabel: 'Nothing is downloading.',
          ),
          SliverList.list(
            children: [
              const SizedBox(height: AppSpacing.sm),
              SectionHeader(
                title: 'Seeding and idle',
                subtitle: transmissionTorrentCountLabel(resting?.length),
                showChevron: false,
              ),
              const SizedBox(height: 2),
            ],
          ),
          _torrentRows(
            ref,
            torrentsAsync: torrentsAsync,
            rows: resting,
            emptyLabel: 'Nothing is seeding.',
          ),
          SliverToBoxAdapter(
            child: SizedBox(
              height: FloatingNavBarMetrics.getScrollViewBottomPadding(context),
            ),
          ),
        ],
      ),
    );
  }
}

/// The count a Queue section header states, or null while there is nothing to
/// count.
///
/// Null rather than `0 torrents` during a load or after a failure: a figure
/// whose source did not answer is not a zero, and the header goes without a
/// count until the daemon has said how many there are. Public so the rule is
/// testable without a widget tree.
String? transmissionTorrentCountLabel(int? count) {
  if (count == null) return null;
  return count == 1 ? '1 torrent' : '$count torrents';
}

/// One section's rows, as a sliver.
///
/// [rows] is the section's slice of the loaded list — null exactly when
/// [torrentsAsync] is not in its data branch. The loading and failure states
/// are drawn once per section, as before; only the data state changed, from
/// the first N rows in a `Column` to every row in a lazily built list.
Widget _torrentRows(
  WidgetRef ref, {
  required AsyncValue<List<TransmissionTorrent>> torrentsAsync,
  required List<TransmissionTorrent>? rows,
  required String emptyLabel,
}) {
  return torrentsAsync.when(
    data: (_) {
      final visible = rows ?? const <TransmissionTorrent>[];
      if (visible.isEmpty) {
        return SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.md,
            ),
            child: Text(emptyLabel),
          ),
        );
      }
      return SliverList.builder(
        itemCount: visible.length,
        itemBuilder: (context, index) {
          final torrent = visible[index];
          return TransmissionTorrentTile(
            torrent: torrent,
            // The menu is built here rather than inside the tile: it
            // dispatches through this screen's `ref`, and a plate that
            // reached for a provider would stop being a plate.
            actions: _TorrentMenu(torrent: torrent),
          );
        },
      );
    },
    loading: () => const SliverToBoxAdapter(child: ListRowsShimmer()),
    error: (error, _) => SliverToBoxAdapter(
      child: InlineErrorRetry(
        message: 'Failed to load torrents',
        onRetry: () => ref.invalidate(transmissionTorrentsProvider),
      ),
    ),
  );
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
  final value = (await showDialog<String>(
    context: context,
    builder: (context) => const _AddTorrentDialog(),
  ))?.trim();
  if (value == null || value.isEmpty || !context.mounted) return;

  // Not [runTransmissionAction]: its yes/no cannot say "already there" or
  // "may have been added", and this flow used to print "Torrent added" after
  // the failure toast whatever the daemon said.
  await runTransmissionAdd(
    context,
    ref,
    value,
    invalidate: _invalidateAfterAction,
  );
}

/// The link field of the add flow. Pops with the text on Add, null on Cancel.
///
/// A widget of its own so the field's controller lives exactly as long as the
/// field. It used to be disposed the moment `showDialog` returned — which is
/// when the route *starts* its exit animation, with the field still on screen
/// and still listening to it.
class _AddTorrentDialog extends StatefulWidget {
  const _AddTorrentDialog();

  @override
  State<_AddTorrentDialog> createState() => _AddTorrentDialogState();
}

class _AddTorrentDialogState extends State<_AddTorrentDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add torrent'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        keyboardType: TextInputType.url,
        decoration: const InputDecoration(
          labelText: 'Magnet link or .torrent URL',
          hintText: 'magnet:?xt=urn:btih:…',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: const Text('Add'),
        ),
      ],
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
              successMessage: 'Verifying, this runs in the background',
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
/// the user has to reach for — and once they do, the button's own words change
/// to *Remove and delete files*. Nothing turns red: red means unreachable and
/// nothing else.
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
    confirmLabel: 'Remove torrent',
    confirmLabelFor: (checked) =>
        checked('deleteData') ? 'Remove and delete files' : 'Remove torrent',
    options: const [
      AppConfirmOption(
        key: 'deleteData',
        label: 'Also delete the downloaded files',
        subtitle:
            'Removes the data from the Transmission host. This cannot be '
            'undone.',
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
