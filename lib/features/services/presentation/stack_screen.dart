import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/lifecycle/refresh_on_return.dart';
import 'package:cupola/core/providers/navigation_refresh_provider.dart';
import 'package:cupola/core/widgets/ambient_scaffold.dart';
import 'package:cupola/core/widgets/floating_bottom_nav_bar.dart';
import 'package:cupola/core/widgets/glass_app_bar.dart';
import 'package:cupola/features/services/domain/services_semantics.dart';
import 'package:cupola/features/services/presentation/service_kpi_provider.dart';
import 'package:cupola/features/services/presentation/nothing_set_up.dart';
import 'package:cupola/features/services/presentation/service_matrix.dart';
import 'package:cupola/features/services/presentation/services_alert_band.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/shell/domain/settings_return.dart';
import 'package:cupola/features/shell/domain/stack_health.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// The Stack tab: every service, its light, and the way into its room.
///
/// It was the Dashboard, the app's first tab, until the Home of modules took
/// that place: what needs you, what is moving and what arrived went to the
/// Home, and this page kept the fleet. Its own redesign is the Stack surface's.
/// Settings opens from its gear, the one place the operator's bar has no tab
/// for.
class StackScreen extends ConsumerWidget {
  const StackScreen({super.key});

  /// How stale the stack may be before returning to it earns a refetch.
  ///
  /// Generous on purpose: this screen reads every service, so a return is
  /// expensive and the figures it shows are not second-by-second. Two minutes is
  /// long enough that tab-hopping never triggers it and short enough that a
  /// screen left over lunch is not believed.
  static const _staleAfter = Duration(minutes: 2);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bottomPadding = FloatingNavBarMetrics.getScrollViewBottomPadding(
      context,
    );

    ref.listen<int>(navigationRefreshProvider(NavigationSection.stack), (
      previous,
      next,
    ) {
      _invalidateStack(ref);
    });

    final settings = ref.watch(currentSettingsProvider);
    // A Seerr account that signed out is a connection somebody set up: the
    // stack is not empty, it has a step to take.
    final allUnconfigured = ServiceKey.values.every(
      (s) => !settings.hasServiceConnection(s),
    );

    return RefreshOnReturn(
      id: 'services.stack',
      maxAge: _staleAfter,
      // The same refresh a re-tap of the tab performs, rather than a second
      // path to the same invalidations, and silent, because nobody pressed
      // anything.
      onStale: () => ref.triggerNavigationRefresh(NavigationSection.stack),
      child: AmbientScaffold(
        // No accent passed: the room on this screen is lit by the neutral lamp,
        // like every room with no artwork. The fleet below is seventeen
        // services, and each is named by its mark and its title, never a hue.
        // "Stack", because the crumb and the tab both say Stack and the app
        // bar is *where you are*. The h1 below is what you are looking at:
        // the fleet. The two are different sentences.
        appBar: GlassAppBar(
          title: const Text('Stack'),
          actions: [
            IconButton(
              tooltip: 'Settings',
              icon: const Icon(Icons.settings_outlined),
              onPressed: () => openSettings(context, ref),
            ),
          ],
        ),
        body: allUnconfigured
            ? NothingSetUpView(bottomPadding: bottomPadding)
            : RefreshIndicator(
                onRefresh: () => _refreshStack(ref),
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.only(bottom: bottomPadding),
                  //  * the header is one line of StackHealth under the h1, and
                  //    it is neutral when clear: no permanent green
                  //  * the band is absent unless something stopped answering
                  //  * the stack is the instrument and the launcher
                  children: const [
                    _StackHeadline(),
                    ServicesAlertBand(),
                    ServiceMatrix(),
                  ],
                ),
              ),
      ),
    );
  }
}

/// The h1 and the one line under it.
///
/// `Your stack`, not `Stack`. The tab and the crumb already say Stack twice
/// over; the h1 is the one line on the screen that can say what is being looked
/// at instead of where you are, and the fleet *is* the subject here.
///
/// The sentence under it is [StackHealth]'s, counting **connections folded per
/// service** rather than the lensed summary, so a Radarr with one of its two
/// connections dark reads as *degraded* rather than inheriting whichever answer
/// the lens happened to be pointing at.
class _StackHeadline extends ConsumerWidget {
  const _StackHeadline();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final health = ref.watch(stackHealthProvider);
    final sentence = health.sentenceAt(DateTime.now());

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      child: Semantics(
        container: true,
        header: true,
        label: 'Your stack',
        value: spokenFromDotted(sentence),
        excludeSemantics: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Your stack',
              style: theme.textTheme.headlineSmall?.copyWith(
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              sentence,
              // Neutral, always: no permanent green. A stack that is entirely
              // healthy says so in words and spends no colour on it; the tone
              // this page has to spare belongs to the one card that is not.
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Pull-to-refresh: drop everything the screen shows, then hold the spinner
/// until the slowest of it has actually come back.
///
/// `onRefresh` used to be `() async => _invalidateStack(ref)`, whose
/// future completes on the same microtask, so the indicator retracted while
/// thirteen summaries and three merged lists were still in flight. A control-room
/// screen that says "done" before it has re-read anything is worse than one with
/// no refresh: the user reads the stale figure as the fresh one.
///
/// Failures are swallowed rather than propagated. Every source here already
/// degrades to `[]`/offline and paints its own state; letting one rejection out
/// would abort `Future.wait` and retract the spinner early: the exact bug being
/// fixed, restored by the unhappy path.
Future<void> _refreshStack(WidgetRef ref) async {
  _invalidateStack(ref);

  Future<void> settle(Future<Object?> pending) async {
    try {
      await pending;
    } catch (_) {}
  }

  await Future.wait([
    for (final service in ServiceKey.values)
      settle(ref.read(serviceSummaryProvider(service).future)),
  ]);
}

void _invalidateStack(WidgetRef ref) {
  for (final service in ServiceKey.values) {
    ref.invalidate(serviceSummaryProvider(service));
    // The matrix's live line is the reason to pull-to-refresh this screen, and
    // it was the one thing refresh did not touch: the KPI providers were only
    // ever invalidated from the individual service pages.
    ref.invalidate(serviceKpiProvider(service));
    ref.invalidate(serviceSignalProvider(service));
    // The stack card's two figures. Reduced from the same KPI list, but its own
    // `autoDispose` family entry; invalidating only the single-figure provider
    // left the cards showing the figures from before the pull.
    ref.invalidate(serviceSignalPairProvider(service));
    // And the fleet's, for the multi-connection cards. Its own family entry
    // again, and it reads every connection rather than the lens, so a refresh
    // that stopped at the lens left a folded card stale by N-1 servers.
    ref.invalidate(foldedServiceKpisProvider(service));
    ref.invalidate(foldedServiceSignalPairProvider(service));
  }
  // The per-connection leg, invalidated as a whole family: it is keyed on the
  // connection, and the loop above only knows service keys.
  ref.invalidate(serviceKpiForProvider);
  // And the reachability probe itself, which is the same shape of mistake one
  // layer down: `serviceSummaryProvider` only delegates to this, so the loop
  // above rebuilt a wrapper that awaited an answer already in the cache. A pull
  // that redrew every figure and re-asked no server whether it was up.
  ref.invalidate(instanceSummaryProvider);
  // The library providers the KPI builders read through, and therefore the two
  // figures on every stack card. Invalidating `serviceKpiProvider` alone would
  // recompute the same numbers from the same cached libraries, which is a pull
  // that looks like it worked and changes nothing. The recently-added rail no
  // longer reads these: it rides one history page per arr.
  ref.invalidate(servicesMoviesProvider);
  ref.invalidate(servicesSeriesProvider);
  ref.invalidate(servicesMusicProvider);
  // And the four non-swallowing reads the rail makes of those same libraries.
  // They are separate providers so that a server which did not answer reads an
  // em dash rather than a confident zero; separate also means a pull that
  // stopped at the line above refreshed the grids and left every figure on
  // every stack card exactly where it was.
  //
  // Every service's, not four: `serviceKpiSources` is exhaustive over
  // `ServiceKey`, which the hand-written list of the four arrs was not.
  for (final service in ServiceKey.values) {
    for (final source in serviceKpiSources(service)) {
      ref.invalidate(source);
    }
  }
}
