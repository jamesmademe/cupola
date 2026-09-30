import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/app_animation.dart';
import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/dockge/data/dockge_client.dart';
import 'package:cupola/features/dockge/domain/models/dockge_stack.dart';
import 'package:cupola/features/dockge/presentation/dockge_actions.dart';
import 'package:cupola/features/dockge/presentation/dockge_agent_lens_button.dart';
import 'package:cupola/features/dockge/presentation/dockge_provider.dart';
import 'package:cupola/features/services/presentation/service_kpi_provider.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

class DockgeScreen extends ConsumerWidget {
  const DockgeScreen({super.key, this.showAppBar = true, this.topPadding = 0});

  final bool showAppBar;
  final double topPadding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(currentSettingsProvider);
    final isConfigured = settings.isServiceConfigured(ServiceKey.dockge);

    return AmbientScaffold(
      accent: AppColors.dockge,
      appBar: showAppBar
          ? const GlassAppBar(
              title: Text('Dockge'),
              // The lens belongs beside the title, not in a tab: it says which
              // Dockge the rows below came off (decision 41). It draws nothing
              // until there are two instances to tell apart.
              actions: [
                DockgeAgentLensButton(),
                SizedBox(width: AppSpacing.sm),
              ],
            )
          : null,
      body: SafeArea(
        // The inset is the app bar's to consume when this page draws one. In
        // the tab shell it does not: the service band and the tab bar float
        // above the content at fixed offsets from the top of the screen, and
        // `topPadding` is what clears them — consuming the inset here as well
        // would push the first row a status bar's height below the tab bar.
        top: showAppBar,
        child: isConfigured
            ? _DockgeDashboard(topPadding: topPadding)
            : const NotConfiguredPlaceholder(serviceName: 'Dockge'),
      ),
    );
  }
}

class _DockgeDashboard extends ConsumerWidget {
  const _DockgeDashboard({required this.topPadding});

  final double topPadding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stacksAsync = ref.watch(dockgeStackListProvider);

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(dockgeStackListProvider);
        ref.invalidate(serviceKpiProvider(ServiceKey.dockge));
        ref.invalidate(serviceSummaryProvider(ServiceKey.dockge));
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
            kpis: ref.watch(serviceKpiProvider(ServiceKey.dockge)),
            accent: AppColors.dockge,
          ),
          const SizedBox(height: AppSpacing.xs),
          SectionHeader.action(
            title: 'Stacks',
            trailing: TextButton.icon(
              onPressed: () => context.push(ServiceRoutes.dockgeNewStack),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('New'),
              style: TextButton.styleFrom(foregroundColor: AppColors.dockge),
            ),
          ),
          const SizedBox(height: 2),
          stacksAsync.when(
            data: (stacks) => _StackList(stacks: stacks),
            loading: () => const ListRowsShimmer(),
            error: (error, _) => AppErrorState(
              error: error,
              onRetry: () => ref.invalidate(dockgeStackListProvider),
            ),
          ),
        ],
      ),
    );
  }
}

class _StackList extends StatelessWidget {
  const _StackList({required this.stacks});

  final List<DockgeStack> stacks;

  @override
  Widget build(BuildContext context) {
    if (stacks.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.xl,
        ),
        child: AppEmptyState(
          icon: Icons.layers_clear_rounded,
          title: 'No stacks yet',
          message: 'Compose stacks managed by Dockge will appear here.',
        ),
      );
    }
    return Column(children: stacks.map((s) => _StackTile(stack: s)).toList());
  }
}

class _StackTile extends ConsumerWidget {
  const _StackTile({required this.stack});

  final DockgeStack stack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final statusColor = statusToneColor(colorScheme, stack.status.tone);

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.xs,
      ),
      child: Material(
        color: colorScheme.surface,
        borderRadius: AppRadius.borderRadiusMd,
        child: InkWell(
          borderRadius: AppRadius.borderRadiusMd,
          onTap: () => context.push(ServiceRoutes.dockgeStack(stack.name)),
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              border: Border.all(color: colorScheme.outlineVariant),
              borderRadius: AppRadius.borderRadiusMd,
            ),
            child: Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: statusColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        stack.name,
                        style: Theme.of(
                          context,
                        ).textTheme.bodyMedium!.weight(FontWeight.w600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        stack.status.label,
                        style: Theme.of(
                          context,
                        ).textTheme.bodySmall?.copyWith(color: statusColor),
                      ),
                    ],
                  ),
                ),
                _StackQuickActions(stack: stack),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Inline start/stop/restart controls on a stack row.
class _StackQuickActions extends ConsumerWidget {
  const _StackQuickActions({required this.stack});

  final DockgeStack stack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    // `isActive` rather than `== running`: the enum already owns what "this
    // stack is up" means, and a second copy of that test is a second place to
    // forget when Dockge adds a state.
    final isRunning = stack.status.isActive;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (isRunning)
          IconButton(
            tooltip: 'Stop',
            icon: const Icon(Icons.stop_rounded),
            // Not red. Red on this canvas means a connection that did not
            // answer, and this is a button offering to stop something that is
            // running fine — the confirm below is where the weight belongs.
            color: colorScheme.onSurfaceVariant,
            // Confirmed first: these buttons sit on a scrolling list of live
            // production stacks, and a mis-tap took one down with no warning —
            // while deleting a movie, a far smaller consequence, already asked.
            onPressed: () => _confirmThenRun(
              context,
              ref,
              verb: DockgeStackLifecycle.stop,
              action: (c) => c.stopStack(stack.name),
              success: 'Stopped ${stack.name}',
              failure: 'Failed to stop ${stack.name}',
            ),
          )
        else
          IconButton(
            tooltip: 'Start',
            icon: const Icon(Icons.play_arrow_rounded),
            color: statusToneColor(colorScheme, StatusTone.success),
            onPressed: () => runDockgeStackAction(
              context,
              ref,
              (c) => c.startStack(stack.name),
              'Started ${stack.name}',
              'Failed to start ${stack.name}',
              invalidate: [dockgeStackListProvider],
            ),
          ),
        IconButton(
          tooltip: 'Restart',
          icon: const Icon(Icons.restart_alt_rounded),
          color: AppColors.dockge,
          onPressed: () => _confirmThenRun(
            context,
            ref,
            verb: DockgeStackLifecycle.restart,
            action: (c) => c.restartStack(stack.name),
            success: 'Restarted ${stack.name}',
            failure: 'Failed to restart ${stack.name}',
          ),
        ),
      ],
    );
  }

  /// Asks before running a lifecycle action, then runs it.
  ///
  /// Starting a stack is additive and stays a single tap; stopping and
  /// restarting interrupt something the user is running, so they confirm.
  Future<void> _confirmThenRun(
    BuildContext context,
    WidgetRef ref, {
    required DockgeStackLifecycle verb,
    required Future<void> Function(DockgeClient client) action,
    required String success,
    required String failure,
  }) async {
    // The stack page asks with the same words: see `dockgeLifecycleCopy`.
    final confirmed = await confirmDockgeLifecycle(context, verb, stack.name);
    if (!confirmed || !context.mounted) return;

    await runDockgeStackAction(
      context,
      ref,
      action,
      success,
      failure,
      invalidate: [dockgeStackListProvider],
    );
  }
}
