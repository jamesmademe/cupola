import 'package:flutter/material.dart';
import 'package:cupola/core/generated/design_tokens.g.dart';

/// Motion.
///
/// One ease carries almost everything — `Cubic(0.2, 0.8, 0.2, 1)`, a fast start
/// and a long settle — and the durations are named for what moves. The older
/// ladder ([durationXs] … [durationXl]) resolves onto the role each step stood
/// for. Every animation has its Reduce Motion answer, written beside the role
/// in `design/tokens/core.json`.
class AppAnimation {
  AppAnimation._();

  // === DURATIONS (the older ladder) ===

  /// 180ms - Micro-interactions: the press dip, a highlight. [press].
  static const Duration durationXs = DesignTokens.durationXs;

  /// 320ms - Simple state changes. [standard].
  static const Duration durationSm = DesignTokens.durationSm;

  /// 320ms - Standard transitions. [standard].
  static const Duration durationMd = DesignTokens.durationMd;

  /// 420ms - Complex transitions: the pager, the segmented thumb. [emphasized].
  static const Duration durationLg = DesignTokens.durationLg;

  /// 520ms - Entrances. [enter].
  static const Duration durationXl = DesignTokens.durationXl;

  // === CURVES ===

  /// The one ease, for state changes and anything that moves across the
  /// screen.
  static const Curve standardCurve = DesignTokens.motionCurveStandard;

  /// The one ease again, for elements appearing on screen: the room has a
  /// single curve for press, state, pager and entrance, and these two names
  /// are kept so the call sites stand.
  static const Curve emphasizedCurve = DesignTokens.motionCurveStandard;

  /// Sheets and dialogs arriving.
  static const Curve sheetInCurve = DesignTokens.motionSheetInCurve;

  /// Sheets and dialogs leaving.
  static const Curve sheetOutCurve = DesignTokens.motionSheetOutCurve;

  /// A figure rolling into place (easeOutCubic).
  static const Curve rollCurve = DesignTokens.motionRollCurve;

  // === ROLES ===

  /// 180ms - The press dip.
  static const Duration press = DesignTokens.motionPressDuration;

  /// The scale a pressed target dips to.
  static const double pressScale = DesignTokens.motionPressScale;

  /// 320ms - State changes, expand, select.
  static const Duration standard = DesignTokens.motionStandardDuration;

  /// 420ms - The pager, the segmented thumb, the chip rail.
  static const Duration emphasized = DesignTokens.motionEmphasizedDuration;

  /// 520ms - An entrance: rise [enterRise] and fade.
  static const Duration enter = DesignTokens.motionEnterDuration;

  /// How far an entering element rises.
  static const double enterRise = DesignTokens.motionEnterRise;

  /// 40ms - The delay between siblings entering.
  static const Duration enterStagger = DesignTokens.motionEnterStagger;

  /// Siblings past this many enter together.
  static final int enterStaggerMax = DesignTokens.motionEnterStaggerMax.round();

  /// 380ms - Sheets and dialogs in.
  static const Duration sheetIn = DesignTokens.motionSheetInDuration;

  /// 240ms - Sheets and dialogs out.
  static const Duration sheetOut = DesignTokens.motionSheetOutDuration;

  /// 450ms - The poster → Media flight.
  static const Duration shared = DesignTokens.motionSharedDuration;

  /// 600ms - A bar moving to a new value.
  static const Duration progress = DesignTokens.motionProgressDuration;

  /// 900ms - A figure rolling once from "—" to its value.
  static const Duration roll = DesignTokens.motionRollDuration;

  /// 1500ms - The room light moving to a new title.
  static const Duration light = DesignTokens.motionLightDuration;

  // === COMMON ANIMATION CONFIGS ===

  /// 1600ms - Shimmer animation cycle
  static const Duration shimmerDuration = DesignTokens.durationShimmer;

  /// How long a transient success confirmation (a check that replaces a
  /// button's icon after an action lands) stays visible before reverting.
  /// Long enough to be seen after the eye returns from the snackbar, short
  /// enough that the control is back to normal by the next glance.
  static const Duration confirmationHold =
      DesignTokens.durationConfirmationHold;
}
