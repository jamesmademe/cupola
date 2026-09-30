import 'package:flutter/material.dart';
import 'package:cupola/core/widgets/floating_bottom_nav_bar.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/widgets/app_card.dart';
import 'package:cupola/core/widgets/app_dialog.dart';
import 'package:cupola/core/widgets/app_skeleton.dart';
import 'package:cupola/core/widgets/inline_error_retry.dart';
import 'package:cupola/core/widgets/section_header.dart';
import 'package:cupola/features/qbittorrent/domain/models/parse_utils.dart';
import 'package:cupola/features/settings/domain/connection_presentation.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/truenas/domain/models/virt_instance.dart';
import 'package:cupola/features/truenas/presentation/truenas_actions.dart';
import 'package:cupola/features/truenas/presentation/truenas_provider.dart';
import 'package:cupola/features/truenas/presentation/virt/truenas_virt_providers.dart';
import 'package:cupola/features/truenas/presentation/virt/truenas_virt_screen.dart';
import 'package:cupola/features/truenas/presentation/widgets/truenas_async_body.dart';
import 'package:cupola/features/truenas/presentation/widgets/truenas_info_row.dart';
import 'package:cupola/features/truenas/presentation/widgets/truenas_section_scaffold.dart';
import 'package:cupola/features/truenas/presentation/truenas_console_shell.dart';
import 'package:cupola/features/truenas/presentation/truenas_capability.dart';
import 'package:cupola/features/truenas/domain/truenas_capability.dart';

class TrueNasVirtDetailScreen extends ConsumerWidget {
  final String id;
  final String type;
  const TrueNasVirtDetailScreen({
    super.key,
    required this.id,
    required this.type,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final instance = ref.watch(truenasVirtInstanceProvider(id));

    return TrueNasSectionScaffold(
      title: id,
      capabilityAreas: {TrueNasCapabilityArea.virt.key},
      actions: [
        trueNasGatedIcon(
          ref: ref,
          area: TrueNasCapabilityArea.virt.key,
          verbPhrase: 'delete instances',
          icon: const Icon(Icons.delete_outline_rounded),
          tooltip: 'Delete instance',
          onTap: () async {
            final result = await showAppConfirmDialog(
              context: context,
              title: 'Delete "$id"?',
              message:
                  'This permanently deletes the instance and its disks. '
                  'This cannot be undone.',
              confirmLabel: 'Delete instance',
            );
            if (!result.confirmed || !context.mounted) return;
            final ok = await runTrueNasAction(
              context,
              ref,
              action: () => ref.read(truenasVirtApiProvider).delete(id),
              successMessage: 'Deleted "$id"',
              failureMessage: 'Could not delete',
              invalidate: [truenasVirtInstancesProvider(type)],
            );
            if (ok && context.mounted) context.pop();
          },
        ),
      ],
      body: TrueNasConsoleShell(
        child: TrueNasAsyncBody(
          value: instance,
          onRetry: () {
            ref.invalidate(truenasVirtInstanceProvider(id));
            ref.invalidate(truenasVirtDevicesProvider(id));
          },
          skeleton: ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [AppSkeleton.detailBody()],
          ),
          data: (data) => data == null
              ? ListView(
                  children: const [
                    Padding(
                      padding: EdgeInsets.all(AppSpacing.xl),
                      child: Text('Instance not found.'),
                    ),
                  ],
                )
              : _DetailBody(instance: data, type: type),
        ),
      ),
    );
  }
}

class _DetailBody extends ConsumerWidget {
  final TrueNasVirtInstance instance;
  final String type;
  const _DetailBody({required this.instance, required this.type});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final devices = ref.watch(truenasVirtDevicesProvider(instance.id));

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
              Row(
                children: [
                  Expanded(
                    child: TrueNasInfoRow(
                      label: 'Status',
                      value: instance.status,
                    ),
                  ),
                  VirtLifecycleButton(instance: instance, type: type),
                ],
              ),
              TrueNasInfoRow(label: 'Type', value: instance.type),
              TrueNasInfoRow(label: 'Image', value: instance.image),
              TrueNasInfoRow(
                label: 'vCPUs',
                value: instance.cpuCount?.toString(),
              ),
              TrueNasInfoRow(
                label: 'Memory',
                value: instance.memoryBytes != null
                    ? formatSize(instance.memoryBytes!)
                    : null,
              ),
              TrueNasInfoRow(
                label: 'Autostart',
                value: instance.autostart ? 'Yes' : 'No',
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        const SectionHeader(title: 'Devices', showChevron: false),
        const SizedBox(height: AppSpacing.sm),
        devices.when(
          loading: () => AppSkeleton.listRows(count: 3),
          error: (error, _) => InlineErrorRetry(
            message: sectionFailureMessage(
              ServiceKey.truenas,
              error,
              consequence: 'the devices are not shown',
            ),
            error: error,
            onRetry: () =>
                ref.invalidate(truenasVirtDevicesProvider(instance.id)),
          ),
          data: (list) => list.isEmpty
              ? AppCard.surfaceOutlined(
                  child: Text(
                    'No devices.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                )
              : Column(
                  children: [
                    for (final device in list)
                      AppCard.surfaceOutlined(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.md,
                          vertical: AppSpacing.sm,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                device.name,
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            ),
                            Text(
                              device.type,
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}
