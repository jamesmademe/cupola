import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/snack_bar_helper.dart';
import 'package:cupola/core/widgets/ambient_scaffold.dart';
import 'package:cupola/core/widgets/app_card.dart';
import 'package:cupola/core/widgets/app_dialog.dart';
import 'package:cupola/core/widgets/app_empty_state.dart';
import 'package:cupola/core/widgets/async_value_widget.dart';
import 'package:cupola/core/widgets/not_configured_placeholder.dart';
import 'package:cupola/core/widgets/section_header.dart';
import 'package:cupola/core/widgets/status_badge.dart';
import 'package:cupola/features/bazarr/domain/models/bazarr_models.dart';
import 'package:cupola/features/bazarr/presentation/bazarr_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// Bazarr's provider view, split between the aggregate configured count from
/// `/api/badges` and the status rows returned by `/api/providers`.
///
/// The latter is a throttle/degraded-status feed, not a complete provider
/// registry. The screen reports that boundary explicitly and never invents
/// healthy provider names, quotas or missing timing data.
class BazarrProvidersScreen extends ConsumerWidget {
  const BazarrProvidersScreen({super.key, this.topPadding = 0});

  final double topPadding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final configured = ref.watch(
      currentSettingsProvider.select(
        (settings) => settings.isServiceConfigured(ServiceKey.bazarr),
      ),
    );
    if (!configured) {
      return NotConfiguredPlaceholder.forService(ServiceKey.bazarr);
    }

    final summary = ref.watch(bazarrProviderSummaryProvider);
    return AmbientScaffold(
      accent: ServiceKey.bazarr.accent,
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(bazarrProviderSummaryProvider);
          ref.invalidate(bazarrProviderStatusesProvider);
          await Future.wait([
            ref.read(bazarrProviderSummaryProvider.future),
            ref.read(bazarrProviderStatusesProvider.future),
          ]);
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(
            AppSpacing.lg,
            topPadding + AppSpacing.md,
            AppSpacing.lg,
            AppSpacing.xxl,
          ),
          children: [
            SectionHeader(
              title: 'Providers',
              subtitle: _countLabel(summary),
              showChevron: false,
              semanticLabel: 'Providers, ${_countLabel(summary)}',
            ),
            const SizedBox(height: AppSpacing.sm),
            AsyncValueWidget<BazarrProviderSummary>(
              value: summary,
              serviceName: 'Bazarr providers',
              loadingLabel: 'Loading Bazarr provider summary',
              onRetry: () => ref.invalidate(bazarrProviderSummaryProvider),
              data: (value) => _ProviderSummaryCard(summary: value),
            ),
            const SizedBox(height: AppSpacing.lg),
            SectionHeader(
              title: 'Needs attention',
              subtitle: _statusCountLabel(
                ref.watch(bazarrProviderStatusesProvider),
              ),
              showChevron: false,
            ),
            const SizedBox(height: AppSpacing.sm),
            AsyncValueWidget<List<BazarrProviderStatus>>(
              value: ref.watch(bazarrProviderStatusesProvider),
              serviceName: 'Bazarr provider status',
              loadingLabel: 'Loading provider status',
              onRetry: () => ref.invalidate(bazarrProviderStatusesProvider),
              isEmpty: (items) => items.isEmpty,
              emptyBuilder: const AppEmptyState.inline(
                icon: Icons.check_circle_outline_rounded,
                title: 'No providers throttled',
              ),
              data: (items) => _ProviderStatusList(
                items: items,
                onReset: () => _confirmReset(context, ref, items.length),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _countLabel(AsyncValue<BazarrProviderSummary> value) {
    final count = value.asData?.value.configuredCount;
    return count == null ? '—' : '$count configured';
  }

  static String _statusCountLabel(
    AsyncValue<List<BazarrProviderStatus>> value,
  ) {
    final count = value.asData?.value.length;
    return count == null ? '—' : '$count';
  }

  /// Asks before the throttles are cleared.
  ///
  /// The button was the whole guard. Nothing is deleted, but the throttle is
  /// how Bazarr stops asking a provider that has told it to wait, and it
  /// cannot be put back once cleared — worth one question. [count] is the
  /// whole list on screen, not a sample of it.
  static Future<void> _confirmReset(
    BuildContext context,
    WidgetRef ref,
    int count,
  ) async {
    final providers = count == 1
        ? '1 throttled provider'
        : '$count throttled providers';
    final result = await showAppConfirmDialog(
      context: context,
      icon: Icons.refresh_rounded,
      title: 'Reset provider throttles?',
      message:
          'Bazarr stops waiting out $providers and asks them again on its '
          'next search. A provider still over its limit throttles again.',
      confirmLabel: 'Reset throttles',
    );
    if (!result.confirmed || !context.mounted) return;
    await _resetStatuses(context, ref);
  }

  static Future<void> _resetStatuses(
    BuildContext context,
    WidgetRef ref,
  ) async {
    try {
      await ref.read(bazarrServiceProvider).resetProviderStatuses();
      ref.invalidate(bazarrProviderStatusesProvider);
      if (context.mounted) {
        SnackBarHelper.success(context, 'Provider throttles reset');
      }
    } catch (error) {
      if (context.mounted) {
        SnackBarHelper.error(
          context,
          'Failed to reset provider throttles',
          detail: error,
        );
      }
    }
  }
}

class _ProviderSummaryCard extends StatelessWidget {
  const _ProviderSummaryCard({required this.summary});

  final BazarrProviderSummary summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final count = summary.configuredCount;
    final countLabel = count?.toString() ?? '—';
    final spoken = count == null
        ? 'Bazarr providers, configured count unavailable'
        : 'Bazarr providers, $count configured';

    return AppCard.outlined(
      padding: const EdgeInsets.all(AppSpacing.lg),
      semanticLabel: spoken,
      excludeChildSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ExcludeSemantics(
                child: Icon(
                  Icons.hub_outlined,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  'Configured providers',
                  style: AppTheme.panelHeader(theme.brightness),
                ),
              ),
              Text(
                countLabel,
                style: AppTheme.data(
                  theme.brightness,
                ).copyWith(color: ServiceKey.bazarr.accent),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            'Live provider status',
            style: AppTheme.rowTitle(theme.brightness),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Bazarr reports throttled providers separately. A clear list means no provider currently needs attention; it is not a claim that no providers are configured.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: CupolaThemeColors.of(context).dimText,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProviderStatusList extends StatelessWidget {
  const _ProviderStatusList({required this.items, required this.onReset});

  final List<BazarrProviderStatus> items;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var index = 0; index < items.length; index++) ...[
          _ProviderStatusCard(item: items[index]),
          if (index != items.length - 1) const SizedBox(height: AppSpacing.sm),
        ],
        const SizedBox(height: AppSpacing.md),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.tonalIcon(
            key: const ValueKey('bazarr-reset-provider-throttles'),
            onPressed: onReset,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Reset throttles'),
          ),
        ),
      ],
    );
  }
}

class _ProviderStatusCard extends StatelessWidget {
  const _ProviderStatusCard({required this.item});

  final BazarrProviderStatus item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = statusToneColor(
      theme.colorScheme,
      item.tone,
      surface: theme.colorScheme.surfaceContainer,
    );
    final sentence =
        '${item.displayName}, ${item.statusLabel}, retry ${item.retryLabel}';

    return AppCard.outlined(
      padding: const EdgeInsets.all(AppSpacing.md),
      semanticLabel: sentence,
      excludeChildSemantics: true,
      child: Row(
        children: [
          ExcludeSemantics(child: Icon(Icons.hub_outlined, color: color)),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.displayName,
                  style: AppTheme.rowTitle(theme.brightness),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  item.statusLabel,
                  style: theme.textTheme.bodySmall?.copyWith(color: color),
                ),
              ],
            ),
          ),
          Text(
            item.retryLabel,
            style: theme.textTheme.bodySmall?.copyWith(
              color: CupolaThemeColors.of(context).dimText,
            ),
          ),
        ],
      ),
    );
  }
}
