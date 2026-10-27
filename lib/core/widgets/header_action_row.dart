import 'package:flutter/material.dart';

import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/focus_ring.dart';
import 'package:cupola/core/generated/design_tokens.g.dart';
import 'package:cupola/core/theme.dart';

/// The button styles of the media detail header actions: the promoted primary
/// (`expandedButtonStyle`) and the square disc beside it (`iconOnlyButtonStyle`).
abstract final class HeaderActionRow {
  /// The glyph size every action control draws its icon at.
  static const double glyphSize = 18;

  static const double buttonHeight = DesignTokens.sizeButtonL;

  /// Shared shape for all detail header action buttons: `radius.button` (16),
  /// the large button's, continuous. These are controls, and full or
  /// near-full radius is the metadata shape in this system.
  static final _buttonShape = RoundedSuperellipseBorder(
    borderRadius: BorderRadius.circular(AppRadius.button),
  );

  /// [_buttonShape], ringed in `line.focus` while the keyboard holds it
  /// (`FocusRingBorder`): a style that sets its own shape replaces the
  /// theme's, ring included, so the band draws it itself.
  static WidgetStateProperty<OutlinedBorder> _ringed(BuildContext context) =>
      focusRingShape(_buttonShape, ring: CupolaRoom.of(context).focus);

  static ButtonStyle _filledButtonStyle(
    BuildContext context, {
    EdgeInsetsGeometry? padding,
    Size? minimumSize,
    Size? fixedSize,
    Color? foregroundColor,
    Color? backgroundColor,
  }) => FilledButton.styleFrom(
    padding: padding,
    minimumSize: minimumSize,
    fixedSize: fixedSize,
    foregroundColor: foregroundColor,
    backgroundColor: backgroundColor,
  ).copyWith(shape: _ringed(context));

  /// Creates a [ButtonStyle] for icon-only [FilledButton] trailing widgets.
  ///
  /// Produces a [buttonHeight]×[buttonHeight] square button. Pass
  /// [backgroundColor] and [foregroundColor] for variants like error/delete.
  static ButtonStyle iconOnlyButtonStyle(
    BuildContext context, {
    Color? foregroundColor,
    Color? backgroundColor,
  }) => _filledButtonStyle(
    context,
    padding: EdgeInsets.zero,
    minimumSize: const Size(buttonHeight, buttonHeight),
    fixedSize: const Size(buttonHeight, buttonHeight),
    foregroundColor: foregroundColor,
    backgroundColor: backgroundColor,
  );

  /// Creates a [ButtonStyle] for expanded [FilledButton.icon] widgets.
  ///
  /// [minimumSize], never `fixedSize`: a fixed height cannot grow, so a label
  /// that no longer fits is broken *inside the word*, which is how the request
  /// button came to read "Requeste / d" at an accessibility reading size. The
  /// button grows instead.
  static ButtonStyle expandedButtonStyle(
    BuildContext context, {
    Color? foregroundColor,
    Color? backgroundColor,
    Color? disabledForegroundColor,
    Color? disabledBackgroundColor,
  }) => FilledButton.styleFrom(
    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
    minimumSize: const Size(double.infinity, buttonHeight),
    // Standard density on every platform: the desktop's compact density takes
    // 8 off `minimumSize`, which painted this button 40 tall beside the 48pt
    // discs (`fixedSize`, which density does not touch): two heights in one
    // band.
    visualDensity: VisualDensity.standard,
    foregroundColor: foregroundColor,
    backgroundColor: backgroundColor,
    disabledForegroundColor: disabledForegroundColor,
    disabledBackgroundColor: disabledBackgroundColor,
  ).copyWith(shape: _ringed(context));
}
