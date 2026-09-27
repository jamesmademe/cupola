import 'package:flutter/material.dart';
import 'package:cupola/core/widgets/floating_bottom_nav_bar.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/service_theme.dart';
import 'package:cupola/core/widgets/status_badge.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/core/widgets/app_card.dart';
import 'package:cupola/core/widgets/app_empty_state.dart';
import 'package:cupola/core/widgets/pressable_scale.dart';
import 'package:cupola/core/widgets/selection_pills.dart';
import 'package:cupola/features/qbittorrent/domain/models/parse_utils.dart';
import 'package:cupola/features/truenas/domain/models/virt_instance.dart';
import 'package:cupola/features/truenas/domain/truenas_version.dart';
import 'package:cupola/features/truenas/presentation/truenas_actions.dart';
import 'package:cupola/features/truenas/presentation/truenas_provider.dart';
import 'package:cupola/features/truenas/presentation/virt/truenas_virt_actions.dart';
import 'package:cupola/features/truenas/presentation/virt/truenas_virt_providers.dart';
import 'package:cupola/features/truenas/presentation/widgets/truenas_async_body.dart';
import 'package:cupola/features/truenas/presentation/widgets/truenas_section_scaffold.dart';
import 'package:cupola/features/truenas/presentation/truenas_console_shell.dart';

/// The two things Incus runs, and the only axis this section has.
enum TrueNasVirtKind {
  container('CONTAINER', 'Containers', 'container'),
  vm('VM', 'VMs', 'VM');

  const TrueNasVirtKind(this.wire, this.label, this.singular);

  /// The value `virt.instance.query` filters on, and the string the instance
  /// providers and the create flow are keyed by.
  final String wire;

  /// The pill's label.
  final String label;

  /// For sentences: "No containers yet", "Delete this VM".
  final String singular;

  static TrueNasVirtKind fromWire(String? raw) => raw?.toUpperCase() == 'VM'
      ? TrueNasVirtKind.vm
      : TrueNasVirtKind.container;
}

/// Virtualization: one door, two pills.
///
/// It used to be two doors. `Containers` and `Virtual Machines` were separate
/// rail rows, separate routes and two instances of this screen, which split one
/// question ("what is running on this NAS?") across two places and made the rail
/// ten rows where the design draws nine (decision 36). They are one section with
/// a `Containers | VMs` selector now.
///
/// The other half of decision 36: **Incus instances only**. This screen used to
/// also list legacy KVM VMs out of `vm.query` and route their lifecycle calls to
/// the `vm.*` RPCs — and, because those VMs do not need an Incus storage pool,
/// the VM door deliberately *bypassed* the readiness gate, so it was the one
/// place in the console that could show instances the rest of the section could
/// not act on. TrueNAS 25.04 is this client's minimum anyway (the JSON-RPC
/// transport it speaks arrived with it), so below that the section says so and
/// offers nothing rather than half-working.
class TrueNasVirtScreen extends ConsumerStatefulWidget {
  const TrueNasVirtScreen({
    super.key,
    required this.type,
    this.title,
    this.experimental = false,
  });

  /// Which pill this screen opens on, so the two old paths still land where
  /// they used to point. Deep links keep working; the door is one.
  final String type;

  /// Accepted and unused. The two old routes still pass the labels of the two
  /// doors they used to be ("Containers", "Virtual Machines"); this page names
  /// itself now. Owed outside this feature: `router.dart` collapsing
  /// `/containers` and `/vms` into one `virtualization` route with a `?kind=`
  /// query parameter, after which this parameter and [experimental] go.
  final String? title;

  /// Accepted and unused: see [title]. The LXC-is-experimental note moved onto
  /// the Containers pill's own list, where it belongs, so it no longer has to
  /// be threaded in from the route table.
  final bool experimental;

  @override
  ConsumerState<TrueNasVirtScreen> createState() => _TrueNasVirtScreenState();
}

class _TrueNasVirtScreenState extends ConsumerState<TrueNasVirtScreen> {
  late TrueNasVirtKind _kind = TrueNasVirtKind.fromWire(widget.type);

  @override
  Widget build(BuildContext context) {
    final version = ref.watch(truenasVersionProvider);
    final global = ref.watch(truenasVirtGlobalProvider);

    return TrueNasSectionScaffold(
      title: 'Virtualization',
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.truenas,
        onPressed: () => createInstanceFlow(context, ref, type: _kind.wire),
        tooltip: 'New ${_kind.singular}',
        child: const Icon(Icons.add_rounded),
      ),
      body: TrueNasConsoleShell(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: SelectionPills<TrueNasVirtKind>(
                values: TrueNasVirtKind.values,
                selected: _kind,
                labelBuilder: (kind) => kind.label,
                accent: AppColors.truenas,
                onSelected: (kind) => setState(() => _kind = kind),
              ),
            ),
            Expanded(
              child: TrueNasAsyncBody(
                value: global,
                onRetry: () {
                  ref.invalidate(truenasVirtGlobalProvider);
                  ref.invalidate(truenasVirtInstancesProvider(_kind.wire));
                },
                data: (cfg) =>
                    _VirtPane(kind: _kind, config: cfg, version: version),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// What the section can show once `virt.global.config` has answered: the
/// version floor first, then the storage-pool gate, then the instances.
class _VirtPane extends ConsumerWidget {
  const _VirtPane({
    required this.kind,
    required this.config,
    required this.version,
  });

  final TrueNasVirtKind kind;
  final TrueNasVirtGlobalConfig config;
  final AsyncValue<TrueNasVersion?> version;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final parsed = version.asData?.value;
    // Fail open on an unparseable version string — the same rule
    // `TrueNasVersion.isVersionSupported` states — but never on a parsed one
    // that is genuinely older: `virt.*` does not exist before 25.04 and every
    // control on this page would throw "method not found".
    if (parsed != null && !parsed.isSupported) {
      return ListView(
        children: [
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xxl),
            child: AppEmptyState(
              icon: Icons.layers_clear_rounded,
              title: 'Virtualization needs SCALE $kTrueNasMinVersion',
              message:
                  'This server reports $parsed. Incus virtualization '
                  '(containers and VMs) arrived in $kTrueNasMinVersion, so '
                  'Cupola has nothing to show or start here.',
              accentColor: AppColors.truenas,
            ),
          ),
        ],
      );
    }

    if (!config.isReady) {
      return ListView(
        children: const [
          Padding(
            padding: EdgeInsets.only(top: AppSpacing.xxl),
            child: AppEmptyState(
              icon: Icons.settings_suggest_rounded,
              title: 'Virtualization not configured',
              message:
                  'Choose a storage pool for instances in the '
                  'TrueNAS web UI (Virtualization) to get started.',
              accentColor: AppColors.truenas,
            ),
          ),
        ],
      );
    }

    return _InstanceList(kind: kind);
  }
}

class _InstanceList extends ConsumerWidget {
  const _InstanceList({required this.kind});

  final TrueNasVirtKind kind;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final instances = ref.watch(truenasVirtInstancesProvider(kind.wire));

    return TrueNasAsyncBody(
      value: instances,
      onRetry: () => ref.invalidate(truenasVirtInstancesProvider(kind.wire)),
      data: (list) => ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.md,
          AppSpacing.lg,
          FloatingNavBarMetrics.getScrollViewBottomPadding(context),
        ),
        children: [
          if (kind == TrueNasVirtKind.container)
            const Padding(
              padding: EdgeInsets.only(bottom: AppSpacing.sm),
              child: _ExperimentalNote(),
            ),
          if (list.isEmpty)
            AppCard.surfaceOutlined(
              child: Text(
                'No ${kind.label.toLowerCase()} yet.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            )
          else
            for (final instance in list)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: _InstanceCard(instance: instance, kind: kind),
              ),
        ],
      ),
    );
  }
}

class _ExperimentalNote extends StatelessWidget {
  const _ExperimentalNote();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    // Amber, because "experimental" is TrueNAS warning about its own feature —
    // a fault it is pre-announcing. The tint is a container, so the ink walks
    // for contrast against the tint rather than against the page.
    final tone = statusToneColor(colorScheme, StatusTone.warning);
    final ink = statusToneColor(
      colorScheme,
      StatusTone.warning,
      surface: colorScheme.surface,
    );
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppSpacing.md),
        border: Border.all(color: tone.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.science_rounded, size: 16, color: ink),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'LXC containers are experimental in TrueNAS SCALE.',
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

class _InstanceCard extends ConsumerWidget {
  const _InstanceCard({required this.instance, required this.kind});

  final TrueNasVirtInstance instance;
  final TrueNasVirtKind kind;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final route = kind == TrueNasVirtKind.vm
        ? ServiceRoutes.truenasVm(instance.id)
        : ServiceRoutes.truenasContainer(instance.id);
    final specs = <String>[
      if (instance.cpuCount != null) '${instance.cpuCount} vCPU',
      if (instance.memoryBytes != null) formatSize(instance.memoryBytes!),
      if (instance.image != null) instance.image!,
    ];

    return PressableScale(
      onTap: () => context.push(route),
      child: AppCard.surfaceOutlined(
        child: Row(
          children: [
            _StatusDot(running: instance.isRunning),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          instance.name,
                          style: theme.textTheme.titleSmall!.weight(
                            FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (instance.autostart) ...[
                        const SizedBox(width: AppSpacing.sm),
                        const _AutostartBadge(),
                      ],
                    ],
                  ),
                  if (specs.isNotEmpty)
                    Text(
                      specs.join(' · '),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            VirtLifecycleButton(instance: instance, type: kind.wire),
          ],
        ),
      ),
    );
  }
}

/// Small pill indicating the instance is set to auto-start on boot.
class _AutostartBadge extends StatelessWidget {
  const _AutostartBadge();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.truenas.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.power_settings_new_rounded,
            size: 11,
            color: ServiceTheme.onTint(
              AppColors.truenas,
              surface: theme.colorScheme.surface,
              tintAlpha: 0.12,
            ),
          ),
          const SizedBox(width: 3),
          Text(
            'Autostart',
            style: theme.textTheme.labelSmall!
                .weight(FontWeight.w600)
                .copyWith(
                  color: ServiceTheme.onTint(
                    AppColors.truenas,
                    surface: theme.colorScheme.surface,
                    tintAlpha: 0.12,
                  ),
                ),
          ),
        ],
      ),
    );
  }
}

class _StatusDot extends StatelessWidget {
  final bool running;
  const _StatusDot({required this.running});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        // A stopped instance is backlog, not a fault: nothing failed, somebody
        // stopped it (decision 15). Neutral, and only running is green.
        color: statusToneColor(
          colorScheme,
          running ? StatusTone.success : StatusTone.neutral,
        ),
      ),
    );
  }
}

/// Start/stop/restart control shared by list cards and the detail screen.
class VirtLifecycleButton extends ConsumerWidget {
  final TrueNasVirtInstance instance;
  final String type;
  const VirtLifecycleButton({
    super.key,
    required this.instance,
    required this.type,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final api = ref.read(truenasVirtApiProvider);
    void invalidate() {
      ref.invalidate(truenasVirtInstancesProvider(type));
      ref.invalidate(truenasVirtInstanceProvider(instance.id));
    }

    if (instance.isRunning) {
      return PopupMenuButton<String>(
        icon: const Icon(Icons.more_vert_rounded),
        tooltip: 'Actions for ${instance.name}',
        onSelected: (value) => runTrueNasAction(
          context,
          ref,
          action: () => value == 'restart'
              ? api.restart(instance.id)
              : api.stop(instance.id),
          successMessage: value == 'restart' ? 'Restarting' : 'Stopping',
          failureMessage: 'Action failed',
        ).then((_) => invalidate()),
        itemBuilder: (context) => const [
          PopupMenuItem(value: 'stop', child: Text('Stop')),
          PopupMenuItem(value: 'restart', child: Text('Restart')),
        ],
      );
    }
    return IconButton(
      icon: const Icon(Icons.play_arrow_rounded),
      color: statusToneColor(Theme.of(context).colorScheme, StatusTone.success),
      tooltip: 'Start ${instance.name}',
      onPressed: () => runTrueNasAction(
        context,
        ref,
        action: () => api.start(instance.id),
        successMessage: 'Starting ${instance.name}',
        failureMessage: 'Could not start',
      ).then((_) => invalidate()),
    );
  }
}
