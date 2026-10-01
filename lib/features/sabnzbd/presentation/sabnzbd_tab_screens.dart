import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/app_animation.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/byte_format.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/activity/presentation/widgets/activity_formatters.dart';
import 'package:cupola/features/sabnzbd/domain/models/sabnzbd_models.dart';
import 'package:cupola/features/sabnzbd/presentation/sabnzbd_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/connection_presentation.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

enum _SabnzbdHistoryFilter {
  all('All'),
  completed('Completed'),
  failed('Failed');

  const _SabnzbdHistoryFilter(this.label);

  final String label;
}

/// The recent window returned by SABnzbd's history endpoint.
///
/// The client currently requests twenty rows and the response model does not
/// carry a total. This screen therefore never calls the result "all history"
/// and never prints a total inferred from the page in hand.
class SabnzbdHistoryScreen extends ConsumerStatefulWidget {
  const SabnzbdHistoryScreen({super.key, this.topPadding = 0});

  final double topPadding;

  @override
  ConsumerState<SabnzbdHistoryScreen> createState() =>
      _SabnzbdHistoryScreenState();
}

class _SabnzbdHistoryScreenState extends ConsumerState<SabnzbdHistoryScreen> {
  _SabnzbdHistoryFilter _filter = _SabnzbdHistoryFilter.all;

  @override
  Widget build(BuildContext context) {
    final configured = ref.watch(
      currentSettingsProvider.select(
        (settings) => settings.isServiceConfigured(ServiceKey.sabnzbd),
      ),
    );
    if (!configured) {
      return NotConfiguredPlaceholder.forService(ServiceKey.sabnzbd);
    }

    final history = ref.watch(sabnzbdHistoryProvider);
    final page = AsyncValueWidget<List<SabnzbdHistorySlot>>(
      value: history,
      serviceName: 'SABnzbd history',
      loadingLabel: 'Loading recent SABnzbd history',
      onRetry: () => ref.invalidate(sabnzbdHistoryProvider),
      skeleton: const ListRowsShimmer(count: 6),
      data: _historyBody,
    );
    return AmbientScaffold(
      accent: ServiceKey.sabnzbd.accent,
      body: Column(
        children: [
          SizedBox(height: widget.topPadding),
          SelectionPills<_SabnzbdHistoryFilter>(
            values: _SabnzbdHistoryFilter.values,
            selected: _filter,
            labelBuilder: (filter) => filter.label,
            onSelected: (filter) => setState(() => _filter = filter),
          ),
          Expanded(
            child: history.hasValue ? page : AppScrollablePage(child: page),
          ),
        ],
      ),
    );
  }

  Widget _historyBody(List<SabnzbdHistorySlot> history) {
    final visible = switch (_filter) {
      _SabnzbdHistoryFilter.all => history,
      _SabnzbdHistoryFilter.completed =>
        history.where((item) => !item.failed).toList(growable: false),
      _SabnzbdHistoryFilter.failed =>
        history.where((item) => item.failed).toList(growable: false),
    };

    if (visible.isEmpty) {
      final filtered = _filter != _SabnzbdHistoryFilter.all;
      return AppEmptyStatePage(
        emptyState: AppEmptyState(
          icon: Icons.history_toggle_off_rounded,
          title: filtered
              ? 'No ${_filter.label.toLowerCase()} jobs'
              : 'No recent history',
          message: filtered
              ? 'The recent history window has no matching jobs.'
              : 'Completed and failed jobs will appear here.',
          accentColor: ServiceKey.sabnzbd.accent,
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(sabnzbdHistoryProvider);
        await Future<void>.delayed(AppAnimation.durationMd);
      },
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.sm,
          AppSpacing.lg,
          FloatingNavBarMetrics.getScrollViewBottomPadding(context),
        ),
        itemCount: visible.length,
        separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
        itemBuilder: (context, index) =>
            _SabnzbdHistoryRow(item: visible[index]),
      ),
    );
  }
}

class _SabnzbdHistoryRow extends StatelessWidget {
  const _SabnzbdHistoryRow({required this.item});

  final SabnzbdHistorySlot item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = item.status.trim();
    final completed = status.toLowerCase() == 'completed';
    final tone = item.failed
        ? StatusTone.warning
        : completed
        ? StatusTone.success
        : StatusTone.neutral;
    final toneColor = statusToneColor(
      theme.colorScheme,
      tone,
      surface: theme.colorScheme.surfaceContainer,
    );
    final category = item.category.trim().isEmpty
        ? 'No category'
        : item.category.trim();
    final when = formatDateTimeStamp(item.completed);
    final size = formatBytes(item.bytes);
    final failure = item.failMessage?.trim();
    final detail = [
      category,
      size,
      when,
      if (failure != null && failure.isNotEmpty) failure,
    ].join(' · ');
    final spokenStatus = status.isEmpty ? 'status unavailable' : status;
    final spokenWhen = item.completed == null
        ? 'completion time unavailable'
        : when;
    final spoken = [
      item.name,
      spokenStatus,
      category,
      size,
      spokenWhen,
      if (failure != null && failure.isNotEmpty) failure,
    ].join(', ');

    return Semantics(
      container: true,
      label: spoken,
      child: ExcludeSemantics(
        child: AppCard.outlined(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              Icon(
                item.failed
                    ? Icons.error_outline_rounded
                    : Icons.download_done_rounded,
                color: toneColor,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.rowTitle(theme.brightness),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      detail,
                      maxLines: failure == null ? 2 : 3,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: CupolaThemeColors.of(context).dimText,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Flexible(
                child: Text(
                  status.isEmpty ? '—' : status,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: theme.textTheme.labelSmall
                      ?.weight(FontWeight.w600)
                      .copyWith(color: toneColor),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// SABnzbd's configured news servers and the independent volume report.
///
/// Configuration and `server_stats` are separate API calls. Keeping them as
/// separate sections means a permission or payload problem in one never turns
/// valid data from the other into an empty page.
class SabnzbdServersScreen extends ConsumerWidget {
  const SabnzbdServersScreen({super.key, this.topPadding = 0});

  final double topPadding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final configured = ref.watch(
      currentSettingsProvider.select(
        (settings) => settings.isServiceConfigured(ServiceKey.sabnzbd),
      ),
    );
    if (!configured) {
      return NotConfiguredPlaceholder.forService(ServiceKey.sabnzbd);
    }

    final configs = ref.watch(sabnzbdServersProvider);
    final stats = ref.watch(sabnzbdServerStatsProvider);

    if (configs.hasError && stats.hasError) {
      return AmbientScaffold(
        accent: ServiceKey.sabnzbd.accent,
        body: Padding(
          padding: EdgeInsets.only(top: topPadding),
          child: AppErrorState(
            error: configs.error!,
            serviceName: 'SABnzbd servers',
            service: ServiceKey.sabnzbd,
            onRetry: () => _refresh(ref),
          ),
        ),
      );
    }

    return AmbientScaffold(
      accent: ServiceKey.sabnzbd.accent,
      body: RefreshIndicator(
        onRefresh: () async {
          _refresh(ref);
          await Future<void>.delayed(AppAnimation.durationMd);
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(
            0,
            topPadding,
            0,
            FloatingNavBarMetrics.getScrollViewBottomPadding(context),
          ),
          children: [
            const SectionHeader(
              title: 'Transfer volume',
              subtitle: 'As reported by SABnzbd',
              showChevron: false,
            ),
            const SizedBox(height: AppSpacing.sm),
            _StatsSection(value: stats, onRetry: () => _refreshStats(ref)),
            const SizedBox(height: AppSpacing.lg),
            const SectionHeader(
              title: 'Configured servers',
              subtitle: 'Credentials stay on the SABnzbd host',
              showChevron: false,
            ),
            const SizedBox(height: AppSpacing.sm),
            _ServerConfigSection(
              value: configs,
              onRetry: () => _refreshConfigs(ref),
            ),
          ],
        ),
      ),
    );
  }
}

void _refresh(WidgetRef ref) {
  _refreshConfigs(ref);
  _refreshStats(ref);
}

void _refreshConfigs(WidgetRef ref) => ref.invalidate(sabnzbdServersProvider);

void _refreshStats(WidgetRef ref) => ref.invalidate(sabnzbdServerStatsProvider);

class _StatsSection extends StatelessWidget {
  const _StatsSection({required this.value, required this.onRetry});

  final AsyncValue<SabnzbdServerStats> value;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => value.when(
    loading: () => const Padding(
      padding: EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: ServiceOverviewRowsSkeleton(rows: 3),
    ),
    error: (error, _) => InlineErrorRetry(
      message: sectionFailureMessage(
        ServiceKey.sabnzbd,
        error,
        consequence: 'the transfer volume is not shown',
      ),
      error: error,
      service: ServiceKey.sabnzbd,
      onRetry: onRetry,
    ),
    data: (stats) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppCard.filled(
            accentColor: ServiceKey.sabnzbd.accent,
            child: Wrap(
              spacing: AppSpacing.xl,
              runSpacing: AppSpacing.md,
              children: [
                _VolumeFigure(label: 'Today', value: stats.dayLabel),
                _VolumeFigure(label: 'This week', value: stats.weekLabel),
                _VolumeFigure(label: 'This month', value: stats.monthLabel),
                _VolumeFigure(label: 'All time', value: stats.totalLabel),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          if (stats.servers.isEmpty)
            const AppEmptyState.inline(
              icon: Icons.dns_outlined,
              title: 'No per-server usage reported',
              message: 'The aggregate volumes above are still valid.',
            )
          else
            for (var index = 0; index < stats.servers.length; index++) ...[
              _ServerUsageRow(usage: stats.servers[index]),
              if (index != stats.servers.length - 1)
                const SizedBox(height: AppSpacing.sm),
            ],
        ],
      ),
    ),
  );
}

class _VolumeFigure extends StatelessWidget {
  const _VolumeFigure({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      label: '$label, $value',
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value, style: AppTheme.data(theme.brightness)),
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

class _ServerUsageRow extends StatelessWidget {
  const _ServerUsageRow({required this.usage});

  final SabnzbdServerUsage usage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasFailures = usage.articlesFailed > 0;
    final hasTraffic = usage.articlesTried > 0;
    final tone = hasFailures
        ? StatusTone.warning
        : hasTraffic
        ? StatusTone.success
        : StatusTone.neutral;
    final color = statusToneColor(
      theme.colorScheme,
      tone,
      surface: theme.colorScheme.surfaceContainer,
    );
    final articleDetail = usage.articlesTried == 0
        ? 'No article attempts reported'
        : '${usage.articlesSucceeded} of ${usage.articlesTried} articles succeeded';
    final spoken =
        '${usage.name}, ${usage.totalLabel}, $articleDetail, '
        '${usage.articlesFailed} failed';

    return Semantics(
      container: true,
      label: spoken,
      child: ExcludeSemantics(
        child: AppCard.outlined(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              Icon(Icons.query_stats_rounded, color: color),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      usage.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.rowTitle(theme.brightness),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      articleDetail,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: CupolaThemeColors.of(context).dimText,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                usage.totalLabel,
                style: AppTheme.data(theme.brightness).copyWith(color: color),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ServerConfigSection extends StatelessWidget {
  const _ServerConfigSection({required this.value, required this.onRetry});

  final AsyncValue<List<SabnzbdServerConfig>> value;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => value.when(
    loading: () => const Padding(
      padding: EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: ServiceOverviewRowsSkeleton(rows: 3),
    ),
    error: (error, _) => InlineErrorRetry(
      message: sectionFailureMessage(
        ServiceKey.sabnzbd,
        error,
        consequence: 'its news servers are not shown',
      ),
      error: error,
      service: ServiceKey.sabnzbd,
      onRetry: onRetry,
    ),
    data: (servers) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: servers.isEmpty
          ? const AppEmptyState.inline(
              icon: Icons.dns_outlined,
              title: 'No configured servers',
              message: 'Add a news server in SABnzbd to see it here.',
            )
          : Column(
              children: [
                for (var index = 0; index < servers.length; index++) ...[
                  _ServerConfigRow(server: servers[index]),
                  if (index != servers.length - 1)
                    const SizedBox(height: AppSpacing.sm),
                ],
              ],
            ),
    ),
  );
}

class _ServerConfigRow extends StatelessWidget {
  const _ServerConfigRow({required this.server});

  final SabnzbdServerConfig server;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tone = server.enabled ? StatusTone.success : StatusTone.neutral;
    final color = statusToneColor(
      theme.colorScheme,
      tone,
      surface: theme.colorScheme.surfaceContainer,
    );
    final name = server.name.trim().isNotEmpty
        ? server.name.trim()
        : server.host.trim().isNotEmpty
        ? server.host.trim()
        : 'Unnamed server';
    final host = server.host.trim().isEmpty
        ? 'Host unavailable'
        : server.port > 0
        ? '${server.host.trim()}:${server.port}'
        : server.host.trim();
    final state = server.enabled ? 'Enabled' : 'Disabled';
    final transport = server.ssl ? 'TLS' : 'Plain connection';
    final optional = server.optional ? 'optional' : 'required';
    final detail =
        '$host · $transport · ${server.connections} connections · priority ${server.priority}';
    final spoken =
        '$name, $state, $host, $transport, ${server.connections} connections, '
        'priority ${server.priority}, $optional';

    return Semantics(
      container: true,
      label: spoken,
      child: ExcludeSemantics(
        child: AppCard.outlined(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              Icon(Icons.dns_rounded, color: color),
              const SizedBox(width: AppSpacing.md),
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
                      detail,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: CupolaThemeColors.of(context).dimText,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                state,
                style: theme.textTheme.labelSmall
                    ?.weight(FontWeight.w600)
                    .copyWith(color: color),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
