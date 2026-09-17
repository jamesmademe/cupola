import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/app_animation.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/readarr/domain/models/readarr_models.dart';
import 'package:cupola/features/readarr/presentation/readarr_provider.dart';
import 'package:cupola/features/readarr/presentation/widgets/readarr_tiles.dart';
import 'package:cupola/features/services/domain/service_tab.dart';
import 'package:cupola/features/services/presentation/service_kpi_provider.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// Readarr service dashboard: author overview, library KPIs and recent activity.
///
/// Readarr is archived upstream, so its v1 API is frozen — which is why
/// decision 13 makes full parity with the other three arrs a *fixed* target
/// rather than a moving one, and why "read-only for the first release" is a
/// gap in this screen rather than a boundary of the product.
///
/// What parity still needs, and none of it is UI work:
/// - `getAuthor(id)` — `readarr_service.dart` has `getAuthors()` and
///   `getRecentHistory()` and nothing else, so an author detail page has no
///   first fetch. `GET /api/v1/author/{id}`.
/// - a book list — `GET /api/v1/book` (optionally `?authorId=`), plus a
///   `ReadarrBook` model. Today `ReadarrAuthor` is the only library entity.
/// - the calendar — `GET /api/v1/calendar`, the same shape and the same
///   builder the other three arrs need and none of them calls yet.
/// - wanted and cutoff — `getMissingPage`/`getCutoffPage` already exist on the
///   shared base, so these are provider and screen work, not client work.
/// - the writes — `PUT /api/v1/author` for monitor and profile, `POST
///   /api/v1/command` for the searches, `DELETE /api/v1/author/{id}`, and the
///   manual-import routes.
///
/// The transport is settled: the standard *arr header-auth `ApiClient` and
/// `ArrActivityMixin` already cover queue, history, releases and blocklist.
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
            onTap: () => _goToTab(context, ServiceTab.library),
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

/// Switches to another of Readarr's tabs.
///
/// It was `context.push(ServiceRoutes.readarrLibrary)`, which was right while
/// the author list was a pushed page and is wrong now that it is a tab: a push
/// would stack the Library tab's root on the *Overview* branch, so the bar
/// would light Library over a shell whose index still said Overview, and back
/// would return here rather than to wherever Library had been left.
///
/// `goBranch` restores that branch's own stack instead, which is the whole of
/// "back returns to the tab you left". `maybeOf` rather than `of` because this
/// screen is also legitimately built outside a shell — a widget test, a
/// preview — where there is no branch to switch and the link does nothing
/// rather than throwing.
void _goToTab(BuildContext context, ServiceTab tab) {
  final tabs = tabsFor(ServiceKey.readarr);
  if (tabs == null) return;
  final index = tabs.indexOf(tab);
  if (index < 0) return;
  StatefulNavigationShell.maybeOf(context)?.goBranch(index);
}

void _invalidateAll(WidgetRef ref) {
  ref.invalidate(readarrAuthorsProvider);
  // And the rail's own non-swallowing read of it. See
  // `readarrKpiLibraryProvider`.
  ref.invalidate(readarrKpiLibraryProvider);
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
