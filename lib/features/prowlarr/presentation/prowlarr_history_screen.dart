import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/prowlarr/domain/models/prowlarr_models.dart';
import 'package:cupola/features/prowlarr/presentation/prowlarr_history_format.dart';
import 'package:cupola/features/prowlarr/presentation/prowlarr_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

enum _HistoryFilter {
  all('All', null),
  queries('Queries', 'indexerQuery'),
  grabs('Grabs', 'releaseGrabbed'),
  rss('RSS', 'indexerRss'),
  auth('Auth', 'indexerAuth');

  const _HistoryFilter(this.label, this.eventType);

  final String label;
  final String? eventType;
}

/// Full, server-paged Prowlarr history.
///
/// The router hosts this below the service and tab bands, so the screen owns
/// only the page body. Filtering happens on the server: filtering a first page
/// locally would quietly hide matching records from later pages.
class ProwlarrHistoryScreen extends ConsumerStatefulWidget {
  const ProwlarrHistoryScreen({super.key, this.topPadding = 0});

  final double topPadding;

  @override
  ConsumerState<ProwlarrHistoryScreen> createState() =>
      _ProwlarrHistoryScreenState();
}

class _ProwlarrHistoryScreenState extends ConsumerState<ProwlarrHistoryScreen> {
  static const _pageSize = 50;

  _HistoryFilter _filter = _HistoryFilter.all;
  final List<ProwlarrHistoryItem> _items = [];
  int _page = 1;
  int? _total;
  bool _scheduled = false;
  bool _loading = false;
  bool _loadingMore = false;
  Object? _error;

  bool get _hasMore => _total != null && _items.length < _total!;

  Future<ProwlarrHistoryPage> _readPage(int page) {
    return ref.read(
      prowlarrHistoryPageProvider((
        page: page,
        pageSize: _pageSize,
        eventType: _filter.eventType,
      )).future,
    );
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
      _page = 1;
      _total = null;
    });
    try {
      final result = await _readPage(1);
      if (!mounted) return;
      setState(() {
        _items
          ..clear()
          ..addAll(result.records);
        _total = result.totalRecords;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    final nextPage = _page + 1;
    setState(() {
      _loadingMore = true;
      _error = null;
    });
    try {
      final result = await _readPage(nextPage);
      if (!mounted) return;
      setState(() {
        _items.addAll(result.records);
        _page = nextPage;
        _total = result.totalRecords;
        _loadingMore = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loadingMore = false;
      });
    }
  }

  void _select(_HistoryFilter filter) {
    if (_filter == filter) return;
    setState(() => _filter = filter);
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final configured = ref
        .watch(currentSettingsProvider)
        .isServiceConfigured(ServiceKey.prowlarr);
    if (!configured) {
      return NotConfiguredPlaceholder.forService(ServiceKey.prowlarr);
    }

    if (!_scheduled) {
      _scheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _reload());
    }

    return Scaffold(
      body: Column(
        children: [
          SizedBox(height: widget.topPadding),
          SelectionPills<_HistoryFilter>(
            values: _HistoryFilter.values,
            selected: _filter,
            labelBuilder: (value) => value.label,
            onSelected: _select,
            accent: ServiceKey.prowlarr.accent,
          ),
          Expanded(child: _body()),
        ],
      ),
    );
  }

  Widget _body() {
    if (_loading && _items.isEmpty) {
      return const ShimmerList.page(itemCount: 6);
    }
    if (_error != null && _items.isEmpty) {
      return AppErrorState(
        error: _error!,
        serviceName: 'Prowlarr history',
        onRetry: _reload,
      );
    }
    if (_items.isEmpty) {
      return AppEmptyStatePage(
        emptyState: AppEmptyState(
          icon: Icons.history_toggle_off_rounded,
          title: 'No history in this view',
          message: 'Prowlarr has no ${_filter.label.toLowerCase()} to show.',
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _reload,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.sm,
          AppSpacing.lg,
          FloatingNavBarMetrics.getScrollViewBottomPadding(context),
        ),
        itemCount: _items.length + 1,
        separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
        itemBuilder: (context, index) {
          if (index == _items.length) return _footer();
          return _ProwlarrHistoryRow(item: _items[index]);
        },
      ),
    );
  }

  Widget _footer() {
    final total = _total;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      child: Column(
        children: [
          Text(
            total == null
                ? '${_items.length} shown'
                : 'Showing ${_items.length} of $total',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: CupolaThemeColors.of(context).dimText,
            ),
          ),
          if (_error != null) ...[
            InlineErrorRetry(
              message: 'Could not load more history',
              onRetry: _loadMore,
            ),
          ] else if (_hasMore) ...[
            const SizedBox(height: AppSpacing.sm),
            OutlinedButton.icon(
              onPressed: _loadingMore ? null : _loadMore,
              icon: _loadingMore
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.expand_more_rounded),
              label: const Text('Load more'),
            ),
          ],
        ],
      ),
    );
  }
}

class _ProwlarrHistoryRow extends StatelessWidget {
  const _ProwlarrHistoryRow({required this.item});

  final ProwlarrHistoryItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = prowlarrEventStyle(item, theme.colorScheme);
    final title = prowlarrHistoryTitle(item);
    final source = prowlarrHistorySource(item);
    final when = item.date == null ? null : prowlarrRelativeTime(item.date!);
    final detail = [source, when].whereType<String>().join(' · ');
    final spoken = [
      title,
      style.label,
      source,
      when,
    ].whereType<String>().join(', ');

    return Semantics(
      container: true,
      label: spoken,
      child: ExcludeSemantics(
        child: AppCard.outlined(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              Icon(style.icon, color: style.color),
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
                    if (detail.isNotEmpty) ...[
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
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                style.label,
                style: theme.textTheme.labelSmall
                    ?.weight(FontWeight.w800)
                    .copyWith(color: style.color),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
