import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/lifecycle/gated_poll.dart';
import 'package:cupola/core/lifecycle/page_activity.dart';
import 'package:cupola/features/release_search/domain/release_search_job.dart';
import 'package:cupola/features/release_search/presentation/release_search_jobs_provider.dart';
import 'package:cupola/features/release_search/presentation/release_search_sheet.dart';
import 'package:cupola/features/release_search/presentation/widgets/release_search_job_card.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';

/// Keeps the windows honest while the section is on screen.
///
/// No network of its own — it re-evaluates in-memory grab windows — but it can
/// start a queued search as a consequence, which is reason enough to hold it to
/// the same rule as everything else: a section nobody is looking at does not get
/// to begin an indexer search.
final releaseSearchTickProvider = Provider.autoDispose<void>((ref) {
  ref.gatedPoll(
    id: 'releaseSearch.windows',
    interval: const Duration(seconds: 10),
    onTick: () => ref.read(releaseSearchJobsProvider.notifier).refreshWindows(),
  );
});

/// The searches still running, and the finished ones whose releases can
/// still be picked: the group at the head of Activity's Downloads, drawn
/// only while there is one.
///
/// Holds the notification's half of the handoff too: a tapped "pick one"
/// opens its sheet here, so the group is built (empty or not) wherever the
/// notification lands.
class ReleaseSearchesGroup extends ConsumerWidget {
  const ReleaseSearchesGroup({super.key, this.heading});

  /// What stands above the cards while there are any: the page's section
  /// heading, built with the number of searches.
  final Widget Function(int count)? heading;

  /// Opens the sheet a tapped notification asked for, once.
  ///
  /// This is the half of the notification handoff that needs a `BuildContext` —
  /// see [pendingReleaseSearchJobProvider] for why the tap cannot open the sheet
  /// itself. Cleared *before* showing, so a rebuild while the sheet is up cannot
  /// stack a second one; and post-frame, because opening a route during build is
  /// not allowed.
  void _openPendingSheet(BuildContext context, WidgetRef ref) {
    final pending = ref.watch(pendingReleaseSearchJobProvider);
    if (pending == null) return;

    // Everything happens after the frame — including the clear. Riverpod
    // forbids writing to a provider during build, and a request for a job that
    // no longer exists still has to be cleared or it would be retried forever.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!context.mounted) return;
      ref.read(pendingReleaseSearchJobProvider.notifier).clear();
      final job = ref.read(releaseSearchJobsProvider.notifier).jobById(pending);
      if (job == null) return;
      // Only a job with releases to pick earns the sheet. A stopped search's
      // notice says "Search stopped", not "pick one", and its destination is
      // the card in this list — verdict, and Search again beside it. Opening a
      // picker over an empty or failed result would answer a question the
      // notification never asked.
      if (!job.isGrabbable) return;
      ReleaseSearchSheet.show(
        context: context,
        ref: ref,
        jobId: job.id,
        target: job.target,
        reusedResults: job.status == ReleaseSearchJobStatus.completed,
      );
    });
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watchWhileLive(context, releaseSearchTickProvider);
    _openPendingSheet(context, ref);
    final jobs = ref.watch(releaseSearchJobsProvider);
    if (jobs.isEmpty) return const SizedBox.shrink();
    final now = DateTime.now();

    // Queue positions are 1-based and counted oldest-first, which is the order
    // the manager actually starts them in.
    final queued = jobs
        .where((j) => j.status == ReleaseSearchJobStatus.queued)
        .toList()
        .reversed
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ?heading?.call(jobs.length),
        for (final (index, job) in jobs.indexed) ...[
          if (index > 0) const SizedBox(height: AppSpacing.sm),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: ReleaseSearchJobCard(
              job: job,
              now: now,
              connection: ref.watch(
                currentSettingsProvider.select(job.target.connectionIn),
              ),
              queuePosition: switch (queued.indexWhere((j) => j.id == job.id)) {
                final position when position > 0 => position,
                _ => null,
              },
              expandVerdict: true,
              onTap: () => ReleaseSearchSheet.show(
                context: context,
                ref: ref,
                jobId: job.id,
                target: job.target,
                reusedResults: job.status == ReleaseSearchJobStatus.completed,
              ),
              onCancel: () =>
                  ref.read(releaseSearchJobsProvider.notifier).cancel(job.id),
              onSearchAgain: () => ref
                  .read(releaseSearchJobsProvider.notifier)
                  .searchAgain(job.target),
              onDismiss: () =>
                  ref.read(releaseSearchJobsProvider.notifier).dismiss(job.id),
            ),
          ),
        ],
      ],
    );
  }
}
