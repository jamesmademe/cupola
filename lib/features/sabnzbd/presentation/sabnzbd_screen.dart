import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderOrFamily;

import 'package:cupola/core/app_animation.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/sabnzbd/domain/models/sabnzbd_models.dart';
import 'package:cupola/features/sabnzbd/presentation/sabnzbd_actions.dart';
import 'package:cupola/features/sabnzbd/presentation/sabnzbd_provider.dart';
import 'package:cupola/features/services/presentation/service_kpi_provider.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/connection_presentation.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// SABnzbd's Queue tab: the whole download queue, with the controls that act
/// on it.
///
/// History is not drawn here. It has its own tab, and the Overview previews it
/// with a link there; the ten-row block this page used to end with was a third,
/// shorter copy of the same list, capped without saying so.
class SabnzbdScreen extends ConsumerWidget {
  const SabnzbdScreen({super.key, this.showAppBar = true, this.topPadding = 0});

  final bool showAppBar;
  final double topPadding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(currentSettingsProvider);
    final isConfigured = settings.isServiceConfigured(ServiceKey.sabnzbd);

    return AmbientScaffold(
      accent: ServiceKey.sabnzbd.accent,
      appBar: showAppBar ? const GlassAppBar(title: Text('SABnzbd')) : null,
      body: SafeArea(
        // The shared placeholder, not a private copy. Four dashboards had grown
        // their own version of "this service isn't set up" — same shape, four
        // different icons, paddings and sentences — while
        // `NotConfiguredPlaceholder` exists precisely to unify that state.
        child: isConfigured
            ? _SabnzbdDashboard(topPadding: topPadding)
            : NotConfiguredPlaceholder.forService(ServiceKey.sabnzbd),
      ),
    );
  }
}

class _SabnzbdDashboard extends ConsumerWidget {
  const _SabnzbdDashboard({required this.topPadding});

  final double topPadding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queueAsync = ref.watch(sabnzbdQueueProvider);
    final summaryAsync = ref.watch(serviceSummaryProvider(ServiceKey.sabnzbd));
    // A failed probe, in its own words: "did not answer" only when nothing did,
    // the refusal and its remedy when the key was refused.
    final failed = summaryAsync.whenOrNull(
      data: (summary) => summary.isOnline ? null : summary,
    );

    if (failed != null) {
      return ServiceOfflineState.fromSummary(
        summary: failed,
        onRetry: () => _invalidateAll(ref),
      );
    }

    // Through the same `when` the rows draw with, so the header never counts
    // a queue its section is not showing.
    final queue = queueAsync.whenOrNull(data: (queue) => queue);

    return RefreshIndicator(
      onRefresh: () async {
        _invalidateAll(ref);
        await Future<void>.delayed(AppAnimation.durationMd);
      },
      // The whole queue, built lazily. This tab used to draw the first five
      // jobs with no count and no way to reach the rest, so a queue of eight
      // read as a queue of five. Every slot `mode=queue` returned is a row
      // here, the header states how many jobs there are, and only the rows on
      // screen are built.
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverList.list(
            children: [
              if (topPadding > 0) SizedBox(height: topPadding),
              ServiceKpiPeek(
                kpis: ref.watch(serviceKpiProvider(ServiceKey.sabnzbd)),
                accent: ServiceKey.sabnzbd.accent,
              ),
              const SizedBox(height: AppSpacing.sm),
              _SabnzbdActionsBar(queueAsync: queueAsync),
              const SizedBox(height: AppSpacing.sm),
              SectionHeader(
                title: 'Downloading',
                subtitle: sabnzbdQueueCountLabel(queue),
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
/// source did not answer is not a zero. The number is [SabnzbdQueue.jobCount] —
/// the server's own `noofslots_total` — never the length of the page in hand,
/// and should the server ever report more jobs than it sent, the header says
/// how many of them are drawn instead of passing the page off as the queue.
String? sabnzbdQueueCountLabel(SabnzbdQueue? queue) {
  if (queue == null) return null;
  final total = queue.jobCount;
  final noun = total == 1 ? 'job' : 'jobs';
  final shown = queue.slots.length;
  if (shown < total) return '$shown of $total $noun shown';
  return '$total $noun';
}

/// The queue's rows, as a sliver: every slot, lazily built.
Widget _queueRows(WidgetRef ref, AsyncValue<SabnzbdQueue> queueAsync) {
  return queueAsync.when(
    data: (queue) {
      if (queue.slots.isEmpty) {
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
        itemCount: queue.slots.length,
        itemBuilder: (context, index) => _QueueTile(slot: queue.slots[index]),
      );
    },
    loading: () => const SliverToBoxAdapter(child: ListRowsShimmer()),
    error: (error, _) => SliverToBoxAdapter(
      child: InlineErrorRetry(
        message: sectionFailureMessage(
          ServiceKey.sabnzbd,
          error,
          consequence: 'the queue is not shown',
        ),
        error: error,
        onRetry: () => ref.invalidate(sabnzbdQueueProvider),
      ),
    ),
  );
}

/// Providers refreshed after any SABnzbd mutation.
final _sabnzbdInvalidateAfterAction = <ProviderOrFamily>[
  sabnzbdQueueProvider,
  sabnzbdHistoryProvider,
];

/// Global controls: add an NZB by URL and pause/resume the whole queue.
void _invalidateAll(WidgetRef ref) {
  ref.invalidate(sabnzbdQueueProvider);
  ref.invalidate(sabnzbdHistoryProvider);
  ref.invalidate(serviceKpiProvider(ServiceKey.sabnzbd));
  ref.invalidate(serviceSummaryProvider(ServiceKey.sabnzbd));
}

class _SabnzbdActionsBar extends ConsumerWidget {
  const _SabnzbdActionsBar({required this.queueAsync});

  final AsyncValue<SabnzbdQueue> queueAsync;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Null until the first queue load lands. Defaulting that to `false` meant
    // an already-paused queue rendered "Pause all" for the duration of the
    // first fetch, and a tap in that window sent `pause()` to a queue that was
    // already paused. The toggle is inert until its own state is known.
    final paused = queueAsync.value?.paused;
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
                      runSabnzbdAction(
                        context,
                        ref,
                        action: (c) => paused ? c.resume() : c.pause(),
                        successMessage: paused
                            ? 'Queue resumed'
                            : 'Queue stopped',
                        failureMessage: paused
                            ? 'Failed to resume the queue'
                            : 'Failed to pause the queue',
                        invalidate: _sabnzbdInvalidateAfterAction,
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

/// Prompts for an NZB URL (and optional category) and enqueues it.
Future<void> _showAddNzbDialog(BuildContext context, WidgetRef ref) async {
  final result = await showDialog<_AddNzbRequest>(
    context: context,
    builder: (context) => const _AddNzbDialog(),
  );

  if (result == null || !context.mounted) return;

  await runSabnzbdAction(
    context,
    ref,
    action: (c) => c.addUrl(result.url, category: result.category),
    successMessage: 'NZB added',
    failureMessage: 'Failed to add the NZB',
    invalidate: _sabnzbdInvalidateAfterAction,
  );
}

/// What the add dialog hands back once the user commits.
class _AddNzbRequest {
  const _AddNzbRequest({required this.url, this.category});

  final String url;
  final String? category;
}

/// The add-NZB form.
///
/// A `ConsumerStatefulWidget` that **watches** the categories rather than
/// reading them once. `ref.read(sabnzbdCategoriesProvider).asData?.value` was
/// the previous shape, and nothing else in the app watches that provider — so
/// on first open it was cold, the read returned `AsyncLoading` with no value,
/// the dropdown was hidden entirely and the NZB went in with no category at
/// all. The captured local was never re-read either, so the dropdown stayed
/// hidden even after the fetch landed while the dialog was still open.
class _AddNzbDialog extends ConsumerStatefulWidget {
  const _AddNzbDialog();

  @override
  ConsumerState<_AddNzbDialog> createState() => _AddNzbDialogState();
}

class _AddNzbDialogState extends ConsumerState<_AddNzbDialog> {
  final _urlController = TextEditingController();
  String? _category;

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  void _submit() {
    final url = _urlController.text.trim();
    if (url.isEmpty) return;
    Navigator.of(context).pop(_AddNzbRequest(url: url, category: _category));
  }

  @override
  Widget build(BuildContext context) {
    final categoriesAsync = ref.watch(sabnzbdCategoriesProvider);

    return AlertDialog(
      title: const Text('Add NZB by URL'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _urlController,
            autofocus: true,
            keyboardType: TextInputType.url,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
            decoration: const InputDecoration(
              labelText: 'NZB URL',
              hintText: 'https://…/download.nzb',
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          categoriesAsync.when(
            data: (categories) => categories.isEmpty
                ? const SizedBox.shrink()
                : DropdownButtonFormField<String>(
                    initialValue: _category,
                    decoration: const InputDecoration(labelText: 'Category'),
                    items: categories
                        .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                        .toList(),
                    onChanged: (v) => setState(() => _category = v),
                  ),
            // Plain text rather than a spinner: it says the same thing, and an
            // indeterminate indicator inside a dialog is a frame the eye has to
            // keep discarding.
            loading: () => const Align(
              alignment: Alignment.centerLeft,
              child: Text('Loading categories…'),
            ),
            // A category is optional; SABnzbd applies its default. Failing to
            // list them is not a reason to block adding the NZB.
            error: (_, _) => const SizedBox.shrink(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Add')),
      ],
    );
  }
}

class _QueueTile extends ConsumerWidget {
  const _QueueTile({required this.slot});

  final SabnzbdQueueSlot slot;

  bool get _paused => slot.status.toLowerCase() == 'paused';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DownloadQueueTile(
      title: slot.filename,
      // `1.2 GB left of 3.4 GB`, not the bare remainder this row used to
      // print. Remaining alone reads identically at 30% and at 95%, which is
      // the one thing a queue row is looked at to tell apart — and the bare
      // figure did not even say it was a remainder. The clause is dropped
      // whole when the slot carried no total; see
      // `SabnzbdQueueSlot.sizeProgressLabel`.
      subtitle: <String>[
        if (slot.status.isNotEmpty) slot.status,
        if (slot.timeLeft.isNotEmpty) slot.timeLeft,
        slot.sizeProgressLabel,
      ].join(' · '),
      progress: slot.progress,
      percentage: slot.percentage,
      accent: ServiceKey.sabnzbd.accent,
      actions: DownloadQueueActionsMenu(
        paused: _paused,
        onCommand: (command) => _run(context, ref, command),
      ),
    );
  }

  void _run(BuildContext context, WidgetRef ref, DownloadQueueCommand command) {
    switch (command) {
      case DownloadQueueCommand.pause:
        runSabnzbdAction(
          context,
          ref,
          action: (c) => c.pauseJob(slot.nzoId),
          successMessage: 'Job stopped',
          failureMessage: 'Failed to pause the job',
          invalidate: _sabnzbdInvalidateAfterAction,
        );
      case DownloadQueueCommand.resume:
        runSabnzbdAction(
          context,
          ref,
          action: (c) => c.resumeJob(slot.nzoId),
          successMessage: 'Job resumed',
          failureMessage: 'Failed to resume the job',
          invalidate: _sabnzbdInvalidateAfterAction,
        );
      case DownloadQueueCommand.delete:
        _confirmDelete(context, ref);
    }
  }

  /// Asks before a job leaves the queue.
  ///
  /// It used to go on the tap, toast "Job removed", and that was the only
  /// word about it — on a menu row one slip of the finger from Pause. The
  /// files question is SABnzbd's own: it keeps what it downloaded unless told
  /// otherwise, so the box starts unticked, and ticking it is the one way here
  /// to lose them.
  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final result = await showAppConfirmDialog(
      context: context,
      icon: Icons.delete_outline_rounded,
      title: 'Delete this job?',
      message:
          '${slot.filename} leaves the SABnzbd queue and stops downloading.',
      confirmLabel: 'Delete job',
      confirmLabelFor: (checked) =>
          checked(_deleteFilesOption) ? 'Delete job and files' : 'Delete job',
      options: const [
        AppConfirmOption(
          key: _deleteFilesOption,
          label: 'Also delete downloaded files',
          subtitle:
              'What SABnzbd already fetched for this job. This cannot be '
              'undone.',
        ),
      ],
    );
    if (!result.confirmed || !context.mounted) return;
    final deleteFiles = result.option(_deleteFilesOption);

    await runSabnzbdAction(
      context,
      ref,
      action: (c) => c.deleteJob(slot.nzoId, deleteFiles: deleteFiles),
      successMessage: deleteFiles ? 'Job and its files deleted' : 'Job removed',
      failureMessage: 'Failed to remove the job',
      invalidate: _sabnzbdInvalidateAfterAction,
    );
  }
}

const _deleteFilesOption = 'deleteFiles';
