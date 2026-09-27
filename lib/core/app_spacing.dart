import 'package:cupola/core/generated/design_tokens.g.dart';

/// Material Design 3 Spacing Scale
///
/// Based on 4dp grid system for consistent rhythm across the app.
/// Use these values for all margins, paddings, and gaps.
class AppSpacing {
  AppSpacing._();

  /// 4dp - Minimal spacing for tight layouts
  static const double xs = DesignTokens.spaceXs;

  /// 8dp - Small spacing for related elements
  static const double sm = DesignTokens.spaceSm;

  /// 12dp - Compact spacing
  static const double md = DesignTokens.spaceMd;

  /// 16dp - Default spacing for most layouts
  static const double lg = DesignTokens.spaceLg;

  /// 24dp - Large spacing for section separation
  static const double xl = DesignTokens.spaceXl;

  /// 32dp - Extra large spacing
  static const double xxl = DesignTokens.spaceXxl;

  /// 48dp - Maximum spacing for major sections
  static const double xxxl = DesignTokens.spaceXxxl;

  // --- Grid Spacing ---

  /// Gap between grid items
  static const double gridGap = DesignTokens.spaceGridGap;

  /// Gap between carousel items
  static const double carouselGap = DesignTokens.spaceCarouselGap;
}
