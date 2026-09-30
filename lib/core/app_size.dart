import 'package:cupola/core/generated/design_tokens.g.dart';

/// Component sizes.
///
/// A target is at least [touch] even where the drawing is smaller: a 36pt chip
/// sits inside a 44pt target, and the area grows, not the drawing.
abstract final class AppSize {
  /// 44 - The minimum touch target.
  static const double touch = DesignTokens.sizeTouch;

  /// 52 - A primary button.
  static const double buttonLarge = DesignTokens.sizeButtonL;

  /// 44 - A secondary button.
  static const double buttonMedium = DesignTokens.sizeButtonM;

  /// 52 - A text field.
  static const double field = DesignTokens.sizeField;

  /// 48 - The search field.
  static const double search = DesignTokens.sizeSearch;

  /// 36 - A chip, inside a 44 target.
  static const double chip = DesignTokens.sizeChip;

  /// 62 - The floating tab bar.
  static const double tabBar = DesignTokens.sizeTabbar;

  /// 20 - An icon in a row or a button.
  static const double icon = DesignTokens.sizeIcon;

  /// 24 - A large icon.
  static const double iconLarge = DesignTokens.sizeIconL;

  /// 36 - A row thumbnail's width.
  static const double thumbWidth = DesignTokens.sizeThumbW;

  /// 54 - A row thumbnail's height.
  static const double thumbHeight = DesignTokens.sizeThumbH;
}
