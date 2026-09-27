import 'package:flutter/material.dart';
import 'package:cupola/core/generated/design_tokens.g.dart';

/// Material Design 3 Animation Constants
///
/// Following M3 motion guidelines for consistent, fluid animations.
/// Use these durations and curves for all animations.
class AppAnimation {
  AppAnimation._();

  // === DURATIONS ===

  /// 100ms - Extra short for micro-interactions (ripples, highlights)
  static const Duration durationXs = DesignTokens.durationXs;

  /// 200ms - Short for simple state changes
  static const Duration durationSm = DesignTokens.durationSm;

  /// 300ms - Medium for standard transitions
  static const Duration durationMd = DesignTokens.durationMd;

  /// 400ms - Long for complex transitions
  static const Duration durationLg = DesignTokens.durationLg;

  /// 500ms - Extra long for dramatic effects
  static const Duration durationXl = DesignTokens.durationXl;

  // === M3 EASING CURVES ===

  /// Standard easing for most animations
  /// Use for elements that move across the screen
  static const Curve standardCurve = Curves.easeInOutCubicEmphasized;

  /// Emphasized easing for entering elements
  /// Use for elements appearing on screen
  static const Curve emphasizedCurve = Curves.easeOutCubic;

  // === COMMON ANIMATION CONFIGS ===

  /// Shimmer animation cycle
  static const Duration shimmerDuration = DesignTokens.durationShimmer;

  /// How long a transient success confirmation (a check that replaces a
  /// button's icon after an action lands) stays visible before reverting.
  /// Long enough to be seen after the eye returns from the snackbar, short
  /// enough that the control is back to normal by the next glance.
  static const Duration confirmationHold =
      DesignTokens.durationConfirmationHold;
}
