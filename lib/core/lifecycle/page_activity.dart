import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/utils/side_pane_route.dart';
import 'package:cupola/features/release_search/presentation/release_search_lifecycle.dart';

/// Why a page is not allowed to spend anything.
///
/// Ordered by how far the page is from the user's eye, so [PageActivity.reason]
/// names the outermost cause: the one worth logging when a poller went quiet.
enum PageInactiveReason {
  appBackgrounded,
  branchInactive,
  coveredByPortal,
  coveredByRoute,
}

/// The answer to one question: *is this page the page the user is looking at?*
///
/// Four independent facts, resolved at the widget that asks. Anything costing
/// network, battery or frame budget is expected to consult this and stop when it
/// says no; see [watchPageActivity] for the contract that makes the dependency
/// automatic.
@immutable
class PageActivity {
  const PageActivity({
    required this.branchActive,
    required this.routeIsCurrent,
    required this.appInForeground,
    required this.portalCovering,
  });

  /// Live, with nothing in the way: the default a screen sees outside the shell.
  const PageActivity.live()
    : this(
        branchActive: true,
        routeIsCurrent: true,
        appInForeground: true,
        portalCovering: false,
      );

  final bool branchActive;
  final bool routeIsCurrent;
  final bool appInForeground;
  final bool portalCovering;

  /// The one predicate. `&&`, never `||`: every signal is a veto.
  bool get isLive =>
      appInForeground && branchActive && !portalCovering && routeIsCurrent;

  PageInactiveReason? get reason {
    if (!appInForeground) return PageInactiveReason.appBackgrounded;
    if (!branchActive) return PageInactiveReason.branchInactive;
    if (portalCovering) return PageInactiveReason.coveredByPortal;
    if (!routeIsCurrent) return PageInactiveReason.coveredByRoute;
    return null;
  }

  @override
  bool operator ==(Object other) =>
      other is PageActivity &&
      other.branchActive == branchActive &&
      other.routeIsCurrent == routeIsCurrent &&
      other.appInForeground == appInForeground &&
      other.portalCovering == portalCovering;

  @override
  int get hashCode => Object.hash(
    branchActive,
    routeIsCurrent,
    appInForeground,
    portalCovering,
  );

  @override
  String toString() =>
      'PageActivity(live: $isLive${reason == null ? '' : ', ${reason!.name}'})';
}

/// Resolves [PageActivity] for the calling widget, registering a dependency on
/// every one of the four signals.
///
/// **Must be called from `build`.** Each read here is an inherited-widget or
/// provider dependency, and that is the whole mechanism: when a branch goes
/// offstage, when a page is pushed on top, when the Portal opens, or when the app
/// leaves the foreground, the caller rebuilds and re-decides. Nothing polls the
/// gate; the gate pushes.
///
/// The defaults are deliberately permissive: no scope found means live, so a
/// screen under test in isolation, or hosted outside the shell (`/import/*`,
/// `/onboarding`), behaves exactly as it does today.
PageActivity watchPageActivity(BuildContext context, WidgetRef ref) =>
    PageActivity(
      branchActive: BranchActivityScope.isActiveOf(context),
      // A page beside a tablet's pane is on screen though the slot over it
      // is the current route (`SidePaneSlotRoute`).
      routeIsCurrent:
          (ModalRoute.isCurrentOf(context) ?? true) ||
          SidePaneScope.hostsOf(context),
      appInForeground: ref.watch(appInForegroundProvider),
      portalCovering: PageCoverageScope.coveringOf(context),
    );

extension PageGatedWatch on WidgetRef {
  /// Watches [poller] only while this page is the one on screen.
  ///
  /// The single line a screen writes. [poller] is expected to be an `autoDispose`
  /// provider built with `Ref.gatedPoll`: dropping this watch drops its last
  /// listener, which cancels the timer. Returns the resolved activity, so a
  /// caller that wants to render a "paused" affordance has it to hand.
  ///
  /// Typed as `Provider<void>` rather than any listenable: a gated poller
  /// produces no value, and a provider that does is a data source, which is not
  /// what this gate is for.
  PageActivity watchWhileLive(BuildContext context, Provider<void> poller) {
    final activity = watchPageActivity(context, this);
    if (activity.isLive) watch(poller);
    return activity;
  }
}

/// Marks a branch subtree as the active one.
///
/// Emitted by the shell's branch container next to, never instead of,
/// [TickerMode]. Deliberately its own widget rather than reading
/// `TickerMode.of`: `TickerMode` means "animations are muted here", which is a
/// superset of "this branch is hidden" that any widget is free to switch off for
/// its own local reasons. Coupling the network gate to it would let a local
/// animation decision silently stop polling in a different file.
class BranchActivityScope extends InheritedWidget {
  const BranchActivityScope({
    super.key,
    required this.isActive,
    required this.branchIndex,
    required super.child,
  });

  final bool isActive;
  final int branchIndex;

  /// True when no scope is found: outside the shell there are no branches, so
  /// there is nothing to be inactive.
  static bool isActiveOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<BranchActivityScope>()
          ?.isActive ??
      true;

  static int? branchIndexOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<BranchActivityScope>()?.branchIndex;

  @override
  bool updateShouldNotify(BranchActivityScope oldWidget) =>
      isActive != oldWidget.isActive || branchIndex != oldWidget.branchIndex;
}

/// Reports that something inside the shell is covering the whole page.
///
/// Today that is exactly one thing: the Portal. It is not a route, so
/// [ModalRoute.isCurrentOf] cannot see it, and the snapshot it takes freezes the
/// page's *pixels* while its timers keep running; a poller behind an open Portal
/// would go on hitting the network to update something nobody can see.
///
/// An [InheritedNotifier] over a boolean, not over the open/close animation:
/// dependents must rebuild twice per gesture, not sixty times a second.
class PageCoverageScope extends InheritedNotifier<ValueListenable<bool>> {
  const PageCoverageScope({
    super.key,
    required ValueListenable<bool> covering,
    required super.child,
  }) : super(notifier: covering);

  static bool coveringOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<PageCoverageScope>()
          ?.notifier
          ?.value ??
      false;
}
