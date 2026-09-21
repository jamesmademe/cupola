import 'package:flutter/material.dart';
import 'package:cupola/core/widgets/floating_bottom_nav_bar.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/status_badge.dart';
import 'package:cupola/core/widgets/app_card.dart';
import 'package:cupola/core/widgets/app_empty_state.dart';
import 'package:cupola/features/truenas/domain/models/service_item.dart';
import 'package:cupola/features/truenas/presentation/shares/truenas_shares_providers.dart';
import 'package:cupola/features/truenas/presentation/truenas_actions.dart';
import 'package:cupola/features/truenas/presentation/truenas_provider.dart';
import 'package:cupola/features/truenas/presentation/widgets/truenas_async_body.dart';
import 'package:cupola/features/truenas/presentation/widgets/truenas_section_scaffold.dart';
import 'package:cupola/features/truenas/presentation/truenas_console_shell.dart';

class TrueNasServicesScreen extends ConsumerWidget {
  const TrueNasServicesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final services = ref.watch(truenasServicesProvider);

    return TrueNasSectionScaffold(
      title: 'Services',
      body: TrueNasConsoleShell(
        child: TrueNasAsyncBody(
          value: services,
          onRetry: () => ref.invalidate(truenasServicesProvider),
          data: (list) {
            if (list.isEmpty) {
              return const AppEmptyStatePage(
                emptyState: AppEmptyState(
                  icon: Icons.miscellaneous_services_rounded,
                  title: 'No services reported',
                  message: 'TrueNAS returned no system services.',
                ),
              );
            }
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.md,
                AppSpacing.lg,
                FloatingNavBarMetrics.getScrollViewBottomPadding(context),
              ),
              children: [
                for (final item in list)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: _ServiceTile(item: item),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ServiceTile extends ConsumerWidget {
  final TrueNasServiceItem item;
  const _ServiceTile({required this.item});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final api = ref.read(truenasSystemApiProvider);

    return AppCard.surfaceOutlined(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              // A stopped service is backlog, not a fault: somebody stopped it,
              // or it was never started. Neutral, per decision 15.
              color: statusToneColor(
                theme.colorScheme,
                item.running ? StatusTone.success : StatusTone.neutral,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  style: theme.textTheme.bodyMedium!.weight(FontWeight.w600),
                ),
                if (item.enabled)
                  Text(
                    'Starts on boot',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          if (item.id != null)
            IconButton(
              tooltip: item.enabled ? 'Disable autostart' : 'Enable autostart',
              icon: Icon(
                item.enabled ? Icons.flash_on_rounded : Icons.flash_off_rounded,
                size: 18,
                // Autostart on is a *setting*, not a fault — amber said
                // something was wrong with a service configured correctly. The
                // service accent marks it as "on" the way every other toggle in
                // the console does.
                color: item.enabled
                    ? AppColors.truenas
                    : theme.colorScheme.outline,
              ),
              onPressed: () => runTrueNasAction(
                context,
                ref,
                action: () => api.setServiceAutostart(item.id!, !item.enabled),
                successMessage: item.enabled
                    ? 'Autostart disabled'
                    : 'Autostart enabled',
                failureMessage: 'Could not update service',
                invalidate: [truenasServicesProvider],
              ),
            ),
          Switch(
            value: item.running,
            onChanged: (value) => runTrueNasAction(
              context,
              ref,
              action: () => value
                  ? api.startService(item.name)
                  : api.stopService(item.name),
              successMessage: value
                  ? 'Started ${item.name}'
                  : 'Stopped ${item.name}',
              failureMessage: 'Action failed',
              invalidate: [truenasServicesProvider],
            ),
          ),
        ],
      ),
    );
  }
}
