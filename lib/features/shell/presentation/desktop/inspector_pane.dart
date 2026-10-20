import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/features/activity/data/selected_download.dart';
import 'package:cupola/features/activity/presentation/download_page.dart';
import 'package:cupola/features/shell/domain/inspector_state.dart';
import 'package:cupola/features/shell/domain/shell_shortcuts.dart';

/// The inspector: the thing you chose, without leaving what you are doing.
///
/// It used to stand open with the queue in it, a third of the window that most
/// of the time said `Nothing downloading right now`. The queue now sits folded
/// at the foot of the sidebar (`InFlightGlance`), and the pane opens only on a
/// choice: a download picked in Activity's table. With nothing chosen it is not
/// laid out at all, and its switch in the window strip is dimmed.
///
/// Everything in it also exists in `/activity`. That is the rule for the whole
/// desktop layer: the inspector is an accelerator, so nothing may live only
/// here, or a phone user would be missing a feature rather than a shortcut.
class InspectorPane extends ConsumerWidget {
  const InspectorPane({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final selected = ref.watch(selectedDownloadProvider);
    if (selected == null) return const SizedBox.shrink();

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest.withValues(alpha: 0.72),
        border: Border(
          left: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.55),
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _InspectorHeader(selected: selected),
          Expanded(
            child: DownloadPage.inspector(
              key: ValueKey(selected),
              instanceId: selected.instanceId,
              downloadKey: selected.key,
            ),
          ),
        ],
      ),
    );
  }
}

/// 44pt, matching the window strip above it, so the two read as one bar.
///
/// Its buttons keep the theme's standard density, 40pt in the 44pt bar:
/// `VisualDensity.compact` took them to 32, under the pointer floor every
/// other desktop control keeps.
///
/// It reads `Selected download`: its first button opens the download's page,
/// its second puts the choice down, which closes the pane.
class _InspectorHeader extends ConsumerWidget {
  const _InspectorHeader({required this.selected});

  final DownloadSelection selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.slabY),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.55),
          ),
        ),
      ),
      child: Row(
        children: [
          // The secondary ink, like every mark in the chrome: the pane is
          // named by its title beside the glyph, and a section colour here once
          // measured 2.20:1 on paper.
          Icon(
            Icons.download_rounded,
            size: 16,
            color: colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Semantics(
              header: true,
              child: Text(
                'Selected download',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTheme.chrome(
                  context,
                  size: 13,
                  weight: FontWeight.w600,
                  color: colorScheme.onSurface,
                ),
              ),
            ),
          ),
          IconButton(
            onPressed: () => GoRouter.of(context).go(
              ServiceRoutes.activityDownload(
                instanceId: selected.instanceId,
                key: selected.key,
              ),
            ),
            icon: const Icon(Icons.open_in_full_rounded, size: 15),
            iconSize: 15,
            tooltip: "Open the download's page",
          ),
          IconButton(
            onPressed: () =>
                ref.read(selectedDownloadProvider.notifier).clear(),
            icon: const Icon(Icons.close_rounded, size: 16),
            iconSize: 16,
            tooltip: 'Close  ${ShellShortcuts.inspector}',
          ),
        ],
      ),
    );
  }
}

/// The split handle: a 3pt line in a 9pt hit area.
///
/// Nine because a 3pt target is a miss with a mouse and impossible with a
/// trackpad, and the visual has to stay 3 or the window grows a seam. Double
/// click restores the drawn width: the one gesture that makes an experiment
/// with the width free.
class InspectorSplitHandle extends ConsumerWidget {
  const InspectorSplitHandle({super.key});

  static const double width = 9;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final notifier = ref.read(inspectorStateProvider.notifier);
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: (details) =>
            notifier.resizeBy(details.delta.dx),
        onDoubleTap: notifier.resetWidth,
        child: SizedBox(
          width: width,
          child: Center(
            child: Container(width: 3, color: colorScheme.surfaceContainerLow),
          ),
        ),
      ),
    );
  }
}
