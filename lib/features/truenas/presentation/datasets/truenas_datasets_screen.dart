import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/app_breakpoints.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/core/widgets/app_card.dart';
import 'package:cupola/core/widgets/app_empty_state.dart';
import 'package:cupola/core/widgets/floating_bottom_nav_bar.dart';
import 'package:cupola/features/qbittorrent/domain/models/parse_utils.dart';
import 'package:cupola/features/truenas/domain/models/dataset.dart';
import 'package:cupola/features/truenas/presentation/datasets/truenas_dataset_actions.dart';
import 'package:cupola/features/truenas/presentation/datasets/truenas_dataset_providers.dart';
import 'package:cupola/features/truenas/presentation/widgets/truenas_async_body.dart';
import 'package:cupola/features/truenas/presentation/widgets/truenas_section_scaffold.dart';
import 'package:cupola/features/truenas/presentation/truenas_console_shell.dart';

class TrueNasDatasetsScreen extends ConsumerWidget {
  const TrueNasDatasetsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tree = ref.watch(truenasDatasetTreeProvider);

    return TrueNasSectionScaffold(
      title: 'Datasets',
      floatingActionButton: const DatasetCreateButton(),
      body: TrueNasConsoleShell(
        child: TrueNasAsyncBody(
          value: tree,
          onRetry: () => ref.invalidate(truenasDatasetTreeProvider),
          data: (roots) => roots.isEmpty
              ? const AppEmptyState(
                  icon: Icons.account_tree_rounded,
                  title: 'No datasets',
                  accentColor: AppColors.truenas,
                )
              : ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.md,
                    AppSpacing.lg,
                    FloatingNavBarMetrics.getScrollViewBottomPadding(context),
                  ),
                  children: [
                    for (final root in roots)
                      Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                        child: AppCard.surfaceOutlined(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.sm,
                            vertical: AppSpacing.xs,
                          ),
                          child: _DatasetNode(dataset: root, depth: 0),
                        ),
                      ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _DatasetNode extends StatelessWidget {
  final TrueNasDataset dataset;
  final int depth;
  const _DatasetNode({required this.dataset, required this.depth});

  /// The height floor of a tree row and of its Details button.
  ///
  /// 44 anywhere a finger can reach the tree: the floor is binding for every
  /// touch build (DESIGN.md, decided 2026-09-27). A desktop build is driven by
  /// a pointer and never by a finger, so there the tree keeps the denser 40 it
  /// was drawn at; WCAG 2.5.8 asks 24px of a pointer target. The switch is
  /// [AppBreakpoints.isDesktopPlatform], the per-build constant the shell
  /// already uses, not a width, because a narrow desktop window is still
  /// driven by a pointer.
  ///
  /// Declared as `minTileHeight` and never left to `VisualDensity.compact`,
  /// which takes 8 off a default height: the tree used to declare 40 under
  /// compact and reached the floor only because the Details button happened
  /// to be taller than the row.
  static double get _rowFloor => AppBreakpoints.isDesktopPlatform ? 40 : 44;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtitle = dataset.isVolume
        ? 'zvol · ${dataset.volsizeBytes != null ? formatSize(dataset.volsizeBytes!) : '—'}'
        : 'used ${dataset.usedBytes != null ? formatSize(dataset.usedBytes!) : '—'}';

    final tileTitle = Row(
      children: [
        Icon(
          dataset.isVolume ? Icons.storage_rounded : Icons.folder_rounded,
          size: 16,
          color: AppColors.truenas,
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            depth == 0 ? dataset.id : dataset.shortName,
            style: theme.textTheme.bodyMedium!.weight(FontWeight.w600),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.info_outline_rounded, size: 16),
          tooltip: 'Details',
          padding: EdgeInsets.zero,
          // The row's own floor even though the glyph is 16pt: the visual
          // stays compact in a dense tree while the target meets the floor.
          // Without `VisualDensity.compact`, which took 8 off these
          // constraints and left the target at 40.
          constraints: BoxConstraints(
            minWidth: _rowFloor,
            minHeight: _rowFloor,
          ),
          onPressed: () =>
              context.push(ServiceRoutes.truenasDataset(dataset.id)),
        ),
      ],
    );

    if (dataset.children.isEmpty) {
      return ListTile(
        contentPadding: EdgeInsets.only(left: depth * 10.0),
        dense: true,
        minTileHeight: _rowFloor,
        minVerticalPadding: 2,
        title: tileTitle,
        subtitle: Text(subtitle, style: theme.textTheme.labelSmall!.tabular),
        onTap: () => context.push(ServiceRoutes.truenasDataset(dataset.id)),
      );
    }

    return Padding(
      padding: EdgeInsets.only(left: depth * 10.0),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: EdgeInsets.zero,
        minTileHeight: _rowFloor,
        shape: const Border(),
        collapsedShape: const Border(),
        initiallyExpanded: depth == 0,
        title: tileTitle,
        subtitle: Text(subtitle, style: theme.textTheme.labelSmall!.tabular),
        children: [
          for (final child in dataset.children)
            _DatasetNode(dataset: child, depth: depth + 1),
        ],
      ),
    );
  }
}

/// A floating action to create a top-level dataset, shared with the section
/// scaffold via [DatasetCreateButton].
class DatasetCreateButton extends ConsumerWidget {
  const DatasetCreateButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FloatingActionButton.extended(
      onPressed: () => createDatasetFlow(context, ref, parentId: null),
      backgroundColor: AppColors.truenas,
      icon: const Icon(Icons.add_rounded),
      label: const Text('New dataset'),
    );
  }
}
