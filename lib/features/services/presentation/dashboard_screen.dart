import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/lifecycle/refresh_on_return.dart';
import 'package:cupola/core/providers/navigation_refresh_provider.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/ambient_scaffold.dart';
import 'package:cupola/core/widgets/floating_bottom_nav_bar.dart';
import 'package:cupola/core/widgets/glass_app_bar.dart';
import 'package:cupola/core/widgets/service_ring.dart';
import 'package:cupola/features/services/domain/services_semantics.dart';
import 'package:cupola/features/services/presentation/service_kpi_provider.dart';
import 'package:cupola/features/services/presentation/service_matrix.dart';
import 'package:cupola/features/services/presentation/services_alert_band.dart';
import 'package:cupola/features/services/presentation/dashboard_sections.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  /// How stale the control room may be before returning to it earns a refetch.
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

    ref.listen<int>(navigationRefreshProvider(NavigationSection.dashboard), (
      previous,
      next,
    ) {
      _invalidateServicesDashboard(ref);
    });

    final settings = ref.watch(currentSettingsProvider);
    final allUnconfigured = ServiceKey.values.every(
      (s) => !settings.isServiceConfigured(s),
    );

    return RefreshOnReturn(
      id: 'services.dashboard',
      maxAge: _staleAfter,
      // The same refresh a re-tap of the tab performs, rather than a second
      // path to the same invalidations — and silent, because nobody pressed
      // anything.
      onStale: () => ref.triggerNavigationRefresh(NavigationSection.dashboard),
      child: AmbientScaffold(
        // No accent passed: the room on this screen is lit by the brand primary.
        // Seventeen service accents cannot light one room, so identity is
        // confined to each stack card's glyph and its wash — see the Room Light
        // Rule's one documented exception in DESIGN.md.
        // "Dashboard", because the crumb and the tab both say Dashboard and
        // the app bar is *where you are*. The h1 below is what you are looking
        // at — the fleet — and the two are different sentences. The desktop
        // shell's window strip already carries the crumb, which is why the
        // canvas draws nothing between it and the h1.
        appBar: const GlassAppBar(title: Text('Dashboard')),
        body: allUnconfigured
            // The page owns the viewport, not the empty state — see the contract
            // on `AppEmptyState`. Its height is entirely text, and at an
            // accessibility reading size a 72pt icon well, a wrapped title, a
            // two-line message and a button clear a short phone, taking the only
            // button on the screen with them. The `minHeight` keeps it centred
            // while it fits, so nothing moves at the default reading size.
            //
            // Default physics deliberately: there is no `RefreshIndicator` on this
            // branch, because with nothing configured there is nothing to re-fetch
            // — the screen rebuilds off settings.
            ? LayoutBuilder(
                builder: (context, constraints) => SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight,
                    ),
                    // The nav bar floats *over* this branch, so centring in the
                    // full viewport puts the optical centre behind it and the
                    // block reads low. Reserving the clearance inside the centring
                    // box is what lifts it back onto the visible middle.
                    child: Padding(
                      padding: EdgeInsets.only(bottom: bottomPadding),
                      child: _ServicesEmptyState(
                        onSetUpServices: () => context.go('/settings/services'),
                      ),
                    ),
                  ),
                ),
              )
            : RefreshIndicator(
                onRefresh: () => _refreshServicesDashboard(ref),
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.only(bottom: bottomPadding),
                  // Three questions, in this order: *is everything all right* →
                  // *what needs me* → *what is happening*. The stack itself is
                  // fourth — it is a launcher, not the headline.
                  //
                  //  * the header is one line of StackReadout under the h1, and
                  //    it is neutral when clear: no permanent green
                  //  * the band is absent unless something stopped answering
                  //  * decisions is the centre of the screen and is absent when
                  //    nothing is waiting — presence is the signal
                  //  * the stack is the instrument and the launcher
                  //  * In flight is what is moving without you
                  //  * Recently added is what landed, and the only thing here
                  //    that leads into a library
                  children: const [
                    _StackHeadline(),
                    ServicesAlertBand(),
                    DashboardDecisionsSection(),
                    ServiceMatrix(),
                    ServicesInFlightSection(),
                    ServicesRecentlyAddedSection(),
                  ],
                ),
              ),
      ),
    );
  }
}

/// The h1 and the one line under it.
///
/// `Your stack`, not `Dashboard` (decision 2). The tab and the crumb already say
/// Dashboard twice over; the h1 is the one line on the screen that can say what
/// is being looked at instead of where you are, and the fleet *is* the subject
/// here.
///
/// The sentence under it is [StackReadout]'s, counting **connections folded per
/// service** rather than the lensed summary — so a Radarr with one of its two
/// connections dark reads as *degraded* rather than inheriting whichever answer
/// the lens happened to be pointing at.
class _StackHeadline extends ConsumerWidget {
  const _StackHeadline();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final readout = ref.watch(stackReadoutProvider);
    final sentence = readout.sentenceAt(DateTime.now());

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
              style: theme.textTheme.headlineSmall
                  ?.weight(FontWeight.w700)
                  .copyWith(color: colorScheme.onSurface),
            ),
            const SizedBox(height: 2),
            Text(
              sentence,
              // Neutral, always — no permanent green. A stack that is entirely
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

/// The ring at rest, and the claim it makes.
///
/// This is the same object onboarding opens with, which is what makes "Skip for
/// now" cost nothing: the promise persists as the empty state instead of
/// evaporating into a grey placeholder, and the button leads back into the same
/// pick step. Deliberately *not* [AppEmptyState] — that widget is for a region
/// that came up empty, and this screen is the product's front door on a first
/// run.
class _ServicesEmptyState extends StatelessWidget {
  const _ServicesEmptyState({required this.onSetUpServices});
  final VoidCallback onSetUpServices;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xl,
        vertical: AppSpacing.xxl,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          ServiceRing(
            states: const {},
            diameter: serviceRingDiameter(context, preferred: 268),
            spin: true,
          ),
          const SizedBox(height: AppSpacing.xl),
          Text(
            'Nothing answers yet.',
            style: theme.textTheme.titleLarge!
                .weight(FontWeight.w700)
                .copyWith(color: scheme.onSurface),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            '${ServiceKey.values.length} services are waiting for an address. '
            'Light one up and this screen fills in.',
            style: theme.textTheme.bodyMedium!.copyWith(
              color: scheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.xl),
          FilledButton(
            onPressed: onSetUpServices,
            child: const Text('Pick your services'),
          ),
        ],
      ),
    );
  }
}

/// Pull-to-refresh: drop everything the screen shows, then hold the spinner
/// until the slowest of it has actually come back.
///
/// `onRefresh` used to be `() async => _invalidateServicesDashboard(ref)`, whose
/// future completes on the same microtask — so the indicator retracted while
/// thirteen summaries and three merged lists were still in flight. A control-room
/// screen that says "done" before it has re-read anything is worse than one with
/// no refresh: the user reads the stale figure as the fresh one.
///
/// Failures are swallowed rather than propagated. Every source here already
/// degrades to `[]`/offline and paints its own state; letting one rejection out
/// would abort `Future.wait` and retract the spinner early — the exact bug being
/// fixed, restored by the unhappy path.
Future<void> _refreshServicesDashboard(WidgetRef ref) async {
  _invalidateServicesDashboard(ref);

  Future<void> settle(Future<Object?> pending) async {
    try {
      await pending;
    } catch (_) {}
  }

  await Future.wait([
    for (final service in ServiceKey.values)
      settle(ref.read(serviceSummaryProvider(service).future)),
    settle(ref.read(servicesQueueProvider.future)),
    settle(ref.read(dashboardDecisionsProvider.future)),
    settle(ref.read(servicesRecentlyAddedProvider.future)),
  ]);
}

void _invalidateServicesDashboard(WidgetRef ref) {
  for (final service in ServiceKey.values) {
    ref.invalidate(serviceSummaryProvider(service));
    // The matrix's live line is the reason to pull-to-refresh this screen, and
    // it was the one thing refresh did not touch: the KPI providers were only
    // ever invalidated from the individual service pages.
    ref.invalidate(serviceKpiProvider(service));
    ref.invalidate(serviceSignalProvider(service));
    // The stack card's two figures. Reduced from the same KPI list, but its own
    // `autoDispose` family entry — invalidating only the single-figure provider
    // left the cards showing the figures from before the pull.
    ref.invalidate(serviceSignalPairProvider(service));
  }
  ref.invalidate(servicesRequestsProvider);
  ref.invalidate(servicesQueueProvider);
  // One history read per arr, feeding both Recently added and the failed-import
  // decisions. Invalidated at the source rather than through either of its two
  // readers, so the two cannot end up disagreeing about the same page.
  ref.invalidate(servicesArrHistoryProvider);
  ref.invalidate(servicesRecentlyAddedProvider);
  ref.invalidate(dashboardDecisionsProvider);
  // The library providers the KPI builders read through — and therefore the two
  // figures on every stack card. Invalidating `serviceKpiProvider` alone would
  // recompute the same numbers from the same cached libraries, which is a pull
  // that looks like it worked and changes nothing. The recently-added rail no
  // longer reads these: it rides one history page per arr.
  ref.invalidate(servicesMoviesProvider);
  ref.invalidate(servicesSeriesProvider);
  ref.invalidate(servicesMusicProvider);
}
