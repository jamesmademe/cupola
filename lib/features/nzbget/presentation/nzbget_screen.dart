import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderOrFamily;

import 'package:cupola/core/app_animation.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/nzbget/domain/models/nzbget_models.dart';
import 'package:cupola/features/nzbget/presentation/nzbget_actions.dart';
import 'package:cupola/features/nzbget/presentation/nzbget_provider.dart';
import 'package:cupola/features/services/presentation/service_kpi_provider.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// NZBGet's Queue tab: every group in the download queue, with the controls
/// that act on it.
///
/// History is not drawn here, for the reason the SABnzbd Queue tab states: it
/// has its own tab and an Overview preview, and the ten-row block this page
/// used to end with was a third, shorter copy of it, capped without saying so.
class NzbgetScreen extends ConsumerWidget {
  const NzbgetScreen({super.key, this.showAppBar = true, this.topPadding = 0});

  final bool showAppBar;
  final double topPadding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(currentSettingsProvider);
    final isConfigured = settings.isServiceConfigured(ServiceKey.nzbget);

    return AmbientScaffold(
      accent: AppColors.nzbget,
      appBar: showAppBar ? const GlassAppBar(title: Text('NZBGet')) : null,
      body: SafeArea(
        // The shared placeholder, not a private copy — see the note on the
        // SABnzbd dashboard, which had grown the same widget independently.
        child: isConfigured
            ? _NzbgetDashboard(topPadding: topPadding)
            : NotConfiguredPlaceholder.forService(ServiceKey.nzbget),
      ),
    );
  }
}

class _NzbgetDashboard extends ConsumerWidget {
  const _NzbgetDashboard({required this.topPadding});

  final double topPadding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queueAsync = ref.watch(nzbgetQueueProvider);
    final summaryAsync = ref.watch(serviceSummaryProvider(ServiceKey.nzbget));
    final isOffline = summaryAsync.maybeWhen(
      data: (summary) => !summary.isOnline,
      orElse: () => false,
    );

    if (isOffline) {
      return ServiceOfflineState(
        serviceName: ServiceKey.nzbget.title,
        accent: AppColors.nzbget,
        onRetry: () => _invalidateAll(ref),
      );
    }

    // Through the same `when` the rows draw with, so the header never counts
    // a queue its section is not showing.
    final groups = queueAsync.whenOrNull(data: (groups) => groups);

    return RefreshIndicator(
      onRefresh: () async {
        _invalidateAll(ref);
        await Future<void>.delayed(AppAnimation.durationMd);
      },
      // The whole queue, built lazily. This tab used to draw the first five
      // groups with no count and no way to reach the rest. `listgroups` returns
      // every group, so every group is a row, the header says how many there
      // are, and only the rows on screen are built.
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverList.list(
            children: [
              if (topPadding > 0) SizedBox(height: topPadding),
              ServiceKpiPeek(
                kpis: ref.watch(serviceKpiProvider(ServiceKey.nzbget)),
                accent: AppColors.nzbget,
              ),
              const SizedBox(height: AppSpacing.sm),
              const _NzbgetActionsBar(),
              const SizedBox(height: AppSpacing.sm),
              SectionHeader(
                title: 'Downloading',
                subtitle: nzbgetQueueCountLabel(groups?.length),
                showChevron: false,
              ),
              const SizedBox(height: 2),
            ],
          ),
          _queueRows(ref, queueAsync),
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

/// The count the Queue header states, or null while there is nothing to count.
///
/// Null rather than `0 jobs` during a load or after a failure: a figure whose
/// source did not answer is not a zero.
String? nzbgetQueueCountLabel(int? count) {
  if (count == null) return null;
  return count == 1 ? '1 job' : '$count jobs';
}

/// The queue's rows, as a sliver: every group, lazily built.
Widget _queueRows(WidgetRef ref, AsyncValue<List<NzbgetGroup>> queueAsync) {
  return queueAsync.when(
    data: (groups) {
      if (groups.isEmpty) {
        return const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.md,
            ),
            child: Text('Queue is empty.'),
          ),
        );
      }
      return SliverList.builder(
        itemCount: groups.length,
        itemBuilder: (context, index) => _QueueTile(group: groups[index]),
      );
    },
    loading: () => const SliverToBoxAdapter(child: ListRowsShimmer()),
    error: (error, _) => SliverToBoxAdapter(
      child: InlineErrorRetry(
        message: 'Failed to load the queue',
        onRetry: () => ref.invalidate(nzbgetQueueProvider),
      ),
    ),
  );
}

/// Providers refreshed after any NZBGet mutation.
final _nzbgetInvalidateAfterAction = <ProviderOrFamily>[
  nzbgetStatusProvider,
  nzbgetQueueProvider,
  nzbgetHistoryProvider,
];

/// Global controls: add an NZB by URL and pause/resume the whole queue.
void _invalidateAll(WidgetRef ref) {
  ref.invalidate(nzbgetStatusProvider);
  ref.invalidate(nzbgetQueueProvider);
  ref.invalidate(nzbgetHistoryProvider);
  ref.invalidate(serviceKpiProvider(ServiceKey.nzbget));
  ref.invalidate(serviceSummaryProvider(ServiceKey.nzbget));
}

class _NzbgetActionsBar extends ConsumerWidget {
  const _NzbgetActionsBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Null until the first status load lands. Defaulting that to `false` meant
    // an already-paused client rendered "Pause all" for the duration of the
    // first fetch, and a tap in that window sent `pausedownload()` to something
    // that was already paused. The toggle is inert until its state is known.
    final paused = ref.watch(nzbgetStatusProvider).value?.paused;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => _showAddNzbDialog(context, ref),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Add NZB'),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: FilledButton.tonalIcon(
              onPressed: paused == null
                  ? null
                  : () {
                      HapticFeedback.selectionClick();
                      runNzbgetAction(
                        context,
                        ref,
                        action: (c) =>
                            paused ? c.resumeDownload() : c.pauseDownload(),
                        successMessage: paused
                            ? 'Downloads resumed'
                            : 'Downloads paused',
                        failureMessage: paused
                            ? 'Failed to resume downloads'
                            : 'Failed to pause downloads',
                        invalidate: _nzbgetInvalidateAfterAction,
                      );
                    },
              icon: Icon(
                paused ?? false
                    ? Icons.play_arrow_rounded
                    : Icons.pause_rounded,
                size: 18,
              ),
              label: Text(paused ?? false ? 'Resume all' : 'Pause all'),
            ),
          ),
        ],
      ),
    );
  }
}

/// Prompts for an NZB URL and enqueues it via `append`.
Future<void> _showAddNzbDialog(BuildContext context, WidgetRef ref) async {
  final urlController = TextEditingController();
  final submitted = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Add NZB by URL'),
      content: TextField(
        controller: urlController,
        autofocus: true,
        keyboardType: TextInputType.url,
        decoration: const InputDecoration(
          labelText: 'NZB URL',
          hintText: 'https://…/download.nzb',
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
    urlController.dispose();
    return;
  }
  final url = urlController.text.trim();
  urlController.dispose();
  if (url.isEmpty || !context.mounted) return;

  // NZBGet fetches the URL server-side; the filename is only a display label.
  final name = url.split('/').last.split('?').first;
  await runNzbgetAction(
    context,
    ref,
    action: (c) => c.append(name.isEmpty ? 'cupola.nzb' : name, url),
    successMessage: 'NZB added',
    failureMessage: 'Failed to add the NZB',
    invalidate: _nzbgetInvalidateAfterAction,
  );
}

class _QueueTile extends ConsumerWidget {
  const _QueueTile({required this.group});

  final NzbgetGroup group;

  bool get _paused => group.status.toUpperCase().contains('PAUSED');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DownloadQueueTile(
      title: group.name,
      subtitle: <String>[
        if (group.status.isNotEmpty) group.status,
        if (group.category.isNotEmpty) group.category,
        // "progress unknown" rather than "— left": the em dash alone reads as
        // a missing size, and what is actually missing is the whole
        // measurement. It is also the line that contradicts the `0%` below.
        if (group.percentage == null)
          'progress unknown'
        else
          group.remainingLabel,
      ].join(' · '),
      // Null when NZBGet reported no size or no remaining size, so the bar is
      // simply not drawn — which is the fix: the old `0` default computed a
      // full bar for a job nobody measured.
      progress: group.progress,
      // Preserve the distinction between a real zero and a percentage NZBGet
      // could not compute. The shared plate renders the latter as an em dash.
      percentage: group.percentage,
      accent: AppColors.nzbget,
      actions: DownloadQueueActionsMenu(
        paused: _paused,
        onCommand: (command) => _run(context, ref, command),
      ),
    );
  }

  void _run(BuildContext context, WidgetRef ref, DownloadQueueCommand command) {
    switch (command) {
      case DownloadQueueCommand.pause:
        runNzbgetAction(
          context,
          ref,
          action: (c) => c.pauseGroup(group.nzbId),
          successMessage: 'Job paused',
          failureMessage: 'Failed to pause the job',
          invalidate: _nzbgetInvalidateAfterAction,
        );
      case DownloadQueueCommand.resume:
        runNzbgetAction(
          context,
          ref,
          action: (c) => c.resumeGroup(group.nzbId),
          successMessage: 'Job resumed',
          failureMessage: 'Failed to resume the job',
          invalidate: _nzbgetInvalidateAfterAction,
        );
      case DownloadQueueCommand.delete:
        _confirmDelete(context, ref);
    }
  }

  /// Asks before a job leaves the queue.
  ///
  /// It used to go on the tap. No "also delete files" choice, unlike SABnzbd:
  /// `GroupDelete` is documented only as "delete groups and put to history",
  /// and whether it clears what was already downloaded depends on the
  /// server's own settings and version — a checkbox here would be a promise
  /// this app cannot check. The sentence says only what the API does say.
  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final result = await showAppConfirmDialog(
      context: context,
      icon: Icons.delete_outline_rounded,
      title: 'Delete this job?',
      message:
          '${group.name} leaves the NZBGet queue and stops downloading. '
          'NZBGet moves it to its history.',
      confirmLabel: 'Delete job',
    );
    if (!result.confirmed || !context.mounted) return;

    await runNzbgetAction(
      context,
      ref,
      action: (c) => c.deleteGroup(group.nzbId),
      successMessage: 'Job removed',
      failureMessage: 'Failed to remove the job',
      invalidate: _nzbgetInvalidateAfterAction,
    );
  }
}
