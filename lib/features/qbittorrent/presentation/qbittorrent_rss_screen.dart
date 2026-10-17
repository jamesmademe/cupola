import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/qbittorrent/domain/models/rss.dart';
import 'package:cupola/features/qbittorrent/presentation/qbittorrent_provider.dart';
import 'package:cupola/features/qbittorrent/presentation/qbittorrent_rss_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/connection_presentation.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// qBittorrent's RSS subscriptions and automatic-download rules.
///
/// The two endpoints are independent on purpose: an older or partially
/// restricted WebUI can answer the feed tree while refusing the rule list, and
/// losing the useful half would turn a capability gap into a blank page.
class QbittorrentRssScreen extends ConsumerWidget {
  const QbittorrentRssScreen({super.key, this.topPadding = 0});

  final double topPadding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final configured = ref
        .watch(currentSettingsProvider)
        .isServiceConfigured(ServiceKey.qbittorrent);
    if (!configured) {
      return NotConfiguredPlaceholder.forService(ServiceKey.qbittorrent);
    }

    final feeds = ref.watch(qbittorrentRssFeedsProvider);
    final rules = ref.watch(qbittorrentRssRulesProvider);
    return AmbientScaffold(
      accent: ServiceKey.qbittorrent.accent,
      body: RefreshIndicator(
        // Awaited, so the indicator stays down until both halves have
        // answered. Each failure is drawn by the section watching it, so
        // neither can escape as an unhandled rejection here.
        onRefresh: () async {
          clearQbittorrentLoginRefusal(ref);
          ref.invalidate(qbittorrentRssFeedsProvider);
          ref.invalidate(qbittorrentRssRulesProvider);
          await Future.wait([
            ref
                .read(qbittorrentRssFeedsProvider.future)
                .catchError((_) => const <QbittorrentRssFeed>[]),
            ref
                .read(qbittorrentRssRulesProvider.future)
                .catchError((_) => const <QbittorrentRssRule>[]),
          ]);
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(
            AppSpacing.lg,
            // Under the host's bands, the status bar the upper one consumes
            // included: nothing on this page takes the inset off first.
            topPadding + MediaQuery.paddingOf(context).top + AppSpacing.md,
            AppSpacing.lg,
            FloatingNavBarMetrics.getScrollViewBottomPadding(context),
          ),
          children: [
            SectionHeader.inset(
              title: 'Feeds',
              subtitle: feeds.hasValue ? '${feeds.requireValue.length}' : null,
              showChevron: false,
            ),
            const SizedBox(height: AppSpacing.sm),
            _FeedsSection(value: feeds),
            const SizedBox(height: AppSpacing.xl),
            SectionHeader.inset(
              title: 'Automatic download rules',
              subtitle: rules.hasValue ? '${rules.requireValue.length}' : null,
              showChevron: false,
            ),
            const SizedBox(height: AppSpacing.sm),
            _RulesSection(value: rules),
          ],
        ),
      ),
    );
  }
}

class _FeedsSection extends ConsumerWidget {
  const _FeedsSection({required this.value});

  final AsyncValue<List<QbittorrentRssFeed>> value;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return value.when(
      loading: () => const _LoadingRows(),
      error: (error, _) => InlineErrorRetry(
        message: sectionFailureMessage(
          ServiceKey.qbittorrent,
          error,
          consequence: 'the RSS feeds are not shown',
        ),
        error: error,
        service: ServiceKey.qbittorrent,
        onRetry: () {
          clearQbittorrentLoginRefusal(ref);
          ref.invalidate(qbittorrentRssFeedsProvider);
        },
      ),
      data: (feeds) {
        if (feeds.isEmpty) {
          return const AppEmptyState.compact(
            icon: Icons.rss_feed_rounded,
            title: 'No RSS feeds',
            message: 'Add a feed in qBittorrent to see it here.',
          );
        }
        return Column(
          children: [
            for (var i = 0; i < feeds.length; i++) ...[
              _FeedRow(feed: feeds[i]),
              if (i != feeds.length - 1) const SizedBox(height: AppSpacing.sm),
            ],
          ],
        );
      },
    );
  }
}

class _RulesSection extends ConsumerWidget {
  const _RulesSection({required this.value});

  final AsyncValue<List<QbittorrentRssRule>> value;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return value.when(
      loading: () => const _LoadingRows(count: 2),
      error: (error, _) => InlineErrorRetry(
        message: sectionFailureMessage(
          ServiceKey.qbittorrent,
          error,
          consequence: 'the RSS rules are not shown',
        ),
        error: error,
        service: ServiceKey.qbittorrent,
        onRetry: () {
          clearQbittorrentLoginRefusal(ref);
          ref.invalidate(qbittorrentRssRulesProvider);
        },
      ),
      data: (rules) {
        if (rules.isEmpty) {
          return const AppEmptyState.compact(
            icon: Icons.rule_folder_outlined,
            title: 'No automatic rules',
            message: 'RSS items will not be grabbed automatically.',
          );
        }
        return Column(
          children: [
            for (var i = 0; i < rules.length; i++) ...[
              _RuleRow(rule: rules[i]),
              if (i != rules.length - 1) const SizedBox(height: AppSpacing.sm),
            ],
          ],
        );
      },
    );
  }
}

class _FeedRow extends StatelessWidget {
  const _FeedRow({required this.feed});

  final QbittorrentRssFeed feed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = feed.hasError
        ? 'Fault'
        : feed.isLoading
        ? 'Updating'
        : 'Available';
    final tone = feed.hasError
        ? StatusTone.warning
        : feed.isLoading
        ? StatusTone.info
        : StatusTone.success;
    final color = statusToneColor(theme.colorScheme, tone);
    final detail = feed.url.trim().isEmpty ? '—' : feed.url.trim();
    final unread = feed.unreadCount;
    final spoken = [
      feed.displayName,
      state,
      unread == null ? 'unread count unavailable' : '$unread unread',
      detail,
    ].join(', ');

    return Semantics(
      container: true,
      label: spoken,
      child: ExcludeSemantics(
        child: AppCard.outlined(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              Icon(Icons.rss_feed_rounded, color: color),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      feed.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.rowTitle(theme.brightness),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      detail,
                      maxLines: 1,
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
                unread == null ? '—' : '$unread',
                style: AppTheme.data(theme.brightness).copyWith(color: color),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RuleRow extends StatelessWidget {
  const _RuleRow({required this.rule});

  final QbittorrentRssRule rule;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = statusToneColor(
      theme.colorScheme,
      rule.enabled ? StatusTone.success : StatusTone.neutral,
    );
    final category = rule.assignedCategory.trim().isEmpty
        ? 'No category'
        : rule.assignedCategory.trim();
    final match = rule.mustContain.trim().isEmpty
        ? 'Any title'
        : 'Contains ${rule.mustContain.trim()}';
    final state = rule.enabled ? 'Enabled' : 'Disabled';

    return Semantics(
      container: true,
      label:
          '${rule.name}, $state, $match, $category, '
          '${rule.affectedFeeds.length} feeds',
      child: ExcludeSemantics(
        child: AppCard.outlined(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              Icon(Icons.rule_rounded, color: color),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      rule.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.rowTitle(theme.brightness),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      '$match\u00A0· $category',
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

class _LoadingRows extends StatelessWidget {
  const _LoadingRows({this.count = 3});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < count; i++) ...[
          ShimmerPlaceholder.card(height: 72),
          if (i != count - 1) const SizedBox(height: AppSpacing.sm),
        ],
      ],
    );
  }
}
