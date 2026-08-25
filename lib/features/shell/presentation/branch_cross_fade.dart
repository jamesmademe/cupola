import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/app_animation.dart';
import 'package:cupola/core/lifecycle/page_activity.dart';

/// The container for the shell's branch navigators.
///
/// Replaces `StatefulShellRoute.indexedStack`'s own container for one reason:
/// that one swaps branches with no transition at all, and a hard cut between two
/// opaque full-screen surfaces reads as a glitch rather than as a move. It keeps
/// everything else that container does — including, load-bearing, the
/// [Offstage] + [TickerMode] pair described on [_BranchLayer].
///
/// Uniform on every platform by construction: no `TargetPlatform` is consulted
/// anywhere here. Tabs are siblings, and a fade is what Material prescribes for
/// moving between top-level destinations — the platform page transitions (on
/// Android, a zoom that cost 30–38ms of raster per frame on a real device) are
/// for pushing a child over a parent, which is what a branch root's own page
/// transition still does.
Widget buildBranchCrossFade(
  BuildContext context,
  StatefulNavigationShell navigationShell,
  List<Widget> children,
) => BranchCrossFade(
  currentIndex: navigationShell.currentIndex,
  children: children,
);

/// The container itself, taking the index rather than the shell.
///
/// Public because [StatefulNavigationShell] cannot be constructed outside
/// go_router, and the index is the only thing this reads off it: a test drives
/// the real widget instead of a stand-in for it.
class BranchCrossFade extends StatefulWidget {
  const BranchCrossFade({
    super.key,
    required this.currentIndex,
    required this.children,
  });

  final int currentIndex;
  final List<Widget> children;

  @override
  State<BranchCrossFade> createState() => _BranchCrossFadeState();
}

class _BranchCrossFadeState extends State<BranchCrossFade>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fade = AnimationController(
    vsync: this,
    duration: AppAnimation.durationSm,
    value: 1,
  );

  late final Animation<double> _incoming = _fade.drive(
    CurveTween(curve: AppAnimation.emphasizedCurve),
  );
  late final Animation<double> _outgoing = ReverseAnimation(_incoming);

  /// The branch being shown. Tracked separately from the widget's own index so
  /// the frame the index changes still knows where it came from.
  late int _current = widget.currentIndex;

  /// The branch fading out, or null when the shell is settled. Only these two
  /// layers are ever onstage at once.
  int? _outgoingIndex;

  @override
  void dispose() {
    _fade.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(BranchCrossFade oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.currentIndex == _current) return;

    _outgoingIndex = _current;
    _current = widget.currentIndex;

    if (MediaQuery.disableAnimationsOf(context)) {
      _fade.value = 1;
      _outgoingIndex = null;
      return;
    }

    _fade.forward(from: 0).whenCompleteOrCancel(() {
      if (mounted) setState(() => _outgoingIndex = null);
    });
  }

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      for (var index = 0; index < widget.children.length; index++)
        _BranchLayer(
          key: ValueKey<int>(index),
          branchIndex: index,
          isCurrent: index == _current,
          isOutgoing: index == _outgoingIndex,
          opacity: index == _current ? _incoming : _outgoing,
          child: widget.children[index],
        ),
    ],
  );
}

/// One branch, in whichever of the three states it is in: current, fading out,
/// or put away.
class _BranchLayer extends StatelessWidget {
  const _BranchLayer({
    super.key,
    required this.branchIndex,
    required this.isCurrent,
    required this.isOutgoing,
    required this.opacity,
    required this.child,
  });

  final int branchIndex;
  final bool isCurrent;
  final bool isOutgoing;
  final Animation<double> opacity;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // Both wrappers are go_router's own, reproduced deliberately rather than
    // inherited, because this container replaces the one that used to apply
    // them. Neither may be simplified away:
    //
    //  * `Offstage` is what stops a put-away branch laying out, painting,
    //    hit-testing or reaching a screen reader.
    //  * `TickerMode(enabled:)` is what mutes its `AnimationController`s — the
    //    service ring's spinner and every shimmer placeholder are silenced by
    //    this line and by nothing else in the app. Dropping it sets them
    //    animating behind a tab nobody is looking at.
    //
    // `TickerMode` follows `isCurrent` rather than visibility: an outgoing
    // branch is frozen for the 200ms it spends fading away, which nobody can
    // see, and which keeps the gate's answer binary.
    return Offstage(
      offstage: !(isCurrent || isOutgoing),
      child: TickerMode(
        enabled: isCurrent,
        child: BranchActivityScope(
          isActive: isCurrent,
          branchIndex: branchIndex,
          child: ExcludeSemantics(
            excluding: !isCurrent,
            child: IgnorePointer(
              ignoring: !isCurrent,
              // `FadeTransition`, not `Opacity`: it listens for repaint only —
              // no rebuild per frame — and skips its layer entirely at opacity
              // 1, so a settled shell pays nothing for the machinery. The
              // boundary hands the engine a cached raster to blend during the
              // fade instead of re-rasterising a whole screen every frame.
              child: FadeTransition(
                opacity: opacity,
                child: RepaintBoundary(child: child),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
