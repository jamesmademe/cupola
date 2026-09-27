import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/app_animation.dart';
import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/service_theme.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/dockge/data/dockge_client.dart';
import 'package:cupola/features/dockge/domain/models/dockge_stack.dart';
import 'package:cupola/features/dockge/domain/models/dockge_stack_detail.dart';
import 'package:cupola/features/dockge/presentation/dockge_actions.dart';
import 'package:cupola/features/dockge/presentation/dockge_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

class DockgeStackDetailScreen extends ConsumerWidget {
  const DockgeStackDetailScreen({super.key, required this.name});

  final String name;

  void _refresh(WidgetRef ref) {
    ref.invalidate(dockgeStackDetailProvider(name));
    ref.invalidate(dockgeServiceStatusProvider(name));
    ref.invalidate(dockgeStackListProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Checked **before** the detail provider is read. This page is reachable by
    // deep link — `/dashboard/dockge/stacks/stack/<name>`, and every pre-tab
    // spelling still rewrites onto it — so it can be the first Dockge thing the
    // app builds on an install that was never set up. `dockgeClientProvider`
    // throws there, and a provider that throws is a failed provider scheduling
    // a retry with backoff for a condition no waiting changes.
    final isConfigured = ref
        .watch(currentSettingsProvider)
        .isServiceConfigured(ServiceKey.dockge);

    return AmbientScaffold(
      accent: AppColors.dockge,
      appBar: GlassAppBar(
        title: Text(name),
        actions: [
          if (isConfigured)
            IconButton(
              tooltip: 'Edit compose',
              icon: const Icon(Icons.edit_note_rounded),
              onPressed: () =>
                  context.push(ServiceRoutes.dockgeStackEdit(name)),
            ),
        ],
      ),
      body: SafeArea(
        child: isConfigured
            ? _StackDetailBody(name: name, onRefresh: _refresh)
            : const NotConfiguredPlaceholder(serviceName: 'Dockge'),
      ),
    );
  }
}

/// The detail itself, mounted only once Dockge is configured.
///
/// Its own widget rather than a branch inside [DockgeStackDetailScreen.build],
/// because `ref.watch` inside a conditional is still a watch: the provider has
/// to be unreachable, not merely undrawn.
class _StackDetailBody extends ConsumerWidget {
  const _StackDetailBody({required this.name, required this.onRefresh});

  final String name;
  final void Function(WidgetRef ref) onRefresh;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref
        .watch(dockgeStackDetailProvider(name))
        .when(
          data: (detail) => _DetailBody(detail: detail, onRefresh: onRefresh),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) =>
              AppErrorState(error: error, onRetry: () => onRefresh(ref)),
        );
  }
}

class _DetailBody extends ConsumerWidget {
  const _DetailBody({required this.detail, required this.onRefresh});

  final DockgeStackDetail detail;
  final void Function(WidgetRef ref) onRefresh;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final servicesAsync = ref.watch(dockgeServiceStatusProvider(detail.name));

    return RefreshIndicator(
      onRefresh: () async {
        onRefresh(ref);
        await Future<void>.delayed(AppAnimation.durationMd);
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.md,
          AppSpacing.lg,
          AppSpacing.xxl,
        ),
        children: [
          _StatusHeader(status: detail.status),
          const SizedBox(height: AppSpacing.lg),
          _ActionBar(name: detail.name, onRefresh: onRefresh),
          const SizedBox(height: 20),
          Text(
            'Services',
            style: Theme.of(
              context,
            ).textTheme.titleSmall!.weight(FontWeight.w600),
          ),
          const SizedBox(height: AppSpacing.sm),
          servicesAsync.when(
            data: (services) => _ServiceStatusList(services: services),
            loading: () => const ShimmerPlaceholder(height: 120),
            error: (error, _) => AppErrorState.compact(error: error),
          ),
          const SizedBox(height: 20),
          _TerminalLog(stackName: detail.name),
        ],
      ),
    );
  }
}

class _StatusHeader extends StatelessWidget {
  const _StatusHeader({required this.status});

  final DockgeStackStatus status;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final statusColor = statusToneColor(colorScheme, status.tone);

    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle),
        ),
        const SizedBox(width: 10),
        Text(
          status.label,
          style: Theme.of(context).textTheme.titleMedium!
              .weight(FontWeight.w600)
              .copyWith(color: statusColor),
        ),
      ],
    );
  }
}

class _ActionBar extends ConsumerWidget {
  const _ActionBar({required this.name, required this.onRefresh});

  final String name;
  final void Function(WidgetRef ref) onRefresh;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    // Six chips that used to be six palette colours — green Start, red Stop,
    // blue Update, amber Down — which put the whole status vocabulary on a row
    // of *controls*. A tone describes a state; nothing here has a state. Amber
    // on "Down" claimed a fault about an action the user is about to take on
    // purpose, and red on a status says "unreachable", which is the one thing
    // red means on this canvas. So: the service accent for everything that is
    // an ordinary operation, and red only for Delete, because red on an action
    // means it cannot be undone. Stop used to be red too, and a stopped stack is
    // one Start away from running again.
    final destructive = statusToneColor(
      colorScheme,
      StatusTone.error,
      surface: colorScheme.surface,
      tintAlpha: 0.12,
    );
    final accent = ServiceTheme.onTint(
      AppColors.dockge,
      surface: colorScheme.surface,
      tintAlpha: 0.12,
    );
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _ActionChip(
          icon: Icons.play_arrow_rounded,
          label: 'Start',
          color: accent,
          onTap: () => runDockgeStackAction(
            context,
            ref,
            (c) => c.startStack(name),
            'Started $name',
            'Failed to start',
            onSuccess: () => onRefresh(ref),
          ),
        ),
        _ActionChip(
          icon: Icons.stop_rounded,
          label: 'Stop',
          color: accent,
          onTap: () => runDockgeStackAction(
            context,
            ref,
            (c) => c.stopStack(name),
            'Stopped $name',
            'Failed to stop',
            onSuccess: () => onRefresh(ref),
          ),
        ),
        _ActionChip(
          icon: Icons.restart_alt_rounded,
          label: 'Restart',
          color: accent,
          onTap: () => runDockgeStackAction(
            context,
            ref,
            (c) => c.restartStack(name),
            'Restarted $name',
            'Failed to restart',
            onSuccess: () => onRefresh(ref),
          ),
        ),
        _ActionChip(
          icon: Icons.system_update_alt_rounded,
          label: 'Update',
          color: accent,
          onTap: () => runDockgeStackAction(
            context,
            ref,
            (c) => c.updateStack(name),
            'Updated $name',
            'Failed to update',
            onSuccess: () => onRefresh(ref),
          ),
        ),
        _ActionChip(
          icon: Icons.arrow_downward_rounded,
          label: 'Down',
          color: accent,
          onTap: () => runDockgeStackAction(
            context,
            ref,
            (c) => c.downStack(name),
            'Stack $name is down',
            'Failed to bring down',
            onSuccess: () => onRefresh(ref),
          ),
        ),
        _ActionChip(
          icon: Icons.delete_outline_rounded,
          label: 'Delete',
          color: destructive,
          onTap: () => _confirmDelete(context, ref),
        ),
      ],
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete $name?'),
        content: const Text(
          'This removes the stack and its compose files from Dockge. '
          'This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: statusToneFill(
                Theme.of(ctx).colorScheme,
                StatusTone.error,
              ),
              // Measured against the fill: `onError` white reads 3.5:1 on the
              // light theme's red.
              foregroundColor: ServiceTheme.foregroundOn(
                statusToneFill(Theme.of(ctx).colorScheme, StatusTone.error),
              ),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final ok = await runDockgeAction(
      context,
      ref,
      action: (c) => c.deleteStack(name),
      successMessage: 'Deleted $name',
      failureMessage: 'Failed to delete',
      invalidate: [dockgeStackListProvider],
    );
    if (ok && context.mounted) context.pop();
  }
}

class _ActionChip extends StatelessWidget {
  const _ActionChip({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withValues(alpha: 0.12),
      borderRadius: AppRadius.borderRadiusSm,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.borderRadiusSm,
        child: Container(
          // A finger's 44pt. The padding and a labelMedium line came to about
          // 34 (measured), so the chip met the floor only once the text had grown. The
          // floor wraps the padding, which hands the row a minimum it centres
          // its icon and label in.
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            border: Border.all(color: color.withValues(alpha: 0.4)),
            borderRadius: AppRadius.borderRadiusSm,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Text(
                label,
                style: Theme.of(context).textTheme.labelMedium!
                    .weight(FontWeight.w600)
                    .copyWith(color: color),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ServiceStatusList extends StatelessWidget {
  const _ServiceStatusList({required this.services});

  final List<DockgeServiceStatus> services;

  @override
  Widget build(BuildContext context) {
    if (services.isEmpty) {
      return const AppEmptyState.compact(
        icon: Icons.dns_rounded,
        title: 'No running services',
      );
    }
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      children: services.map((service) {
        // A container that is not running is not necessarily broken, and this
        // payload cannot tell a deliberate stop from a crash (decision 15). Red
        // asserted the crash on every one of them.
        final color = statusToneColor(
          colorScheme,
          service.isRunning ? StatusTone.success : StatusTone.neutral,
        );
        return Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: colorScheme.surface,
              border: Border.all(color: colorScheme.outlineVariant),
              borderRadius: AppRadius.borderRadiusMd,
            ),
            child: Row(
              children: [
                Icon(Icons.widgets_rounded, size: 18, color: AppColors.dockge),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    service.serviceName,
                    style: Theme.of(
                      context,
                    ).textTheme.bodyMedium!.weight(FontWeight.w600),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: AppRadius.borderRadiusSm,
                  ),
                  child: Text(
                    service.statusLabel,
                    style: Theme.of(context).textTheme.labelSmall!
                        .weight(FontWeight.w600)
                        .copyWith(color: color),
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

/// Live tail of the stack's combined terminal (deploy/up/down logs).
class _TerminalLog extends ConsumerStatefulWidget {
  const _TerminalLog({required this.stackName});

  final String stackName;

  @override
  ConsumerState<_TerminalLog> createState() => _TerminalLogState();
}

class _TerminalLogState extends ConsumerState<_TerminalLog> {
  /// Hard caps so a long-running deploy can't grow the buffer without bound.
  static const int _maxChars = 64 * 1024;
  static const int _maxLines = 2000;

  /// Batch window: coalesce bursts of chunks into a single rebuild.
  static const Duration _flushInterval = Duration(milliseconds: 100);

  /// How close to the bottom still counts as "following" the tail.
  static const double _autoScrollThreshold = 24;

  String _text = '';
  final StringBuffer _pending = StringBuffer();
  StreamSubscription<DockgeTerminalOutput>? _sub;
  Timer? _flushTimer;
  final ScrollController _scroll = ScrollController();
  bool _autoScroll = true;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    final client = ref.read(dockgeClientProvider);
    final terminalName = client.combinedTerminalName(widget.stackName);
    // Re-join so Dockge streams the combined terminal to us.
    unawaited(client.joinCombinedTerminal(widget.stackName));
    _sub = client.terminalOutput.listen((output) {
      if (output.terminalName != terminalName) return;
      if (!mounted) return;
      _pending.write(output.data);
      // Throttle: rebuild at most once per [_flushInterval] instead of on
      // every chunk.
      _flushTimer ??= Timer(_flushInterval, _flush);
    });
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    // Resume auto-scroll only while the user stays pinned near the bottom.
    _autoScroll =
        _scroll.position.pixels >=
        _scroll.position.maxScrollExtent - _autoScrollThreshold;
  }

  void _flush() {
    _flushTimer = null;
    if (!mounted || _pending.isEmpty) return;
    final combined = _capBuffer(_text + _pending.toString());
    _pending.clear();
    setState(() => _text = combined);
    if (_autoScroll) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.jumpTo(_scroll.position.maxScrollExtent);
        }
      });
    }
  }

  /// Keeps only the tail of the log, trimming from the head to stay within the
  /// character and line caps.
  static String _capBuffer(String text) {
    var result = text;
    if (result.length > _maxChars) {
      result = result.substring(result.length - _maxChars);
    }
    final newlines = '\n'.allMatches(result).length;
    if (newlines > _maxLines) {
      var cut = 0;
      var toDrop = newlines - _maxLines;
      while (toDrop > 0) {
        final idx = result.indexOf('\n', cut);
        if (idx < 0) break;
        cut = idx + 1;
        toDrop--;
      }
      result = result.substring(cut);
    }
    return result;
  }

  @override
  void dispose() {
    _flushTimer?.cancel();
    _sub?.cancel();
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = _text;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Terminal',
          style: Theme.of(
            context,
          ).textTheme.titleSmall!.weight(FontWeight.w600),
        ),
        const SizedBox(height: AppSpacing.sm),
        Container(
          height: 220,
          width: double.infinity,
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: const Color(0xFF0A0B11),
            borderRadius: AppRadius.borderRadiusMd,
            border: Border.all(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
          child: text.isEmpty
              ? Center(
                  child: Text(
                    'No output yet. Run an action to see logs.',
                    // Pinned dark like the log body beside it: this panel is
                    // dark in both themes, and the theme-derived dim tone
                    // measured 3.73:1 on it in light mode. The dark dim tone
                    // clears AA at 5.30:1.
                    style: Theme.of(context).textTheme.bodySmall!.copyWith(
                      color: CupolaThemeColors.of(context).dimText,
                    ),
                  ),
                )
              : SingleChildScrollView(
                  controller: _scroll,
                  child: SelectableText(
                    text,
                    // Container logs are read in columns, so this goes through
                    // `.mono` rather than the 'monospace' alias that silently
                    // falls back to a proportional face on iOS/macOS.
                    // `bodySmall`'s 1.40 leading is what keeps a dense tail
                    // scannable. The panel behind it is permanently dark, so
                    // the foreground stays on the dark-theme variant tone.
                    style: Theme.of(context).textTheme.bodySmall!.mono.copyWith(
                      color: AppColors.onSurfaceVariantDark,
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}
