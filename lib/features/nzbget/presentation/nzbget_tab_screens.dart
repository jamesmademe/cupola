import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/unit_space.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/activity/presentation/widgets/activity_formatters.dart';
import 'package:cupola/features/nzbget/domain/models/nzbget_models.dart';
import 'package:cupola/features/nzbget/presentation/nzbget_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

class NzbgetHistoryScreen extends ConsumerWidget {
  const NzbgetHistoryScreen({super.key, this.topPadding = 0});

  final double topPadding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!_isConfigured(ref)) return _notConfigured();
    return ServiceListPage<NzbgetHistoryItem>.unsummarised(
      service: ServiceKey.nzbget,
      // The host's two bands and the status bar the upper one consumes.
      topPadding: topPadding + MediaQuery.paddingOf(context).top,
      value: ref.watch(nzbgetHistoryProvider),
      serviceName: 'NZBGet history',
      emptyIcon: Icons.history_rounded,
      emptyTitle: 'No download history',
      emptyMessage: 'Completed and failed jobs will appear here.',
      onRetry: () => ref.invalidate(nzbgetHistoryProvider),
      rowBuilder: (item) => _HistoryRow(item: item),
    );
  }
}

class NzbgetFeedsScreen extends ConsumerWidget {
  const NzbgetFeedsScreen({super.key, this.topPadding = 0});

  final double topPadding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!_isConfigured(ref)) return _notConfigured();
    return ServiceListPage<NzbgetFeed>.unsummarised(
      service: ServiceKey.nzbget,
      // The host's two bands and the status bar the upper one consumes.
      topPadding: topPadding + MediaQuery.paddingOf(context).top,
      value: ref.watch(nzbgetFeedsProvider),
      serviceName: 'NZBGet feeds',
      emptyIcon: Icons.rss_feed_rounded,
      emptyTitle: 'No configured feeds',
      emptyMessage: 'Add an RSS feed in NZBGet to see it here.',
      onRetry: () => ref.invalidate(nzbgetFeedsProvider),
      rowBuilder: (feed) => _FeedRow(feed: feed),
    );
  }
}

class NzbgetMessagesScreen extends ConsumerWidget {
  const NzbgetMessagesScreen({super.key, this.topPadding = 0});

  final double topPadding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!_isConfigured(ref)) return _notConfigured();
    return ServiceListPage<NzbgetMessage>.unsummarised(
      service: ServiceKey.nzbget,
      // The host's two bands and the status bar the upper one consumes.
      topPadding: topPadding + MediaQuery.paddingOf(context).top,
      value: ref.watch(nzbgetMessagesProvider),
      serviceName: 'NZBGet messages',
      emptyIcon: Icons.notes_rounded,
      emptyTitle: 'No messages',
      emptyMessage: 'NZBGet returned an empty screen log.',
      onRetry: () => ref.invalidate(nzbgetMessagesProvider),
      rowBuilder: (message) => _MessageRow(message: message),
    );
  }
}

bool _isConfigured(WidgetRef ref) =>
    ref.watch(currentSettingsProvider).isServiceConfigured(ServiceKey.nzbget);

Widget _notConfigured() =>
    NotConfiguredPlaceholder.forService(ServiceKey.nzbget);

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.item});

  final NzbgetHistoryItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tone = item.failed
        ? StatusTone.warning
        : item.success
        ? StatusTone.success
        : StatusTone.neutral;
    final color = statusToneColor(theme.colorScheme, tone);
    final category = item.category.trim().isEmpty
        ? 'No category'
        : item.category;
    final when = formatDateTimeStamp(item.time);
    return _NzbgetRow(
      icon: item.failed
          ? Icons.error_outline_rounded
          : Icons.download_done_rounded,
      color: color,
      title: item.name,
      detail: '$category · $when',
      trailing: item.status.isEmpty ? '—' : item.status,
      semanticLabel:
          '${item.name}, ${item.status.isEmpty ? 'status unavailable' : item.status}, '
          '$category, $when',
    );
  }
}

class _FeedRow extends StatelessWidget {
  const _FeedRow({required this.feed});

  final NzbgetFeed feed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = statusToneColor(theme.colorScheme, StatusTone.info);
    final name = feed.name.trim().isEmpty ? 'Feed ${feed.index}' : feed.name;
    final category = feed.category.trim().isEmpty
        ? 'No category'
        : feed.category.trim();
    final interval = feed.intervalMinutes > 0
        ? 'Every ${withUnit(feed.intervalMinutes, 'min')}'
        : 'Manual refresh';
    return _NzbgetRow(
      icon: Icons.rss_feed_rounded,
      color: color,
      title: name,
      detail: '$interval · $category',
      trailing: feed.pauseNzb ? 'Added stopped' : 'Active',
      semanticLabel:
          '$name, $interval, $category, '
          '${feed.pauseNzb ? 'added stopped' : 'active'}',
    );
  }
}

class _MessageRow extends StatelessWidget {
  const _MessageRow({required this.message});

  final NzbgetMessage message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tone = message.isFault ? StatusTone.warning : StatusTone.neutral;
    final color = statusToneColor(theme.colorScheme, tone);
    final kind = message.kind.trim().isEmpty ? 'Message' : message.kind.trim();
    final when = formatDateTimeStamp(message.time);
    return _NzbgetRow(
      icon: message.isFault ? Icons.warning_amber_rounded : Icons.notes_rounded,
      color: color,
      title: message.text.trim().isEmpty ? '—' : message.text.trim(),
      detail: when,
      trailing: kind,
      semanticLabel:
          '$kind, ${message.text.trim().isEmpty ? 'message unavailable' : message.text.trim()}, $when',
    );
  }
}

class _NzbgetRow extends StatelessWidget {
  const _NzbgetRow({
    required this.icon,
    required this.color,
    required this.title,
    required this.detail,
    required this.trailing,
    required this.semanticLabel,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String detail;
  final String trailing;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      container: true,
      label: semanticLabel,
      child: ExcludeSemantics(
        child: AppCard.outlined(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              Icon(icon, color: color),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.rowTitle(theme.brightness),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      detail,
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
                  trailing,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: theme.textTheme.labelSmall
                      ?.weight(FontWeight.w600)
                      .copyWith(color: color),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
