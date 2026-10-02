import 'package:flutter/material.dart';

import 'package:cupola/core/app_animation.dart';
import 'package:cupola/core/app_gradients.dart';
import 'package:cupola/core/theme.dart';

/// Paints the app's ambient background — an opaque base surface with soft accent
/// radial glows — behind [child], full-bleed.
///
/// Because the base is opaque, this can sit directly behind a transparent
/// [Scaffold] (and a transparent/glass app bar) so the gradient reads
/// continuously across the whole screen, including the status-bar and app-bar
/// band. This is what fixes the "app bar breaks the gradient with a flat
/// black/white strip" seam: instead of an opaque scaffold surface showing
/// through the transparent app bar, the gradient shows through.
///
/// [accent] is the room's light. With none the room is lit by the neutral lamp
/// ([AppColors.lamp]), the light of a room with no artwork — and a service's
/// room is lit by it too, since `ServiceKey.accent` is the lamp for every
/// service: the room takes its light from the content, never from the service.
/// Never the primary ink: in the dark room that is near-white, and a white
/// wash reads as fog.
///
/// **The accent drifts, it does not cut.** A change to [accent] is animated over
/// [AppAnimation.durationMd] on the standard curve, which is the same clock the
/// page transition and the onboarding ring's resize run on — three instruments,
/// one beat. Swapping the glow instantly while the other two travel is what made
/// a change of subject read as a repaint instead of a move. The onboarding walk
/// had already worked this out and carried a private `_AmbientRoom` wrapper to
/// get it; the tween belongs here, where every other caller — a service
/// dashboard switching services, most obviously — inherits it rather than
/// re-implementing it.
class AmbientBackground extends StatelessWidget {
  final Widget child;
  final Color? accent;

  const AmbientBackground({super.key, required this.child, this.accent});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Resolved *before* the tween, not inside its builder. [accent] is nullable
    // and `ColorTween` asserts on a null `end` — `Color? lerp` is fine with a
    // null *begin* (it fades up from transparent) but a null end has nothing to
    // travel to. Naming the fallback here is also what makes a screen drift out
    // of and back into the lamp rather than cutting at the edges of a lit
    // stretch.
    final target = accent ?? AppColors.lamp;

    // Reduce Motion **removes** the animator rather than shortening it, which is
    // the rule the rest of the app keeps (`reel_line`, `service_ring`,
    // `pressable_scale`): with the tween gone the room is simply already the new
    // colour, and every flow stays completable without a single frame of
    // interpolation.
    if (MediaQuery.disableAnimationsOf(context)) {
      return _Glow(scheme: scheme, accent: target, child: child);
    }

    return TweenAnimationBuilder<Color?>(
      // `ColorTween`, not `Tween<Color?>`: only the former knows how to
      // interpolate a colour, and the plain one would snap at the halfway frame.
      tween: ColorTween(end: target),
      duration: AppAnimation.durationMd,
      curve: AppAnimation.standardCurve,
      // The subtree is built once and carried through every frame of the drift:
      // the room repaints, the screen inside it does not rebuild.
      child: child,
      builder: (context, drifting, builtChild) => _Glow(
        scheme: scheme,
        // `drifting` is null only on the very first frame, before the tween has
        // a begin value; the target is the right answer there too.
        accent: drifting ?? target,
        child: builtChild!,
      ),
    );
  }
}

/// The three stacked decorations, split out so the tween's builder repaints only
/// them and the reduced-motion path renders the identical tree.
class _Glow extends StatelessWidget {
  const _Glow({
    required this.scheme,
    required this.accent,
    required this.child,
  });

  final ColorScheme scheme;
  final Color accent;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      // Opaque base so nothing behind (page transitions, shell) bleeds through.
      decoration: BoxDecoration(color: scheme.surface),
      child: DecoratedBox(
        // Primary glow anchored top-left.
        decoration: BoxDecoration(
          gradient: AppGradients.ambientBackground(scheme, accent: accent),
        ),
        child: DecoratedBox(
          // Secondary glow bottom-right for depth, as strong as the first.
          decoration: BoxDecoration(
            gradient: AppGradients.ambientBackground(
              scheme,
              accent: accent,
              center: const Alignment(0.95, 0.75),
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}
