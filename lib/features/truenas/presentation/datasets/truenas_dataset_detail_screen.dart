import 'package:flutter/material.dart';
import 'package:cupola/core/widgets/floating_bottom_nav_bar.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/app_card.dart';
import 'package:cupola/core/widgets/app_dialog.dart';
import 'package:cupola/core/widgets/app_skeleton.dart';
import 'package:cupola/core/widgets/inline_error_retry.dart';
import 'package:cupola/core/utils/string_utils.dart';
import 'package:cupola/core/widgets/section_header.dart';
import 'package:cupola/features/qbittorrent/domain/models/parse_utils.dart';
import 'package:cupola/features/truenas/domain/models/dataset.dart';
import 'package:cupola/features/truenas/presentation/datasets/truenas_dataset_actions.dart';
import 'package:cupola/features/truenas/presentation/datasets/truenas_dataset_providers.dart';
import 'package:cupola/features/truenas/presentation/truenas_actions.dart';
import 'package:cupola/features/truenas/presentation/truenas_provider.dart';
import 'package:cupola/features/truenas/presentation/widgets/truenas_info_row.dart';
import 'package:cupola/features/truenas/presentation/widgets/truenas_async_body.dart';
import 'package:cupola/features/truenas/presentation/widgets/truenas_section_scaffold.dart';
import 'package:cupola/features/truenas/presentation/truenas_console_shell.dart';
import 'package:cupola/features/truenas/presentation/truenas_capability.dart';
import 'package:cupola/features/truenas/domain/truenas_capability.dart';

class TrueNasDatasetDetailScreen extends ConsumerWidget {
  final String datasetId;
  const TrueNasDatasetDetailScreen({super.key, required this.datasetId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dataset = ref.watch(truenasDatasetProvider(datasetId));

    return TrueNasSectionScaffold(
      title: datasetId.split('/').last,
      capabilityAreas: {
        TrueNasCapabilityArea.datasetWrite.key,
        TrueNasCapabilityArea.datasetDelete.key,
        TrueNasCapabilityArea.snapshotWrite.key,
        TrueNasCapabilityArea.snapshotDelete.key,
      },
      actions: [
        dataset.maybeWhen(
          data: (d) => d == null
              ? const SizedBox.shrink()
              : PopupMenuButton<String>(
                  onSelected: (value) async {
                    switch (value) {
                      case 'edit':
                        if (!trueNasWriteAllowed(
                          context,
                          ref,
                          area: TrueNasCapabilityArea.datasetWrite.key,
                          verbPhrase: 'edit datasets',
                        )) {
                          return;
                        }
                        await editDatasetFlow(context, ref, d);
                      case 'child':
                        if (!trueNasWriteAllowed(
                          context,
                          ref,
                          area: TrueNasCapabilityArea.datasetWrite.key,
                          verbPhrase: 'create datasets',
                        )) {
                          return;
                        }
                        await createDatasetFlow(context, ref, parentId: d.id);
                      case 'delete':
                        if (!trueNasWriteAllowed(
                          context,
                          ref,
                          area: TrueNasCapabilityArea.datasetDelete.key,
                          verbPhrase: 'delete datasets',
                        )) {
                          return;
                        }
                        final deleted = await deleteDatasetFlow(
                          context,
                          ref,
                          d,
                        );
                        if (deleted && context.mounted) context.pop();
                    }
                  },
                  // Never `enabled: false`: a disabled item drops off the
                  // screen reader's path, taking the explanation with it.
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: 'edit',
                      child: trueNasGatedMenuLabel(
                        ref: ref,
                        area: TrueNasCapabilityArea.datasetWrite.key,
                        text: 'Edit',
                      ),
                    ),
                    PopupMenuItem(
                      value: 'child',
                      child: trueNasGatedMenuLabel(
                        ref: ref,
                        area: TrueNasCapabilityArea.datasetWrite.key,
                        text: 'Create child dataset',
                      ),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      child: trueNasGatedMenuLabel(
                        ref: ref,
                        area: TrueNasCapabilityArea.datasetDelete.key,
                        text: 'Delete',
                      ),
                    ),
                  ],
                ),
          orElse: () => const SizedBox.shrink(),
        ),
      ],
      body: TrueNasConsoleShell(
        child: TrueNasAsyncBody(
          value: dataset,
          onRetry: () {
            ref.invalidate(truenasDatasetProvider(datasetId));
            ref.invalidate(truenasSnapshotsProvider(datasetId));
          },
          skeleton: ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [AppSkeleton.detailBody()],
          ),
          data: (d) => d == null
              ? ListView(
                  children: const [
                    Padding(
                      padding: EdgeInsets.all(AppSpacing.xl),
                      child: Text('Dataset not found.'),
                    ),
                  ],
                )
              : _DetailBody(dataset: d),
        ),
      ),
    );
  }
}

class _DetailBody extends ConsumerWidget {
  final TrueNasDataset dataset;
  const _DetailBody({required this.dataset});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshots = ref.watch(truenasSnapshotsProvider(dataset.id));

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        FloatingNavBarMetrics.getScrollViewBottomPadding(context),
      ),
      children: [
        AppCard.surfaceOutlined(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TrueNasInfoRow(label: 'Path', value: dataset.id),
              TrueNasInfoRow(label: 'Type', value: dataset.type),
              TrueNasInfoRow(
                label: 'Used',
                value: dataset.usedBytes != null
                    ? formatSize(dataset.usedBytes!)
                    : null,
              ),
              TrueNasInfoRow(
                label: 'Available',
                value: dataset.availableBytes != null
                    ? formatSize(dataset.availableBytes!)
                    : null,
              ),
              if (dataset.quotaBytes != null && dataset.quotaBytes! > 0)
                TrueNasInfoRow(
                  label: 'Quota',
                  value: formatSize(dataset.quotaBytes!),
                ),
              TrueNasInfoRow(label: 'Compression', value: dataset.compression),
              TrueNasInfoRow(label: 'Ratio', value: dataset.compressionRatio),
              TrueNasInfoRow(label: 'Record size', value: dataset.recordsize),
              TrueNasInfoRow(label: 'Dedup', value: dataset.dedup),
              TrueNasInfoRow(
                label: 'Encrypted',
                value: dataset.encrypted ? 'Yes' : 'No',
              ),
              TrueNasInfoRow(label: 'Comment', value: dataset.comments),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        SectionHeader.action(
          title: 'Snapshots',
          trailing: trueNasGatedButton(
            ref: ref,
            area: TrueNasCapabilityArea.snapshotWrite.key,
            verbPhrase: 'create snapshots',
            onTap: () => createSnapshotFlow(context, ref, dataset.id),
            builder: (context, onPressed, annotate) => TextButton(
              onPressed: onPressed,
              child: annotate(
                const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.add_rounded, size: 16),
                    SizedBox(width: AppSpacing.xs),
                    Text('New'),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        snapshots.when(
          loading: () => AppSkeleton.listRows(count: 3),
          // The section's own fallback, never the raw exception: the page
          // above still reads, and the snapshot list is the one part that did
          // not answer. See `TrueNasDatasetApi.getSnapshots` for the upstream
          // change that makes this likely on TrueNAS 25.10.
          error: (_, _) => InlineErrorRetry(
            message: 'Failed to load snapshots',
            onRetry: () => ref.invalidate(truenasSnapshotsProvider(dataset.id)),
          ),
          data: (list) => list.isEmpty
              ? AppCard.surfaceOutlined(
                  child: Text(
                    'No snapshots.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                )
              : Column(
                  children: [
                    for (final snap in list)
                      _SnapshotTile(snapshot: snap, dataset: dataset.id),
                  ],
                ),
        ),
      ],
    );
  }
}

class _SnapshotTile extends ConsumerWidget {
  final TrueNasSnapshot snapshot;
  final String dataset;
  const _SnapshotTile({required this.snapshot, required this.dataset});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return AppCard.surfaceOutlined(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  snapshot.name,
                  style: theme.textTheme.bodyMedium!.weight(FontWeight.w600),
                ),
                Text(
                  [
                    'used ${snapshot.usedBytes != null ? formatSize(snapshot.usedBytes!) : '—'}',
                    // The dense-row date voice, matching the activity feed.
                    if (snapshot.createdMs != null)
                      formatIsoDate(
                        DateTime.fromMillisecondsSinceEpoch(
                          snapshot.createdMs!,
                        ).toIso8601String(),
                      ),
                  ].join(' · '),
                  style: theme.textTheme.labelSmall!.tabular.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          trueNasGatedIcon(
            ref: ref,
            area: TrueNasCapabilityArea.snapshotDelete.key,
            verbPhrase: 'delete snapshots',
            // Neutral: the confirmation says what goes, in words.
            icon: const Icon(Icons.delete_outline_rounded, size: 18),
            tooltip: 'Delete snapshot',
            onTap: () async {
              final result = await showAppConfirmDialog(
                context: context,
                title: 'Delete snapshot?',
                message: '${snapshot.id} is destroyed. This cannot be undone.',
                confirmLabel: 'Delete snapshot',
              );
              if (!result.confirmed || !context.mounted) return;
              await runTrueNasAction(
                context,
                ref,
                action: () => ref
                    .read(truenasDatasetApiProvider)
                    .deleteSnapshot(snapshot.id),
                successMessage: 'Snapshot deleted',
                failureMessage: 'Could not delete snapshot',
                invalidate: [truenasSnapshotsProvider(dataset)],
              );
            },
          ),
        ],
      ),
    );
  }
}
