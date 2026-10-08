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
import 'package:cupola/features/services/domain/dashboard_decision.dart';
import 'package:cupola/features/services/presentation/dashboard_retry.dart';
import 'package:cupola/features/services/presentation/dashboard_sections.dart';
import 'package:cupola/features/services/presentation/nothing_set_up.dart';
import 'package:cupola/features/services/presentation/services_alert_band.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/shell/domain/settings_return.dart';
import 'package:cupola/features/shell/domain/shell_audience.dart';

/// The first tab.
///
/// For now the regions the stack's page gave up when it became Stack — what
/// needs a decision, what is moving, what arrived — under the band that says
/// which service stopped answering. The Home of modules replaces them one
/// module at a time.
///
/// The requester's Home is hers: two of Seerr's shelves, and her account in
/// the corner, which is her way to Settings now that the bar has no tab for
/// it.
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

    return RefreshOnReturn(
      id: 'home',
      maxAge: _staleAfter,
      onStale: () => ref.triggerNavigationRefresh(NavigationSection.home),
      child: AmbientScaffold(
        appBar: GlassAppBar(
          title: const Text('Home'),
          actions: [if (requester) const _AccountButton()],
        ),
        body: allUnconfigured
            ? NothingSetUpView(bottomPadding: bottomPadding)
            : RefreshIndicator(
                onRefresh: () => _refreshHome(ref),
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.only(bottom: bottomPadding),
                  children: requester
                      ? [
                          DiscoverCarousel(
                            title: 'Trending this week',
                            sectionId: 'home_trending',
                            items: ref.watch(atriumTrendingProvider),
                            onRetry: () =>
                                ref.invalidate(atriumTrendingProvider),
                          ),
                          DiscoverCarousel(
                            title: 'Coming soon',
                            sectionId: 'home_coming_soon',
                            items: ref.watch(comingSoonProvider),
                            onRetry: () => ref.invalidate(comingSoonProvider),
                          ),
                        ]
                      : const [
                          ServicesAlertBand(),
                          DashboardDecisionsSection(),
                          ServicesInFlightSection(),
                          ServicesRecentlyAddedSection(),
                        ],
                ),
              ),
      ),
    );
  }
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
    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.sm),
      child: PressableScale(
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
  // The band's question, asked again of every server: whether it answers.
  ref.invalidate(instanceSummaryProvider);
  for (final service in ServiceKey.values) {
    ref.invalidate(serviceSummaryProvider(service));
  }
  ref.invalidate(servicesRequestsProvider);
  ref.invalidate(servicesQueueProvider);
  // One history read per arr, feeding both Recently added and the failed-import
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
