import 'package:cupola/core/generated/design_tokens.g.dart';

/// Spacing.
///
/// The scale is `space.scale` in `design/tokens/core.json` (2, 4, 6, 8, 10,
/// 12, 14, 16, 20, 24, 28, 32, 40, 56); the older ladder ([xs] … [xxxl])
/// resolves onto it, and the named rhythm steps ([row], [slabY], [gutter],
/// [section], [top]) are the ones the layouts are drawn with.
class AppSpacing {
  AppSpacing._();

  /// 2dp - Inside components only: glyph-to-label gap.
  static const double xxs = DesignTokens.spaceXxs;

  /// 4dp - Minimal spacing for tight layouts
  static const double xs = DesignTokens.spaceXs;

  /// 6dp - Inside components only: chip inner padding.
  static const double s = DesignTokens.spaceS;

  /// 8dp - Small spacing for related elements
  static const double sm = DesignTokens.spaceSm;

  /// 12dp - Compact spacing
  static const double md = DesignTokens.spaceMd;

  /// 16dp - Default spacing for most layouts: the gutter.
  static const double lg = DesignTokens.spaceLg;

  /// 24dp - Large spacing for section separation
  static const double xl = DesignTokens.spaceXl;

  /// 32dp - Extra large spacing
  static const double xxl = DesignTokens.spaceXxl;

  /// 40dp - Maximum spacing for major sections: the scale's largest step.
  static const double xxxl = DesignTokens.spaceXxxl;

  // --- Rhythm ---

  /// 10dp - A row's vertical padding.
  static const double row = DesignTokens.spaceScaleRow;

  /// 14dp - A slab's vertical padding.
  static const double slabY = DesignTokens.spaceScaleSlabY;

  /// 16dp - The page gutter and a slab's padding.
  static const double gutter = DesignTokens.spaceScaleGutter;

  /// 20dp - The scale's step between the gutter and 24.
  static const double scaleXl = DesignTokens.spaceScaleXl;

  /// 28dp - The space above a section heading.
  static const double section = DesignTokens.spaceScaleSection;

  /// 56dp - A screen's top margin, under the status bar.
  static const double top = DesignTokens.spaceScaleTop;

  // --- Grid Spacing ---

  /// Gap between grid items
  static const double gridGap = DesignTokens.spaceGridGap;

  /// Gap between carousel items
  static const double carouselGap = DesignTokens.spaceCarouselGap;
}
