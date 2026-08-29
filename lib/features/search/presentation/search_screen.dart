import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// ignore: implementation_imports
import 'package:flutter_riverpod/legacy.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/providers/navigation_refresh_provider.dart';
import 'package:cupola/core/reel_motion.dart';
import 'package:cupola/core/service_theme.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/ambient_scaffold.dart';
import 'package:cupola/core/widgets/app_card.dart';
import 'package:cupola/core/widgets/app_empty_state.dart';
import 'package:cupola/core/widgets/app_skeleton.dart';
import 'package:cupola/core/widgets/async_value_widget.dart';
import 'package:cupola/core/widgets/content_card.dart';
import 'package:cupola/core/widgets/floating_bottom_nav_bar.dart';
import 'package:cupola/core/widgets/glass_app_bar.dart';
import 'package:cupola/core/widgets/media_poster_card.dart';
import 'package:cupola/core/widgets/pressable_scale.dart';
import 'package:cupola/core/widgets/reel_line.dart';
import 'package:cupola/core/widgets/search_bar_header.dart';
import 'package:cupola/features/search/domain/global_search_result.dart';
import 'package:cupola/features/search/presentation/arr_add_form_provider.dart';
import 'package:cupola/features/search/presentation/arr_add_sheet.dart';
import 'package:cupola/features/search/presentation/global_search_provider.dart';
import 'package:cupola/features/search/presentation/recent_searches_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

class SearchScreen extends ConsumerWidget {
  const SearchScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = ref.watch(globalSearchQueryProvider);
    final selectedService = ref.watch(_selectedSearchServiceProvider);
    final results = ref.watch(globalSearchResultsProvider);
    final resetVersion = ref.watch(_globalSearchResetVersionProvider);
    final bottomPadding = FloatingNavBarMetrics.getScrollViewBottomPadding(
      context,
    );

    ref.listen<int>(navigationRefreshProvider(NavigationSection.search), (
      previous,
      next,
    ) {
      ref.read(globalSearchQueryProvider.notifier).state = '';
      ref.read(_globalSearchResetVersionProvider.notifier).state++;
    });

    // Record queries that returned results as recent searches.
    ref.listen<AsyncValue<List<GlobalSearchServiceResults>>>(
      globalSearchResultsProvider,
      (previous, next) {
        next.whenData((groups) {
          final q = ref.read(globalSearchQueryProvider).trim();
          if (q.isNotEmpty && groups.any((g) => g.results.isNotEmpty)) {
            ref.read(recentSearchesProvider.notifier).add(q);
          }
        });
      },
    );

    return AmbientScaffold(
      appBar: const GlassAppBar(title: Text('Search')),
      body: Column(
        children: [
          SearchBarHeader(
            key: ValueKey(resetVersion),
            initialQuery: query,
            hintText: 'Movies, shows, artists...',
            onQueryChanged: (value) {
              ref.read(globalSearchQueryProvider.notifier).state = value;
            },
          ),
          _ServiceFilterChips(
            selectedService: selectedService,
            onSelected: (service) {
              ref.read(_selectedSearchServiceProvider.notifier).state = service;
            },
          ),
          Divider(
            height: 1,
            indent: AppSpacing.lg,
            endIndent: AppSpacing.lg,
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
          Expanded(
            child: query.trim().isEmpty
                ? const _SearchEmptyState()
                : AsyncValueWidget<List<GlobalSearchServiceResults>>(
                    value: results,
                    serviceName: 'search',
                    skeleton: Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.md),
                      child: AppSkeleton.listRows(),
                    ),
                    data: (groups) => _SearchResultsList(
                      groups: groups,
                      selectedService: selectedService,
                      bottomPadding: bottomPadding,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

final _globalSearchResetVersionProvider = StateProvider<int>((ref) => 0);

final _selectedSearchServiceProvider = StateProvider<ServiceKey?>(
  (ref) => null,
);

class _ServiceFilterChips extends StatelessWidget {
  final ServiceKey? selectedService;
  final ValueChanged<ServiceKey?> onSelected;

  const _ServiceFilterChips({
    required this.selectedService,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.md,
      ),
      child: Row(
        children: [
          _FilterChip(
            label: 'All services',
            selected: selectedService == null,
            onTap: () => onSelected(null),
          ),
          for (final service in ServiceKey.values.where((s) => s.isSearchable))
            _FilterChip(
              label: service.title,
              color: service.accent,
              selected: selectedService == service,
              onTap: () => onSelected(service),
            ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final Color? color;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.onTap,
    this.color,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveColor = color ?? Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.sm),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          decoration: BoxDecoration(
            color: selected
                ? effectiveColor
                : effectiveColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(20),
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelMedium
                ?.weight(FontWeight.w700)
                .copyWith(
                  // Foreground picked from the fill's luminance: white on the
                  // Radarr amber measures 2.15:1, well below AA.
                  color: selected
                      ? ServiceTheme.foregroundOn(effectiveColor)
                      : effectiveColor,
                ),
          ),
        ),
      ),
    );
  }
}

class _SearchResultsList extends StatelessWidget {
  final List<GlobalSearchServiceResults> groups;
  final ServiceKey? selectedService;
  final double bottomPadding;

  const _SearchResultsList({
    required this.groups,
    required this.selectedService,
    required this.bottomPadding,
  });

  @override
  Widget build(BuildContext context) {
    final visibleGroups = groups
        .where(
          (group) =>
              selectedService == null || group.service == selectedService,
        )
        .toList(growable: false);
    final hasAnyResult = visibleGroups.any((group) => group.results.isNotEmpty);

    if (selectedService == null &&
        !hasAnyResult &&
        !visibleGroups.any((group) => group.hasError)) {
      return const _NoResultsState();
    }

    // Sections and their rows share one flat index so the sliver can build
    // lazily. Nesting a section's cards in a single `Column` made the whole
    // section one list child: a service answering with 50 results laid out and
    // painted 50 cards — and fired 50 poster requests, each with its own
    // repeating shimmer ticker — the moment any part of that section touched
    // the cache extent.
    final rows = <Object>[];
    for (final group in visibleGroups) {
      rows.add(group);
      if (group.hasError) {
        rows.add(_SectionOffline(group.service));
      } else if (group.results.isEmpty) {
        rows.add(_SectionNoResults(group.service));
      } else {
        rows.addAll(group.results);
      }
    }

    return ListView.builder(
      padding: EdgeInsets.only(top: AppSpacing.sm, bottom: bottomPadding),
      itemCount: rows.length,
      itemBuilder: (context, index) => switch (rows[index]) {
        final GlobalSearchServiceResults group => _SearchSectionHeader(
          group: group,
        ),
        _SectionOffline(:final service) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: _SearchSectionMessage(
            icon: Icons.cloud_off_rounded,
            text: '${service.title} is offline',
            color: Theme.of(context).colorScheme.error,
          ),
        ),
        _SectionNoResults(:final service) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: _SearchSectionMessage(
            icon: Icons.search_off_rounded,
            text: 'No ${service.title} results',
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        // The section's horizontal inset used to live on the wrapper around the
        // cards' `Column`; folded together with the per-card bottom gap it is
        // the same box.
        final GlobalSearchResult result => Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            0,
            AppSpacing.lg,
            AppSpacing.sm,
          ),
          child: _SearchResultCard(result: result),
        ),
        _ => const SizedBox.shrink(),
      },
    );
  }
}

/// A section body that is a message rather than a list of cards: the service
/// did not answer.
class _SectionOffline {
  final ServiceKey service;

  const _SectionOffline(this.service);
}

/// A section body that is a message rather than a list of cards: the service
/// answered with nothing.
class _SectionNoResults {
  final ServiceKey service;

  const _SectionNoResults(this.service);
}

class _SearchSectionHeader extends StatelessWidget {
  final GlobalSearchServiceResults group;

  const _SearchSectionHeader({required this.group});

  @override
  Widget build(BuildContext context) {
    final service = group.service;
    final colorScheme = Theme.of(context).colorScheme;
    final count = group.results.length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      child: Row(
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: service.accent.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(service.icon, size: 14, color: service.accent),
          ),
          const SizedBox(width: AppSpacing.sm),
          Flexible(
            child: Text(
              service.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.labelLarge?.weight(FontWeight.w700),
            ),
          ),
          // Which connection answered. On the heading rather than on the rows:
          // one leg queries one server, so every result below came from this
          // one and a chip repeated down forty rows would say it forty times.
          // Absent entirely while the service has a single connection.
          if (group.instanceLabel.isNotEmpty) ...[
            const SizedBox(width: AppSpacing.xs),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: service.accent.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: service.accent.withValues(alpha: 0.34),
                ),
              ),
              child: Text(
                group.instanceLabel.toUpperCase(),
                style: AppTheme.eyebrow(service.accent),
              ),
            ),
          ],
          const SizedBox(width: AppSpacing.xs),
          // A global search fans out to every configured service and they
          // answer at their own pace, so this count genuinely arrives — it
          // is not a number that was always there. Rolling it is the section
          // reporting in. `.tabular` still does the anti-jitter work; the
          // roll is what marks the arrival.
          ReelLine(
            group.hasError
                ? 'offline'
                : '$count result${count == 1 ? '' : 's'}',
            options: ReelMotion.figure,
            style: Theme.of(context).textTheme.labelSmall?.tabular.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
            fallbackMaxLines: 1,
          ),
        ],
      ),
    );
  }
}

class _SearchResultCard extends ConsumerWidget {
  final GlobalSearchResult result;

  const _SearchResultCard({required this.result});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final service = result.service;
    final addRequest = result.addRequest;
    // Held by the server that listed it — either when the lookup said so, or
    // because this session put it there. `select` so an add repaints the one
    // row it concerns rather than every card on screen.
    final owned =
        result.inLibrary ||
        (addRequest != null &&
            ref.watch(
              libraryAdditionsProvider.select(
                (keys) => keys.contains(addRequest.libraryKey),
              ),
            ));

    return AppCard.outlined(
      onTap: () => context.push(result.route, extra: result.routeExtra),
      backgroundColor: colorScheme.surfaceContainer,
      borderColor: colorScheme.outlineVariant,
      borderRadius: AppRadius.borderRadiusMd,
      padding: const EdgeInsets.all(11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 50, height: 75, child: _ResultPoster(result: result)),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  result.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.weight(FontWeight.w700),
                ),
                const SizedBox(height: 3),
                Text(
                  result.subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final tag in result.tags.take(3))
                      _ResultTag(label: tag, color: service.accent),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          _ResultAction(
            result: result,
            owned: owned,
            // A plus only where there is a real add behind it. Every other row
            // gets the glyph without the tap target: it is a state marker, and
            // a marker that responds to a finger is a promise.
            onAdd: owned || addRequest == null
                ? null
                : () => showArrAddSheet(context, ref, addRequest),
          ),
        ],
      ),
    );
  }
}

/// The row's trailing state glyph, and — where an add is genuinely possible —
/// the control that starts one.
///
/// Green tick for a title the server already holds, the service's own accent
/// and a plus for one it does not. It reads [owned] rather than sniffing the
/// tags for the substring `available`: that tied the affordance to a label's
/// wording, and to a field (`hasFile`) the lookup endpoints never populate — so
/// the tick never appeared and every row invited an add, including the ones
/// already sitting on the server.
class _ResultAction extends StatelessWidget {
  final GlobalSearchResult result;
  final bool owned;
  final VoidCallback? onAdd;

  const _ResultAction({
    required this.result,
    required this.owned,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    final glyph = SizedBox.square(
      dimension: 32,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: owned ? AppColors.success : result.service.accent,
          shape: BoxShape.circle,
        ),
        child: Icon(
          owned ? Icons.check_rounded : Icons.add_rounded,
          size: 15,
          color: Colors.white,
        ),
      ),
    );

    if (onAdd == null) return glyph;

    // 44 wide around a 32 circle: the glyph's own size is below the touch
    // target floor, and this is now a control rather than a badge.
    return PressableScale(
      onTap: onAdd,
      semanticLabel: 'Add ${result.title}',
      excludeChildSemantics: true,
      child: SizedBox(width: 44, height: 44, child: Center(child: glyph)),
    );
  }
}

/// A result's poster, flying into its detail page as a shared element.
///
/// The Hero is skipped where the service has no artwork (Bazarr), matching the
/// Recently Added rail: an empty grey box flying into a fallback glyph is
/// motion with nothing to follow.
class _ResultPoster extends StatelessWidget {
  final GlobalSearchResult result;

  const _ResultPoster({required this.result});

  @override
  Widget build(BuildContext context) {
    final card = ContentCard(
      imageUrl: result.imageUrl,
      httpHeaders: result.imageHeaders,
      badge: Align(
        alignment: Alignment.bottomLeft,
        child: Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: result.service.accent,
            shape: BoxShape.circle,
          ),
        ),
      ),
    );

    if (!result.canFlyPoster) return card;

    return Hero(
      tag: result.heroTag,
      transitionOnUserGestures: MediaPosterCard.flightOnUserGestures,
      child: card,
    );
  }
}

class _ResultTag extends StatelessWidget {
  final String label;
  final Color color;

  const _ResultTag({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: AppRadius.borderRadiusSm,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      child: Text(
        label,
        style: Theme.of(
          context,
        ).textTheme.labelSmall?.weight(FontWeight.w800).copyWith(color: color),
      ),
    );
  }
}

class _SearchSectionMessage extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;

  const _SearchSectionMessage({
    required this.icon,
    required this.text,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        border: Border.all(color: colorScheme.outlineVariant),
        borderRadius: AppRadius.borderRadiusLg,
      ),
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NoResultsState extends StatelessWidget {
  const _NoResultsState();

  @override
  Widget build(BuildContext context) {
    return const AppEmptyState(
      icon: Icons.search_off_rounded,
      title: 'No results found',
      message: 'Try a different title or spelling.',
    );
  }
}

/// "Radarr", "Radarr and Sonarr", "Seerr, Radarr and Sonarr".
String _serviceList(List<ServiceKey> services) {
  final titles = services.map((s) => s.title).toList(growable: false);
  if (titles.length == 1) return titles.single;
  return '${titles.sublist(0, titles.length - 1).join(', ')} and ${titles.last}';
}

class _SearchEmptyState extends ConsumerWidget {
  const _SearchEmptyState();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final recents = ref.watch(recentSearchesProvider);
    final settings = ref.watch(currentSettingsProvider);

    // Name the services that will actually be queried. The copy used to list
    // "Seerr, Radarr, Sonarr, Lidarr, and Bazarr" unconditionally, so a user with
    // only Radarr connected was promised four searches that could not happen.
    final searchable = ServiceKey.values
        .where((s) => s.isSearchable && settings.isServiceConfigured(s))
        .toList(growable: false);
    final hasAny = searchable.isNotEmpty;

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      children: [
        const SizedBox(height: AppSpacing.xl),
        Icon(
          hasAny ? Icons.search_rounded : Icons.link_off_rounded,
          size: 48,
          color: colorScheme.onSurfaceVariant,
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          hasAny
              ? 'Search across every service'
              : 'No searchable service connected',
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.weight(FontWeight.w700),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          hasAny
              ? 'Enter a title, show, or artist to query '
                    '${_serviceList(searchable)}.'
              : 'Connect Seerr, Radarr, Sonarr, Lidarr or Bazarr in Settings to '
                    'search your libraries from here.',
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
        ),
        if (!hasAny) ...[
          const SizedBox(height: AppSpacing.lg),
          Center(
            child: FilledButton.icon(
              // `go`, not `push`: a push keeps the *origin* branch's navigator,
              // so Settings would render inside the Search tab while the bar
              // stayed lit on Search. `go` switches to the Settings branch,
              // which is what the button says it does.
              onPressed: () => context.go('/settings'),
              icon: const Icon(Icons.settings_rounded, size: 18),
              label: const Text('Open Settings'),
            ),
          ),
        ],
        if (recents.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xxl),
          Row(
            children: [
              Text(
                'RECENT',
                style: AppTheme.eyebrow(colorScheme.onSurfaceVariant),
              ),
              const Spacer(),
              // TextButton rather than a bare GestureDetector on 11pt text: it
              // brings a 44pt hit area, a button role for screen readers and a
              // press state for free.
              TextButton(
                onPressed: () =>
                    ref.read(recentSearchesProvider.notifier).clear(),
                style: TextButton.styleFrom(
                  minimumSize: const Size(44, 44),
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                  ),
                  visualDensity: VisualDensity.compact,
                ),
                child: Text(
                  'Clear',
                  style: Theme.of(context).textTheme.labelSmall
                      ?.weight(FontWeight.w700)
                      .copyWith(color: colorScheme.primary),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (final query in recents)
                _RecentChip(
                  label: query,
                  onTap: () {
                    ref.read(globalSearchQueryProvider.notifier).state = query;
                    ref
                        .read(_globalSearchResetVersionProvider.notifier)
                        .state++;
                  },
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _RecentChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _RecentChip({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: colorScheme.outlineVariant),
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.history_rounded,
              size: 14,
              color: colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: AppSpacing.xs),
            Text(
              label,
              style: Theme.of(
                context,
              ).textTheme.labelMedium?.copyWith(color: colorScheme.onSurface),
            ),
          ],
        ),
      ),
    );
  }
}
