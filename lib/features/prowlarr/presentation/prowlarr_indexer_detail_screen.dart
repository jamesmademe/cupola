import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/app_animation.dart';
import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/route_utils.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/core/widgets/app_error_state.dart';
import 'package:cupola/core/widgets/inline_error_retry.dart';
import 'package:cupola/core/widgets/not_configured_placeholder.dart';
import 'package:cupola/core/widgets/status_badge.dart';
import 'package:cupola/features/prowlarr/domain/models/prowlarr_models.dart';
import 'package:cupola/features/prowlarr/presentation/prowlarr_history_format.dart';
import 'package:cupola/features/prowlarr/presentation/prowlarr_indexer_actions.dart';
import 'package:cupola/features/prowlarr/presentation/prowlarr_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/connection_presentation.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

class ProwlarrIndexerDetailScreen extends ConsumerWidget {
  const ProwlarrIndexerDetailScreen({super.key, required this.indexerId});

  final int indexerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Before any provider: a deep link can land here with Prowlarr not set up,
    // and the service provider's "not configured" throw would read as "Failed
    // to load indexer" with a Retry that can never succeed.
    final configured = ref.watch(
      currentSettingsProvider.select(
        (settings) => settings.isServiceConfigured(ServiceKey.prowlarr),
      ),
    );
    if (!configured) {
      return Scaffold(
        appBar: AppBar(
          backgroundColor: ServiceKey.prowlarr.accent.withValues(alpha: 0.12),
          leading: IconButton(
            icon: const Icon(Icons.chevron_left_rounded),
            onPressed: () =>
                RouteUtils.popOrGo(context, ServiceRoutes.prowlarrIndexers),
            tooltip: 'Back',
          ),
          title: const Text('Indexer'),
        ),
        body: NotConfiguredPlaceholder.forService(ServiceKey.prowlarr),
      );
    }

    final indexerAsync = ref.watch(prowlarrIndexerByIdProvider(indexerId));

    return Scaffold(
      appBar: AppBar(
        backgroundColor: ServiceKey.prowlarr.accent.withValues(alpha: 0.12),
        leading: IconButton(
          icon: const Icon(Icons.chevron_left_rounded),
          onPressed: () =>
              RouteUtils.popOrGo(context, ServiceRoutes.prowlarrIndexers),
          tooltip: 'Back',
        ),
        title: Text(
          indexerAsync.maybeWhen(
            data: (indexer) => indexer?.name ?? 'Indexer',
            orElse: () => 'Indexer',
          ),
        ),
        actions: [
          indexerAsync.maybeWhen(
            data: (indexer) => indexer == null
                ? const SizedBox.shrink()
                : IconButton(
                    icon: const Icon(Icons.edit_outlined),
                    tooltip: 'Edit indexer',
                    onPressed: () => _edit(context, ref, indexer),
                  ),
            orElse: () => const SizedBox.shrink(),
          ),
        ],
      ),
      body: indexerAsync.when(
        data: (indexer) {
          if (indexer == null) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(AppSpacing.xl),
                child: Text('Indexer not found.'),
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(prowlarrIndexersProvider);
              ref.invalidate(prowlarrIndexerStatsProvider);
              ref.invalidate(prowlarrIndexerStatusProvider);
              ref.invalidate(prowlarrIndexerHistoryProvider(indexerId));
              await Future<void>.delayed(AppAnimation.durationMd);
            },
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              children: [
                _StatusBanner(indexerId: indexerId),
                _ActionRow(indexer: indexer),
                _InfoCard(indexer: indexer),
                const SizedBox(height: AppSpacing.sm),
                // The window, said out loud. These four figures are scoped to
                // `prowlarrStatsWindow` — an unlabelled "Queries 4812" reads as
                // a lifetime total and tells a self-hoster nothing about today.
                _SectionLabel(text: 'Last 24 hours'),
                _StatsSection(indexerId: indexerId),
                const SizedBox(height: AppSpacing.sm),
                _SectionLabel(text: 'Recent activity'),
                _IndexerHistory(indexerId: indexerId),
                const SizedBox(height: AppSpacing.xl),
              ],
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => AppErrorState(
          error: error,
          serviceName: ServiceKey.prowlarr.title,
          // The source, not the lookup: `prowlarrIndexerByIdProvider`
          // only re-reads the list, so invalidating it alone re-read
          // the list's cached failure and the Retry did nothing.
          onRetry: () => ref.invalidate(prowlarrIndexersProvider),
        ),
      ),
    );
  }
}

/// Opens the edit form; leaves the screen when the indexer ends up deleted.
Future<void> _edit(
  BuildContext context,
  WidgetRef ref,
  ProwlarrIndexer indexer,
) async {
  final deleted = await editIndexerFlow(context, ref, indexer);
  if (deleted && context.mounted) {
    RouteUtils.popOrGo(context, ServiceRoutes.prowlarrIndexers);
  }
}

/// Per-indexer write actions, matching what the web UI offers on an indexer.
class _ActionRow extends ConsumerWidget {
  const _ActionRow({required this.indexer});

  final ProwlarrIndexer indexer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      child: Row(
        children: [
          Expanded(
            child: FilledButton.icon(
              onPressed: () => testIndexerFlow(context, ref, indexer),
              icon: const Icon(Icons.network_check_rounded, size: 18),
              label: const Text('Test'),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => toggleIndexerFlow(context, ref, indexer),
              icon: Icon(
                indexer.enable
                    ? Icons.pause_circle_outline_rounded
                    : Icons.play_circle_outline_rounded,
                size: 18,
              ),
              label: Text(indexer.enable ? 'Disable' : 'Enable'),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          IconButton.filled(
            onPressed: () async {
              final deleted = await deleteIndexerFlow(context, ref, indexer);
              if (deleted && context.mounted) {
                RouteUtils.popOrGo(context, ServiceRoutes.prowlarrIndexers);
              }
            },
            icon: const Icon(Icons.delete_outline_rounded, size: 18),
            tooltip: 'Delete indexer',
            // Neutral: the theme's own filled icon button. Red means
            // unreachable and nothing else.
          ),
        ],
      ),
    );
  }
}

class _StatusBanner extends ConsumerWidget {
  const _StatusBanner({required this.indexerId});

  final int indexerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statusAsync = ref.watch(prowlarrIndexerStatusByIdProvider(indexerId));
    return statusAsync.maybeWhen(
      data: (status) {
        if (status == null) return const SizedBox.shrink();
        final colorScheme = Theme.of(context).colorScheme;
        final until = status.disabledTill;
        return Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            0,
            AppSpacing.lg,
            AppSpacing.sm,
          ),
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            // A tonal card, not an alarm. The fill and border were the raw
            // `AppColors.warning` at 0.1 and 0.4 — the chrome the app reserves
            // for a service that did not answer — around a fact Prowlarr
            // answered perfectly well: one of its indexers is failing. The
            // icon and the ink carry the tone; the container stays quiet.
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
              borderRadius: AppRadius.borderRadiusMd,
              border: Border.all(color: colorScheme.outlineVariant),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.error_outline_rounded,
                  size: 18,
                  color: statusToneColor(
                    colorScheme,
                    StatusTone.warning,
                    // The tone lands on an elevated container, not on the page
                    // ground — only this caller knows that.
                    surface: colorScheme.surfaceContainerHighest,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    until != null
                        ? 'Disabled due to failures until $until'
                        : 'Indexer is currently failing',
                    style: Theme.of(context).textTheme.bodySmall,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        );
      },
      orElse: () => const SizedBox.shrink(),
    );
  }
}

class _InfoCard extends ConsumerWidget {
  const _InfoCard({required this.indexer});

  final ProwlarrIndexer indexer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final tagLabels = ref.watch(prowlarrTagLabelsProvider);
    final profiles = ref.watch(prowlarrAppProfilesProvider).asData?.value;
    final profileName = profiles
        ?.where((profile) => profile.id == indexer.appProfileId)
        .map((profile) => profile.name)
        .whereType<String>()
        .firstOrNull;
    final tags = indexer.tags
        .map((id) => tagLabels[id] ?? '#$id')
        .toList(growable: false);

    final rows = <(String, String)>[
      ('Status', indexer.enable ? 'Enabled' : 'Disabled'),
      if (indexer.protocol != null) ('Protocol', indexer.protocol!),
      if (indexer.privacy != null) ('Privacy', indexer.privacy!),
      if (indexer.language != null) ('Language', indexer.language!),
      if (indexer.priority != null) ('Priority', '${indexer.priority}'),
      if (profileName != null) ('Sync profile', profileName),
      ('RSS', indexer.supportsRss ? 'Yes' : 'No'),
      ('Search', indexer.supportsSearch ? 'Yes' : 'No'),
      if (indexer.supportsRedirect)
        ('Redirect', indexer.redirect ? 'On' : 'Off'),
      if (tags.isNotEmpty) ('Tags', tags.join(', ')),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: AppRadius.borderRadiusMd,
          border: Border.all(color: colorScheme.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (indexer.description != null) ...[
              Text(
                indexer.description!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const Divider(height: 20),
            ],
            for (final row in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      row.$1,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      row.$2,
                      style: Theme.of(
                        context,
                      ).textTheme.bodyMedium!.weight(FontWeight.w600),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _StatsSection extends ConsumerWidget {
  const _StatsSection({required this.indexerId});

  final int indexerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statAsync = ref.watch(prowlarrIndexerStatByIdProvider(indexerId));
    return statAsync.maybeWhen(
      data: (stat) {
        if (stat == null) {
          // Prowlarr answered and this indexer was simply not in the window —
          // a real reading of zero activity, not a figure the app is missing.
          return const Padding(
            padding: EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.xs,
            ),
            child: Text('No queries in the last 24 hours.'),
          );
        }
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: Row(
            children: [
              _StatTile(
                label: 'Queries',
                value: '${stat.numberOfQueries}',
                icon: Icons.search_rounded,
              ),
              const SizedBox(width: AppSpacing.sm),
              _StatTile(
                label: 'Grabs',
                value: '${stat.numberOfGrabs}',
                icon: Icons.download_rounded,
              ),
              const SizedBox(width: AppSpacing.sm),
              _StatTile(
                label: 'Fails',
                value: '${stat.numberOfFailures}',
                icon: Icons.error_outline_rounded,
                accent: stat.numberOfFailures > 0
                    ? statusToneColor(
                        Theme.of(context).colorScheme,
                        StatusTone.warning,
                      )
                    : null,
              ),
              const SizedBox(width: AppSpacing.sm),
              _StatTile(
                label: 'Resp',
                value: '${stat.averageResponseTime}ms',
                icon: Icons.timer_outlined,
              ),
            ],
          ),
        );
      },
      orElse: () => const SizedBox.shrink(),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.label,
    required this.value,
    required this.icon,
    this.accent,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final color = accent ?? colorScheme.onSurfaceVariant;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(
          vertical: AppSpacing.md,
          horizontal: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: AppRadius.borderRadiusMd,
          border: Border.all(color: colorScheme.outlineVariant),
        ),
        child: Column(
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(height: 6),
            Text(
              value,
              // Query/grab/failure counts and the response time all refresh in
              // place, so the digits get a fixed advance.
              style: Theme.of(
                context,
              ).textTheme.titleSmall!.weight(FontWeight.w600).tabular,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.xs,
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.titleSmall!.weight(FontWeight.w600),
      ),
    );
  }
}

class _IndexerHistory extends ConsumerWidget {
  const _IndexerHistory({required this.indexerId});

  final int indexerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyAsync = ref.watch(prowlarrIndexerHistoryProvider(indexerId));
    return historyAsync.when(
      data: (items) {
        if (items.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.sm,
            ),
            child: Text('No recent activity for this indexer.'),
          );
        }
        return Column(
          children: items
              .take(15)
              .map((item) => _HistoryRow(item: item))
              .toList(),
        );
      },
      loading: () => const Padding(
        padding: EdgeInsets.all(AppSpacing.lg),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => InlineErrorRetry(
        message: sectionFailureMessage(
          ServiceKey.prowlarr,
          error,
          consequence: 'its activity is not shown',
        ),
        error: error,
        onRetry: () =>
            ref.invalidate(prowlarrIndexerHistoryProvider(indexerId)),
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.item});

  final ProwlarrHistoryItem item;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final event = prowlarrEventStyle(item, colorScheme);
    final title = prowlarrHistoryTitle(item);

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.xs,
      ),
      child: Container(
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: AppRadius.borderRadiusMd,
          border: Border.all(color: colorScheme.outlineVariant),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(
                      context,
                    ).textTheme.titleSmall!.weight(FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (item.date != null)
                    Text(
                      prowlarrRelativeTime(item.date!),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: event.color.withValues(alpha: 0.12),
                borderRadius: AppRadius.borderRadiusSm,
              ),
              child: Text(
                event.label,
                style: Theme.of(context).textTheme.labelSmall!
                    .weight(FontWeight.w600)
                    .copyWith(color: event.color),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
