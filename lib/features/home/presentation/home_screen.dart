import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/capability/audience.dart';
import 'package:cupola/core/lifecycle/refresh_on_return.dart';
import 'package:cupola/core/providers/navigation_refresh_provider.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/ambient_scaffold.dart';
import 'package:cupola/core/widgets/floating_bottom_nav_bar.dart';
import 'package:cupola/core/widgets/glass_app_bar.dart';
import 'package:cupola/core/widgets/pressable_scale.dart';
import 'package:cupola/features/discover/presentation/catalog_providers.dart';
import 'package:cupola/features/discover/presentation/widgets/discover_carousel.dart';
import 'package:cupola/features/home/data/home_layout_provider.dart';
import 'package:cupola/features/home/domain/home_module.dart';
import 'package:cupola/features/home/presentation/widgets/home_header.dart';
import 'package:cupola/features/home/presentation/widgets/needs_you_banner.dart';
import 'package:cupola/features/home/presentation/widgets/set_up_next_module.dart';
import 'package:cupola/features/services/domain/dashboard_decision.dart';
import 'package:cupola/features/services/presentation/dashboard_retry.dart';
import 'package:cupola/features/services/presentation/dashboard_sections.dart';
import 'package:cupola/features/services/presentation/nothing_set_up.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/shell/domain/settings_return.dart';
import 'package:cupola/features/shell/domain/shell_audience.dart';

/// The first tab: today, and the modules the person keeps on it.
///
/// The day is the title, the health of the stack the line under it; then the
/// person's modules in the order they keep them (`homeLayoutProvider`), each
/// drawing itself or stepping aside when it has nothing to say. The operator's
/// Home ends with Set up next and the way to Edit Home.
///
/// No app bar: the page scrolls under the status bar, where a scrim fades it
/// into the room.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  /// How stale the Home may be before returning to it earns a refetch: the
  /// same two minutes the stack's page always had, for the same reads.
  static const _staleAfter = Duration(minutes: 2);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bottomPadding = FloatingNavBarMetrics.getScrollViewBottomPadding(
      context,
    );
    ref.listen<int>(navigationRefreshProvider(NavigationSection.home), (
      previous,
      next,
    ) {
      _invalidateHome(ref);
    });

    final requester = ref.watch(shellAudienceProvider) == Audience.requester;
    final settings = ref.watch(currentSettingsProvider);
    // A Seerr account that signed out is a connection somebody set up: the
    // Home is not empty, it has a step to take.
    final allUnconfigured = ServiceKey.values.every(
      (s) => !settings.hasServiceConnection(s),
    );
    final layout = ref.watch(homeLayoutProvider);

    return RefreshOnReturn(
      id: 'home',
      maxAge: _staleAfter,
      onStale: () => ref.triggerNavigationRefresh(NavigationSection.home),
      child: AmbientScaffold(
        body: allUnconfigured
            ? NothingSetUpView(bottomPadding: bottomPadding)
            : Stack(
                children: [
                  RefreshIndicator(
                    onRefresh: () => _refreshHome(ref),
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: EdgeInsets.only(bottom: bottomPadding),
                      children: [
                        HomeHeader(
                          showsHealth: !requester,
                          trailing: requester ? const _AccountButton() : null,
                        ),
                        for (final module in layout.shown)
                          homeModuleView(module),
                        if (!requester) const EditHomeRow(),
                        const SizedBox(height: AppSpacing.lg),
                      ],
                    ),
                  ),
                  const Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: StatusBarScrim(),
                  ),
                ],
              ),
      ),
    );
  }
}

/// The widget that draws [module]: exhaustive, so a module cannot join the
/// registry without one.
Widget homeModuleView(HomeModule module) => switch (module) {
  HomeModule.needsYou => const NeedsYouBanner(),
  HomeModule.arrived => const HomeArrivedModule(),
  HomeModule.downloads => const HomeDownloadsModule(),
  HomeModule.requests => const HomeRequestsModule(),
  HomeModule.setUpNext => const SetUpNextModule(),
  HomeModule.trending => const _TrendingShelf(),
  HomeModule.comingSoon => const _ComingSoonShelf(),
};

class _TrendingShelf extends ConsumerWidget {
  const _TrendingShelf();

  @override
  Widget build(BuildContext context, WidgetRef ref) => DiscoverCarousel(
    title: HomeModule.trending.label,
    sectionId: 'home_trending',
    items: ref.watch(atriumTrendingProvider),
    onRetry: () => ref.invalidate(atriumTrendingProvider),
  );
}

class _ComingSoonShelf extends ConsumerWidget {
  const _ComingSoonShelf();

  @override
  Widget build(BuildContext context, WidgetRef ref) => DiscoverCarousel(
    title: HomeModule.comingSoon.label,
    sectionId: 'home_coming_soon',
    items: ref.watch(comingSoonProvider),
    onRetry: () => ref.invalidate(comingSoonProvider),
  );
}

/// The requester's way to her account and Settings: her initial in a disc,
/// as the boards draw it.
class _AccountButton extends ConsumerWidget {
  const _AccountButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final room = CupolaRoom.of(context);
    final name = ref.watch(
      currentSettingsProvider.select(
        (s) => s
            .instancesOf(ServiceKey.seerr)
            .map((instance) => instance.account?.displayName.trim() ?? '')
            .firstWhere((name) => name.isNotEmpty, orElse: () => ''),
      ),
    );
    final initial = name.isEmpty ? null : name.characters.first.toUpperCase();
    return PressableScale(
      onTap: () => openSettings(context, ref),
      semanticLabel: name.isEmpty ? 'Your account' : '$name, your account',
      excludeChildSemantics: true,
      child: Container(
        width: 44,
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: room.fillStrong,
          border: Border.all(color: room.edge),
        ),
        child: initial == null
            ? Icon(Icons.person_outline_rounded, color: room.ink, size: 22)
            : Text(initial, style: AppType.row.copyWith(color: room.ink)),
      ),
    );
  }
}

/// Pull-to-refresh: drop what the Home shows, then hold the spinner until the
/// slowest of it has come back. Failures are swallowed: every source here
/// already degrades and paints its own state, and one rejection would retract
/// the spinner early.
Future<void> _refreshHome(WidgetRef ref) async {
  _invalidateHome(ref);

  Future<void> settle(Future<Object?> pending) async {
    try {
      await pending;
    } catch (_) {}
  }

  if (ref.read(shellAudienceProvider) == Audience.requester) {
    await Future.wait([
      settle(ref.read(atriumTrendingProvider.future)),
      settle(ref.read(comingSoonProvider.future)),
    ]);
    return;
  }
  await Future.wait([
    settle(ref.read(servicesQueueProvider.future)),
    for (final source in DecisionSource.values)
      settle(ref.read(dashboardDecisionSourceProvider(source).future)),
    settle(ref.read(servicesRecentlyAddedProvider.future)),
  ]);
}

void _invalidateHome(WidgetRef ref) {
  if (ref.read(shellAudienceProvider) == Audience.requester) {
    ref.invalidate(atriumTrendingProvider);
    ref.invalidate(comingSoonProvider);
    return;
  }
  // The header's question, asked again of every server: whether it answers.
  ref.invalidate(instanceSummaryProvider);
  for (final service in ServiceKey.values) {
    ref.invalidate(serviceSummaryProvider(service));
  }
  ref.invalidate(servicesRequestsProvider);
  ref.invalidate(servicesQueueProvider);
  // One history read per arr, feeding both Arrived and the failed-import
  // decisions. Invalidated at the source rather than through either of its two
  // readers, so the two cannot end up disagreeing about the same page.
  ref.invalidate(servicesArrHistoryProvider);
  ref.invalidate(servicesRecentlyAddedProvider);
  // Each decision source, and what they read that keeps an answer of its own
  // — Prowlarr's indexer status among them, which nothing else here drops, so
  // a pull left a fixed indexer on the list as failing.
  ref.invalidate(dashboardDecisionSourceProvider);
  for (final service in ServiceKey.values) {
    for (final source in dashboardSourcesOf(service)) {
      ref.invalidate(source);
    }
  }
}
