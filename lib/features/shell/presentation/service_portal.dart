/// The Portal: drag the nav bar upward and the current screen recedes into a
/// card, revealing the real Services matrix underneath — tap a card to travel.
///
/// ## The gesture, end to end
///
/// The bar's rubber-band drag (until now purely aesthetic) is the prelude of
/// the gesture. One line governs everything: the **trigger threshold**,
/// measured as the finger's travel from where the drag began. Below it the bar
/// follows the finger with elastic resistance and the screen anticipates
/// calmly ([PortalPhysics.cardAnticipation] of the finger's travel). At the
/// threshold: haptic, the bar eases home on its own, and the card's bottom
/// edge leaps to the finger and stays glued to it. Releasing only completes
/// the opening beyond the **safe zone** (or with a flick past the gate);
/// anything less springs everything back. While open: tap a matrix card to
/// travel, tap the receded card / pull the floor down / drag the bar down /
/// tap any tab to come back.
///
/// If the finger retreats after triggering, the bar rises slowly to meet it
/// and re-grabs the moment the finger returns to the height the bar had
/// reached — continuity, not a jump cut.
///
/// ## Why the numbers are literals and not [AppAnimation] tokens
///
/// Every constant in [PortalPhysics] was hand-tuned on the interactive mock
/// (2026-08-20, `lib/zz_portale_mock.dart`) until the feel was signed off.
/// Do not normalise them to the motion tokens without re-tuning by hand: the
/// values ARE the design.
///
/// ## Geometry is linear on purpose
///
/// The card's bottom edge is a *linear* function of the portal's `t`, so the
/// pixels the mappings ask for are the pixels on screen. Easing belongs to the
/// finger while dragging and to the spring after release — never to the map.
/// (The first mock routed `t` through an easing curve and the "calm
/// anticipation" became a 2pt whisper nobody could see.)
library;

import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';

import 'package:cupola/core/app_elevation.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/widgets/ambient_background.dart';
import 'package:cupola/core/widgets/floating_bottom_nav_bar.dart';
import 'package:cupola/features/services/presentation/service_matrix.dart';
import 'package:cupola/features/shell/presentation/portal_dismiss_scope.dart';

/// Hand-tuned physics of the Portal gesture. See the library doc before
/// touching anything here.
abstract final class PortalPhysics {
  /// Finger travel (pt, from drag start) that triggers the Portal. Also the
  /// bar's vertical ceiling: with the elastic below, the bar physically tops
  /// out around 23pt, so the clamp never bites before the trigger does.
  static const double threshold = 75.0;

  /// How much the bar follows the finger in the elastic zone (the vertical
  /// counterpart of the bar's own `_baseResistance`, retuned for the prelude).
  static const double baseResistance = 0.60;

  /// How quickly the elastic stiffens as the bar rises.
  static const double falloff = 7.0;

  /// Fraction of the finger's pre-trigger travel that the card's bottom edge
  /// anticipates ("the screen is already listening").
  static const double cardAnticipation = 0.80;

  /// Finger travel beyond which a release completes the opening on its own.
  static const double safeZone = 140.0;

  /// Release spring for the portal (open and close).
  static const double springStiffness = 520.0;
  static const double springDampingRatio = 0.95;

  /// Flick velocity (px/s) that completes upward / cancels downward
  /// regardless of position.
  static const double flickGate = 700.0;

  /// Card geometry at t = 1: top glides down by [cardTopInset], the card ends
  /// at `cardTopInset + cardScale * screenHeight`.
  static const double cardTopInset = 34.0;
  static const double cardScale = 0.42;
  static const double cardCornerRadius = 22.0;

  /// Mode-switch blends: the leap onto the finger, and the hand-back.
  static const Duration engageBlend = Duration(milliseconds: 160);
  static const Duration disengageBlend = Duration(milliseconds: 220);

  /// The bar easing home after the trigger, finger still down.
  static const Duration barHome = Duration(milliseconds: 260);

  /// The bar's release spring-back — same duration and curve as the bar's own
  /// aesthetic rubber band, so the two reads are one material.
  static const Duration barSpringBack = Duration(milliseconds: 500);
}

/// Owns the Portal state machine. The shell creates one per shell instance,
/// hands it to [FloatingBottomNavBar] as its vertical-drag delegate and to
/// [PortalStage] as the scene director.
class ServicePortalController implements FloatingNavBarVerticalDragDelegate {
  ServicePortalController({required TickerProvider vsync})
    : portal = AnimationController(
        vsync: vsync,
        duration: const Duration(milliseconds: 400),
      ),
      _barSpring = AnimationController(
        vsync: vsync,
        duration: PortalPhysics.barSpringBack,
      ),
      _blend = AnimationController(
        vsync: vsync,
        duration: PortalPhysics.engageBlend,
      ) {
    portal.addListener(_onPortalTick);
    _blend.addListener(_onBlendTick);
  }

  /// 0 = screen full-bleed, 1 = Portal open. Listen to repaint the stage.
  final AnimationController portal;

  /// Freezes the receding screen to a texture so the scrub costs the same on
  /// every page. Cleared whenever the content under the card changes.
  final SnapshotController snapshot = SnapshotController();

  final AnimationController _barSpring;
  final AnimationController _blend;
  final ValueNotifier<double> _lift = ValueNotifier<double>(0);

  Animation<double>? _barAnim;
  VoidCallback? _barAnimTick;

  double _rawUp = 0;
  double _dragStartY = 0;
  double _engageLift = 0;
  double _blendFrom = 0;
  bool _engaged = false;
  bool _closing = false;

  /// Where the last release spring was aimed, or null while the finger owns the
  /// Portal. Read by [closeFromUi] to tell "close it" from "close it again".
  double? _springTarget;

  /// Set by [PortalStage] each layout; the geometry has no other input.
  double screenHeight = 800;

  /// Fired when the Portal commits to opening: a release past the safe zone,
  /// or [openFromUi]. The shell uses it to reset the coach mark's need-counter —
  /// using the Portal is the proof the hint is no longer needed — and to say,
  /// once, what the floor holds.
  VoidCallback? onOpened;

  /// Whether the Portal is over the page under it.
  ///
  /// The page's own pixels are frozen by [snapshot] the moment this turns true,
  /// but its timers are not: a poller under an open Portal would go on fetching
  /// to update a texture. Pages read this through `PageCoverageScope` and stop.
  ///
  /// A boolean derived from [portal] rather than the animation itself, because
  /// what depends on it must rebuild when the Portal opens and when it closes —
  /// twice — and not on each of the 400ms of frames in between. Assigning an
  /// unchanged value to a [ValueNotifier] does not notify, so the debounce is
  /// the notifier's own.
  final ValueNotifier<bool> covering = ValueNotifier<bool>(false);

  @override
  ValueListenable<double> get verticalLift => _lift;

  bool get isOpenOrEngaged => _engaged || portal.value > 0.05;

  double get _finalBottom =>
      PortalPhysics.cardTopInset + screenHeight * PortalPhysics.cardScale;
  double get _travel => screenHeight - _finalBottom;

  // Before the trigger: the card anticipates the finger, calmly.
  double _tCalm(double raw) =>
      (PortalPhysics.cardAnticipation * raw / _travel).clamp(0.0, 1.0);

  // After the trigger: the card's bottom edge is glued to the finger.
  double _tGlued(double raw) {
    final bottom = (_dragStartY - raw).clamp(_finalBottom, screenHeight);
    return ((screenHeight - bottom) / _travel).clamp(0.0, 1.0);
  }

  double _liveT() => _engaged ? _tGlued(_rawUp) : _tCalm(_rawUp);

  void _switchMode({required bool engage}) {
    _blendFrom = portal.value;
    _blend.duration = engage
        ? PortalPhysics.engageBlend
        : PortalPhysics.disengageBlend;
    _blend.forward(from: 0);
  }

  // Applies the blend even with the finger perfectly still: without this the
  // leap would only advance when new drag events happen to arrive.
  void _onBlendTick() {
    if (_closing) return;
    final k = Curves.easeOutCubic.transform(_blend.value);
    portal.value = lerpDouble(_blendFrom, _liveT(), k)!;
  }

  void _onPortalTick() {
    final v = portal.value;
    if (v > 0 && !snapshot.allowSnapshotting) snapshot.allowSnapshotting = true;
    if (v == 0 && snapshot.allowSnapshotting) {
      snapshot.allowSnapshotting = false;
    }
    // Same threshold as the snapshot above: the page is covered from the first
    // frame it stops being what the user sees.
    covering.value = v > 0;
  }

  // ---------------------------------------------------------------- bar drag

  @override
  void onBarDragStart(double globalY) {
    portal.stop();
    _stopBarAnim();
    _blend.stop();
    // The finger has taken the Portal back, so whatever the last spring was
    // aiming at is no longer what is happening — and [closeFromUi] must arm
    // again for the release this drag ends in.
    _springTarget = null;
    _closing = portal.value > 0.5;
    _dragStartY = globalY;
    _engaged = false;
    _rawUp = 0;
  }

  @override
  void onBarDragDelta(double dy) {
    if (_closing) {
      portal.value = (portal.value - dy / _travel).clamp(0.0, 1.0);
      return;
    }
    _rawUp = math.max(0, _rawUp - dy); // up = positive

    if (!_engaged && _rawUp >= PortalPhysics.threshold) {
      // TRIGGER: haptic, the bar goes home on its own, the card leaps to the
      // finger.
      _engaged = true;
      _engageLift = _lift.value;
      HapticFeedback.lightImpact();
      _runBarAnim(PortalPhysics.barHome, Curves.easeOutCubic);
      _switchMode(engage: true);
    } else if (_engaged && _rawUp <= _engageLift) {
      // The finger is back at the height the bar had reached: immediate
      // re-grab, bar exactly under the finger.
      _engaged = false;
      HapticFeedback.selectionClick();
      _stopBarAnim();
      _lift.value = _rawUp;
      _switchMode(engage: false);
    }

    if (_engaged) {
      // Finger above threshold coming back down: the bar rises slowly to
      // meet it, so re-grab is a touch, not a cut.
      final approach =
          ((PortalPhysics.threshold - _rawUp) /
                  math.max(1.0, PortalPhysics.threshold - _engageLift))
              .clamp(0.0, 1.0);
      final lift = _engageLift * approach;
      if (lift > _lift.value || !_barSpring.isAnimating) {
        _stopBarAnim();
        _lift.value = lift;
      }
    } else {
      if (dy < 0) {
        // Rising: the bar's real elastic formula, portal-tuned parameters.
        final resistance =
            PortalPhysics.baseResistance /
            (1 + _lift.value / PortalPhysics.falloff);
        _lift.value = (_lift.value - dy * resistance).clamp(
          0.0,
          PortalPhysics.threshold,
        );
      } else if (_lift.value > 0) {
        // Descending while lifted: the bar is in the finger's hand, 1:1.
        _lift.value = math.max(0.0, _lift.value - dy);
      }
    }

    final k = _blend.isAnimating
        ? Curves.easeOutCubic.transform(_blend.value)
        : 1.0;
    portal.value = lerpDouble(_blendFrom, _liveT(), k)!;
  }

  @override
  void onBarDragEnd(double velocityY) {
    final vUp = -velocityY;
    _blend.stop();
    if (_closing) {
      _closing = false;
      _springTo(_releaseTarget(vUp, portal.value > 0.6), vUp / _travel);
      return;
    }
    // A release completes ONLY beyond the safe zone (or with a flick past the
    // gate); a downward flick always cancels.
    final commit =
        _engaged &&
        _releaseTarget(vUp, _rawUp >= PortalPhysics.safeZone) == 1.0;
    _engaged = false;
    if (_lift.value != 0) {
      _runBarAnim(PortalPhysics.barSpringBack, Curves.elasticOut);
    }
    if (commit) {
      HapticFeedback.mediumImpact();
      onOpened?.call();
    }
    _springTo(commit ? 1 : 0, vUp / _travel);
  }

  /// The demo bounce (Settings → Hints): the gesture's physics in miniature.
  /// The bar lifts 12pt, the screen anticipates ~9px, a beat, then both come
  /// back with the same elastic return a real release uses. No-op unless the
  /// Portal is fully idle; aborted if a real drag arrives mid-demo.
  Future<void> playDemoBounce() async {
    if (_engaged || _closing || portal.isAnimating || portal.value > 0) return;
    final anticipation = (9.0 / _travel).clamp(0.0, 0.05);
    _runBarAnim(
      const Duration(milliseconds: 240),
      Curves.easeOutCubic,
      end: 12,
    );
    await portal.animateTo(
      anticipation,
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
    );
    await Future<void>.delayed(const Duration(milliseconds: 140));
    if (_engaged || _closing) return; // il dito è arrivato davvero
    _runBarAnim(PortalPhysics.barSpringBack, Curves.elasticOut);
    _springTo(0, 0);
  }

  double _releaseTarget(double vUp, bool positionSaysOpen) {
    if (vUp <= -PortalPhysics.flickGate) return 0;
    if (vUp >= PortalPhysics.flickGate) return 1;
    return positionSaysOpen ? 1 : 0;
  }

  // ------------------------------------------------------------------- APIs

  /// Open without a finger: the tab bar's accessibility action.
  ///
  /// The same commit a release past the safe zone makes — [onOpened], then the
  /// release spring from rest — with no haptic, because there was no gesture
  /// for it to confirm. A no-op while the finger owns the Portal and while it is
  /// already open or opening, so a second activation cannot restart the spring.
  void openFromUi() {
    if (_engaged || _closing || _springTarget == 1) return;
    _blend.stop();
    if (_lift.value != 0) {
      _runBarAnim(PortalPhysics.barSpringBack, Curves.elasticOut);
    }
    onOpened?.call();
    _springTo(1, 0);
  }

  /// Close from any UI affordance: tab tap, tap on the receded card, floor
  /// pull-down, a picker cell being chosen. Safe to call when already closed,
  /// and safe to call twice.
  ///
  /// Idempotent on purpose, and that is load-bearing since the floor's cells
  /// started closing on the act: choosing a cell that also moves the lens asks
  /// for the close twice — once from the cell, once from the shell's route hook
  /// a frame later. A second [_springTo] would restart the spring from wherever
  /// the first had reached with zero velocity, which is a visible hitch
  /// two-thirds of the way home. So a close already under way is left to
  /// finish; anything that takes the Portal back — a new drag — clears the flag
  /// and this arms again.
  void closeFromUi() {
    if (_springTarget == 0 && !_engaged && !_closing) return;
    _blend.stop();
    _closing = false;
    _engaged = false;
    if (_lift.value != 0) {
      _runBarAnim(PortalPhysics.barSpringBack, Curves.elasticOut);
    }
    _springTo(0, 0);
  }

  /// The route under the card changed (a matrix cell navigated, a deep link
  /// fired). The choreography, in order: the card expands back to fullscreen
  /// still showing the FROZEN departure screen; the new route mounts and runs
  /// its page transition unseen beneath the veil; at t == 0 the snapshot
  /// switches itself off ([_onPortalTick]) and the destination is simply
  /// there. Deliberately NO `snapshot.clear()` here — dropping the veil at
  /// tap time exposed the route transition mid-flight under a closing card,
  /// which read as one jerky cut.
  void handleRouteChanged() {
    if (!isOpenOrEngaged) return;
    closeFromUi();
  }

  void _springTo(double target, double velocity) {
    _springTarget = target;
    portal
        .animateWith(
          SpringSimulation(
            SpringDescription.withDampingRatio(
              mass: 1,
              stiffness: PortalPhysics.springStiffness,
              ratio: PortalPhysics.springDampingRatio,
            ),
            portal.value,
            target,
            velocity,
          ),
        )
        .whenComplete(() {
          // A spring stops within an epsilon of its target, never ON it — and
          // both AbsorbPointer and snapshotting gate on t == 0 exactly. Left
          // at 0.004, the whole app would sit behind an invisible absorber.
          // Skipped if something else took over (a new drag, a new spring).
          if (!portal.isAnimating &&
              !_engaged &&
              !_closing &&
              (portal.value - target).abs() < 0.05) {
            portal.value = target;
          }
        });
  }

  void _runBarAnim(Duration duration, Curve curve, {double end = 0}) {
    if (_lift.value == end) return;
    _stopBarAnim();
    _barSpring.duration = duration;
    final anim = Tween<double>(
      begin: _lift.value,
      end: end,
    ).animate(CurvedAnimation(parent: _barSpring, curve: curve));
    void tick() => _lift.value = anim.value;
    anim.addListener(tick);
    _barAnim = anim;
    _barAnimTick = tick;
    _barSpring.forward(from: 0).whenComplete(() => anim.removeListener(tick));
  }

  void _stopBarAnim() {
    if (_barSpring.isAnimating) _barSpring.stop();
    final anim = _barAnim;
    final tick = _barAnimTick;
    if (anim != null && tick != null) anim.removeListener(tick);
    _barAnim = null;
    _barAnimTick = null;
  }

  void dispose() {
    portal.removeListener(_onPortalTick);
    _blend.removeListener(_onBlendTick);
    portal.dispose();
    _barSpring.dispose();
    _blend.dispose();
    _lift.dispose();
    covering.dispose();
    snapshot.dispose();
  }
}

/// The scene: floor (ambient + the real [ServiceMatrix]) under the receding
/// screen card. Wraps the shell's body; costs nothing while closed (the floor
/// is not even mounted and snapshotting is off).
class PortalStage extends StatelessWidget {
  const PortalStage({super.key, required this.controller, required this.child});

  final ServicePortalController controller;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    controller.screenHeight = MediaQuery.sizeOf(context).height;
    return AnimatedBuilder(
      animation: controller.portal,
      child: child,
      builder: (context, body) {
        final t = controller.portal.value;
        // Three layers, and the order is the design: the ambient ground sits
        // UNDER the receded screen, the scrolling matrix OVER it. Scrolling
        // the floor therefore carries the cells across the card instead of
        // swallowing them beneath it. (A plain z-swap of the old two layers
        // would not do: the floor's ambient base is opaque and would bury
        // the card.)
        return Stack(
          fit: StackFit.expand,
          children: [
            if (t > 0) _PortalBackdrop(controller: controller),
            _PortalCard(controller: controller, t: t, child: body!),
            if (t > 0) _PortalFloor(controller: controller),
          ],
        );
      },
    );
  }
}

/// The ground the Portal opens onto: ambient only, no content. Lives BELOW
/// the receded screen so the card reads as a card sitting on it.
class _PortalBackdrop extends StatelessWidget {
  const _PortalBackdrop({required this.controller});

  final ServicePortalController controller;

  @override
  Widget build(BuildContext context) {
    final t = controller.portal.value;
    return Positioned.fill(
      child: IgnorePointer(
        child: Opacity(
          opacity: ((t - 0.08) / 0.5).clamp(0.0, 1.0),
          child: const AmbientBackground(child: SizedBox.expand()),
        ),
      ),
    );
  }
}

/// The matrix itself, scrolling ABOVE the card on a transparent ground.
class _PortalFloor extends StatelessWidget {
  const _PortalFloor({required this.controller});

  final ServicePortalController controller;

  bool _onScroll(ScrollNotification notification) {
    // Pull-down past the top over-scroll = "let me back": the iOS-native way
    // to dismiss a sheet-like layer without a dedicated control.
    if (notification is ScrollUpdateNotification &&
        notification.metrics.pixels < -64 &&
        controller.portal.value > 0.9) {
      controller.closeFromUi();
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final t = controller.portal.value;
    final visibility = ((t - 0.08) / 0.5).clamp(0.0, 1.0);
    // The spacer tracks the card's LIVE bottom edge, not its resting spot:
    // while the Portal opens or closes the panel therefore always sits below
    // the card — the veil can only cross it when the USER scrolls. This is
    // also the floor's entrance (it emerges from under the card's edge), so
    // no separate parallax is needed.
    final h = controller.screenHeight;
    final finalBottom =
        PortalPhysics.cardTopInset + h * PortalPhysics.cardScale;
    final cardBottom = h - t * (h - finalBottom);
    final spacerHeight = cardBottom + AppSpacing.md;
    // Near-opaque, not opaque: the card should read as a presence under the
    // veil, not vanish. Surface-based so both themes get their own ground.
    final panelColor = Theme.of(
      context,
    ).colorScheme.surface.withValues(alpha: 0.90);
    return Positioned.fill(
      child: IgnorePointer(
        ignoring: t < 0.7,
        child: Opacity(
          opacity: visibility,
          child: NotificationListener<ScrollNotification>(
            onNotification: _onScroll,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics(),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // The stretch above the matrix — where the receded card
                  // shows through — is a real child, not padding: a tap there
                  // goes back, a drag there scrolls. (The scrollable is opaque
                  // to hits, so the card's own tap can't be reached anymore.)
                  //
                  // Named for a screen reader, which reaches it first: it is
                  // the one way back that is on the floor itself, and on iOS
                  // there is no back button to reach for instead.
                  Semantics(
                    container: true,
                    button: true,
                    label: 'Close the Portal',
                    onTap: controller.closeFromUi,
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onTap: controller.closeFromUi,
                      excludeFromSemantics: true,
                      child: SizedBox(height: spacerHeight),
                    ),
                  ),
                  // The matrix rides its own panel: a soft-fading top edge
                  // and a near-opaque surface fill that scroll WITH the
                  // cells, so when the list travels over the frozen card it
                  // brings its own contrast along. Deliberately no backdrop
                  // blur — this panel scrolls every frame.
                  Container(
                    height: 56,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [panelColor.withValues(alpha: 0), panelColor],
                      ),
                    ),
                  ),
                  Container(
                    color: panelColor,
                    padding: EdgeInsets.only(
                      left: AppSpacing.lg,
                      right: AppSpacing.lg,
                      bottom: FloatingNavBarMetrics.getScrollViewBottomPadding(
                        context,
                      ),
                    ),
                    // Picker, not readout: this floor exists to be tapped,
                    // and a folded cell would reach the service while hiding
                    // every connection but the one the lens already points at.
                    //
                    // Wrapped so a cell can close the Portal on the ACT of
                    // being tapped. The shell's route hook closes it when the
                    // content under the card moves, which is a different
                    // question and misses the tap that moves nothing — see
                    // [PortalDismissScope].
                    child: PortalDismissScope(
                      onDismiss: controller.closeFromUi,
                      child: const ServiceMatrix(
                        role: ServiceMatrixRole.picker,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PortalCard extends StatelessWidget {
  const _PortalCard({
    required this.controller,
    required this.t,
    required this.child,
  });

  final ServicePortalController controller;
  final double t;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = colorScheme.brightness == Brightness.dark;
    final h = controller.screenHeight;
    final finalBottom =
        PortalPhysics.cardTopInset + h * PortalPhysics.cardScale;
    // Linear on purpose — see the library doc.
    final top = PortalPhysics.cardTopInset * t;
    final bottom = h - t * (h - finalBottom);
    final scale = ((bottom - top) / h).clamp(PortalPhysics.cardScale, 1.0);
    final radius = lerpDouble(
      0,
      PortalPhysics.cardCornerRadius,
      (t * 3).clamp(0.0, 1.0),
    )!;
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.14 * t)
        : colorScheme.outline.withValues(alpha: 0.85 * t);
    final shadows = t == 0
        ? const <BoxShadow>[]
        : [
            for (final shadow in AppElevation.level3(colorScheme))
              BoxShadow(
                color: shadow.color.withValues(alpha: shadow.color.a * t),
                offset: shadow.offset,
                blurRadius: shadow.blurRadius,
                spreadRadius: shadow.spreadRadius,
              ),
          ];

    return Positioned.fill(
      child: Transform(
        alignment: Alignment.topCenter,
        transform: Matrix4.identity()
          ..translateByDouble(0, top, 0, 1)
          ..scaleByDouble(scale, scale, 1, 1),
        child: GestureDetector(
          onTap: t > 0.9 ? controller.closeFromUi : null,
          // The floor's spacer is the reader's close, named; a second,
          // nameless tap target on the card would be a stop that says nothing.
          excludeFromSemantics: true,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(radius),
              boxShadow: shadows,
              border: t == 0 ? null : Border.all(color: borderColor),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(radius),
              child: SnapshotWidget(
                controller: controller.snapshot,
                mode: SnapshotMode.permissive,
                // Inert to the reader as it is to the finger. The card is a
                // frozen picture of the page, and a screen reader walking into
                // it would read a page it cannot act on — and, once a cell has
                // been chosen, the new route mounting unseen beneath it.
                child: ExcludeSemantics(
                  excluding: t > 0,
                  child: AbsorbPointer(absorbing: t > 0, child: child),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
