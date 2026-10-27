import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/status/lexicon.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/dot_separator.dart';
import 'package:cupola/core/utils/snack_bar_helper.dart';
import 'package:cupola/core/widgets/ambient_scaffold.dart';
import 'package:cupola/core/widgets/app_card.dart';
import 'package:cupola/core/widgets/app_dialog.dart';
import 'package:cupola/core/widgets/app_empty_state.dart';
import 'package:cupola/core/widgets/async_value_widget.dart';
import 'package:cupola/core/widgets/not_configured_placeholder.dart';
import 'package:cupola/core/widgets/section_header.dart';
import 'package:cupola/core/widgets/status_badge.dart';
import 'package:cupola/core/widgets/floating_bottom_nav_bar.dart';
import 'package:cupola/features/bazarr/domain/models/bazarr_models.dart';
import 'package:cupola/features/bazarr/presentation/bazarr_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// Bazarr's providers: every one it has enabled, ready or waited out, from
/// `/api/providers`, with the reason and the time Bazarr asks a throttled one
/// again. A Bazarr with none enabled finds no subtitle, and the page says so.
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

    final providers = ref.watch(bazarrProviderStatusesProvider);
    return AmbientScaffold(
      accent: ServiceKey.bazarr.accent,
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(bazarrProviderStatusesProvider);
          await ref.read(bazarrProviderStatusesProvider.future);
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          // No side inset here: the header carries its own, and the rows
          // take theirs below.
          padding: EdgeInsets.only(
            // Under the host's bands, the status bar the upper one consumes
            // included: nothing on this page takes the inset off first.
            top: topPadding + MediaQuery.paddingOf(context).top + AppSpacing.md,
            bottom: FloatingNavBarMetrics.getScrollViewBottomPadding(context),
          ),
          children: [
            SectionHeader(
              title: 'Providers',
              subtitle: _countLabel(providers),
              showChevron: false,
            ),
            const SizedBox(height: AppSpacing.sm),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: AsyncValueWidget<List<BazarrProviderStatus>>(
                value: providers,
                serviceName: 'Bazarr providers',
                silentService: ServiceKey.bazarr,
                loadingLabel: 'Loading Bazarr providers',
                onRetry: () => ref.invalidate(bazarrProviderStatusesProvider),
                isEmpty: (items) => items.isEmpty,
                emptyBuilder: const AppEmptyState.inline(
                  icon: Icons.subtitles_off_outlined,
                  title: 'No providers enabled',
                  message:
                      'Bazarr finds no subtitles until one is enabled in '
                      'Bazarr → Settings → Providers.',
                ),
                data: (items) => _ProviderStatusList(
                  items: items,
                  onReset: () => _confirmReset(
                    context,
                    ref,
                    items.where((item) => item.throttled).length,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// `4 enabled · 1 throttled`, or an em dash until Bazarr answers.
  static String _countLabel(AsyncValue<List<BazarrProviderStatus>> value) {
    final items = value.asData?.value;
    if (items == null) return Lexicon.noFigure;
    final throttled = items.where((item) => item.throttled).length;
    return [
      '${items.length} enabled',
      if (throttled > 0) '$throttled throttled',
    ].join(dotSeparator);
  }

  /// Asks before the throttles are cleared.
  ///
  /// The button was the whole guard. Nothing is deleted, but the throttle is
  /// how Bazarr stops asking a provider that has told it to wait, and it
  /// cannot be put back once cleared: worth one question. [count] is the
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
      enterConfirms: true,
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
          'Could not reset provider throttles',
          detail: error,
        );
      }
    }
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
        // Only while Bazarr waits one out: clearing nothing is no control.
        if (items.any((item) => item.throttled)) ...[
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
    final retry = item.throttled ? item.retryLabel : null;
    final sentence = [
      item.displayName,
      item.statusLabel,
      if (retry != null) 'asks again $retry',
    ].join(', ');

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
          if (retry != null)
            Text(
              retry,
              style: theme.textTheme.bodySmall?.copyWith(
                color: CupolaThemeColors.of(context).dimText,
              ),
            ),
        ],
      ),
    );
  }
}
