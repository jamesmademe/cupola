import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:cupola/core/generated/design_tokens.g.dart';

/// Centralised gradient tokens for Cupola.
///
/// Gradients were previously hand-rolled inline across onboarding, media detail
/// backdrops and poster scrims. Routing them through [AppGradients] keeps the
/// premium look consistent and makes the brand language editable in one place.
class AppGradients {
  AppGradients._();

  /// Bottom-up scrim laid over a poster/backdrop so foreground text and badges
  /// stay legible. Fades from the given [surface] colour to transparent.
  ///
  /// [depth] (0–1) progressively dims the art as the detail hero collapses:
  /// at 0 this is the resting scrim, at 1 the mid stop goes fully opaque and
  /// the top stop picks up a 35% wash so the art recedes behind chrome. The
  /// deepening scrim is deliberately the whole legibility story: blurring the
  /// backdrop image was evaluated and rejected because an `ImageFiltered` over
  /// a full-bleed image re-rasterises it on every scroll frame, the same
  /// per-frame cost class the No-Blur-Under-Scroll rule exists to prevent.
  static LinearGradient heroScrim(Color surface, {double depth = 0}) {
    return LinearGradient(
      begin: Alignment.bottomCenter,
      end: Alignment.topCenter,
      colors: [
        surface,
        surface.withValues(
          alpha: lerpDouble(DesignTokens.opacityHeroScrimRest, 1.0, depth)!,
        ),
        surface.withValues(
          alpha: lerpDouble(0.0, DesignTokens.opacityHeroScrimDeep, depth)!,
        ),
      ],
      stops: const [0.0, 0.35, 1.0],
    );
  }

  /// Ambient background wash: a soft radial of the room's light over the base
  /// surface, used behind headers and the onboarding canvas to add depth.
  ///
  /// Without an [accent] the room is lit by the neutral lamp, the light of a
  /// room with no artwork. (The primary ink is not a light: it is white in the
  /// dark room, and a white wash would read as fog.)
  static RadialGradient ambientBackground(
    ColorScheme scheme, {
    Color? accent,
    Alignment center = const Alignment(-0.7, -0.9),
  }) {
    final glow = (accent ?? DesignTokens.colorTitleLightFallback);
    return RadialGradient(
      center: center,
      radius: 1.4,
      colors: [
        glow.withValues(
          alpha: scheme.brightness == Brightness.dark
              ? DesignTokensDark.opacityAmbientGlow
              : DesignTokensLight.opacityAmbientGlow,
        ),
        scheme.surface.withValues(alpha: 0.0),
      ],
      stops: const [0.0, 1.0],
    );
  }

  /// A radial glow of [accent], for a card or a hero lit from one corner.
  ///
  /// [accent] is a light: the lamp (`ServiceKey.accent` is the lamp for every
  /// service), a shadow ink behind a badge, or a tone on a card that is about a
  /// state. [alpha] is the wash at the centre. The 0.22 default lights one card
  /// on its own; a grid that repeats the treatment needs a fraction of it, or
  /// thirteen washes read as thirteen lit cells rather than one room.
  static RadialGradient serviceGlow(
    Color accent, {
    Alignment center = Alignment.topRight,
    double radius = 1.2,
    double alpha = DesignTokens.opacityServiceGlow,
  }) {
    return RadialGradient(
      center: center,
      radius: radius,
      colors: [
        accent.withValues(alpha: alpha),
        accent.withValues(alpha: 0.0),
      ],
      stops: const [0.0, 1.0],
    );
  }
}
