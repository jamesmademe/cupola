import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/lifecycle/page_activity.dart';
import 'package:cupola/core/providers/navigation_refresh_provider.dart';
import 'package:cupola/core/service_theme.dart';
import 'package:cupola/core/utils/a11y_announce.dart';
import 'package:cupola/core/widgets/floating_bottom_nav_bar.dart';
import 'package:cupola/features/release_search/presentation/release_search_jobs_provider.dart';
import 'package:cupola/features/release_search/presentation/release_search_lifecycle.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/nav_tab.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/shell/domain/portal_hints.dart';
import 'package:cupola/features/shell/domain/shell_branches.dart';
import 'package:cupola/features/shell/presentation/portal_coach_mark.dart';
import 'package:cupola/features/shell/presentation/service_portal.dart';

/// Main shell screen with floating bottom navigation.
///
/// Uses a custom [FloatingBottomNavBar] with rounded corners and floating design.
/// Outlined icons for unselected state and filled icons for selected state.
class ShellScreen extends ConsumerStatefulWidget {
  /// The four branch navigators, and the tab index that says which one shows.
  ///
  /// Carries a `GlobalKey` of its own, so crossing the rail breakpoint
  /// re-parents it instead of rebuilding it: every branch's stack survives a
  /// resize, which the single-navigator shell could not offer.
  final StatefulNavigationShell navigationShell;

  const ShellScreen({super.key, required this.navigationShell});

  /// Width at or above which navigation moves from a bottom bar to a side rail.
  ///
  /// 840 rather than 600: at 600 a phone in landscape (roughly 850pt wide on a
  /// modern iPhone) also got the rail, replacing the thumb-reachable bottom bar
  /// with a side rail on a device held in two hands. 840 is Material's
  /// expanded-window breakpoint and keeps phones on the bar in both
  /// orientations, while tablets and desktop windows still get the rail.
  static const double _railBreakpoint = 840;

  @override
  ConsumerState<ShellScreen> createState() => _ShellScreenState();
}

class _ShellScreenState extends ConsumerState<ShellScreen>
    with TickerProviderStateMixin {
  /// One Portal per shell: the machine behind the bar's upward drag.
  ///
  /// Created eagerly in [initState]: as a `late final` initializer its first
  /// access could be [dispose] (rail layout never touches it in build), and
  /// creating a ticker during unmount trips the deactivated-ancestor assert.
  late final ServicePortalController _portal;

  String? _lastLocation;

  /// The lens map as it was the last time this built.
  ///
  /// Held by identity rather than by value: [ActiveInstancesNotifier] hands out
  /// a fresh `Map` on every `select`, and never otherwise, so `identical` is
  /// exactly the question "did somebody move a lens since the last frame" — and
  /// it costs no comparison of seventeen entries to ask it.
  Map<ServiceKey, String>? _lastLenses;
  Timer? _demoTimer;

  @override
  void initState() {
    super.initState();
    _portal = ServicePortalController(vsync: this);
    // Using the Portal is the proof the coach mark is no longer needed.
    _portal.onOpened = () =>
        ref.read(portalHintsProvider.notifier).notePortalUsed();
    WidgetsBinding.instance.addPostFrameCallback((_) => _armDemoBounce());
  }

  /// The one-shot demo bounce (Settings → Hints re-arms it): only on the phone
  /// layout, never under a screen reader, and only while the Portal is idle.
  /// A cancellable timer, not a bare delay: the shell may be torn down first.
  void _armDemoBounce() {
    if (!mounted) return;
    if (MediaQuery.sizeOf(context).width >= ShellScreen._railBreakpoint) return;
    if (MediaQuery.accessibleNavigationOf(context)) return;
    if (!ref.read(portalHintsProvider).demoBouncePending) return;
    // A breath after the first frame: the bounce has to read as a gesture of
    // the bar, not as a startup glitch.
    _demoTimer = Timer(const Duration(milliseconds: 700), () {
      if (!mounted || !ref.read(portalHintsProvider).demoBouncePending) return;
      ref.read(portalHintsProvider.notifier).markDemoShown();
      _portal.playDemoBounce();
    });
  }

  @override
  void dispose() {
    _demoTimer?.cancel();
    _portal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Straight off the shell, which is the authority: with four stacks the
    // location and the visible branch can disagree — an imperative push from
    // another tab lands on this branch while the path reads like somebody
    // else's — and it is the branch that the bar must agree with.
    final selectedIndex = widget.navigationShell.currentIndex;
    final useRail =
        MediaQuery.sizeOf(context).width >= ShellScreen._railBreakpoint;
    // The Portal's drag is unusable under a screen reader; there the bar keeps
    // its pure elastic and switching stays on the accessible paths.
    final accessibleNav = MediaQuery.accessibleNavigationOf(context);

    // Any change to what sits under the card closes an open Portal and drops
    // the stale snapshot. Post-frame: starting animations inside build is not
    // allowed.
    //
    // TWO inputs, not one, and the second is the whole of this hook's
    // multi-instance story. The path is the obvious one. The other is the
    // LENS: a picker cell travelling from Radarr · 4K to Radarr · HD calls
    // `go('/services/radarr')` both times, so `uri.path` is byte-identical
    // across a travel that changes every pixel under the card. Watched here
    // rather than solved at the cell, because this is already the one place
    // that decides the Portal closes because its content moved, and the badge
    // sheet can move a lens too.
    //
    // The path comparison stays on the FULL path — never weaken it to the
    // service's routeParam. A hook keyed on the service alone would hold the
    // Portal open across `/services/radarr` → `/services/radarr/movie/12`.
    //
    // And this hook is only half the story: it is REACTIVE, and closing on an
    // ACTION lives elsewhere. A picker cell closes the Portal itself, through
    // `PortalDismissScope`, because a tap that navigates to the path it is
    // already on without moving the lens moves neither of the two inputs below
    // and is invisible from here. Do not answer that case by widening these
    // conditions — the question this hook asks ("has the content under the card
    // moved, so is the snapshot dead?") is a different one, and it is right.
    final location = GoRouterState.of(context).uri.path;
    final lenses = ref.watch(activeInstancesProvider);
    final pathMoved = _lastLocation != null && _lastLocation != location;
    final lensMoved = _lastLenses != null && !identical(_lastLenses, lenses);
    _lastLenses = lenses;
    if (pathMoved || lensMoved) {
      if (_portal.isOpenOrEngaged) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _portal.handleRouteChanged();
        });
      } else if (pathMoved &&
          // Spelled out rather than left to the arithmetic: a lens moving with
          // the path unchanged cannot satisfy the two tests below, but the
          // journey being counted is a *journey*, and it should say so.
          _lastLocation == NavTab.services.routePath &&
          location.startsWith('${NavTab.services.routePath}/')) {
        // Dashboard → service without going through the Portal: exactly the
        // journey the Portal replaces. The coach mark counts these.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            ref.read(portalHintsProvider.notifier).noteManualJourney();
          }
        });
      }
    }
    _lastLocation = location;

    // Built once, above the layout branch, and handed to whichever navigation
    // this window is wide enough for. The rail used to build its own bare
    // `NavigationRailDestination`s, which is how it ended up as the one surface
    // where a finished search never showed a badge — the channel that has to
    // keep working when notifications are denied, off, or missed.
    final searchesWaiting = ref.watch(unseenReleaseSearchCountProvider);
    final destinations = NavTab.values
        .map((tab) => _destinationFor(tab, searchesWaiting))
        .toList(growable: false);

    // Outside the branch, so it wraps *both* layouts and survives a resize.
    // Inside the phone branch it was two bugs at once: on macOS and tablet
    // nothing ever observed the app lifecycle — `appInForegroundProvider` stayed
    // permanently true, `noteBackgrounded()` never fired (so a search the OS
    // killed was blamed on the network instead of on leaving the app) and
    // `refreshWindows()` never ran on resume — and dragging a window across
    // 840pt mounted or unmounted the observer mid-session.
    return ReleaseSearchLifecycle(
      child: useRail
          ? Scaffold(
              body: Row(
                children: [
                  // SafeArea on the rail side only: on a tablet held on its
                  // side the camera housing and the rounded corner sit on the
                  // leading edge, and the rail was laid out underneath them.
                  // The content keeps its own insets. Only tablets reach this
                  // branch on touch — the phone is portrait-only and never
                  // 840pt wide — but tablets still rotate, so the inset is
                  // real.
                  SafeArea(
                    right: false,
                    child: _ServicesNavRail(
                      selectedIndex: selectedIndex,
                      destinations: destinations,
                      onDestinationSelected: (int idx) =>
                          _onItemTapped(idx, context, selectedIndex),
                    ),
                  ),
                  Expanded(child: widget.navigationShell),
                ],
              ),
            )
          : Scaffold(
              extendBody: true,
              body:
                  // The Portal is a cover the route system cannot see: it
                  // freezes the page's pixels while leaving its timers running.
                  // Scoping the stage tells whatever polls under there to stop —
                  // see `PageCoverageScope`.
                  PageCoverageScope(
                    covering: _portal.covering,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        PortalStage(
                          controller: _portal,
                          child: widget.navigationShell,
                        ),
                        if (!accessibleNav)
                          PortalCoachMark(controller: _portal),
                      ],
                    ),
                  ),
              bottomNavigationBar: FloatingBottomNavBar(
                selectedIndex: selectedIndex,
                onDestinationSelected: (int idx) =>
                    _onItemTapped(idx, context, selectedIndex),
                destinations: destinations,
                verticalDragDelegate: accessibleNav ? null : _portal,
              ),
            ),
    );
  }

  void _onItemTapped(int index, BuildContext context, int currentIndex) {
    HapticFeedback.selectionClick();

    // A tab tap with the Portal open always closes it; landing on the tab is
    // the rest of the answer. A re-tap on the current tab then stops there —
    // "take me back where I was" must not also fire a refresh.
    final portalWasOpen = _portal.isOpenOrEngaged;
    if (portalWasOpen) _portal.closeFromUi();

    final tab = NavTab.values[index];

    if (index == currentIndex) {
      if (portalWasOpen) return;

      // "Am I deep in this tab?" asked of the branch's own Navigator rather
      // than by comparing the location to the tab's root path. The comparison
      // was right while one stack meant the location and the visible page could
      // not disagree; with four of them they can, and whether this branch has
      // something to pop is the structural question anyway.
      if (branchNavigatorKeyFor(tab).currentState?.canPop() ?? false) {
        // Take me back where I started. `initialLocation: true` navigates the
        // branch to its root, which pops it and nothing else: a return journey
        // must not also fire a fetch.
        widget.navigationShell.goBranch(index, initialLocation: true);
        return;
      }

      final section = _refreshSectionFor(tab);
      if (section != null) {
        ref.triggerNavigationRefresh(section);
        // A re-tap refresh changes nothing on screen — no spinner, no route
        // change, no focus move — so for a screen-reader user it is otherwise
        // indistinguishable from a no-op. Start only: the shell never learns
        // when the invalidated providers settle, so there is no completion to
        // announce.
        announce(context, 'Refreshing ${tab.label}');
      }
      return;
    }

    // Not announced: switching tabs replaces the whole screen, which is its own
    // feedback. `goBranch`, not `go`: it restores the branch's own stack, which
    // is the entire point of the four navigators.
    widget.navigationShell.goBranch(index);
  }

  FloatingNavDestination _destinationFor(NavTab tab, int searchesWaiting) {
    // Only Activity carries a count, and only for finished searches nobody has
    // opened — the channel that has to keep working when notifications are
    // denied, off, or missed.
    final badge = tab == NavTab.activity ? searchesWaiting : 0;
    return FloatingNavDestination(
      icon: tab.icon,
      selectedIcon: tab.selectedIcon,
      label: tab.label,
      accentColor: tab.accentColor,
      badgeCount: badge,
      badgeSemanticLabel: badge == 0
          ? null
          : '$badge finished search${badge == 1 ? '' : 'es'} to look at',
    );
  }

  NavigationSection? _refreshSectionFor(NavTab tab) {
    switch (tab) {
      case NavTab.services:
        return NavigationSection.services;
      case NavTab.activity:
        return NavigationSection.activity;
      case NavTab.search:
        return NavigationSection.search;
      case NavTab.settings:
        return null;
    }
  }
}

/// Side navigation shown on tablet and desktop widths.
///
/// Takes the *same* [FloatingNavDestination] list the bottom bar does rather
/// than rebuilding one from [NavTab]. That is the whole point: badge counts and
/// their spoken labels are set in one place, so a desktop window cannot end up
/// as the one form factor where a finished search is never announced.
class _ServicesNavRail extends StatelessWidget {
  const _ServicesNavRail({
    required this.selectedIndex,
    required this.destinations,
    required this.onDestinationSelected,
  });

  final int selectedIndex;
  final List<FloatingNavDestination> destinations;
  final ValueChanged<int> onDestinationSelected;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return NavigationRail(
      selectedIndex: selectedIndex >= 0 ? selectedIndex : null,
      onDestinationSelected: onDestinationSelected,
      labelType: NavigationRailLabelType.all,
      backgroundColor: colorScheme.surfaceContainerLow,
      indicatorColor: colorScheme.secondaryContainer,
      destinations: [
        for (final destination in destinations)
          NavigationRailDestination(
            icon: _RailBadgedIcon(
              destination: destination,
              icon: destination.icon,
            ),
            selectedIcon: _RailBadgedIcon(
              destination: destination,
              icon: destination.selectedIcon,
            ),
            // The count joins the *spoken* label the way the bottom bar does it:
            // a number painted on an icon is invisible to a screen reader, and
            // the badge itself is excluded so it is not then read twice.
            label: Text(
              destination.label,
              semanticsLabel: destination.badgeSemanticLabel == null
                  ? null
                  : '${destination.label}, ${destination.badgeSemanticLabel}',
            ),
          ),
      ],
    );
  }
}

/// A rail icon carrying its destination's count, in the destination's own
/// accent — never a status tone, for the reason
/// [FloatingNavDestination.badgeCount] documents.
class _RailBadgedIcon extends StatelessWidget {
  const _RailBadgedIcon({required this.destination, required this.icon});

  final FloatingNavDestination destination;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    if (destination.badgeCount <= 0) return Icon(icon);
    return ExcludeSemantics(
      child: Badge.count(
        count: destination.badgeCount,
        backgroundColor: destination.accentColor,
        textColor: ServiceTheme.foregroundOn(destination.accentColor),
        child: Icon(icon),
      ),
    );
  }
}
