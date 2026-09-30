import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/route_utils.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/core/widgets/app_bottom_sheet.dart';
import 'package:cupola/core/widgets/app_empty_state.dart';
import 'package:cupola/core/widgets/not_configured_placeholder.dart';
import 'package:cupola/features/prowlarr/domain/models/prowlarr_models.dart';
import 'package:cupola/features/prowlarr/presentation/prowlarr_indexer_actions.dart';
import 'package:cupola/features/prowlarr/presentation/prowlarr_provider.dart';
import 'package:cupola/features/prowlarr/presentation/widgets/prowlarr_category_picker.dart';
import 'package:cupola/features/prowlarr/presentation/widgets/prowlarr_indexer_tile.dart';
import 'package:cupola/features/prowlarr/presentation/widgets/prowlarr_list_shimmer.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

enum _ProtocolFilter { all, torrent, usenet }

enum _StatusFilter { all, enabled, disabled }

/// Actions offered by the library's overflow menu.
enum _LibraryMenuAction { testAll, syncApps, select, settings }

/// Sort keys of the web UI's indexer index that make sense on a phone.
enum _SortKey {
  name('Name'),
  priority('Priority'),
  protocol('Protocol'),
  privacy('Privacy'),
  status('Status');

  const _SortKey(this.label);

  final String label;
}

class ProwlarrLibraryScreen extends ConsumerStatefulWidget {
  /// Whether to draw this screen's own app bar.
  ///
  /// False inside the tab shell, where `ServiceHomeScreen` draws the service
  /// band and `ServiceTabScaffold` the tab bar above it: a third bar of its own
  /// would put two titles and two back chevrons in one corner.
  final bool showAppBar;

  /// Room those two glass bands take above this page, since they float over it
  /// rather than pushing it down.
  final double topPadding;

  const ProwlarrLibraryScreen({
    super.key,
    this.showAppBar = true,
    this.topPadding = 0,
  });

  @override
  ConsumerState<ProwlarrLibraryScreen> createState() =>
      _ProwlarrLibraryScreenState();
}

class _ProwlarrLibraryScreenState extends ConsumerState<ProwlarrLibraryScreen> {
  final _search = TextEditingController();
  _ProtocolFilter _protocol = _ProtocolFilter.all;
  _StatusFilter _status = _StatusFilter.all;
  String _query = '';

  /// Parent newznab categories the list is narrowed to; empty means no filter.
  Set<int> _categories = const {};
  _SortKey _sortKey = _SortKey.name;
  bool _ascending = true;

  /// Ids picked in bulk-edit mode; null when the mode is off, so an empty
  /// selection ("select mode on, nothing picked") stays representable.
  Set<int>? _selection;

  bool get _selecting => _selection != null;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  bool _matches(ProwlarrIndexer indexer) {
    final protocolOk = switch (_protocol) {
      _ProtocolFilter.all => true,
      _ProtocolFilter.torrent =>
        (indexer.protocol ?? '').toLowerCase() == 'torrent',
      _ProtocolFilter.usenet =>
        (indexer.protocol ?? '').toLowerCase() == 'usenet',
    };
    final statusOk = switch (_status) {
      _StatusFilter.all => true,
      _StatusFilter.enabled => indexer.enable,
      _StatusFilter.disabled => !indexer.enable,
    };
    final queryOk =
        _query.isEmpty ||
        [
          indexer.name,
          indexer.definitionName,
          indexer.description,
        ].whereType<String>().join(' ').toLowerCase().contains(_query);
    final categoryOk =
        _categories.isEmpty ||
        indexer.categoryIds.any(_acceptedCategoryIds.contains);
    return protocolOk && statusOk && queryOk && categoryOk;
  }

  /// The parent selection expanded to the child ids indexers actually
  /// advertise. Recomputed in `build` from the watched category tree, so a tree
  /// that arrives after the selection still filters correctly.
  Set<int> _acceptedCategoryIds = const {};

  Future<void> _pickCategories() async {
    final picked = await showProwlarrCategoryPicker(
      context: context,
      selected: _categories,
    );
    if (picked == null || !mounted) return;
    _changeFilter(() => _categories = picked);
  }

  /// Applies a filter change and drops any selected indexer it hides.
  ///
  /// The header count and every bulk action read [_selection] straight through,
  /// so a selection that outlives the filter which put those rows on screen is a
  /// set the user can neither see nor untick — and "Delete N indexers?" would
  /// happily take rows that were never displayed. Narrowing the view narrows
  /// what the view can act on.
  void _changeFilter(VoidCallback change) {
    setState(() {
      change();
      final selection = _selection;
      if (selection == null || selection.isEmpty) return;
      // `_matches` reads the expanded category ids, which `build` recomputes —
      // and a category change has not been through a build yet.
      _acceptedCategoryIds = prowlarrExpandCategories(
        _categories,
        ref.read(prowlarrCategoriesProvider).value ?? const [],
      );
      final visible = ref
          .read(prowlarrIndexersProvider)
          .value
          ?.where(_matches)
          .map((indexer) => indexer.id)
          .toSet();
      if (visible == null) return;
      _selection = selection.intersection(visible);
    });
  }

  /// Orders the filtered list. Ties fall back to the name so the order is
  /// stable while the user flips between keys.
  int _compare(ProwlarrIndexer a, ProwlarrIndexer b) {
    int byName() =>
        (a.name ?? '').toLowerCase().compareTo((b.name ?? '').toLowerCase());
    final result = switch (_sortKey) {
      _SortKey.name => byName(),
      _SortKey.priority => (a.priority ?? 99).compareTo(b.priority ?? 99),
      _SortKey.protocol => (a.protocol ?? '').compareTo(b.protocol ?? ''),
      _SortKey.privacy => (a.privacy ?? '').compareTo(b.privacy ?? ''),
      _SortKey.status => (a.enable ? 0 : 1).compareTo(b.enable ? 0 : 1),
    };
    final ordered = result != 0 ? result : byName();
    return _ascending ? ordered : -ordered;
  }

  void _toggleSelection(int id) {
    setState(() {
      final selection = {...?_selection};
      if (!selection.remove(id)) selection.add(id);
      _selection = selection;
    });
  }

  Future<void> _handleMenu(_LibraryMenuAction action) async {
    switch (action) {
      case _LibraryMenuAction.testAll:
        await testAllIndexersFlow(context, ref);
      case _LibraryMenuAction.syncApps:
        await syncAppIndexersFlow(context, ref);
      case _LibraryMenuAction.select:
        setState(() => _selection = <int>{});
      case _LibraryMenuAction.settings:
        await context.push(ServiceRoutes.prowlarrSettings);
    }
  }

  /// Long-press menu for a single indexer, the row action menu of the web UI.
  Future<void> _showRowActions(ProwlarrIndexer indexer) async {
    await AppBottomSheet.show<void>(
      context: context,
      title: indexer.name ?? 'Indexer',
      subtitle: indexer.displayImplementation.isEmpty
          ? null
          : indexer.displayImplementation,
      icon: Icons.travel_explore_rounded,
      accent: ServiceKey.prowlarr.accent,
      builder: (sheetContext) => Column(
        children: [
          ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: const Text('Edit'),
            onTap: () {
              Navigator.of(sheetContext).pop();
              editIndexerFlow(context, ref, indexer);
            },
          ),
          ListTile(
            leading: const Icon(Icons.network_check_rounded),
            title: const Text('Test'),
            onTap: () {
              Navigator.of(sheetContext).pop();
              testIndexerFlow(context, ref, indexer);
            },
          ),
          ListTile(
            leading: Icon(
              indexer.enable
                  ? Icons.pause_circle_outline_rounded
                  : Icons.play_circle_outline_rounded,
            ),
            title: Text(indexer.enable ? 'Disable' : 'Enable'),
            onTap: () {
              Navigator.of(sheetContext).pop();
              toggleIndexerFlow(context, ref, indexer);
            },
          ),
          // Neutral, like the rows above it: red means unreachable and nothing
          // else, and the confirmation says what goes.
          ListTile(
            leading: const Icon(Icons.delete_outline_rounded),
            title: const Text('Delete'),
            onTap: () {
              Navigator.of(sheetContext).pop();
              deleteIndexerFlow(context, ref, indexer);
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Asked before anything is read, and that is new with the tab model. This
    // page used to be reachable only by tapping through a configured service,
    // so an unconfigured Prowlarr could only arrive here by deep link and got
    // "Failed to load indexers" with a Retry that retried forever — a dead end
    // wearing fault chrome for a state the user created by not filling in a
    // form. It is a *tab* now: the bar draws it whether or not the service is
    // set up, so this is an ordinary daily arrival.
    final isConfigured = ref.watch(
      currentSettingsProvider.select(
        (settings) => settings.isServiceConfigured(ServiceKey.prowlarr),
      ),
    );
    if (!isConfigured) {
      return Scaffold(
        appBar: widget.showAppBar
            ? AppBar(
                backgroundColor: ServiceKey.prowlarr.accent.withValues(
                  alpha: 0.12,
                ),
                leading: IconButton(
                  icon: const Icon(Icons.chevron_left_rounded),
                  onPressed: () =>
                      RouteUtils.popOrGo(context, ServiceRoutes.prowlarr),
                  tooltip: 'Back',
                ),
                title: const Text('Indexers'),
              )
            : null,
        // `.forService`: its door goes to Prowlarr's own connection form rather
        // than to the settings index, where its setup note is printed.
        body: NotConfiguredPlaceholder.forService(ServiceKey.prowlarr),
      );
    }

    final indexersAsync = ref.watch(prowlarrIndexersProvider);
    final statusAsync = ref.watch(prowlarrIndexerStatusProvider);
    _acceptedCategoryIds = prowlarrExpandCategories(
      _categories,
      ref.watch(prowlarrCategoriesProvider).asData?.value ?? const [],
    );
    final tagLabels = ref.watch(prowlarrTagLabelsProvider);
    final disabledIds = statusAsync.maybeWhen(
      data: (statuses) => statuses.map((s) => s.indexerId).toSet(),
      orElse: () => const <int>{},
    );

    // Computed once, above the `when`, because the selection bar and the
    // select-all button live outside the data branch and must act on exactly
    // the rows the list is showing — not on whatever the selection accumulated
    // under an earlier filter. `AsyncValue.value` keeps the previous data during
    // a refresh, so a pull-to-refresh cannot momentarily empty the selection.
    final allIndexers = indexersAsync.value ?? const <ProwlarrIndexer>[];
    final filtered = allIndexers.where(_matches).toList()..sort(_compare);
    final visibleIds = filtered.map((indexer) => indexer.id).toSet();
    final selection = _selection;
    final selected = selection == null
        ? const <ProwlarrIndexer>[]
        : filtered
              .where((indexer) => selection.contains(indexer.id))
              .toList(growable: false);
    final selectedIds = selected
        .map((indexer) => indexer.id)
        .toList(growable: false);

    // Built once and placed in one of two ways. Hosted, the app bar is gone —
    // but these controls must not go with it, and they cannot move up onto the
    // service band either: Add indexer, Test all, Sync apps and the whole
    // selection mode belong to THIS tab, and the band is drawn above every
    // branch, so they would follow the user onto Overview, History and Stats.
    // They move into the body instead, on one row above the search field.
    final cancelSelection = IconButton(
      icon: const Icon(Icons.close_rounded),
      tooltip: 'Cancel selection',
      onPressed: () => setState(() => _selection = null),
    );
    final selectionTitle = Text(
      '${selected.length} selected',
      style: Theme.of(context).appBarTheme.titleTextStyle,
    );
    final actions = _selecting
        ? <Widget>[
            IconButton(
              icon: const Icon(Icons.select_all_rounded),
              tooltip: 'Select all',
              onPressed: () {
                // Membership, not cardinality: comparing set *sizes* meant
                // that with as many hidden rows selected as there were
                // visible ones, "Select all" cleared the list instead of
                // selecting what the user could see.
                final current = selection ?? const <int>{};
                final allVisibleSelected =
                    visibleIds.isNotEmpty && visibleIds.every(current.contains);
                setState(
                  () => _selection = allVisibleSelected
                      ? current.difference(visibleIds)
                      : {...current, ...visibleIds},
                );
              },
            ),
          ]
        : <Widget>[
            IconButton(
              icon: const Icon(Icons.add_rounded),
              tooltip: 'Add indexer',
              onPressed: () => addIndexerFlow(context, ref),
            ),
            PopupMenuButton<_LibraryMenuAction>(
              tooltip: 'More actions',
              onSelected: _handleMenu,
              itemBuilder: (context) => const [
                PopupMenuItem(
                  value: _LibraryMenuAction.testAll,
                  child: Text('Test all indexers'),
                ),
                PopupMenuItem(
                  value: _LibraryMenuAction.syncApps,
                  child: Text('Sync app indexers'),
                ),
                PopupMenuItem(
                  value: _LibraryMenuAction.select,
                  child: Text('Select indexers'),
                ),
                PopupMenuItem(
                  value: _LibraryMenuAction.settings,
                  child: Text('Prowlarr settings'),
                ),
              ],
            ),
          ];

    return Scaffold(
      appBar: widget.showAppBar
          ? AppBar(
              backgroundColor: ServiceKey.prowlarr.accent.withValues(
                alpha: 0.12,
              ),
              leading: _selecting
                  ? cancelSelection
                  : IconButton(
                      icon: const Icon(Icons.chevron_left_rounded),
                      onPressed: () =>
                          RouteUtils.popOrGo(context, ServiceRoutes.prowlarr),
                      tooltip: 'Back',
                    ),
              title: Text(
                _selecting ? '${selected.length} selected' : 'Indexers',
              ),
              actions: actions,
            )
          : null,
      body: Column(
        children: [
          if (!widget.showAppBar) ...[
            SizedBox(height: widget.topPadding),
            // No back chevron and no 'Indexers' title here: the service band
            // above owns both, and repeating them is the two-titles-in-one-
            // corner problem this mode exists to avoid. The count and the
            // cancel appear only while selecting, when they are the only thing
            // saying the list is in that mode.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
              child: Row(
                children: [
                  if (_selecting) ...[
                    cancelSelection,
                    Expanded(child: selectionTitle),
                  ] else
                    const Spacer(),
                  ...actions,
                ],
              ),
            ),
          ],
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.sm,
              AppSpacing.lg,
              0,
            ),
            child: TextField(
              controller: _search,
              onChanged: (value) =>
                  _changeFilter(() => _query = value.trim().toLowerCase()),
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Search indexers',
                prefixIcon: const Icon(Icons.search_rounded, size: 18),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close_rounded, size: 18),
                        tooltip: 'Clear',
                        onPressed: () {
                          _search.clear();
                          _changeFilter(() => _query = '');
                        },
                      ),
              ),
            ),
          ),
          _FilterBar(
            protocol: _protocol,
            status: _status,
            categoryCount: _categories.length,
            sortKey: _sortKey,
            ascending: _ascending,
            onProtocol: (value) => _changeFilter(() => _protocol = value),
            onStatus: (value) => _changeFilter(() => _status = value),
            onCategories: _pickCategories,
            onSort: (key) => setState(() {
              if (_sortKey == key) {
                _ascending = !_ascending;
              } else {
                _sortKey = key;
                _ascending = true;
              }
            }),
          ),
          Expanded(
            child: indexersAsync.when(
              data: (indexers) {
                if (filtered.isEmpty) {
                  return LayoutBuilder(
                    builder: (context, constraints) => SingleChildScrollView(
                      // The compact desktop shell can leave this body one
                      // pixel shorter than the empty message plus its action.
                      // Let the page own a scroll extent so a centered empty
                      // state grows past that transient constraint instead of
                      // painting a bottom overflow marker.
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: constraints.maxHeight,
                        ),
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.all(AppSpacing.xl),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  indexers.isEmpty
                                      ? 'No indexers configured yet.'
                                      : 'No indexers match the current filters.',
                                  textAlign: TextAlign.center,
                                ),
                                if (indexers.isEmpty) ...[
                                  const SizedBox(height: AppSpacing.md),
                                  FilledButton.icon(
                                    onPressed: () =>
                                        addIndexerFlow(context, ref),
                                    icon: const Icon(
                                      Icons.add_rounded,
                                      size: 18,
                                    ),
                                    label: const Text('Add indexer'),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }
                return RefreshIndicator(
                  onRefresh: () async {
                    ref.invalidate(prowlarrIndexersProvider);
                    ref.invalidate(prowlarrIndexerStatusProvider);
                    ref.invalidate(prowlarrTagsProvider);
                    await Future<void>.delayed(
                      const Duration(milliseconds: 300),
                    );
                  },
                  child: ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.sm,
                    ),
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final indexer = filtered[index];
                      final labels = indexer.tags
                          .map((id) => tagLabels[id])
                          .whereType<String>()
                          .toList(growable: false);
                      if (selection != null) {
                        return ProwlarrIndexerTile.selectable(
                          indexer: indexer,
                          failing: disabledIds.contains(indexer.id),
                          tagLabels: labels,
                          selected: selection.contains(indexer.id),
                          onTap: () => _toggleSelection(indexer.id),
                        );
                      }
                      return ProwlarrIndexerTile.navigable(
                        indexer: indexer,
                        failing: disabledIds.contains(indexer.id),
                        tagLabels: labels,
                        onTap: () => context.push(
                          ServiceRoutes.prowlarrIndexer(indexer.id),
                        ),
                        onLongPress: () => _showRowActions(indexer),
                      );
                    },
                  ),
                );
              },
              loading: () => const AppScrollablePage(
                child: ProwlarrListShimmer(
                  count: 6,
                  verticalPadding: AppSpacing.sm,
                ),
              ),
              error: (error, _) => AppScrollablePage(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.xl),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('Failed to load indexers'),
                        const SizedBox(height: AppSpacing.md),
                        FilledButton(
                          onPressed: () =>
                              ref.invalidate(prowlarrIndexersProvider),
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (selection != null)
            // Every action is handed `selected` — the selection intersected
            // with what is on screen — so a bulk edit, retag or delete can only
            // ever touch rows the user is looking at.
            _SelectionBar(
              count: selected.length,
              onEdit: selected.isEmpty
                  ? null
                  : () => bulkEditIndexersFlow(context, ref, selectedIds),
              onTags: selected.isEmpty
                  ? null
                  : () => bulkTagIndexersFlow(context, ref, selectedIds),
              onDelete: selected.isEmpty
                  ? null
                  : () async {
                      final deleted = await bulkDeleteIndexersFlow(
                        context,
                        ref,
                        selected,
                      );
                      if (deleted && mounted) {
                        setState(() => _selection = <int>{});
                      }
                    },
            ),
        ],
      ),
    );
  }
}

/// Bottom action bar shown while indexers are selected.
class _SelectionBar extends StatelessWidget {
  const _SelectionBar({
    required this.count,
    required this.onEdit,
    required this.onTags,
    required this.onDelete,
  });

  final int count;
  final VoidCallback? onEdit;
  final VoidCallback? onTags;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHigh,
          border: Border(top: BorderSide(color: colorScheme.outlineVariant)),
        ),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onEdit,
                icon: const Icon(Icons.tune_rounded, size: 18),
                label: const Text('Edit'),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onTags,
                icon: const Icon(Icons.sell_outlined, size: 18),
                label: const Text('Tags'),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            IconButton.filled(
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline_rounded, size: 18),
              tooltip: 'Delete $count selected',
              // Neutral: the theme's own filled icon button. Red means
              // unreachable and nothing else.
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.protocol,
    required this.status,
    required this.categoryCount,
    required this.sortKey,
    required this.ascending,
    required this.onProtocol,
    required this.onStatus,
    required this.onCategories,
    required this.onSort,
  });

  final _ProtocolFilter protocol;
  final _StatusFilter status;
  final int categoryCount;
  final _SortKey sortKey;
  final bool ascending;
  final ValueChanged<_ProtocolFilter> onProtocol;
  final ValueChanged<_StatusFilter> onStatus;
  final VoidCallback onCategories;
  final ValueChanged<_SortKey> onSort;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: [
          _FilterChip(
            label: 'All',
            selected: protocol == _ProtocolFilter.all,
            onTap: () => onProtocol(_ProtocolFilter.all),
          ),
          _FilterChip(
            label: 'Torrent',
            selected: protocol == _ProtocolFilter.torrent,
            onTap: () => onProtocol(_ProtocolFilter.torrent),
          ),
          _FilterChip(
            label: 'Usenet',
            selected: protocol == _ProtocolFilter.usenet,
            onTap: () => onProtocol(_ProtocolFilter.usenet),
          ),
          const _FilterDivider(),
          _FilterChip(
            label: 'Enabled',
            selected: status == _StatusFilter.enabled,
            onTap: () => onStatus(
              status == _StatusFilter.enabled
                  ? _StatusFilter.all
                  : _StatusFilter.enabled,
            ),
          ),
          _FilterChip(
            label: 'Disabled',
            selected: status == _StatusFilter.disabled,
            onTap: () => onStatus(
              status == _StatusFilter.disabled
                  ? _StatusFilter.all
                  : _StatusFilter.disabled,
            ),
          ),
          const _FilterDivider(),
          _FilterChip(
            label: categoryCount == 0
                ? 'Categories'
                : 'Categories ($categoryCount)',
            selected: categoryCount > 0,
            onTap: onCategories,
          ),
          PopupMenuButton<_SortKey>(
            tooltip: 'Sort',
            onSelected: onSort,
            itemBuilder: (context) => [
              for (final key in _SortKey.values)
                PopupMenuItem(
                  value: key,
                  child: Row(
                    children: [
                      Expanded(child: Text(key.label)),
                      if (key == sortKey)
                        Icon(
                          ascending
                              ? Icons.arrow_upward_rounded
                              : Icons.arrow_downward_rounded,
                          size: 16,
                        ),
                    ],
                  ),
                ),
            ],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              child: Row(
                children: [
                  Icon(
                    ascending
                        ? Icons.arrow_upward_rounded
                        : Icons.arrow_downward_rounded,
                    size: 18,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    sortKey.label,
                    style: Theme.of(context).textTheme.labelMedium!
                        .weight(FontWeight.w600)
                        .copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterDivider extends StatelessWidget {
  const _FilterDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 24,
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      color: Theme.of(context).colorScheme.outlineVariant,
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.sm),
      child: Material(
        color: selected
            ? ServiceKey.prowlarr.accent.withValues(alpha: 0.15)
            : colorScheme.surfaceContainerHighest,
        borderRadius: AppRadius.borderRadiusSm,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppRadius.borderRadiusSm,
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: AppSpacing.sm,
            ),
            decoration: BoxDecoration(
              borderRadius: AppRadius.borderRadiusSm,
              border: Border.all(
                color: selected
                    ? ServiceKey.prowlarr.accent.withValues(alpha: 0.5)
                    : Colors.transparent,
              ),
            ),
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelMedium!
                  .weight(FontWeight.w600)
                  .copyWith(
                    color: selected
                        ? colorScheme.onSurface
                        : colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
        ),
      ),
    );
  }
}
