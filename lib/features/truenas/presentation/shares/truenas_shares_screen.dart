import 'package:flutter/material.dart';
import 'package:cupola/core/widgets/floating_bottom_nav_bar.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderOrFamily;

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/status_badge.dart';
import 'package:cupola/core/widgets/app_card.dart';
import 'package:cupola/core/widgets/app_dialog.dart';
import 'package:cupola/features/truenas/domain/models/service_item.dart';
import 'package:cupola/features/truenas/domain/models/share.dart';
import 'package:cupola/features/truenas/presentation/shares/truenas_shares_providers.dart';
import 'package:cupola/features/truenas/presentation/truenas_actions.dart';
import 'package:cupola/features/truenas/presentation/truenas_provider.dart';
import 'package:cupola/features/truenas/presentation/widgets/truenas_form_sheet.dart';
import 'package:cupola/features/truenas/presentation/widgets/truenas_async_body.dart';
import 'package:cupola/features/truenas/presentation/widgets/truenas_section_scaffold.dart';
import 'package:cupola/features/truenas/presentation/truenas_console_shell.dart';
import 'package:cupola/features/truenas/presentation/truenas_capability.dart';
import 'package:cupola/features/truenas/domain/truenas_capability.dart';

class TrueNasSharesScreen extends ConsumerStatefulWidget {
  const TrueNasSharesScreen({super.key});

  @override
  ConsumerState<TrueNasSharesScreen> createState() =>
      _TrueNasSharesScreenState();
}

class _TrueNasSharesScreenState extends ConsumerState<TrueNasSharesScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab = TabController(length: 3, vsync: this);

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TrueNasSectionScaffold(
      title: 'Shares',
      capabilityAreas: {
        TrueNasCapabilityArea.smb.key,
        TrueNasCapabilityArea.nfs.key,
        TrueNasCapabilityArea.iscsi.key,
        trueNasServiceArea('cifs'),
        trueNasServiceArea('nfs'),
        trueNasServiceArea('iscsitarget'),
      },
      appBarBottom: TabBar(
        controller: _tab,
        tabs: const [
          Tab(text: 'SMB'),
          Tab(text: 'NFS'),
          Tab(text: 'iSCSI'),
        ],
      ),
      body: TrueNasConsoleShell(
        child: TabBarView(
          controller: _tab,
          children: const [_SmbTab(), _NfsTab(), _IscsiTab()],
        ),
      ),
    );
  }
}

/// A banner showing a share service's running state with a start/stop toggle.
class _ServiceStateBanner extends ConsumerWidget {
  final String serviceName;
  final String label;
  const _ServiceStateBanner({required this.serviceName, required this.label});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final services = ref.watch(truenasServicesProvider);
    final theme = Theme.of(context);
    final list = services.asData?.value ?? const [];
    TrueNasServiceItem? item;
    for (final s in list) {
      if (s.name == serviceName) {
        item = s;
        break;
      }
    }
    if (item == null) return const SizedBox.shrink();
    final running = item.running;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: AppCard.surfaceOutlined(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.xs,
        ),
        child: Row(
          children: [
            Icon(
              running ? Icons.check_circle_rounded : Icons.pause_circle_outline,
              size: 16,
              // A protocol nobody turned on is neutral: not running is the
              // normal state for two of the three on most servers.
              color: statusToneColor(
                theme.colorScheme,
                running ? StatusTone.success : StatusTone.neutral,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                '$label service ${running ? 'running' : 'stopped'}',
                style: theme.textTheme.bodyMedium,
              ),
            ),
            trueNasGatedToggle(
              ref: ref,
              area: trueNasServiceArea(serviceName),
              verbPhrase: 'start or stop the $label service',
              value: running,
              onChanged: (value) => runTrueNasAction(
                context,
                ref,
                action: () => value
                    ? ref
                          .read(truenasSystemApiProvider)
                          .startService(serviceName)
                    : ref
                          .read(truenasSystemApiProvider)
                          .stopService(serviceName),
                successMessage: value ? '$label started' : '$label stopped',
                failureMessage: 'Could not change service',
                invalidate: [truenasServicesProvider],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SmbTab extends ConsumerWidget {
  const _SmbTab();

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final values = await showTrueNasFormSheet(
      context: context,
      title: 'New SMB share',
      submitLabel: 'Create',
      fields: const [
        TrueNasFormField(
          key: 'path',
          label: 'Path',
          required: true,
          hint: '/mnt/tank/share',
        ),
        TrueNasFormField(key: 'name', label: 'Share name', required: true),
        TrueNasFormField(key: 'comment', label: 'Comment'),
        TrueNasFormField(
          key: 'enabled',
          label: 'Enabled',
          boolField: true,
          initialBool: true,
        ),
      ],
    );
    if (values == null || !context.mounted) return;
    await runTrueNasAction(
      context,
      ref,
      action: () => ref.read(truenasSharingApiProvider).createSmbShare({
        'path': values['path'],
        'name': values['name'],
        if (values['comment'] != null) 'comment': values['comment'],
        'enabled': values['enabled'] == true,
      }),
      successMessage: 'SMB share created',
      failureMessage: 'Could not create share',
      invalidate: [truenasSmbSharesProvider],
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shares = ref.watch(truenasSmbSharesProvider);
    return _ShareTabScaffold(
      createArea: TrueNasCapabilityArea.smb.key,
      createVerb: 'create SMB shares',
      onCreate: () => _create(context, ref),
      onRefresh: () => ref.invalidate(truenasSmbSharesProvider),
      serviceBanner: const _ServiceStateBanner(
        serviceName: 'cifs',
        label: 'SMB',
      ),
      child: TrueNasAsyncBody.inline(
        value: shares,
        onRetry: () => ref.invalidate(truenasSmbSharesProvider),
        data: (list) => list.isEmpty
            ? const _EmptyShares(text: 'No SMB shares.')
            : Column(
                children: [
                  for (final share in list) _SmbShareTile(share: share),
                ],
              ),
      ),
    );
  }
}

class _SmbShareTile extends ConsumerWidget {
  final TrueNasSmbShare share;
  const _SmbShareTile({required this.share});

  Future<void> _edit(BuildContext context, WidgetRef ref) async {
    final values = await showTrueNasFormSheet(
      context: context,
      title: 'Edit ${share.name}',
      fields: [
        TrueNasFormField(
          key: 'name',
          label: 'Share name',
          initialValue: share.name,
          required: true,
        ),
        TrueNasFormField(
          key: 'comment',
          label: 'Comment',
          initialValue: share.comment,
        ),
      ],
    );
    if (values == null || !context.mounted) return;
    await runTrueNasAction(
      context,
      ref,
      action: () => ref.read(truenasSharingApiProvider).updateSmbShare(
        share.id,
        {'name': values['name'], 'comment': values['comment'] ?? ''},
      ),
      successMessage: 'Share updated',
      failureMessage: 'Could not update share',
      invalidate: [truenasSmbSharesProvider],
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _ShareRow(
      area: TrueNasCapabilityArea.smb.key,
      noun: 'SMB shares',
      title: share.name,
      subtitle: share.path,
      enabled: share.enabled,
      onToggle: (value) => runTrueNasAction(
        context,
        ref,
        action: () =>
            ref.read(truenasSharingApiProvider).setSmbEnabled(share.id, value),
        successMessage: value ? 'Enabled' : 'Disabled',
        failureMessage: 'Could not update share',
        invalidate: [truenasSmbSharesProvider],
      ),
      onEdit: () => _edit(context, ref),
      onDelete: () => _deleteShare(
        context,
        ref,
        name: share.name,
        delete: () =>
            ref.read(truenasSharingApiProvider).deleteSmbShare(share.id),
        provider: truenasSmbSharesProvider,
      ),
    );
  }
}

class _NfsTab extends ConsumerWidget {
  const _NfsTab();

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final values = await showTrueNasFormSheet(
      context: context,
      title: 'New NFS export',
      submitLabel: 'Create',
      fields: const [
        TrueNasFormField(
          key: 'path',
          label: 'Path',
          required: true,
          hint: '/mnt/tank/export',
        ),
        TrueNasFormField(key: 'comment', label: 'Comment'),
        TrueNasFormField(
          key: 'enabled',
          label: 'Enabled',
          boolField: true,
          initialBool: true,
        ),
      ],
    );
    if (values == null || !context.mounted) return;
    await runTrueNasAction(
      context,
      ref,
      action: () => ref.read(truenasSharingApiProvider).createNfsShare({
        'path': values['path'],
        if (values['comment'] != null) 'comment': values['comment'],
        'enabled': values['enabled'] == true,
      }),
      successMessage: 'NFS export created',
      failureMessage: 'Could not create export',
      invalidate: [truenasNfsSharesProvider],
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shares = ref.watch(truenasNfsSharesProvider);
    return _ShareTabScaffold(
      createArea: TrueNasCapabilityArea.nfs.key,
      createVerb: 'create NFS exports',
      onCreate: () => _create(context, ref),
      onRefresh: () => ref.invalidate(truenasNfsSharesProvider),
      serviceBanner: const _ServiceStateBanner(
        serviceName: 'nfs',
        label: 'NFS',
      ),
      child: TrueNasAsyncBody.inline(
        value: shares,
        onRetry: () => ref.invalidate(truenasNfsSharesProvider),
        data: (list) => list.isEmpty
            ? const _EmptyShares(text: 'No NFS exports.')
            : Column(
                children: [
                  for (final share in list)
                    _ShareRow(
                      area: TrueNasCapabilityArea.nfs.key,
                      noun: 'NFS exports',
                      title: share.displayPath,
                      subtitle: share.comment ?? 'NFS export',
                      enabled: share.enabled,
                      onToggle: (value) => runTrueNasAction(
                        context,
                        ref,
                        action: () => ref
                            .read(truenasSharingApiProvider)
                            .setNfsEnabled(share.id, value),
                        successMessage: value ? 'Enabled' : 'Disabled',
                        failureMessage: 'Could not update export',
                        invalidate: [truenasNfsSharesProvider],
                      ),
                      onDelete: () => _deleteShare(
                        context,
                        ref,
                        name: share.displayPath,
                        delete: () => ref
                            .read(truenasSharingApiProvider)
                            .deleteNfsShare(share.id),
                        provider: truenasNfsSharesProvider,
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}

class _IscsiTab extends ConsumerWidget {
  const _IscsiTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final targets = ref.watch(truenasIscsiTargetsProvider);
    return _ShareTabScaffold(
      onRefresh: () => ref.invalidate(truenasIscsiTargetsProvider),
      serviceBanner: const _ServiceStateBanner(
        serviceName: 'iscsitarget',
        label: 'iSCSI',
      ),
      child: TrueNasAsyncBody.inline(
        value: targets,
        onRetry: () => ref.invalidate(truenasIscsiTargetsProvider),
        data: (list) => list.isEmpty
            ? const _EmptyShares(text: 'No iSCSI targets.')
            : Column(
                children: [
                  for (final target in list)
                    _ShareRow(
                      area: TrueNasCapabilityArea.iscsi.key,
                      noun: 'iSCSI targets',
                      title: target.name,
                      subtitle: target.alias ?? 'iSCSI target',
                      onDelete: () => _deleteShare(
                        context,
                        ref,
                        name: target.name,
                        delete: () => ref
                            .read(truenasSharingApiProvider)
                            .deleteIscsiTarget(target.id),
                        provider: truenasIscsiTargetsProvider,
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}

Future<void> _deleteShare(
  BuildContext context,
  WidgetRef ref, {
  required String name,
  required Future<void> Function() delete,
  required ProviderOrFamily provider,
}) async {
  final result = await showAppConfirmDialog(
    context: context,
    title: 'Delete "$name"?',
    message: 'The share definition is removed. Data on disk is not deleted.',
    confirmLabel: 'Delete share',
  );
  if (!result.confirmed || !context.mounted) return;
  await runTrueNasAction(
    context,
    ref,
    action: delete,
    successMessage: 'Deleted "$name"',
    failureMessage: 'Could not delete',
    invalidate: [provider],
  );
}

class _ShareTabScaffold extends ConsumerWidget {
  final Widget child;
  final Widget serviceBanner;
  final VoidCallback onRefresh;
  final VoidCallback? onCreate;

  /// The area the create action writes, and its blocked-toast verb.
  final String? createArea;
  final String? createVerb;

  const _ShareTabScaffold({
    required this.child,
    required this.serviceBanner,
    required this.onRefresh,
    this.onCreate,
    this.createArea,
    this.createVerb,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Stack(
      children: [
        RefreshIndicator(
          onRefresh: () async => onRefresh(),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.lg,
              FloatingNavBarMetrics.getScrollViewBottomPadding(context),
            ),
            children: [serviceBanner, child],
          ),
        ),
        if (onCreate != null)
          Positioned(
            right: AppSpacing.lg,
            bottom: AppSpacing.lg,
            // Gated at the tap that opens the form, never after it is filled.
            child: trueNasGatedButton(
              ref: ref,
              area: createArea!,
              verbPhrase: createVerb!,
              onTap: onCreate!,
              builder: (context, onPressed, annotate) => FloatingActionButton(
                heroTag: null,
                tooltip: 'New',
                onPressed: onPressed,
                child: annotate(const Icon(Icons.add_rounded)),
              ),
            ),
          ),
      ],
    );
  }
}

class _ShareRow extends ConsumerWidget {
  /// The capability area every write on this row belongs to, and the plural
  /// its blocked toasts name.
  final String area;
  final String noun;
  final String title;
  final String subtitle;
  final bool? enabled;
  final ValueChanged<bool>? onToggle;
  final VoidCallback? onEdit;
  final VoidCallback onDelete;

  const _ShareRow({
    required this.area,
    required this.noun,
    required this.title,
    required this.subtitle,
    required this.onDelete,
    this.enabled,
    this.onToggle,
    this.onEdit,
  });

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
                  title,
                  style: theme.textTheme.bodyMedium!.weight(FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  subtitle,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (onEdit != null)
            trueNasGatedIcon(
              ref: ref,
              area: area,
              verbPhrase: 'edit $noun',
              icon: const Icon(Icons.edit_outlined, size: 18),
              tooltip: 'Edit',
              onTap: onEdit!,
            ),
          trueNasGatedIcon(
            ref: ref,
            area: area,
            verbPhrase: 'delete $noun',
            // Neutral, like Edit beside it: the confirmation says what goes.
            icon: const Icon(Icons.delete_outline_rounded, size: 18),
            tooltip: 'Delete share',
            onTap: onDelete,
          ),
          if (enabled != null && onToggle != null)
            trueNasGatedToggle(
              ref: ref,
              area: area,
              verbPhrase: 'enable or disable $noun',
              value: enabled!,
              onChanged: onToggle!,
            ),
        ],
      ),
    );
  }
}

class _EmptyShares extends StatelessWidget {
  final String text;
  const _EmptyShares({required this.text});

  @override
  Widget build(BuildContext context) {
    return AppCard.surfaceOutlined(
      child: Text(text, style: Theme.of(context).textTheme.bodySmall),
    );
  }
}
