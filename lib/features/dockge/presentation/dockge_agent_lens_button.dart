import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/status_badge.dart';
import 'package:cupola/features/dockge/domain/models/dockge_agent.dart';
import 'package:cupola/features/dockge/presentation/dockge_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// The agent picker, as the app-bar connection lens (decision 41).
///
/// Dockge's agents are not a tab and never were: an agent is not a *place* in
/// this app, it is which Dockge the rows on screen came off — the same thing the
/// connection lens means everywhere else. So it sits in the app bar, beside the
/// title, and everything below it follows.
///
/// It draws nothing when there is only one instance, which is the same rule
/// [ConnectionBadge] keeps: a picker offering one choice is chrome that teaches
/// the user there is a decision to make when there is not. Most Dockge installs
/// are exactly that, which is why the control had to be free at one agent before
/// it could be worth anything at two.
class DockgeAgentLensButton extends ConsumerWidget {
  const DockgeAgentLensButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Configuration is checked **before** the agent stream is watched, and that
    // order matters more since this rides the service band: the band is drawn
    // above every Dockge tab, including on an install that has never been set
    // up, and `dockgeClientProvider` throws there. A provider that throws is a
    // failed provider scheduling a retry with backoff for a condition no
    // waiting changes — and a picker offering a choice between connections that
    // do not exist has nothing to say anyway.
    final configured = ref
        .watch(currentSettingsProvider)
        .isServiceConfigured(ServiceKey.dockge);
    if (!configured) return const SizedBox.shrink();

    final agents = ref.watch(dockgeAgentsProvider).asData?.value ?? const [];
    if (agents.length < 2) return const SizedBox.shrink();

    final selectedEndpoint = ref.watch(dockgeSelectedAgentProvider);
    final selected = agents.firstWhere(
      (a) => a.endpoint == selectedEndpoint,
      // The lens can outlive the agent it points at — Dockge drops a removed
      // agent from the next `agentList`. Falling back to the hub is the one
      // choice that is always reachable.
      orElse: () => DockgeAgent.local,
    );

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Semantics(
      button: true,
      label: 'Dockge instance: ${selected.name}',
      hint: 'Choose which Dockge instance to show',
      excludeSemantics: true,
      child: PopupMenuButton<String>(
        tooltip: 'Dockge instance',
        onSelected: (endpoint) =>
            ref.read(dockgeSelectedAgentProvider.notifier).select(endpoint),
        itemBuilder: (context) => [
          for (final agent in agents)
            PopupMenuItem<String>(
              value: agent.endpoint,
              child: Row(
                children: [
                  _StatusDot(agent: agent),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(child: Text(agent.name)),
                  if (agent.endpoint == selected.endpoint)
                    Icon(
                      Icons.check_rounded,
                      size: 16,
                      color: colorScheme.onSurfaceVariant,
                    ),
                ],
              ),
            ),
        ],
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: 4,
          ),
          decoration: BoxDecoration(
            color: AppColors.dockge.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: AppColors.dockge.withValues(alpha: 0.34)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _StatusDot(agent: selected),
              const SizedBox(width: 6),
              Text(
                selected.name,
                style: AppTheme.chrome(
                  context,
                  size: 12,
                  weight: FontWeight.w600,
                  color: colorScheme.onSurface,
                ),
              ),
              const SizedBox(width: 2),
              // The count is what makes the control legible before it is opened:
              // "local" alone does not say there is anywhere else to go.
              Text(
                '×${agents.length}',
                style: AppTheme.chrome(
                  context,
                  size: 11,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              Icon(
                Icons.expand_more_rounded,
                size: 16,
                color: colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.agent});

  final DockgeAgent agent;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 7,
      height: 7,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: statusToneColor(Theme.of(context).colorScheme, agent.tone),
      ),
    );
  }
}
