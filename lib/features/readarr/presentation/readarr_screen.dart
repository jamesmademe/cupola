import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/app_animation.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/readarr/domain/models/readarr_models.dart';
import 'package:cupola/features/readarr/presentation/readarr_provider.dart';
import 'package:cupola/features/readarr/presentation/widgets/readarr_tiles.dart';
import 'package:cupola/features/services/presentation/service_kpi_provider.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// Readarr service dashboard: author overview, library KPIs and recent activity.
/// Read-only for the first release. Readarr is archived upstream but its v1 API
/// still works, so the standard *arr header-auth pattern applies.
class ReadarrScreen extends ConsumerWidget {
  const ReadarrScreen({super.key, this.showAppBar = true, this.topPadding = 0});

  final bool showAppBar;
  final double topPadding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(currentSettingsProvider);
    final isConfigured = settings.isServiceConfigured(ServiceKey.readarr);

    return AmbientScaffold(
      accent: AppColors.readarr,
      appBar: showAppBar ? const GlassAppBar(title: Text('Readarr')) : null,
      body: SafeArea(
        // The shared placeholder, not a private copy — see the note on the
        // Unraid dashboard, which had grown the same widget independently.
        child: isConfigured
            ? _ReadarrDashboard(topPadding: topPadding)
            : NotConfiguredPlaceholder.forService(ServiceKey.readarr),
      ),
    );
  }
}

class _ReadarrDashboard extends ConsumerWidget {
  const _ReadarrDashboard({required this.topPadding});

  final double topPadding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authorsAsync = ref.watch(readarrAuthorsProvider);
    final historyAsync = ref.watch(readarrRecentHistoryProvider);
    final summaryAsync = ref.watch(serviceSummaryProvider(ServiceKey.readarr));
    final isOffline = summaryAsync.maybeWhen(
      data: (summary) => !summary.isOnline,
      orElse: () => false,
    );

    if (isOffline) {
      return ServiceOfflineState(
        serviceName: ServiceKey.readarr.title,
        accent: AppColors.readarr,
        onRetry: () => _invalidateAll(ref),
      );
    }

    return RefreshIndicator(
      onRefresh: () async {
        _invalidateAll(ref);
        await Future<void>.delayed(AppAnimation.durationMd);
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.only(
          bottom: FloatingNavBarMetrics.getScrollViewBottomPadding(context),
        ),
        children: [
          if (topPadding > 0) SizedBox(height: topPadding),
          ServiceKpiPeek(
            kpis: ref.watch(serviceKpiProvider(ServiceKey.readarr)),
            accent: AppColors.readarr,
          ),
          const SizedBox(height: AppSpacing.sm),
          SectionHeader(
            title: 'Authors',
            showChevron: true,
            onTap: () => context.push(ServiceRoutes.readarrLibrary),
          ),
          const SizedBox(height: 2),
          _AuthorPreview(authorsAsync: authorsAsync),
          const SizedBox(height: AppSpacing.sm),
          const SectionHeader(title: 'Recent Activity', showChevron: false),
          const SizedBox(height: 2),
          _HistoryList(historyAsync: historyAsync),
        ],
      ),
    );
  }
}

void _invalidateAll(WidgetRef ref) {
  ref.invalidate(readarrAuthorsProvider);
  ref.invalidate(readarrRecentHistoryProvider);
  ref.invalidate(readarrQueueProvider);
  ref.invalidate(serviceKpiProvider(ServiceKey.readarr));
  ref.invalidate(serviceSummaryProvider(ServiceKey.readarr));
}

class _AuthorPreview extends ConsumerWidget {
  const _AuthorPreview({required this.authorsAsync});

  final AsyncValue<List<ReadarrAuthor>> authorsAsync;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return authorsAsync.when(
      data: (authors) {
        if (authors.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.md,
            ),
            child: Text('No authors in the library yet.'),
          );
        }
        final sorted = [...authors]
          ..sort(
            (a, b) => a.authorName.toLowerCase().compareTo(
              b.authorName.toLowerCase(),
            ),
          );
        return Column(
          children: sorted
              .take(5)
              .map((author) => ReadarrAuthorTile(author: author))
              .toList(),
        );
      },
      loading: () => const ListRowsShimmer(),
      error: (error, _) => InlineErrorRetry(
        message: 'Failed to load authors',
        onRetry: () => ref.invalidate(readarrAuthorsProvider),
      ),
    );
  }
}

class _HistoryList extends ConsumerWidget {
  const _HistoryList({required this.historyAsync});

  final AsyncValue<List<ReadarrHistoryItem>> historyAsync;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return historyAsync.when(
      data: (items) {
        if (items.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.md,
            ),
            child: Text('No recent activity yet.'),
          );
        }
        return Column(
          children: items
              .take(10)
              .map((item) => ReadarrHistoryTile(item: item))
              .toList(),
        );
      },
      loading: () => const ListRowsShimmer(),
      error: (error, _) => InlineErrorRetry(
        message: 'Failed to load recent activity',
        onRetry: () => ref.invalidate(readarrRecentHistoryProvider),
      ),
    );
  }
}
