import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/bazarr/data/bazarr_service.dart';
import 'package:cupola/features/bazarr/domain/models/bazarr_models.dart';
import 'package:cupola/features/bazarr/presentation/bazarr_overview_provider.dart';
import 'package:cupola/features/bazarr/presentation/bazarr_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

enum _HistoryFilter {
  all('All'),
  episodes('Episodes'),
  movies('Movies');

  const _HistoryFilter(this.label);

  final String label;
}

typedef _PageAttempt = ({
  BazarrHistorySource source,
  BazarrPagedResult<BazarrHistoryItem>? page,
  Object? error,
});

/// Bazarr episode and movie history, loaded from the two API-backed lists.
///
/// The canvas pairs History with a Blacklist control, but the current client
/// has no verified blacklist list or mutation contract. This screen therefore
/// exposes only factual history and source filters; it does not draw a dead
/// Blacklist promise.
class BazarrHistoryScreen extends ConsumerStatefulWidget {
  const BazarrHistoryScreen({super.key, this.topPadding = 0});

  final double topPadding;

  @override
  ConsumerState<BazarrHistoryScreen> createState() =>
      _BazarrHistoryScreenState();
}

class _BazarrHistoryScreenState extends ConsumerState<BazarrHistoryScreen> {
  static const _pageSize = 50;

  _HistoryFilter _filter = _HistoryFilter.all;
  final Map<BazarrHistorySource, List<BazarrHistoryItem>> _items = {
    BazarrHistorySource.episodes: [],
    BazarrHistorySource.movies: [],
  };
  final Map<BazarrHistorySource, int?> _totals = {
    BazarrHistorySource.episodes: null,
    BazarrHistorySource.movies: null,
  };
  final Map<BazarrHistorySource, Object?> _errors = {
    BazarrHistorySource.episodes: null,
    BazarrHistorySource.movies: null,
  };
  bool _scheduled = false;
  bool _loading = false;
  bool _loadingMore = false;

  List<BazarrHistorySource> get _sources => switch (_filter) {
    _HistoryFilter.all => BazarrHistorySource.values,
    _HistoryFilter.episodes => const [BazarrHistorySource.episodes],
    _HistoryFilter.movies => const [BazarrHistorySource.movies],
  };

  String get _emptyLabel => switch (_filter) {
    _HistoryFilter.all => 'subtitle history',
    _HistoryFilter.episodes => 'episodes',
    _HistoryFilter.movies => 'movies',
  };

  List<BazarrHistoryItem> get _visibleItems {
    final merged = [for (final source in _sources) ..._items[source]!];
    merged.sort((a, b) {
      final left = a.parsedTimestamp;
      final right = b.parsedTimestamp;
      if (left == null && right == null) return 0;
      if (left == null) return 1;
      if (right == null) return -1;
      return right.compareTo(left);
    });
    return merged;
  }

  bool _hasMore(BazarrHistorySource source) {
    final total = _totals[source];
    return total != null && _items[source]!.length < total;
  }

  Future<_PageAttempt> _read(
    BazarrHistorySource source, {
    required int start,
  }) async {
    try {
      final page = await ref.read(
        bazarrHistoryPageProvider((
          source: source,
          start: start,
          length: _pageSize,
        )).future,
      );
      return (source: source, page: page, error: null);
    } catch (error) {
      return (source: source, page: null, error: error);
    }
  }

  Future<void> _reload() async {
    final sources = _sources;
    setState(() {
      _loading = true;
      for (final source in sources) {
        _errors[source] = null;
      }
    });
    final attempts = await Future.wait([
      for (final source in sources) _read(source, start: 0),
    ]);
    if (!mounted) return;
    setState(() {
      for (final attempt in attempts) {
        _errors[attempt.source] = attempt.error;
        final page = attempt.page;
        if (page != null) {
          _items[attempt.source]!
            ..clear()
            ..addAll(page.data);
          _totals[attempt.source] = page.total;
        }
      }
      _loading = false;
    });
  }

  Future<void> _loadMore() async {
    if (_loadingMore) return;
    final sources = _sources.where(_hasMore).toList(growable: false);
    if (sources.isEmpty) return;
    setState(() {
      _loadingMore = true;
      for (final source in sources) {
        _errors[source] = null;
      }
    });
    final attempts = await Future.wait([
      for (final source in sources)
        _read(source, start: _items[source]!.length),
    ]);
    if (!mounted) return;
    setState(() {
      for (final attempt in attempts) {
        _errors[attempt.source] = attempt.error;
        final page = attempt.page;
        if (page != null) {
          _items[attempt.source]!.addAll(page.data);
          _totals[attempt.source] = page.total;
        }
      }
      _loadingMore = false;
    });
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
        .isServiceConfigured(ServiceKey.bazarr);
    if (!configured) {
      return NotConfiguredPlaceholder.forService(ServiceKey.bazarr);
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
            accent: ServiceKey.bazarr.accent,
          ),
          Expanded(child: _body()),
        ],
      ),
    );
  }

  Widget _body() {
    final items = _visibleItems;
    final failedSources = _sources.where((source) => _errors[source] != null);
    if (_loading && items.isEmpty) return const ShimmerList.page(itemCount: 6);
    if (failedSources.length == _sources.length && items.isEmpty) {
      return AppScrollablePage(
        child: AppErrorState(
          error: _errors[failedSources.first]!,
          serviceName: 'Bazarr history',
          onRetry: _reload,
        ),
      );
    }
    if (items.isEmpty) {
      return AppEmptyStatePage(
        emptyState: AppEmptyState(
          icon: Icons.subtitles_off_rounded,
          title: 'No subtitle history',
          message: 'Bazarr has no $_emptyLabel to show.',
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
        itemCount: items.length + 1,
        separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
        itemBuilder: (context, index) {
          if (index == items.length) {
            return _footer(failedSources.toList(), items.length);
          }
          return _BazarrHistoryRow(item: items[index]);
        },
      ),
    );
  }

  Widget _footer(List<BazarrHistorySource> failedSources, int shownCount) {
    final canLoadMore = _sources.any(_hasMore);
    final total = _sources.fold<int?>(0, (sum, source) {
      final sourceTotal = _totals[source];
      return sum == null || sourceTotal == null ? null : sum + sourceTotal;
    });
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      child: Column(
        children: [
          if (failedSources.isNotEmpty)
            FaultBand.section(
              message:
                  'Bazarr is answering, but ${_sourceNames(failedSources)} '
                  'history did not load. The other records remain visible.',
              onRetry: _reload,
            ),
          Text(
            total == null
                ? '$shownCount shown'
                : 'Showing $shownCount of $total',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: CupolaThemeColors.of(context).dimText,
            ),
          ),
          if (canLoadMore) ...[
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

String _sourceNames(List<BazarrHistorySource> sources) {
  if (sources.length > 1) return 'episode and movie';
  return sources.single == BazarrHistorySource.episodes ? 'episode' : 'movie';
}

class _BazarrHistoryRow extends StatelessWidget {
  const _BazarrHistoryRow({required this.item});

  final BazarrHistoryItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tone = bazarrHistoryTone(item);
    final color = statusToneColor(theme.colorScheme, tone);
    final headline = bazarrHistoryHeadline(item);
    final detail = [
      item.provider,
      if (item.score case final score?) 'score $score',
      bazarrHistoryWhen(item),
      if (item.blacklisted) 'blacklisted',
    ].whereType<String>().where((value) => value.isNotEmpty).join(' · ');
    final spoken = [headline, detail]
        .where((value) => value.isNotEmpty)
        .map((value) => value.replaceAll(' · ', ', '))
        .join(', ');

    return Semantics(
      container: true,
      label: spoken,
      child: ExcludeSemantics(
        child: AppCard.outlined(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              Icon(
                item.kind == BazarrHistoryKind.episode
                    ? Icons.tv_rounded
                    : Icons.movie_rounded,
                color: color,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      headline,
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
                item.action.label,
                style: theme.textTheme.labelSmall
                    ?.weight(FontWeight.w800)
                    .copyWith(color: color),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
