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
/// The transition is the arriving branch fading and rising over the one it
/// replaces, and every part of that sentence was settled by measurement on a
/// physical device rather than by taste. Cross-fading both layers cost 18ms of
/// average raster per switch against 10ms for a hard cut, because two
/// full-screen `saveLayer`s per frame is the same bill the Android zoom
/// transition was dropped for. Fading only the incoming layer halves that, and
/// the rise happens inside the layer the fade already pays for.
///
/// Uniform on every platform by construction: no `TargetPlatform` is consulted
/// anywhere here. Tabs are siblings, and a fade is what Material prescribes for
/// moving between top-level destinations — the platform page transitions are for
/// pushing a child over a parent, which is what a branch root's own page
/// transition still does.
Widget buildBranchTransition(
  BuildContext context,
  StatefulNavigationShell navigationShell,
  List<Widget> children,
) => BranchTransition(
  currentIndex: navigationShell.currentIndex,
  children: children,
);

/// The container itself, taking the index rather than the shell.
///
/// Public because [StatefulNavigationShell] cannot be constructed outside
/// go_router, and the index is the only thing this reads off it: a test drives
/// the real widget instead of a stand-in for it.
class BranchTransition extends StatefulWidget {
  const BranchTransition({
    super.key,
    required this.currentIndex,
    required this.children,
  });

  final int currentIndex;
  final List<Widget> children;

  @override
  State<BranchTransition> createState() => _BranchTransitionState();
}

class _BranchTransitionState extends State<BranchTransition>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fade = AnimationController(
    vsync: this,
    duration: AppAnimation.durationSm,
    value: 1,
  );

  late final Animation<double> _incoming = _fade.drive(
    CurveTween(curve: AppAnimation.emphasizedCurve),
  );

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
  void didUpdateWidget(BranchTransition oldWidget) {
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
  Widget build(BuildContext context) {
    // Paint order, not branch order: the incoming branch goes LAST so it is on
    // top of the one it is replacing.
    //
    // Ordering by index instead was a bug with a tell — the fade only showed in
    // one direction. Going to a higher-numbered tab it landed on top and faded
    // in; going to a lower-numbered one it faded in *underneath* a fully opaque
    // layer, which is invisible, and read as the hard cut this transition exists
    // to avoid.
    //
    // The keys are what make reordering safe: each layer holds a branch's
    // Navigator, so it has to be re-parented rather than rebuilt.
    final order = [
      for (var index = 0; index < widget.children.length; index++)
        if (index != _current) index,
      _current,
    ];

    return Stack(
      fit: StackFit.expand,
      children: [
        for (final index in order)
          _BranchLayer(
            key: ValueKey<int>(index),
            branchIndex: index,
            isCurrent: index == _current,
            isOutgoing: index == _outgoingIndex,
            opacity: index == _current ? _incoming : null,
            child: widget.children[index],
          ),
      ],
    );
  }
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

  /// Null for a layer that is not animating, which is every layer but the
  /// incoming one.
  final Animation<double>? opacity;
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
              // The incoming branch fades in OVER the outgoing one, which keeps
              // its full opacity underneath and therefore needs no opacity
              // layer at all.
              //
              // Cross-fading the two instead — each in its own FadeTransition —
              // was measured on device at 18ms of average raster per switch
              // against 10ms for a hard cut: two full-screen `saveLayer`s per
              // frame, which is the same bill the Zoom transition was dropped
              // for. One layer buys the move for about a millisecond.
              //
              // The rise is a transform inside that one layer, so it is free:
              // a bare opacity ramp on a whole screen reads as a dissolve, and
              // what a tab switch wants to say is that something arrived.
              // Small on purpose — 4% over 200ms — because the destination must
              // not appear to zoom.
              child: opacity == null
                  ? RepaintBoundary(child: child)
                  : FadeTransition(
                      opacity: opacity!,
                      child: ScaleTransition(
                        scale: Tween<double>(
                          begin: 0.96,
                          end: 1,
                        ).animate(opacity!),
                        child: RepaintBoundary(child: child),
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
