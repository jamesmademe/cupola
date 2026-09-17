import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderOrFamily;

import 'package:cupola/core/app_animation.dart';
import 'package:cupola/core/app_radius.dart';
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

/// NZBGet dashboard: live queue and recent history. Read-only for the first
/// release.
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
    final historyAsync = ref.watch(nzbgetHistoryProvider);
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
            kpis: ref.watch(serviceKpiProvider(ServiceKey.nzbget)),
            accent: AppColors.nzbget,
          ),
          const SizedBox(height: AppSpacing.sm),
          const _NzbgetActionsBar(),
          const SizedBox(height: AppSpacing.sm),
          const SectionHeader(title: 'Downloading', showChevron: false),
          const SizedBox(height: 2),
          _QueueList(queueAsync: queueAsync),
          const SizedBox(height: AppSpacing.sm),
          const SectionHeader(title: 'History', showChevron: false),
          const SizedBox(height: 2),
          _HistoryList(historyAsync: historyAsync),
        ],
      ),
    );
  }
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

class _QueueList extends ConsumerWidget {
  const _QueueList({required this.queueAsync});

  final AsyncValue<List<NzbgetGroup>> queueAsync;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return queueAsync.when(
      data: (groups) {
        if (groups.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.md,
            ),
            child: Text('Queue is empty.'),
          );
        }
        return Column(
          children: groups
              .take(5)
              .map((group) => _QueueTile(group: group))
              .toList(),
        );
      },
      loading: () => const ListRowsShimmer(),
      error: (error, _) => InlineErrorRetry(
        message: 'Failed to load the queue',
        onRetry: () => ref.invalidate(nzbgetQueueProvider),
      ),
    );
  }
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
      // `DownloadQueueTile.percentage` is a non-nullable `int` and always
      // prints, so an unmeasurable job still renders `0%` here. `0%` is at
      // least not a claim that the job finished, and the subtitle says the
      // progress is unknown — but the plate wants a nullable percentage, the
      // way it already has a nullable `progress`.
      percentage: group.percentage ?? 0,
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
        runNzbgetAction(
          context,
          ref,
          action: (c) => c.deleteGroup(group.nzbId),
          successMessage: 'Job removed',
          failureMessage: 'Failed to remove the job',
          invalidate: _nzbgetInvalidateAfterAction,
        );
    }
  }
}

class _HistoryList extends ConsumerWidget {
  const _HistoryList({required this.historyAsync});

  final AsyncValue<List<NzbgetHistoryItem>> historyAsync;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return historyAsync.when(
      data: (items) {
        if (items.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.md,
            ),
            child: Text('No history yet.'),
          );
        }
        return Column(
          children: items
              .take(10)
              .map((item) => _HistoryTile(item: item))
              .toList(),
        );
      },
      loading: () => const ListRowsShimmer(),
      error: (error, _) => InlineErrorRetry(
        message: 'Failed to load history',
        onRetry: () => ref.invalidate(nzbgetHistoryProvider),
      ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({required this.item});

  final NzbgetHistoryItem item;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    // The service answered and told us the job failed: that is a fault, which
    // is amber. Red is kept for a service that did not answer at all.
    final color = statusToneColor(
      colorScheme,
      item.failed ? StatusTone.warning : StatusTone.success,
    );
    final icon = item.failed
        ? Icons.error_outline_rounded
        : Icons.check_circle_rounded;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.xs,
      ),
      child: Material(
        color: colorScheme.surface,
        borderRadius: AppRadius.borderRadiusMd,
        child: Container(
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(
            border: Border.all(color: colorScheme.outlineVariant),
            borderRadius: AppRadius.borderRadiusMd,
          ),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: AppRadius.borderRadiusSm,
                ),
                alignment: Alignment.center,
                child: Icon(icon, size: 16, color: color),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      style: Theme.of(
                        context,
                      ).textTheme.bodyMedium!.weight(FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      [
                        if (item.category.isNotEmpty) item.category,
                        item.status,
                      ].join(' · '),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
