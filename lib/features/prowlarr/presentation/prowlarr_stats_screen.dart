import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/unit_space.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/prowlarr/domain/models/prowlarr_models.dart';
import 'package:cupola/features/prowlarr/presentation/prowlarr_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// Per-indexer Prowlarr statistics over a bounded, user-selectable window.
class ProwlarrStatsScreen extends ConsumerStatefulWidget {
  const ProwlarrStatsScreen({super.key, this.topPadding = 0});

  final double topPadding;

  @override
  ConsumerState<ProwlarrStatsScreen> createState() =>
      _ProwlarrStatsScreenState();
}

class _ProwlarrStatsScreenState extends ConsumerState<ProwlarrStatsScreen> {
  ProwlarrStatsWindow _window = ProwlarrStatsWindow.day;

  @override
  Widget build(BuildContext context) {
    final configured = ref
        .watch(currentSettingsProvider)
        .isServiceConfigured(ServiceKey.prowlarr);
    if (!configured) {
      return NotConfiguredPlaceholder.forService(ServiceKey.prowlarr);
    }

    final stats = ref.watch(prowlarrIndexerStatsForWindowProvider(_window));
    final page = AsyncValueWidget<ProwlarrIndexerStats>(
      value: stats,
      serviceName: 'Prowlarr stats',
      onRetry: () =>
          ref.invalidate(prowlarrIndexerStatsForWindowProvider(_window)),
      isEmpty: (value) => value.indexers.isEmpty,
      emptyBuilder: const AppEmptyStatePage(
        emptyState: AppEmptyState(
          icon: Icons.query_stats_rounded,
          title: 'No indexer activity',
          message: 'Prowlarr reported no indexer statistics for this window.',
        ),
      ),
      data: (value) => _StatsBody(
        stats: value,
        // The await is what keeps the indicator down until the answer
        // is in, and the catch is what stops a dark Prowlarr turning
        // that into an unhandled rejection inside `RefreshIndicator`.
        // The failure is not swallowed: `AsyncValueWidget` above is
        // watching the same provider and draws the band.
        onRefresh: () async {
          ref.invalidate(prowlarrIndexerStatsForWindowProvider(_window));
          try {
            await ref.read(
              prowlarrIndexerStatsForWindowProvider(_window).future,
            );
          } catch (_) {
            // Reported by the widget watching the provider.
          }
        },
      ),
    );
    return Scaffold(
      body: Column(
        children: [
          // The host's two bands and the status bar the upper one consumes:
          // no `SafeArea` and no app bar on this page takes the inset first.
          SizedBox(
            height: widget.topPadding + MediaQuery.paddingOf(context).top,
          ),
          SelectionPills<ProwlarrStatsWindow>(
            values: ProwlarrStatsWindow.values,
            selected: _window,
            labelBuilder: (value) => value.label,
            onSelected: (value) => setState(() => _window = value),
          ),
          Expanded(
            child: stats.hasError && !stats.hasValue
                ? AppScrollablePage(child: page)
                : page,
          ),
        ],
      ),
    );
  }
}

class _StatsBody extends StatelessWidget {
  const _StatsBody({required this.stats, required this.onRefresh});

  final ProwlarrIndexerStats stats;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final rows = [...stats.indexers]
      ..sort((a, b) {
        final failures = b.numberOfFailures.compareTo(a.numberOfFailures);
        return failures != 0
            ? failures
            : b.numberOfQueries.compareTo(a.numberOfQueries);
      });

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.sm,
          AppSpacing.lg,
          FloatingNavBarMetrics.getScrollViewBottomPadding(context),
        ),
        children: [
          _Totals(stats: stats),
          const SizedBox(height: AppSpacing.lg),
          for (var i = 0; i < rows.length; i++) ...[
            _IndexerStatsRow(stat: rows[i]),
            if (i != rows.length - 1) const SizedBox(height: AppSpacing.sm),
          ],
        ],
      ),
    );
  }
}

class _Totals extends StatelessWidget {
  const _Totals({required this.stats});

  final ProwlarrIndexerStats stats;

  @override
  Widget build(BuildContext context) {
    return AppCard.filled(
      accentColor: ServiceKey.prowlarr.accent,
      child: Wrap(
        spacing: AppSpacing.xl,
        runSpacing: AppSpacing.md,
        children: [
          _Total(label: 'Queries', value: stats.totalQueries),
          _Total(label: 'Grabs', value: stats.totalGrabs),
          _Total(label: 'Failures', value: stats.totalFailures),
        ],
      ),
    );
  }
}

class _Total extends StatelessWidget {
  const _Total({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      label: '$label, $value',
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$value',
              style: AppTheme.data(
                theme.brightness,
              ).copyWith(color: theme.colorScheme.onSurface),
            ),
            Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: CupolaThemeColors.of(context).dimText,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _IndexerStatsRow extends StatelessWidget {
  const _IndexerStatsRow({required this.stat});

  final ProwlarrIndexerStat stat;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasFailures = stat.numberOfFailures > 0;
    final failureColor = statusToneColor(
      theme.colorScheme,
      hasFailures ? StatusTone.warning : StatusTone.neutral,
    );
    final name = stat.indexerName?.trim().isNotEmpty == true
        ? stat.indexerName!.trim()
        : 'Indexer ${stat.indexerId}';
    final spoken =
        '$name, ${stat.numberOfQueries} queries, ${stat.numberOfGrabs} grabs, '
        '${stat.numberOfFailures} failures, ${stat.averageResponseTime} milliseconds average response';

    return Semantics(
      container: true,
      label: spoken,
      child: ExcludeSemantics(
        child: AppCard.outlined(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.rowTitle(theme.brightness),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      '${withUnit(stat.averageResponseTime, 'ms')} average response',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: CupolaThemeColors.of(context).dimText,
                      ),
                    ),
                  ],
                ),
              ),
              _Metric(label: 'Q', value: stat.numberOfQueries),
              const SizedBox(width: AppSpacing.md),
              _Metric(label: 'G', value: stat.numberOfGrabs),
              const SizedBox(width: AppSpacing.md),
              _Metric(
                label: 'F',
                value: stat.numberOfFailures,
                color: failureColor,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value, this.color});

  final String label;
  final int value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Text(
          '$value',
          style: AppTheme.data(
            theme.brightness,
          ).copyWith(color: color ?? theme.colorScheme.onSurface),
        ),
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: CupolaThemeColors.of(context).dimText,
          ),
        ),
      ],
    );
  }
}
