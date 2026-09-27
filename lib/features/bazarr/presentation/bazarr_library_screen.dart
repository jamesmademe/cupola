import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/route_utils.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/core/widgets/not_configured_placeholder.dart';
import 'package:cupola/core/widgets/shimmer_placeholder.dart';
import 'package:cupola/core/widgets/status_badge.dart';
import 'package:cupola/features/bazarr/domain/models/bazarr_models.dart';
import 'package:cupola/features/bazarr/presentation/bazarr_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// Which half of Bazarr's library a page lists.
///
/// Public since the tab model: Series and Movies are two entries on Bazarr's
/// own bar now, so the choice is made by the router rather than by a
/// `TabController` inside this file.
enum BazarrLibraryKind {
  series('Series'),
  movies('Movies');

  const BazarrLibraryKind(this.label);

  /// The word the app bar prints when this page draws one of its own.
  final String label;
}

/// One half of the Bazarr library — every series, or every film.
///
/// **It used to be both**, under a two-tab `TabBar` of its own at
/// `/dashboard/bazarr/library`. Bazarr's bar draws Series and Movies as
/// separate destinations (decision 22), so that inner bar became a second
/// row of tabs directly under the service's own — two bars answering the same
/// question. The split is what removes it; `library` still resolves, as a
/// redirect onto Series.
///
/// Named constructors rather than a `kind:` argument or a boolean, following
/// `lib/core/widgets/AGENTS.md`: a call site says which half it wants in the
/// constructor name, and there is no third value to handle.
class BazarrLibraryScreen extends ConsumerWidget {
  /// The series half — Bazarr's Series tab.
  const BazarrLibraryScreen.series({
    super.key,
    this.showAppBar = true,
    this.topPadding = 0,
  }) : kind = BazarrLibraryKind.series;

  /// The film half — Bazarr's Movies tab.
  const BazarrLibraryScreen.movies({
    super.key,
    this.showAppBar = true,
    this.topPadding = 0,
  }) : kind = BazarrLibraryKind.movies;

  final BazarrLibraryKind kind;

  /// Whether to draw this screen's own app bar.
  ///
  /// False inside the tab shell, where `ServiceHomeScreen` draws the service
  /// band and `ServiceTabScaffold` the tab bar above it: a third bar of its own
  /// would put two titles and two back chevrons in one corner.
  final bool showAppBar;

  /// Room those two glass bands take above this page, since they float over it
  /// rather than pushing it down.
  final double topPadding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(currentSettingsProvider);
    final isConfigured = settings.isServiceConfigured(ServiceKey.bazarr);

    return Scaffold(
      appBar: showAppBar
          ? AppBar(
              backgroundColor: AppColors.bazarr.withValues(alpha: 0.12),
              leading: IconButton(
                icon: const Icon(Icons.chevron_left_rounded),
                onPressed: () =>
                    RouteUtils.popOrGo(context, ServiceRoutes.bazarr),
                tooltip: 'Back',
              ),
              title: Text(kind.label),
            )
          : null,
      body: isConfigured
          // Keyed by kind so the two halves cannot share one list state: they
          // are separate branches of the service shell and each keeps its own
          // scroll offset and its own page cursor.
          ? _BazarrLibraryTab(
              key: ValueKey(kind),
              kind: kind,
              topPadding: topPadding,
            )
          : NotConfiguredPlaceholder.forService(ServiceKey.bazarr),
    );
  }
}

class _BazarrLibraryTab extends ConsumerStatefulWidget {
  const _BazarrLibraryTab({super.key, required this.kind, this.topPadding = 0});

  final BazarrLibraryKind kind;

  /// Folded into the list's own padding rather than wrapped around it: the
  /// host's bands float over this page, so the list has to scroll *under* them
  /// and only its first row needs the clearance.
  final double topPadding;

  @override
  ConsumerState<_BazarrLibraryTab> createState() => _BazarrLibraryTabState();
}

class _BazarrLibraryTabState extends ConsumerState<_BazarrLibraryTab> {
  static const int _pageSize = 50;

  final ScrollController _scrollController = ScrollController();
  final List<_BazarrLibraryEntry> _items = [];
  int _start = 0;
  int? _total;
  bool _initialLoading = true;
  bool _loadingMore = false;
  Object? _error;
  String? _errorKey;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_maybeLoadMore);
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadInitial());
  }

  String get _providerKey =>
      widget.kind == BazarrLibraryKind.series ? 'series' : 'movies';

  Future<void> _loadInitial() async {
    setState(() {
      _initialLoading = true;
      _error = null;
    });
    try {
      final service = ref.read(bazarrServiceProvider);
      final page = widget.kind == BazarrLibraryKind.series
          ? await service.getSeries(start: 0, length: _pageSize)
          : await service.getMovies(start: 0, length: _pageSize);
      if (!mounted) return;
      setState(() {
        _items
          ..clear()
          ..addAll(page.data.map(_BazarrLibraryEntry.from));
        _start = page.data.length;
        _total = page.total;
        _initialLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _errorKey = '${_providerKey}_init_${identityHashCode(e)}';
        _initialLoading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore) return;
    if (_total != null && _items.length >= _total!) return;
    setState(() => _loadingMore = true);
    try {
      final service = ref.read(bazarrServiceProvider);
      final page = widget.kind == BazarrLibraryKind.series
          ? await service.getSeries(start: _start, length: _pageSize)
          : await service.getMovies(start: _start, length: _pageSize);
      if (!mounted) return;
      setState(() {
        _items.addAll(page.data.map(_BazarrLibraryEntry.from));
        _start += page.data.length;
        _total = page.total;
        _loadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _errorKey = '${_providerKey}_more_${identityHashCode(e)}';
        _loadingMore = false;
      });
    }
  }

  void _maybeLoadMore() {
    if (_initialLoading || _loadingMore) return;
    if (_error != null) return;
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 240) {
      _loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_initialLoading) {
      return ListView.separated(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.md + widget.topPadding,
          AppSpacing.lg,
          AppSpacing.md,
        ),
        itemCount: 8,
        separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
        itemBuilder: (_, _) => ShimmerPlaceholder(
          height: 64,
          borderRadius: AppRadius.borderRadiusMd,
        ),
      );
    }

    if (_error != null && _items.isEmpty) {
      return _BazarrLibraryError(
        key: ValueKey(_errorKey),
        message: 'Failed to load library',
        onRetry: _loadInitial,
      );
    }

    if (_items.isEmpty) {
      return Center(
        child: Text(
          'No items found in your Bazarr library.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    final hasMore = _total == null ? false : _items.length < _total!;
    return RefreshIndicator(
      onRefresh: _loadInitial,
      child: ListView.separated(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.md + widget.topPadding,
          AppSpacing.lg,
          AppSpacing.md,
        ),
        itemCount: _items.length + (hasMore ? 1 : 0),
        separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
        itemBuilder: (context, index) {
          if (index >= _items.length) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
              child: Center(
                child: _loadingMore
                    ? const CircularProgressIndicator(
                        color: AppColors.bazarr,
                        strokeWidth: 2.4,
                      )
                    : Text(
                        'Pull up to load more',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
              ),
            );
          }
          return _BazarrLibraryRow(entry: _items[index]);
        },
      ),
    );
  }
}

class _BazarrLibraryEntry {
  _BazarrLibraryEntry({
    required this.kind,
    required this.id,
    required this.title,
    required this.subtitle,
  });

  factory _BazarrLibraryEntry.from(dynamic item) {
    if (item is BazarrSeries) {
      return _BazarrLibraryEntry(
        kind: BazarrLibraryKind.series,
        id: item.sonarrSeriesId,
        title: item.title ?? 'Untitled series',
        subtitle: item.path ?? item.sortTitle ?? '',
      );
    }
    if (item is BazarrMovie) {
      final year = item.year != null ? ' (${item.year})' : '';
      return _BazarrLibraryEntry(
        kind: BazarrLibraryKind.movies,
        id: item.radarrId,
        title: '${item.title ?? 'Untitled movie'}$year',
        subtitle: item.path ?? item.sortTitle ?? '',
      );
    }
    return _BazarrLibraryEntry(
      kind: BazarrLibraryKind.series,
      id: 0,
      title: 'Unknown',
      subtitle: '',
    );
  }

  final BazarrLibraryKind kind;
  final int id;
  final String title;
  final String subtitle;
}

class _BazarrLibraryRow extends StatelessWidget {
  const _BazarrLibraryRow({required this.entry});

  final _BazarrLibraryEntry entry;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: colorScheme.surface,
      borderRadius: AppRadius.borderRadiusMd,
      child: InkWell(
        borderRadius: AppRadius.borderRadiusMd,
        onTap: () => _openEntry(context),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            border: Border.all(color: colorScheme.outlineVariant),
            borderRadius: AppRadius.borderRadiusMd,
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest,
                  borderRadius: AppRadius.borderRadiusSm,
                ),
                alignment: Alignment.center,
                child: Text(
                  entry.kind == BazarrLibraryKind.series ? '📺' : '🎬',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.title,
                      style: Theme.of(
                        context,
                      ).textTheme.titleSmall!.weight(FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (entry.subtitle.isNotEmpty)
                      Text(
                        entry.subtitle,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openEntry(BuildContext context) {
    if (entry.kind == BazarrLibraryKind.series) {
      context.push(ServiceRoutes.bazarrSeries(entry.id));
    } else {
      context.push(ServiceRoutes.bazarrMovie(entry.id));
    }
  }
}

class _BazarrLibraryError extends StatelessWidget {
  const _BazarrLibraryError({
    super.key,
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // A load that did not come back: red on the glyph alone, walked
            // against the page it sits on.
            Icon(
              Icons.error_outline_rounded,
              color: statusToneColor(colorScheme, StatusTone.error),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: AppSpacing.md),
            FilledButton.tonalIcon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
